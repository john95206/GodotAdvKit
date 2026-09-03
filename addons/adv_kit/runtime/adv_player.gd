class_name AdvPlayer
extends Node
## シナリオの再生制御（phase-06）。
##
## 扱うのは line の表示・送り、[b]汎用演出（§8）[/b]、
## [b]局所演出（§7）とボイス（§9.4）[/b]。
## 選択肢・話題遷移・フラグ・既読・進行保存（§9.1）と、
## オート・スキップ・バックログ（§9.2〜§9.5）を扱う。

@export var stage: AdvStage
@export var message_window: AdvMessageWindow
## 選択肢表示 UI。未接続でも choice_presented signal は発火する。
@export var choice_menu: AdvChoiceMenu
## バックログ UI。未接続でもバックログ API と signal は利用できる。
@export var backlog_view: AdvBacklogView
## 画面揺れの対象（仕様書 §5.1）。未接続でも shake が無効になるだけで進行は止まらない。
@export var shake_root: Control
## フェード用の最前面レイヤ。未接続でも fade が無効になるだけ。
@export var fade_layer: ColorRect

signal topic_started(topic_id: StringName)
signal topic_finished(topic_id: StringName)
signal step_shown(topic_id: StringName, step_uid: StringName)
signal line_completed(topic_id: StringName, step_uid: StringName)
signal choice_presented(options: Array)
signal choice_selected(index: int, option: Dictionary)
signal flag_changed(flag_name: String, value: bool)
signal backlog_appended(entry: AdvBacklogEntry)
signal auto_mode_changed(enabled: bool)
signal skip_started()
signal skip_stopped(reason: StringName)
signal scenario_finished()

var _book: AdvScenarioBook = null
var _settings: AdvKitSettings = null
var _current_topic: AdvTopic = null
var _current_topic_id: StringName = &""
var _step_cursor: int = -1
var _is_playing: bool = false
var _is_typing: bool = false
var _is_busy: bool = false
var _typing_tween: Tween = null
var _typing_topic_id: StringName = &""
var _typing_step_uid: StringName = &""
var _typing_line: AdvLineStep = null

var _progress: AdvProgressState = AdvProgressState.new()
var _is_choice_open: bool = false
var _choice_options: Array[Dictionary] = []
var _choice_topic_id: StringName = &""
var _choice_step_uid: StringName = &""

var _auto_mode: bool = false
var _auto_wait_token: int = 0
var _is_skipping: bool = false
var _skip_accumulator: float = 0.0
var _is_backlog_open: bool = false
var _backlog: AdvBacklog = AdvBacklog.new()

## play_topic() / stop() のたびに増える。await をまたいだ古い進行を捨てるための世代番号。
var _run_id: int = 0

## effect_id -> ハンドラ（仕様書 §7 の拡張規約）。
var _effects: Dictionary[StringName, AdvEffectHandler] = {}
var _context: AdvEffectContext = null
var _audio: AdvAudioDirector = null
var _voice: AdvVoicePlayer = null

## Web の autoplay ポリシー対応（仕様書 §10）。初回のユーザー操作まで音を鳴らさない。
var _audio_unlocked: bool = false

## キャラクターごとの直近の指定。空の指定を次の行へ引き継ぐ（シナリオ解釈の規則）。
var _current_poses: Dictionary[StringName, StringName] = {}
var _current_expressions: Dictionary[StringName, StringName] = {}
var _current_slots: Dictionary[StringName, StringName] = {}

## 地の文では更新せず、次に話者が現れたときの交代判定に使う。
var _last_speaker_id: StringName = &""


func _ready() -> void:
	set_process(true)
	_ensure_audio_nodes()
	_connect_message_window()
	_connect_choice_menu()
	_connect_backlog_view()


## Book と再生設定を差し替え、表示状態を初期化する。
## 組み込み演出（§7 の 9 種）は未登録ならここで登録する。
func setup(p_book: AdvScenarioBook, p_settings: AdvKitSettings) -> void:
	stop()
	_book = p_book
	_settings = p_settings if p_settings != null else AdvKitSettings.new()
	_backlog.set_max_entries(_settings.backlog_max_entries)
	_progress = AdvProgressState.new()
	_current_poses.clear()
	_current_expressions.clear()
	_current_slots.clear()
	_last_speaker_id = &""
	_ensure_audio_nodes()
	_register_builtin_effects()
	_build_context()
	_voice.setup(_settings.voice_bus)
	_connect_message_window()
	_connect_choice_menu()
	_connect_backlog_view()
	if stage != null:
		stage.clear()
	if message_window != null:
		message_window.clear()
	if choice_menu != null:
		choice_menu.close()
	if backlog_view != null:
		backlog_view.close()


## topic を先頭から再生する。存在しない topic はエラーにして何もしない。
func play_topic(p_topic_id: StringName) -> void:
	if _book == null:
		push_error("AdvPlayer.play_topic(): setup() がまだ呼ばれていません")
		return
	var topic: AdvTopic = _book.get_topic(p_topic_id)
	if topic == null:
		push_error("AdvPlayer.play_topic(): topic が見つかりません: %s" % p_topic_id)
		return

	stop()
	_start_topic(topic, p_topic_id, -1)


