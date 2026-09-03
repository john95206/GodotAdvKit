class_name AdvEffectSchema
extends RefCounted
## 演出パラメータのスキーマ（仕様書 §7 の表）と、文字列 → 型付き値の変換。
##
## スプレッドシートの params セルは "key=value; key=value" の文字列であり
## （仕様書 §6.2）、GAS は分解するだけで型を付けない。
## [b]型変換とスキーマ照合はここで行う。[/b]
##
## 値の型は float / bool / String / Color の4種のみ。

## パラメータの型。
enum ParamType { FLOAT, BOOL, STRING, COLOR }

## パラメータの必須性（仕様書 §7）。
enum Requirement {
	## 欠落は missing_effect_param の ERROR。
	REQUIRED,
	## 欠落時は表の既定値を補う。
	DEFAULT,
	## 欠落時は値を入れず、演出ハンドラが実行時に決める（fade_in の color のみ）。
	RUNTIME,
}

const CODE_MISSING_PARAM := &"missing_effect_param"
const CODE_INVALID_PARAM := &"invalid_effect_param"
const CODE_UNKNOWN_ID := &"unknown_effect_id"
const CODE_UNKNOWN_PARAM := &"unknown_effect_param"

## AdvCharacter.id への参照であるパラメータ名。
## バリデータが unknown_speaker の検証対象に含める（仕様書 §7）。
const SPEAKER_PARAM_KEYS: Array[StringName] = [&"speaker"]

static var _table: Dictionary = {}
static var _targets: Dictionary = {}


## パラメータ1件の仕様。
class ParamSpec extends RefCounted:
	var name: StringName = &""
	## AdvEffectSchema.ParamType の値。
	var type: int = 0
	## AdvEffectSchema.Requirement の値。
	var requirement: int = 0
	var default_value: Variant = null

	static func make(
		p_name: StringName, p_type: int, p_requirement: int, p_default: Variant
	) -> ParamSpec:
		var spec := ParamSpec.new()
		spec.name = p_name
		spec.type = p_type
		spec.requirement = p_requirement
		spec.default_value = p_default
		return spec


## 演出の[b]排他ターゲット[/b]（仕様書 §7）。
##
## 同じステップで同時に走る演出どうしが同じターゲットを取り合うと、
## 2 つの Tween が同じプロパティを書くことになり結果が定まらない。
## `AdvScenarioValidator` がこの集合の重なりを `conflicting_parallel_effects` として弾く。
##
## `play_se` は多重再生可（§7）なので排他ターゲットを持たない。
## [b]未知の effect_id は空集合を返す[/b]（ゲーム側が register_effect() で足す拡張演出は
## 自分でターゲットを宣言する。phase-03）。
static func exclusive_targets(p_effect_id: StringName, p_params: Dictionary) -> PackedStringArray:
	_ensure_targets()
	if not _targets.has(p_effect_id):
		return PackedStringArray()
	var templates: PackedStringArray = _targets[p_effect_id]
	var speaker: String = ""
	if p_params.has(&"speaker"):
		speaker = str(p_params[&"speaker"])
	var result := PackedStringArray()
	for template: String in templates:
		result.append(template.replace("{speaker}", speaker))
	return result


static func _ensure_targets() -> void:
	if not _targets.is_empty():
		return
	_targets = {
		&"shake": PackedStringArray(["shake_root_position"]),
		&"fade_out": PackedStringArray(["fade_layer_alpha"]),
		&"fade_in": PackedStringArray(["fade_layer_alpha"]),
		&"show_portrait": PackedStringArray(["portrait_alpha:{speaker}"]),
		# hide はノードの解放を伴うため、そのキャラの全ターゲットを占有する
		&"hide_portrait": PackedStringArray([
			"portrait_alpha:{speaker}", "portrait_position:{speaker}",
		]),
		&"move_portrait": PackedStringArray(["portrait_position:{speaker}"]),
		&"play_bgm": PackedStringArray(["bgm_channel"]),
		&"stop_bgm": PackedStringArray(["bgm_channel"]),
		&"play_se": PackedStringArray(),
	}


## 演出IDが §7 の表に載っているか。
static func has_effect(p_effect_id: StringName) -> bool:
	_ensure_table()
	return _table.has(p_effect_id)


