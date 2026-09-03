@tool
extends EditorPlugin
## ADV Kit のエディタプラグインエントリ。
##
## phase-01 で行うのは ProjectSettings への出力先登録だけ。
## InputMap の自動登録（仕様書 §4.6）は、実際に入力を使う phase-02 で追加する。

const OUTPUT_DIR_SETTING := "adv_kit/import/output_dir"
const OUTPUT_DIR_DEFAULT := "res://game/resources/adv/scenario/"
const INPUT_SETTING_PREFIX := "input/"
const INPUT_DEADZONE := 0.5


func _enter_tree() -> void:
	_register_input_actions()
	if not ProjectSettings.has_setting(OUTPUT_DIR_SETTING):
		ProjectSettings.set_setting(OUTPUT_DIR_SETTING, OUTPUT_DIR_DEFAULT)
	# 既存値は上書きしない。既定値と型情報だけを毎回登録し直す。
	ProjectSettings.set_initial_value(OUTPUT_DIR_SETTING, OUTPUT_DIR_DEFAULT)
	ProjectSettings.add_property_info({
		"name": OUTPUT_DIR_SETTING,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_DIR,
		"hint_string": "",
	})
	ProjectSettings.set_as_basic(OUTPUT_DIR_SETTING, true)
	var err: int = ProjectSettings.save()
	if err != OK:
		push_warning("ADV Kit: ProjectSettings の保存に失敗しました (error %d)" % err)


## 入力アクションはアドオンを有効化したプロジェクトにだけ追加する。
## 既存アクションはゲーム側が調整した設定を尊重して一切変更しない。
func _register_input_actions() -> void:
	_register_input_action(&"adv_advance", _make_advance_events())
	_register_input_action(&"adv_skip", _make_key_events([KEY_CTRL]))
	_register_input_action(&"adv_auto", _make_key_events([KEY_A]))
	_register_input_action(&"adv_backlog", _make_backlog_events())


func _register_input_action(p_action: StringName, p_events: Array[InputEvent]) -> void:
	if InputMap.has_action(p_action):
		return
	InputMap.add_action(p_action)
	for event: InputEvent in p_events:
		InputMap.action_add_event(p_action, event)
	# InputMap のランタイム状態だけでは project.godot に保存されないため、
	# エディタで有効化した結果を次回起動にも引き継げるよう設定も登録する。
	ProjectSettings.set_setting(INPUT_SETTING_PREFIX + String(p_action), {
		"deadzone": INPUT_DEADZONE,
		"events": p_events,
	})


func _make_advance_events() -> Array[InputEvent]:
	var events: Array[InputEvent] = []
	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = MOUSE_BUTTON_LEFT
	mouse_event.pressed = true
	events.append(mouse_event)
	events.append_array(_make_key_events([KEY_ENTER, KEY_SPACE]))
	return events


func _make_backlog_events() -> Array[InputEvent]:
	var events: Array[InputEvent] = []
	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = MOUSE_BUTTON_WHEEL_UP
	mouse_event.pressed = true
	events.append(mouse_event)
	events.append_array(_make_key_events([KEY_B]))
	return events


func _make_key_events(p_keycodes: Array[int]) -> Array[InputEvent]:
	var events: Array[InputEvent] = []
	for keycode: int in p_keycodes:
		var key_event := InputEventKey.new()
		key_event.keycode = keycode
		key_event.pressed = true
		events.append(key_event)
	return events


func _exit_tree() -> void:
	# プラグインを無効化しても設定は消さない。
	# 出力先はプロジェクトの設定であって、プラグインの内部状態ではないため。
	pass