## 表示中なら全文を表示し、表示済みなら次のステップへ進む。
## [b]BLOCKING 演出の実行中は受け付けない。[/b]
func advance() -> void:
	if _auto_mode:
		set_auto_mode(false)
	unlock_audio()
	if not _is_playing or _is_busy or _is_choice_open or _is_backlog_open:
		return
	if _is_typing:
		skip_typing()
		return
	_process_next_step()


## 現在のタイプライタ表示を即時完了する。
func skip_typing() -> void:
	unlock_audio()
	if not _is_typing:
		return
	_complete_typing()


## 現在選択肢を表示して入力を待っているか。
func is_choice_open() -> bool:
	return _is_choice_open


## 選択肢を外部から選ぶ。ChoiceMenu が無い構成やテスト用 UI でも利用できる。
func choose_option(p_index: int) -> void:
	_on_option_chosen(p_index)


## オートモードを切り替える。待機中に false にすると待機を破棄する。
func set_auto_mode(p_enabled: bool) -> void:
	if _auto_mode == p_enabled:
		if not p_enabled:
			_cancel_auto_wait()
		return
	_auto_mode = p_enabled
	if not _auto_mode:
		_cancel_auto_wait()
	auto_mode_changed.emit(_auto_mode)
	if _auto_mode:
		_schedule_auto_advance()


func is_auto_mode() -> bool:
	return _auto_mode


## skip_action の押下中に呼び続けるスキップを開始する。
func start_skip() -> void:
	if not _is_playing or _is_backlog_open or _is_choice_open:
		return
	if _is_skipping:
		return
	if _auto_mode:
		set_auto_mode(false)
	_is_skipping = true
	_skip_accumulator = 0.0
	skip_started.emit()


## スキップを解除する。解除理由はユーザー操作として記録する。
func stop_skip() -> void:
	_stop_skip(&"user")


func is_skipping() -> bool:
	return _is_skipping


func get_backlog() -> Array[AdvBacklogEntry]:
	return _backlog.get_entries()


## バックログを開き、進行とオート待機を止める。
func open_backlog() -> void:
	if _is_backlog_open:
		return
	_is_backlog_open = true
	if _auto_mode:
		set_auto_mode(false)
	if _is_skipping:
		_stop_skip(&"user")
	if backlog_view != null:
		backlog_view.present(get_backlog())


## バックログを閉じて、通常の入力を再び受け付ける。
func close_backlog() -> void:
	if not _is_backlog_open:
		return
	_is_backlog_open = false
	if backlog_view != null:
		backlog_view.close()


func is_backlog_open() -> bool:
	return _is_backlog_open


## バックログ上のボイスを、通常のボイスチャンネルで再生する。
func replay_voice(p_entry: AdvBacklogEntry) -> void:
	if p_entry == null or _settings == null or not _settings.backlog_voice_replay:
		return
	unlock_audio()
	if _voice != null:
		_voice.play_voice(p_entry.voice_path)


## 現在のフラグを設定する。実際に値が変化したときだけ signal を発火する。
func set_flag(p_flag_name: String, p_value: bool) -> void:
	if _progress.set_flag(p_flag_name, p_value):
		flag_changed.emit(p_flag_name.strip_edges(), p_value)


func has_flag(p_flag_name: String) -> bool:
	return _progress.has_flag(p_flag_name)


func is_step_read(p_step_uid: StringName) -> bool:
	return _progress.is_step_read(p_step_uid)


## 現在の論理進行と、表示中の立ち絵状態を保存用辞書へ変換する。
func get_progress() -> Dictionary:
	var result: Dictionary = _progress.to_dictionary()
	result["portrait_states"] = _get_portrait_states()
	return result


## 保存データを復元し、現在の Book があれば保存位置から再生する。
## 保存データの書き込み自体はゲーム側が担当する。
func restore_progress(p_data: Dictionary) -> void:
	if p_data == null:
		return
	_stop_playback()
	_progress.restore_from_dictionary(p_data)
	_restore_portrait_states(p_data.get("portrait_states", null))

	if _book == null:
		return
	var topic_id: StringName = _progress.get_topic_id()
	if String(topic_id).is_empty():
		return
	var topic: AdvTopic = _book.get_topic(topic_id)
	if topic == null:
		push_warning("AdvPlayer.restore_progress(): topic が見つかりません: %s" % topic_id)
		return
	var step_index: int = -1
	var step_uid: StringName = _progress.get_step_uid()
	if not String(step_uid).is_empty():
		var step: AdvStep = topic.find_step_by_uid(step_uid)
		if step == null:
			push_warning(
				"AdvPlayer.restore_progress(): step_uid が見つかりません: %s" % step_uid)
		else:
			step_index = step.step_index
	_start_topic(topic, topic_id, step_index - 1)