## 表に載っている演出IDの一覧。
static func effect_ids() -> Array[StringName]:
	_ensure_table()
	var ids: Array[StringName] = []
	for key: StringName in _table.keys():
		ids.append(key)
	return ids


## 演出IDのパラメータ仕様（StringName -> ParamSpec）。未知なら空辞書。
static func get_param_specs(p_effect_id: StringName) -> Dictionary:
	_ensure_table()
	if not _table.has(p_effect_id):
		return {}
	var specs: Dictionary = _table[p_effect_id]
	return specs


## 生の params（値はすべて文字列でよい）を型付きの辞書へ変換する。
## 問題は p_issues に積む。[b]例外は投げない。[/b]
## [br]・未知の effect_id → unknown_effect_id (WARNING)。値は文字列のまま全部残す
## [br]・必須欠落 → missing_effect_param (ERROR)
## [br]・型変換できない → invalid_effect_param (ERROR)
## [br]・スキーマ外のキー → unknown_effect_param (WARNING)。[b]値は捨てず文字列で保持[/b]
static func convert_params(
	p_effect_id: StringName,
	p_raw: Dictionary,
	p_location: String,
	p_issues: Array[AdvIssue]
) -> Dictionary:
	var raw: Dictionary = _normalize_keys(p_raw)
	var result: Dictionary = {}

	if not has_effect(p_effect_id):
		p_issues.append(AdvIssue.warning(
			CODE_UNKNOWN_ID,
			p_location,
			"未知の effect_id \"%s\"。ゲーム側が register_effect() で足す拡張演出なら問題ない" % p_effect_id
		))
		for key: StringName in raw.keys():
			result[key] = _as_string(raw[key])
		return result

	var specs: Dictionary = get_param_specs(p_effect_id)
	for param_name: StringName in specs.keys():
		var spec: ParamSpec = specs[param_name]
		if raw.has(param_name):
			var converted: Variant = convert_value(raw[param_name], spec.type)
			if converted == null:
				p_issues.append(AdvIssue.error(
					CODE_INVALID_PARAM,
					p_location,
					"%s の %s に \"%s\" は指定できません（%s が必要）" % [
						p_effect_id, param_name, _as_string(raw[param_name]),
						type_label(spec.type),
					]
				))
				if spec.requirement == Requirement.DEFAULT:
					result[param_name] = spec.default_value
			else:
				result[param_name] = converted
			continue
		match spec.requirement:
			Requirement.REQUIRED:
				p_issues.append(AdvIssue.error(
					CODE_MISSING_PARAM,
					p_location,
					"%s には %s が必須です" % [p_effect_id, param_name]
				))
			Requirement.DEFAULT:
				result[param_name] = spec.default_value
			Requirement.RUNTIME:
				pass

	for key: StringName in raw.keys():
		if specs.has(key):
			continue
		p_issues.append(AdvIssue.warning(
			CODE_UNKNOWN_PARAM,
			p_location,
			"%s のスキーマに無いパラメータ \"%s\"。値は文字列のまま保持する" % [p_effect_id, key]
		))
		result[key] = _as_string(raw[key])

	return result


## 値を1つ変換する。変換できなければ null を返す。
static func convert_value(p_value: Variant, p_type: int) -> Variant:
	match p_type:
		ParamType.FLOAT:
			if p_value is float:
				return p_value
			if p_value is int:
				return float(p_value)
			if p_value is String:
				var text_f: String = (p_value as String).strip_edges()
				if text_f.is_valid_float() or text_f.is_valid_int():
					return text_f.to_float()
			return null
		ParamType.BOOL:
			if p_value is bool:
				return p_value
			if p_value is int:
				return (p_value as int) != 0
			if p_value is String:
				var text_b: String = (p_value as String).strip_edges().to_lower()
				if text_b == "true" or text_b == "1" or text_b == "yes" or text_b == "on":
					return true
				if text_b == "false" or text_b == "0" or text_b == "no" or text_b == "off":
					return false
			return null
		ParamType.STRING:
			if p_value is String:
				return p_value
			if p_value is StringName:
				return String(p_value)
			return null
		ParamType.COLOR:
			if p_value is Color:
				return p_value
			if p_value is String:
				var text_c: String = (p_value as String).strip_edges()
				if Color.html_is_valid(text_c):
					return Color.html(text_c)
			return null
	return null


