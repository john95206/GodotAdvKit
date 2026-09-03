class_name AdvPlayer
extends Node
## シナリオの最小再生制御（phase-02）。
##
## このフェーズでは line の表示と送りだけを扱う。演出・選択肢・話題遷移・
## ボイスなどの非 line ステップは警告を出して素通りし、後続フェーズで置き換える。

@export var stage: AdvStage
@export var message_window: AdvMessageWindow

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
var _typing_tween: Tween = null
var _typing_topic_id: StringName = &""
var _typing_step_uid: StringName = &""

## キャラクターごとの直近の表示状態。空の指定を次の行へ引き継ぐ。
var _current_poses: Dictionary[StringName, StringName] = {}
var _current_expressions: Dictionary[StringName, StringName] = {}
var _current_slots: Dictionary[StringName, StringName] = {}


func _ready() -> void:
	_connect_message_window()


## Book と再生設定を差し替え、表示状態を初期化する。
func setup(p_book: AdvScenarioBook, p_settings: AdvKitSettings) -> void:
	stop()
	_book = p_book
	_settings = p_settings if p_settings != null else AdvKitSettings.new()
	_current_poses.clear()
	_current_expressions.clear()
	_current_slots.clear()
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
func advance() -> void:
	if not _is_playing:
		return
	if _is_typing:
		skip_typing()
		return
	_process_next_step()


## 現在のタイプライタ表示を即時完了する。
func skip_typing() -> void:
	if not _is_typing:
		return
	_complete_typing()


## 再生を中断する。シーン遷移や Stage の破棄はゲーム側が行う。
func stop() -> void:
	_kill_typing_tween()
	_is_playing = false
	_is_typing = false
	_current_topic = null
	_current_topic_id = &""
	_step_cursor = -1


func is_playing() -> bool:
	return _is_playing


func is_typing() -> bool:
	return _is_typing


func _process_next_step() -> void:
	while _is_playing:
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
		_warn_unimplemented_step(step)
		# phase-02 では非 line ステップを消費して次へ進む。


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
				stage.show_character(character, pose, expression, slot, 0.0)

	if message_window != null:
		message_window.show_line(speaker_name, name_color, p_line.text)
	if not p_line.parallel_effects.is_empty():
		push_warning(
			"AdvPlayer: line の parallel_effects は phase-02 では素通りします（phase-03 で実装予定）")

	_typing_topic_id = _current_topic_id
	_typing_step_uid = p_line.uid
	step_shown.emit(_current_topic_id, p_line.uid)
	_begin_typing(p_line.text)


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
	_kill_typing_tween()
	_current_topic = null
	_current_topic_id = &""
	_step_cursor = -1
	if message_window != null:
		message_window.clear()
	topic_finished.emit(finished_topic_id)
	scenario_finished.emit()


func _warn_unimplemented_step(p_step: AdvStep) -> void:
	var phase_name: String = "phase-03"
	if p_step is AdvChoiceStep or p_step is AdvJumpStep:
		phase_name = "phase-05"
	var suffix: String = ""
	if not p_step.parallel_effects.is_empty():
		suffix = "。parallel_effects も無視します"
	push_warning(
		"AdvPlayer: %s は phase-02 では素通りします%s（%s で実装予定）" % [
			p_step.describe(), suffix, phase_name])


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
	return &"center"


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