## 再生を中断する。走っている演出・音・Tween をすべて止める。
## シーン遷移や Stage の破棄はゲーム側が行う。
func stop() -> void:
	_stop_playback(true)


func _stop_playback(p_clear_backlog: bool = false) -> void:
	if _is_skipping:
		_stop_skip(&"user")
	if _auto_mode:
		set_auto_mode(false)
	_cancel_auto_wait()
	_run_id += 1
	_kill_typing_tween()
	_close_choice_menu()
	_is_backlog_open = false
	if backlog_view != null:
		backlog_view.close()
	if _context != null:
		_context.kill_all()
	if _audio != null:
		_audio.stop_all()
	if _voice != null:
		_voice.stop()
	_is_playing = false
	_is_typing = false
	_is_busy = false
	_typing_line = null
	_current_topic = null
	_current_topic_id = &""
	_step_cursor = -1
	_last_speaker_id = &""
	if p_clear_backlog:
		_backlog.clear()


func is_playing() -> bool:
	return _is_playing


func is_typing() -> bool:
	return _is_typing


## BLOCKING 演出の完了待ちなど、入力を受け付けない状態か。
func is_busy() -> bool:
	return _is_busy


func _process(p_delta: float) -> void:
	if not _is_skipping or not _is_playing or _is_backlog_open:
		return
	if _is_choice_open:
		if _skip_stops_at_choice():
			_stop_skip(&"choice")
		return
	if _is_busy:
		return
	_skip_accumulator += maxf(p_delta, 0.0)
	var interval: float = _skip_interval()
	if interval <= 0.0:
		_skip_accumulator = 0.0
		_process_skip_step()
		return
	var guard: int = 0
	while _is_skipping and _skip_accumulator >= interval and guard < 64:
		_skip_accumulator -= interval
		_process_skip_step()
		guard += 1
		if _is_busy or _is_choice_open or not _is_playing:
			return


func _skip_interval() -> float:
	if _settings == null:
		return 0.02
	return maxf(_settings.skip_interval, 0.0)


func _skip_stops_at_choice() -> bool:
	return _settings == null or _settings.skip_stops_at_choice


func _stop_skip(p_reason: StringName) -> void:
	if not _is_skipping:
		return
	_is_skipping = false
	_skip_accumulator = 0.0
	skip_stopped.emit(p_reason)


## 演出を追加・差し替えする（仕様書 §5.3 / §7）。
## 同じ id を登録すると組み込み演出を上書きできる。
func register_effect(p_effect_id: StringName, p_handler: AdvEffectHandler) -> void:
	if String(p_effect_id).is_empty() or p_handler == null:
		push_error("AdvPlayer.register_effect(): effect_id とハンドラは必須です")
		return
	p_handler.effect_id = p_effect_id
	_effects[p_effect_id] = p_handler


func get_effect_handler(p_effect_id: StringName) -> AdvEffectHandler:
	return _effects.get(p_effect_id, null)


## autoplay ガードを解除する（仕様書 §10）。
## 初回の advance() / skip_typing() でも自動的に解除されるが、
## ゲーム側がタイトル画面のクリックなど、より早いユーザー操作で解除してもよい。
func unlock_audio() -> void:
	if _audio_unlocked:
		return
	_audio_unlocked = true
	if _audio != null:
		_audio.set_audio_unlocked(true)
	if _voice != null:
		_voice.set_audio_unlocked(true)


func is_audio_unlocked() -> bool:
	return _audio_unlocked


## SE / BGM のチャンネル。ゲーム側がタイトル BGM などに使ってもよい。
func get_audio_director() -> AdvAudioDirector:
	return _audio


func get_voice_player() -> AdvVoicePlayer:
	return _voice


## 演出ハンドラへ渡している実行文脈。テストと拡張演出のデバッグ用。
func get_effect_context() -> AdvEffectContext:
	return _context


# --- 進行制御 ---------------------------------------------------------------

func _start_topic(
	p_topic: AdvTopic,
	p_topic_id: StringName,
	p_cursor: int,
	p_process_immediately: bool = true
) -> void:
	_current_topic = p_topic
	_current_topic_id = p_topic_id
	_step_cursor = p_cursor
	_last_speaker_id = &""
	_is_playing = true
	_is_busy = false
	_progress.set_position(p_topic_id, &"")
	topic_started.emit(_current_topic_id)
	if p_process_immediately:
		_process_next_step()

