class_name AdvPlayer
extends Node
## シナリオの再生制御（phase-03）。
##
## 扱うのは line の表示・送りと、[b]局所演出（§7）とボイス（§9.4）[/b]。
## 選択肢・話題遷移・フラグ（phase-05）、オート／スキップ／バックログ（phase-06）は
## まだ持たない。該当ステップは警告を出して素通りする。

@export var stage: AdvStage
@export var message_window: AdvMessageWindow
## 画面揺れの対象（仕様書 §5.1）。未接続でも shake が無効になるだけで進行は止まらない。
@export var shake_root: Control
## フェード用の最前面レイヤ。未接続でも fade が無効になるだけ。
@export var fade_layer: ColorRect

signal topic_started(topic_id: StringName)
signal topic_finished(topic_id: StringName)
signal step_shown(topic_id: StringName, step_uid: StringName)
signal line_completed(topic_id: StringName, step_uid: StringName)
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


func _ready() -> void:
	_ensure_audio_nodes()
	_connect_message_window()


## Book と再生設定を差し替え、表示状態を初期化する。
## 組み込み演出（§7 の 9 種）は未登録ならここで登録する。
func setup(p_book: AdvScenarioBook, p_settings: AdvKitSettings) -> void:
	stop()
	_book = p_book
	_settings = p_settings if p_settings != null else AdvKitSettings.new()
	_current_poses.clear()
	_current_expressions.clear()
	_current_slots.clear()
	_ensure_audio_nodes()
	_register_builtin_effects()
	_build_context()
	_voice.setup(_settings.voice_bus)
	_connect_message_window()
	if stage != null:
		stage.clear()
	if message_window != null:
		message_window.clear()


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
	_current_topic = topic
	_current_topic_id = p_topic_id
	_step_cursor = -1
	_is_playing = true
	topic_started.emit(_current_topic_id)
	_process_next_step()


## 表示中なら全文を表示し、表示済みなら次のステップへ進む。
## [b]BLOCKING 演出の実行中は受け付けない。[/b]
func advance() -> void:
	unlock_audio()
	if not _is_playing or _is_busy:
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


## 再生を中断する。走っている演出・音・Tween をすべて止める。
## シーン遷移や Stage の破棄はゲーム側が行う。
func stop() -> void:
	_run_id += 1
	_kill_typing_tween()
	if _context != null:
		_context.kill_all()
	if _audio != null:
		_audio.stop_all()
	if _voice != null:
		_voice.stop()
	_is_playing = false
	_is_typing = false
	_is_busy = false
	_current_topic = null
	_current_topic_id = &""
	_step_cursor = -1


func is_playing() -> bool:
	return _is_playing


func is_typing() -> bool:
	return _is_typing


## BLOCKING 演出の完了待ちなど、入力を受け付けない状態か。
func is_busy() -> bool:
	return _is_busy


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

## 次に「入力待ちになる状態」まで進める。
## BLOCKING 演出に当たった場合はそこで await するため、この関数はコルーチンになる。
func _process_next_step() -> void:
	var run_id: int = _run_id
	while _is_playing and run_id == _run_id:
		if _voice != null:
			_voice.stop()
		_step_cursor += 1
		if _current_topic == null or _step_cursor >= _current_topic.steps.size():
			_finish_topic()
			return

		var step: AdvStep = _current_topic.steps[_step_cursor]
		if step == null:
			continue

		if step is AdvLineStep:
			_show_line(step as AdvLineStep)
			return

		step_shown.emit(_current_topic_id, step.uid)

		var effect: AdvEffectStep = step as AdvEffectStep
		if effect != null:
			_start_parallel_effects(effect)
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

		_warn_unimplemented_step(step)


func _show_line(p_line: AdvLineStep) -> void:
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

	# PARALLEL 演出は本文と同時に走り出す。完了は待たない（仕様書 §4.3）。
	_start_parallel_effects(p_line)

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

	if _voice != null:
		_voice.play_voice(p_line.voice_path)

	if message_window != null:
		message_window.show_line(speaker_name, name_color, p_line.text)

	_typing_topic_id = _current_topic_id
	_typing_step_uid = p_line.uid
	step_shown.emit(_current_topic_id, p_line.uid)
	_begin_typing(p_line.text)


## このステップに畳み込まれた PARALLEL 演出を一斉に起動する。完了は待たない。
func _start_parallel_effects(p_step: AdvStep) -> void:
	for entry: AdvStep in p_step.parallel_effects:
		var effect: AdvEffectStep = entry as AdvEffectStep
		if effect == null:
			continue
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


func _implicit_show_duration() -> float:
	if _settings == null:
		return 0.0
	return maxf(_settings.dim_duration, 0.0)


func _begin_typing(p_text: String) -> void:
	_is_typing = true
	if message_window != null:
		message_window.set_typing_progress(0.0)

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
	line_completed.emit(_typing_topic_id, _typing_step_uid)


func _kill_typing_tween() -> void:
	if _typing_tween != null and is_instance_valid(_typing_tween):
		_typing_tween.kill()
	_typing_tween = null


func _finish_topic() -> void:
	if not _is_playing:
		return
	var finished_topic_id: StringName = _current_topic_id
	_is_playing = false
	_is_typing = false
	_is_busy = false
	_kill_typing_tween()
	_current_topic = null
	_current_topic_id = &""
	_step_cursor = -1
	if _voice != null:
		_voice.stop()
	if message_window != null:
		message_window.clear()
	topic_finished.emit(finished_topic_id)
	scenario_finished.emit()


func _warn_unimplemented_step(p_step: AdvStep) -> void:
	var suffix: String = ""
	if not p_step.parallel_effects.is_empty():
		suffix = "。parallel_effects は再生済み"
	push_warning(
		"AdvPlayer: %s は phase-03 では素通りします%s（phase-05 で実装予定）" % [
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


func _on_advance_requested() -> void:
	advance()


func _on_skip_typing_requested() -> void:
	skip_typing()


func _unhandled_input(p_event: InputEvent) -> void:
	if not _is_playing or _settings == null:
		return
	# phase-03 時点では skip_action を「タイプライタ即時完了」に割り当てている。
	# 本来のスキップ（既読連動）は phase-06 で差し替える。
	if p_event.is_action_pressed(_settings.skip_action):
		skip_typing()
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
