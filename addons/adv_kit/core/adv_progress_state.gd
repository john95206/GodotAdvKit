class_name AdvProgressState
extends RefCounted
## 進行位置・フラグ・既読集合を保持する Node 非依存の状態（仕様書 §9.1）。
##
## 内部では既読 UID を StringName の Dictionary で一意管理し、外部との
## シリアライズ境界でだけ String / PackedStringArray へ変換する。

const KEY_TOPIC_ID := "topic_id"
const KEY_STEP_UID := "step_uid"
const KEY_FLAGS := "flags"
const KEY_READ_STEPS := "read_steps"

var _topic_id: StringName = &""
var _step_uid: StringName = &""
var _flags: Dictionary[String, bool] = {}
var _read_steps: Dictionary[StringName, bool] = {}


func set_position(p_topic_id: StringName, p_step_uid: StringName) -> void:
	_topic_id = p_topic_id
	_step_uid = p_step_uid


func clear_position() -> void:
	_topic_id = &""
	_step_uid = &""


func get_topic_id() -> StringName:
	return _topic_id


func get_step_uid() -> StringName:
	return _step_uid


## フラグが実際に変化した場合だけ true を返す。
func set_flag(p_flag_name: String, p_value: bool) -> bool:
	var flag_name: String = p_flag_name.strip_edges()
	if flag_name.is_empty():
		return false
	var had_flag: bool = _flags.has(flag_name)
	var previous: bool = bool(_flags.get(flag_name, false))
	if had_flag and previous == p_value:
		return false
	_flags[flag_name] = p_value
	return true


func has_flag(p_flag_name: String) -> bool:
	return bool(_flags.get(p_flag_name.strip_edges(), false))


## 内部辞書を外部から変更できないようコピーを返す。
func get_flags() -> Dictionary[String, bool]:
	var result: Dictionary[String, bool] = {}
	for flag_name: String in _flags.keys():
		result[flag_name] = _flags[flag_name]
	return result


func mark_step_read(p_step_uid: StringName) -> void:
	if String(p_step_uid).is_empty():
		return
	_read_steps[p_step_uid] = true


func is_step_read(p_step_uid: StringName) -> bool:
	return _read_steps.has(p_step_uid)


## 保存時にだけ StringName キーを String 配列へ変換する。
func get_read_steps() -> PackedStringArray:
	var result := PackedStringArray()
	for step_uid: StringName in _read_steps.keys():
		result.append(String(step_uid))
	result.sort()
	return result


## JSON 化可能な値だけで構成された進行辞書を返す。
func to_dictionary() -> Dictionary:
	var flags: Dictionary = {}
	for flag_name: String in _flags.keys():
		flags[flag_name] = _flags[flag_name]
	return {
		KEY_TOPIC_ID: String(_topic_id),
		KEY_STEP_UID: String(_step_uid),
		KEY_FLAGS: flags,
		KEY_READ_STEPS: get_read_steps(),
	}


## 保存データの欠損・旧形式を許容して状態を置き換える。
func restore_from_dictionary(p_data: Dictionary) -> void:
	clear_position()
	_flags.clear()
	_read_steps.clear()

	var raw_topic_id: Variant = p_data.get(KEY_TOPIC_ID, "")
	var raw_step_uid: Variant = p_data.get(KEY_STEP_UID, "")
	_topic_id = StringName("") if raw_topic_id == null else StringName(str(raw_topic_id))
	_step_uid = StringName("") if raw_step_uid == null else StringName(str(raw_step_uid))

	var raw_flags: Variant = p_data.get(KEY_FLAGS, {})
	if raw_flags is Dictionary:
		for raw_key: Variant in (raw_flags as Dictionary).keys():
			var flag_name: String = str(raw_key).strip_edges()
			if flag_name.is_empty():
				continue
			_flags[flag_name] = _to_bool((raw_flags as Dictionary)[raw_key])

	var raw_read_steps: Variant = p_data.get(KEY_READ_STEPS, null)
	if raw_read_steps is PackedStringArray:
		for step_uid: String in raw_read_steps:
			_mark_read_string(step_uid)
	elif raw_read_steps is Array:
		for raw_uid: Variant in raw_read_steps as Array:
			_mark_read_string(str(raw_uid))


func _mark_read_string(p_step_uid: String) -> void:
	var step_uid: StringName = StringName(p_step_uid)
	if not String(p_step_uid).is_empty():
		_read_steps[step_uid] = true


static func _to_bool(p_value: Variant) -> bool:
	if p_value is bool:
		return p_value
	if p_value is int:
		return (p_value as int) != 0
	if p_value is float:
		return not is_zero_approx(p_value as float)
	if p_value is String:
		var text: String = (p_value as String).strip_edges().to_lower()
		return text == "true" or text == "1" or text == "yes" or text == "on"
	return false