## 次に「入力待ちになる状態」まで進める。
## BLOCKING 演出に当たった場合はそこで await するため、この関数はコルーチンになる。
func _process_next_step() -> void:
	var run_id: int = _run_id
	while _is_playing and run_id == _run_id and not _is_backlog_open:
		if _voice != null:
			_voice.stop()
		_step_cursor += 1
		if _current_topic == null or _step_cursor >= _current_topic.steps.size():
			_finish_topic()
			return

		var step: AdvStep = _current_topic.steps[_step_cursor]
		if step == null:
			continue

		_progress.set_position(_current_topic_id, step.uid)
		step_shown.emit(_current_topic_id, step.uid)
		_start_parallel_effects(step)

		if step is AdvLineStep:
			_show_line(step as AdvLineStep)
			return

		var effect: AdvEffectStep = step as AdvEffectStep
		if effect != null:
			if effect.is_parallel():
				# 畳み込み漏れ。起動だけして次へ進む（検証は dangling_parallel の担当）。
				_play_effect(effect)
				continue
			_is_busy = true
			await _play_effect(effect)
			_is_busy = false
			if not _is_playing or run_id != _run_id:
				return
			if effect.auto_advance:
				continue
			return

		var choice: AdvChoiceStep = step as AdvChoiceStep
		if choice != null:
			_present_choice(choice)
			return

		var jump: AdvJumpStep = step as AdvJumpStep
		if jump != null:
			if not AdvCondition.evaluate(jump.condition, _progress.get_flags()):
				continue
			if String(jump.goto).is_empty():
				_finish_topic()
				return
			_transition_to_topic(jump.goto)
			return

		_warn_unimplemented_step(step)


## スキップ中に 1 ステップだけ処理する。演出は apply_final() へ置き換える。
func _process_skip_step() -> void:
	if not _is_skipping or not _is_playing or _is_busy or _is_choice_open:
		return
	if _is_typing:
		_complete_typing()
		return
	if _voice != null:
		_voice.stop()
	_step_cursor += 1
	if _current_topic == null or _step_cursor >= _current_topic.steps.size():
		_finish_topic()
		return

	var step: AdvStep = _current_topic.steps[_step_cursor]
	if step == null:
		return
	_progress.set_position(_current_topic_id, step.uid)
	step_shown.emit(_current_topic_id, step.uid)

	# 既読連動が有効なときは未読 line を表示した時点でスキップを解除する。
	var line: AdvLineStep = step as AdvLineStep
	if line != null and not _skip_unread() and not _progress.is_step_read(line.uid):
		_stop_skip(&"unread")
		_start_parallel_effects(step)
		_show_line(line)
		return

	_start_parallel_effects(step)
	if line != null:
		_show_line(line, true)
		return

	var effect: AdvEffectStep = step as AdvEffectStep
	if effect != null:
		_apply_effect_final(effect)
		return

	var choice: AdvChoiceStep = step as AdvChoiceStep
	if choice != null:
		_present_choice(choice)
		return

	var jump: AdvJumpStep = step as AdvJumpStep
	if jump != null:
		if not AdvCondition.evaluate(jump.condition, _progress.get_flags()):
			return
		if String(jump.goto).is_empty():
			_finish_topic()
			return
		_transition_to_topic(jump.goto)
		return

	_warn_unimplemented_step(step)


func _skip_unread() -> bool:
	return _settings != null and _settings.skip_unread


func _show_line(p_line: AdvLineStep, p_skipping: bool = false) -> void:
	var speaker_name: String = ""
	var name_color: Color = Color.WHITE
	var character: AdvCharacter = null
	if not p_line.is_narration() and _book != null:
		character = _book.get_character(p_line.speaker_id)
		if character == null:
			push_warning("AdvPlayer: speaker が見つかりません: %s" % p_line.speaker_id)
		else:
			speaker_name = character.display_name
			name_color = character.name_color

	if character != null:
		var pose: StringName = _resolve_pose(character, p_line.pose)
		var expression: StringName = _resolve_expression(character, p_line.expression)
		var slot: StringName = _resolve_slot(p_line.speaker_id, p_line.slot)
		_current_poses[p_line.speaker_id] = pose
		_current_expressions[p_line.speaker_id] = expression
		_current_slots[p_line.speaker_id] = slot
		if stage != null:
			if stage.has_character(p_line.speaker_id):
				stage.update_character(character, pose, expression, slot)
			else:
				# 暗黙の登場（仕様書 §7）。alpha 0->1 を dim_duration と同じ時間で。
				stage.show_character(
					character, pose, expression, slot, _implicit_show_duration())

		_apply_speaker_direction(p_line.speaker_id)

	if _voice != null and not p_skipping:
		_voice.play_voice(p_line.voice_path)

	if message_window != null:
		message_window.show_line(speaker_name, name_color, p_line.text)

	_typing_topic_id = _current_topic_id
	_typing_step_uid = p_line.uid
	_typing_line = p_line
	_begin_typing(p_line.text, p_skipping)


func _present_choice(p_choice: AdvChoiceStep) -> void:
	var visible_options: Array[Dictionary] = []
	for option: Dictionary in p_choice.options:
		var condition: String = str(option.get(AdvChoiceStep.KEY_CONDITION, ""))
		if not AdvCondition.evaluate(condition, _progress.get_flags()):
			continue
		visible_options.append(option.duplicate(true))

	_choice_options = visible_options
	_choice_topic_id = _current_topic_id
	_choice_step_uid = p_choice.uid
	_is_choice_open = true
	_is_busy = true
	if choice_menu != null:
		choice_menu.present(p_choice.prompt, visible_options)
	else:
		push_warning("AdvPlayer: choice_menu が未接続です。choose_option() または signal を使ってください")
	choice_presented.emit(visible_options)

	# 条件で全選択肢が隠れた場合でも、プレイを停止させない。
	if visible_options.is_empty():
		push_warning("AdvPlayer: 表示可能な選択肢がありません。choice を素通りします")
		_close_choice_menu()
		_is_busy = false
		_process_next_step()