static func type_label(p_type: int) -> String:
	match p_type:
		ParamType.FLOAT:
			return "float"
		ParamType.BOOL:
			return "bool"
		ParamType.STRING:
			return "String"
		ParamType.COLOR:
			return "Color (#rrggbb)"
	return "unknown"


## "key=value; key=value" 形式（仕様書 §6.2）を辞書に分解する。
## 値の型付けは行わない。GAS 側が分解済みの JSON を返す場合はこれを通さない。
static func parse_param_string(p_text: String) -> Dictionary:
	var result: Dictionary = {}
	for chunk: String in p_text.split(";", false):
		var pair: String = chunk.strip_edges()
		if pair.is_empty():
			continue
		var sep: int = pair.find("=")
		if sep < 0:
			result[StringName(pair)] = ""
			continue
		var key: String = pair.substr(0, sep).strip_edges()
		var value: String = pair.substr(sep + 1).strip_edges()
		if not key.is_empty():
			result[StringName(key)] = value
	return result


static func _normalize_keys(p_raw: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in p_raw.keys():
		result[StringName(str(key))] = p_raw[key]
	return result


static func _as_string(p_value: Variant) -> String:
	if p_value is String:
		return p_value
	return str(p_value)


## p_list の要素は ParamSpec。
## 型付き配列 Array[ParamSpec]（インナークラスの typed array）は
## エンジンによる解決差が読めないため、あえて素の Array で受ける。
static func _specs(p_list: Array) -> Dictionary:
	var result: Dictionary = {}
	for spec: ParamSpec in p_list:
		result[spec.name] = spec
	return result


static func _required(p_name: StringName, p_type: int) -> ParamSpec:
	return ParamSpec.make(p_name, p_type, Requirement.REQUIRED, null)


static func _default(p_name: StringName, p_type: int, p_value: Variant) -> ParamSpec:
	return ParamSpec.make(p_name, p_type, Requirement.DEFAULT, p_value)


static func _runtime(p_name: StringName, p_type: int) -> ParamSpec:
	return ParamSpec.make(p_name, p_type, Requirement.RUNTIME, null)


## 仕様書 §7 の表。[b]表とこの辞書を必ず一致させること。[/b]
static func _ensure_table() -> void:
	if not _table.is_empty():
		return
	_table = {
		&"shake": _specs([
			_default(&"strength", ParamType.FLOAT, 8.0),
			_default(&"duration", ParamType.FLOAT, 0.4),
			_default(&"frequency", ParamType.FLOAT, 24.0),
		]),
		&"fade_out": _specs([
			_default(&"duration", ParamType.FLOAT, 0.5),
			_default(&"color", ParamType.COLOR, Color.BLACK),
		]),
		&"fade_in": _specs([
			_default(&"duration", ParamType.FLOAT, 0.5),
			_runtime(&"color", ParamType.COLOR),
		]),
		&"show_portrait": _specs([
			_required(&"speaker", ParamType.STRING),
			_default(&"slot", ParamType.STRING, "center"),
			_default(&"duration", ParamType.FLOAT, 0.2),
		]),
		&"hide_portrait": _specs([
			_required(&"speaker", ParamType.STRING),
			_default(&"duration", ParamType.FLOAT, 0.2),
		]),
		&"move_portrait": _specs([
			_required(&"speaker", ParamType.STRING),
			_required(&"to_slot", ParamType.STRING),
			_default(&"duration", ParamType.FLOAT, 0.4),
			_default(&"ease", ParamType.STRING, "out"),
		]),
		&"play_se": _specs([
			_required(&"stream", ParamType.STRING),
			_default(&"volume_db", ParamType.FLOAT, 0.0),
		]),
		&"play_bgm": _specs([
			_required(&"stream", ParamType.STRING),
			_default(&"fade_in_time", ParamType.FLOAT, 0.0),
			_default(&"loop", ParamType.BOOL, true),
		]),
		&"stop_bgm": _specs([
			_default(&"fade_out_time", ParamType.FLOAT, 0.0),
		]),
	}
