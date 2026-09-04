@tool
extends EditorPlugin
## ADV Kit のエディタプラグインエントリ。
##
## 行うこと:
## [br]・ProjectSettings への出力先登録（phase-01）
## [br]・InputMap の自動登録（phase-02。仕様書 §4.6）
## [br]・シナリオインポータの右ドック追加（phase-07。仕様書 §6.4）

const OUTPUT_DIR_SETTING := "adv_kit/import/output_dir"
const OUTPUT_DIR_DEFAULT := "res://game/resources/adv/scenario/"
const INPUT_SETTING_PREFIX := "input/"
const INPUT_DEADZONE := 0.5
const IMPORT_DOCK_SCENE := "res://addons/adv_kit/editor/adv_import_dock.tscn"

var _import_dock: Control = null


func _enter_tree() -> void:
	_register_input_actions()
	_add_import_dock()
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


## シナリオインポータのドックを右上に追加する（仕様書 §6.4）。
func _add_import_dock() -> void:
	if _import_dock != null:
		return
	if not ResourceLoader.exists(IMPORT_DOCK_SCENE):
		push_warning("ADV Kit: %s が見つかりません" % IMPORT_DOCK_SCENE)
		return
	var scene := load(IMPORT_DOCK_SCENE) as PackedScene
	if scene == null:
		push_warning("ADV Kit: %s を読み込めませんでした" % IMPORT_DOCK_SCENE)
		return
	_import_dock = scene.instantiate() as Control
	if _import_dock == null:
		push_warning("ADV Kit: インポートドックの生成に失敗しました")
		return
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _import_dock)


func _exit_tree() -> void:
	# プラグインを無効化しても設定は消さない。
	# 出力先はプロジェクトの設定であって、プラグインの内部状態ではないため。
	# ドックだけは必ず外して解放する（残すとエディタに幽霊パネルが残る）。
	if _import_dock != null:
		remove_control_from_docks(_import_dock)
		_import_dock.queue_free()
		_import_dock = null