func _on_option_chosen(p_index: int) -> void:
	if not _is_choice_open or p_index < 0 or p_index >= _choice_options.size():
		return
	if _choice_topic_id != _current_topic_id or _choice_step_uid != _progress.get_step_uid():
		return
	unlock_audio()
	var option: Dictionary = _choice_options[p_index]
	var goto: StringName = StringName(str(option.get(AdvChoiceStep.KEY_GOTO, "")))
	var flag_name: String = str(option.get(AdvChoiceStep.KEY_FLAG, ""))
	_close_choice_menu()
	_is_busy = false
	if not flag_name.strip_edges().is_empty():
		set_flag(flag_name, true)
	choice_selected.emit(p_index, option)
	if not String(goto).is_empty():
		_transition_to_topic(goto)
		return
	if _is_skipping:
		return
	_process_next_step()


func _transition_to_topic(p_topic_id: StringName) -> void:
	if _book == null:
		_finish_topic()
		return
	var topic: AdvTopic = _book.get_topic(p_topic_id)
	if topic == null:
		push_warning("AdvPlayer: goto の topic が見つかりません: %s" % p_topic_id)
		_finish_topic()
		return
	_finish_topic(false)
	_start_topic(topic, p_topic_id, -1, not _is_skipping)


## このステップに畳み込まれた PARALLEL 演出を一斉に起動する。完了は待たない。
func _start_parallel_effects(p_step: AdvStep) -> void:
	for entry: AdvStep in p_step.parallel_effects:
		var effect: AdvEffectStep = entry as AdvEffectStep
		if effect == null:
			continue
		if _is_skipping:
			_apply_effect_final(effect)
		else:
			_play_effect(effect)


## 演出を1つ再生する。await すれば完了まで待てる。
func _play_effect(p_effect: AdvEffectStep) -> void:
	var handler: AdvEffectHandler = _effects.get(p_effect.effect_id, null)
	if handler == null:
		push_warning(
			"AdvPlayer: 未登録の effect_id \"%s\" は再生されません。"
			% p_effect.effect_id
			+ "ゲーム側の拡張演出なら register_effect() で登録してください")
		return
	if _context == null:
		_build_context()
	await handler.play(_context, p_effect.params)


func _apply_effect_final(p_effect: AdvEffectStep) -> void:
	var handler: AdvEffectHandler = _effects.get(p_effect.effect_id, null)
	if handler == null:
		return
	if _context == null:
		_build_context()
	handler.apply_final(_context, p_effect.params)


func _implicit_show_duration() -> float:
	if _settings == null:
		return 0.0
	return maxf(_settings.dim_duration, 0.0)


## 話者交代時の非話者ダークと話者交代ホップを開始する。
## どちらも入力を待たせず、Tween は既存の排他台帳へ登録する。
func _apply_speaker_direction(p_speaker_id: StringName) -> void:
	if String(p_speaker_id).is_empty():
		# 地の文は直前話者の明暗状態を維持する。
		return
	var speaker_changed: bool = p_speaker_id != _last_speaker_id
	_last_speaker_id = p_speaker_id
	if not speaker_changed or stage == null:
		return
	var speaker_portrait: AdvPortrait = stage.get_portrait(p_speaker_id)
	if speaker_portrait == null:
		# unknown_speaker 等の不正データでも進行は止めない。
		return

	if _settings != null and _settings.dim_non_speakers:
		_apply_dim_to_portraits(p_speaker_id)
	if _settings != null and _settings.hop_on_speaker_change:
		_start_speaker_hop(p_speaker_id, speaker_portrait)


func _apply_dim_to_portraits(p_speaker_id: StringName) -> void:
	if _context == null or stage == null:
		return
	var dim_color: Color = Color(0.55, 0.55, 0.6)
	var duration: float = 0.15
	if _settings != null:
		dim_color = _settings.dim_color
		duration = maxf(_settings.dim_duration, 0.0)
	for character_id: StringName in stage.get_character_ids():
		var portrait: AdvPortrait = stage.get_portrait(character_id)
		if portrait == null:
			continue
		var target_color: Color = Color.WHITE if character_id == p_speaker_id else dim_color
		_start_modulate_tween(character_id, portrait, target_color, duration)


func _start_modulate_tween(
	p_character_id: StringName,
	p_portrait: AdvPortrait,
	p_target_color: Color,
	p_duration: float
) -> void:
	var target_name: String = "portrait_modulate:%s" % p_character_id
	var targets := PackedStringArray([target_name])
	var finalizer: Callable = func() -> void:
		if is_instance_valid(p_portrait):
			p_portrait.set_modulate_rgb(p_target_color)
	if p_duration <= 0.0:
		_context.kill_targets(targets)
		p_portrait.set_modulate_rgb(p_target_color)
		return
	var tween: Tween = _context.acquire_tween(targets, finalizer)
	if tween == null:
		p_portrait.set_modulate_rgb(p_target_color)
		return
	var start_color: Color = Color(
		p_portrait.modulate.r, p_portrait.modulate.g, p_portrait.modulate.b, 1.0)
	var target_color: Color = Color(
		p_target_color.r, p_target_color.g, p_target_color.b, 1.0)
	tween.tween_method(
		Callable(p_portrait, "set_modulate_rgb"), start_color, target_color, p_duration)


func _start_speaker_hop(p_speaker_id: StringName, p_portrait: AdvPortrait) -> void:
	if _context == null or stage == null:
		return
	var duration: float = 0.22
	var height: float = 18.0
	if _settings != null:
		duration = maxf(_settings.hop_duration, 0.0)
		height = maxf(_settings.hop_height, 0.0)
	var resting_position: Vector2 = stage.get_portrait_position_for(
		p_speaker_id, stage.get_character_slot(p_speaker_id))
	if duration <= 0.0 or height <= 0.0:
		_context.kill_targets(PackedStringArray(["portrait_position:%s" % p_speaker_id]))
		p_portrait.position = resting_position
		return

	var targets := PackedStringArray(["portrait_position:%s" % p_speaker_id])
	var finalizer: Callable = func() -> void:
		if is_instance_valid(p_portrait):
			p_portrait.position = resting_position
	var tween: Tween = _context.acquire_tween(targets, finalizer)
	if tween == null:
		p_portrait.position = resting_position
		return
	var half_duration: float = duration * 0.5
	var hop_position: Vector2 = resting_position - Vector2(0.0, height)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(p_portrait, "position", hop_position, half_duration)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(p_portrait, "position", resting_position, half_duration)


func _begin_typing(p_text: String, p_skipping: bool = false) -> void:
	_is_typing = true
	if message_window != null:
		message_window.set_typing_progress(0.0)
	if p_skipping:
		_complete_typing()
		return

	var typing_speed: float = 0.0
	if _settings != null:
		typing_speed = maxf(_settings.typing_speed, 0.0)
	var display_count: int = _display_character_count(p_text)
	if typing_speed <= 0.0 or display_count <= 0 or not is_inside_tree():
		_complete_typing()
		return

	var duration: float = float(display_count) / typing_speed
	_typing_tween = create_tween()
	_typing_tween.tween_method(
		Callable(self, "_set_typing_progress"), 0.0, 1.0, duration)
	_typing_tween.finished.connect(_on_typing_tween_finished)


func _set_typing_progress(p_ratio: float) -> void:
	if not _is_typing:
		return
	if message_window != null:
		message_window.set_typing_progress(clampf(p_ratio, 0.0, 1.0))


func _on_typing_tween_finished() -> void:
	if _is_typing:
		_complete_typing()


func _complete_typing() -> void:
	if not _is_typing:
		return
	_is_typing = false
	_kill_typing_tween()
	if message_window != null:
		message_window.complete_typing()
	_progress.mark_step_read(_typing_step_uid)
	_append_backlog(_typing_line)
	line_completed.emit(_typing_topic_id, _typing_step_uid)
	_typing_line = null
	if _is_playing and _auto_mode and not _is_skipping and not _is_backlog_open:
		_schedule_auto_advance()


func _append_backlog(p_line: AdvLineStep) -> void:
	if p_line == null:
		return
	var speaker_name: String = ""
	var name_color: Color = Color.WHITE
	if _book != null and not p_line.is_narration():
		var character: AdvCharacter = _book.get_character(p_line.speaker_id)
		if character != null:
			speaker_name = character.display_name
			name_color = character.name_color
	var entry := AdvBacklogEntry.new(
		p_line.uid,
		speaker_name,
		name_color,
		p_line.text,
		p_line.voice_path)
	_backlog.append(entry)
	if _backlog.get_max_entries() > 0:
		backlog_appended.emit(entry)


func _schedule_auto_advance() -> void:
	if not _auto_mode or not _is_playing or _is_typing or _is_busy:
		return
	if _is_backlog_open or _is_choice_open or _is_skipping:
		return
	_auto_wait_token += 1
	var wait_token: int = _auto_wait_token
	var wait_time: float = 0.0
	if _settings != null:
		wait_time = maxf(_settings.auto_wait_time, 0.0)
		if _settings.auto_wait_for_voice and _voice != null:
			wait_time = maxf(wait_time, _voice.get_remaining_time())
	_wait_auto_advance(wait_token, wait_time)


func _wait_auto_advance(p_wait_token: int, p_wait_time: float) -> void:
	if p_wait_time > 0.0 and is_inside_tree():
		await get_tree().create_timer(p_wait_time).timeout
	else:
		await get_tree().process_frame
	if p_wait_token != _auto_wait_token:
		return
	if not _auto_mode or not _is_playing or _is_typing or _is_busy:
		return
	if _is_backlog_open or _is_choice_open or _is_skipping:
		return
	_process_next_step()


func _cancel_auto_wait() -> void:
	_auto_wait_token += 1


func _kill_typing_tween() -> void:
	if _typing_tween != null and is_instance_valid(_typing_tween):
		_typing_tween.kill()
	_typing_tween = null


func _finish_topic(p_emit_scenario_finished: bool = true) -> void:
	if not _is_playing:
		return
	if p_emit_scenario_finished:
		_stop_skip(&"finished")
		if _auto_mode:
			set_auto_mode(false)
	var finished_topic_id: StringName = _current_topic_id
	_is_playing = false
	_is_typing = false
	_is_busy = false
	_typing_line = null
	_close_choice_menu()
	_kill_typing_tween()
	_current_topic = null
	_current_topic_id = &""
	_step_cursor = -1
	if _voice != null:
		_voice.stop()
	if message_window != null:
		message_window.clear()
	topic_finished.emit(finished_topic_id)
	if p_emit_scenario_finished:
		scenario_finished.emit()


func _warn_unimplemented_step(p_step: AdvStep) -> void:
	var suffix: String = ""
	if not p_step.parallel_effects.is_empty():
		suffix = "。parallel_effects は再生済み"
	push_warning(
		"AdvPlayer: 未対応のステップ %s を素通りします%s" % [
			p_step.describe(), suffix])


# --- 演出の登録と文脈 -------------------------------------------------------

## 仕様書 §7 の 9 演出。既に登録済みの id は上書きしない（ゲーム側の差し替えを尊重する）。
func _register_builtin_effects() -> void:
	_register_if_absent(&"shake", AdvShakeEffect.new())
	_register_if_absent(&"fade_out", AdvFadeEffect.new())
	_register_if_absent(&"fade_in", AdvFadeEffect.new())
	_register_if_absent(&"show_portrait", AdvPortraitEffect.new())
	_register_if_absent(&"hide_portrait", AdvPortraitEffect.new())
	_register_if_absent(&"move_portrait", AdvPortraitEffect.new())
	_register_if_absent(&"play_se", AdvAudioEffect.new())
	_register_if_absent(&"play_bgm", AdvAudioEffect.new())
	_register_if_absent(&"stop_bgm", AdvAudioEffect.new())


func _register_if_absent(p_effect_id: StringName, p_handler: AdvEffectHandler) -> void:
	if _effects.has(p_effect_id):
		return
	register_effect(p_effect_id, p_handler)


func _build_context() -> void:
	if _context != null:
		_context.kill_all()
	_context = AdvEffectContext.new()
	_context.host = self
	_context.stage = stage
	_context.shake_root = shake_root
	_context.fade_layer = fade_layer
	_context.book = _book
	_context.settings = _settings
	_context.audio = _audio
	_context.voice = _voice
	if shake_root == null:
		push_warning("AdvPlayer: shake_root が未接続です。shake 演出は無効になります")
	if fade_layer == null:
		push_warning("AdvPlayer: fade_layer が未接続です。fade 演出は無効になります")


# --- 立ち絵を含む進行データ -----------------------------------------------

func _get_portrait_states() -> Dictionary:
	var result: Dictionary = {}
	if stage == null:
		return result
	for character_id: StringName in stage.get_character_ids():
		var portrait: AdvPortrait = stage.get_portrait(character_id)
		if portrait == null:
			continue
		result[String(character_id)] = {
			"pose": String(stage.get_character_pose(character_id)),
			"expression": String(stage.get_character_expression(character_id)),
			"slot": String(stage.get_character_slot(character_id)),
			"modulate": [
				portrait.modulate.r,
				portrait.modulate.g,
				portrait.modulate.b,
				portrait.modulate.a,
			],
		}
	return result


func _restore_portrait_states(p_raw_states: Variant) -> void:
	if not (p_raw_states is Dictionary) or stage == null or _book == null:
		return
	var states: Dictionary = p_raw_states as Dictionary
	stage.clear()
	_current_poses.clear()
	_current_expressions.clear()
	_current_slots.clear()
	for raw_id: Variant in states.keys():
		var character_id: StringName = StringName(str(raw_id))
		var character: AdvCharacter = _book.get_character(character_id)
		if character == null:
			push_warning(
				"AdvPlayer.restore_progress(): portrait の character が見つかりません: %s" %
				character_id)
			continue
		var raw_state: Variant = states[raw_id]
		if not (raw_state is Dictionary):
			continue
		var state: Dictionary = raw_state as Dictionary
		var pose: StringName = StringName(str(state.get("pose", "")))
		var expression: StringName = StringName(str(state.get("expression", "")))
		var slot: StringName = StringName(str(state.get("slot", "center")))
		_current_poses[character_id] = pose
		_current_expressions[character_id] = expression
		_current_slots[character_id] = slot
		stage.show_character(character, pose, expression, slot, 0.0)
		var portrait: AdvPortrait = stage.get_portrait(character_id)
		if portrait == null:
			continue
		var raw_modulate: Variant = state.get("modulate", null)
		if raw_modulate is Array and (raw_modulate as Array).size() >= 4:
			var modulate_values: Array = raw_modulate as Array
			portrait.modulate = Color(
				float(modulate_values[0]),
				float(modulate_values[1]),
				float(modulate_values[2]),
				float(modulate_values[3]))


## 音声ノードは AdvPlayer 自身の子として持つ。
## AdvScene.tscn に置かないのは、ゲーム側が独自のシーン構成を組んでも音が鳴るようにするため。
func _ensure_audio_nodes() -> void:
	if _audio == null or not is_instance_valid(_audio):
		_audio = AdvAudioDirector.new()
		_audio.name = "AdvAudioDirector"
		add_child(_audio)
	if _voice == null or not is_instance_valid(_voice):
		_voice = AdvVoicePlayer.new()
		_voice.name = "AdvVoicePlayer"
		add_child(_voice)
	_audio.set_audio_unlocked(_audio_unlocked)
	_voice.set_audio_unlocked(_audio_unlocked)


# --- 立ち絵指定の引き継ぎ ---------------------------------------------------

func _resolve_pose(p_character: AdvCharacter, p_requested: StringName) -> StringName:
	if not String(p_requested).is_empty():
		return p_requested
	if _current_poses.has(p_character.id):
		return _current_poses[p_character.id]
	if p_character.portrait_set != null:
		return p_character.portrait_set.default_pose
	return &""


func _resolve_expression(p_character: AdvCharacter, p_requested: StringName) -> StringName:
	if not String(p_requested).is_empty():
		return p_requested
	if _current_expressions.has(p_character.id):
		return _current_expressions[p_character.id]
	if p_character.portrait_set != null:
		return p_character.portrait_set.default_expression
	return &""


func _resolve_slot(p_character_id: StringName, p_requested: StringName) -> StringName:
	if not String(p_requested).is_empty():
		return p_requested
	if _current_slots.has(p_character_id):
		return _current_slots[p_character_id]
	if stage != null and stage.has_character(p_character_id):
		return stage.get_character_slot(p_character_id)
	return &"center"


# --- 入力 -------------------------------------------------------------------

func _connect_message_window() -> void:
	if message_window == null:
		return
	if not message_window.advance_requested.is_connected(_on_advance_requested):
		message_window.advance_requested.connect(_on_advance_requested)
	if not message_window.skip_typing_requested.is_connected(_on_skip_typing_requested):
		message_window.skip_typing_requested.connect(_on_skip_typing_requested)


func _connect_choice_menu() -> void:
	if choice_menu == null:
		return
	if not choice_menu.option_chosen.is_connected(_on_option_chosen):
		choice_menu.option_chosen.connect(_on_option_chosen)


func _connect_backlog_view() -> void:
	if backlog_view == null:
		return
	if not backlog_view.closed.is_connected(_on_backlog_closed):
		backlog_view.closed.connect(_on_backlog_closed)
	if not backlog_view.voice_replay_requested.is_connected(
		_on_backlog_voice_replay_requested):
		backlog_view.voice_replay_requested.connect(_on_backlog_voice_replay_requested)


func _close_choice_menu() -> void:
	if choice_menu != null and _is_choice_open:
		choice_menu.close()
	_is_choice_open = false
	_choice_options.clear()
	_choice_topic_id = &""
	_choice_step_uid = &""


func _on_advance_requested() -> void:
	advance()


func _on_skip_typing_requested() -> void:
	skip_typing()


func _on_backlog_closed() -> void:
	close_backlog()


func _on_backlog_voice_replay_requested(p_entry: AdvBacklogEntry) -> void:
	replay_voice(p_entry)


func _unhandled_input(p_event: InputEvent) -> void:
	if not _is_playing or _settings == null:
		return
	if p_event.is_action_released(_settings.skip_action):
		stop_skip()
		get_viewport().set_input_as_handled()
		return
	if p_event.is_action_pressed(_settings.skip_action):
		start_skip()
		get_viewport().set_input_as_handled()
		return
	if p_event.is_action_pressed(_settings.auto_action):
		set_auto_mode(not _auto_mode)
		get_viewport().set_input_as_handled()
		return
	if p_event.is_action_pressed(_settings.backlog_action):
		if _is_backlog_open:
			close_backlog()
		else:
			open_backlog()
		get_viewport().set_input_as_handled()
		return
	if p_event.is_action_pressed(_settings.advance_action):
		advance()
		get_viewport().set_input_as_handled()


static func _display_character_count(p_text: String) -> int:
	var regex := RegEx.new()
	var compile_error: Error = regex.compile("\\[/?[^\\]]+\\]")
	if compile_error != OK:
		return p_text.length()
	return regex.sub(p_text, "", true).length()
