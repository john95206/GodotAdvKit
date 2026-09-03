class_name AdvScenarioParser
extends RefCounted
## パース済み JSON（Dictionary）→ AdvScenarioBook（仕様書 §6.3 / §4.8）。
##
## [b]例外を投げない。[/b] 問題は必ず AdvIssue として AdvParseResult に積む。
## [b]load() / ResourceSaver.save() を呼ばない。[/b] メモリ上に組むところまで。
##
## 行うこと:
## [br]・JSON の order をそのまま AdvStep.order に写す
## [br]・安定ステップID uid = "<topic_id>:<order>" を生成する（仕様書 §4.3）
## [br]・文字列 → 型の変換（id は StringName、name_color の #rrggbb は Color）
## [br]・畳み込み（仕様書 §4.8）と step_index の振り直し

const CODE_UNKNOWN_STEP_TYPE := &"unknown_step_type"
const CODE_MISSING_STEP_ORDER := &"missing_step_order"
const CODE_DUPLICATE_STEP_ORDER := &"duplicate_step_order"
const CODE_DUPLICATE_TOPIC_ID := &"duplicate_topic_id"
const CODE_DUPLICATE_CHARACTER_ID := &"duplicate_character_id"
const CODE_DANGLING_PARALLEL := &"dangling_parallel"
const CODE_DANGLING_OPTION := &"dangling_option"

## [b]仕様書 §4.9 の表に無いコード（phase-01 で追加）。[/b]
## JSON そのものが壊れている場合（読めない／ルートが辞書でない／
## 要素が辞書でない／id が空）に使う。§4.9 にはこの状況のコードが無い。
## handover で仕様書への追記を提案する。
const CODE_INVALID_JSON := &"invalid_json"

## JSON の type として許される値。
const STEP_TYPES: Array[String] = ["line", "effect", "choice", "option", "jump"]

## order として解釈できなかったことを表す番兵。
const ORDER_INVALID: int = -2147483648


## JSON ファイルを読んでパースする。
## [b]FileAccess + JSON.parse_string を使う。load() は使わない。[/b]
static func parse_file(p_path: String) -> AdvParseResult:
	if not FileAccess.file_exists(p_path):
		return _failed(CODE_INVALID_JSON, p_path, "ファイルが見つかりません")
	var text: String = FileAccess.get_file_as_string(p_path)
	if text.is_empty():
		var err: int = FileAccess.get_open_error()
		if err != OK:
			return _failed(CODE_INVALID_JSON, p_path, "読み込みに失敗しました (error %d)" % err)
		return _failed(CODE_INVALID_JSON, p_path, "ファイルが空です")
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		return _failed(CODE_INVALID_JSON, p_path, "JSON のルートがオブジェクトではありません")
	return parse(data)


## パース済み JSON をパースする。
static func parse(p_json_data: Dictionary) -> AdvParseResult:
	var result := AdvParseResult.new()
	var book := AdvScenarioBook.new()
	result.book = book
	_parse_characters(p_json_data, book, result)
	_parse_topics(p_json_data, book, result)
	return result


# --- characters -------------------------------------------------------------

static func _parse_characters(
	p_json_data: Dictionary, p_book: AdvScenarioBook, p_result: AdvParseResult
) -> void:
	var raw_list: Array = _get_array(p_json_data, "characters")
	for index: int in raw_list.size():
		var location: String = "characters[%d]" % index
		var raw: Dictionary = _as_dict(raw_list[index])
		if raw.is_empty():
			p_result.add_issue(AdvIssue.error(
				CODE_INVALID_JSON, location, "キャラクターの要素がオブジェクトではありません"))
			continue
		var id := StringName(_get_string(raw, "id"))
		if String(id).is_empty():
			p_result.add_issue(AdvIssue.error(
				CODE_INVALID_JSON, location, "キャラクターの id が空です"))
			continue
		if p_book.characters.has(id):
			p_result.add_issue(AdvIssue.error(
				CODE_DUPLICATE_CHARACTER_ID, location, "character_id \"%s\" が重複しています" % id))
			continue
		var character := AdvCharacter.new()
		character.id = id
		character.display_name = _get_string(raw, "display_name")
		character.name_color = _parse_color(_get_string(raw, "name_color"), location, p_result)
		character.portrait_set = _build_portrait_set(raw)
		p_book.characters[id] = character


## portrait_dir / poses / expressions から立ち絵パス表を組む。
## パス規約は "<portrait_dir>/<pose>_<expression>.png"（仕様書 §6.3）。
## [b]load() も存在チェックもしない。[/b]
static func _build_portrait_set(p_raw: Dictionary) -> AdvPortraitSet:
	var dir: String = _get_string(p_raw, "portrait_dir").strip_edges()
	var poses: PackedStringArray = _get_packed_strings(p_raw, "poses")
	var expressions: PackedStringArray = _get_packed_strings(p_raw, "expressions")
	if dir.is_empty() or poses.is_empty() or expressions.is_empty():
		return null
	var base: String = dir.trim_suffix("/")
	var portrait_set := AdvPortraitSet.new()
	portrait_set.default_pose = StringName(_get_string(p_raw, "default_pose"))
	portrait_set.default_expression = StringName(_get_string(p_raw, "default_expression"))
	for pose: String in poses:
		for expression: String in expressions:
			var key: String = AdvPortraitSet.make_key(StringName(pose), StringName(expression))
			if key.is_empty():
				continue
			portrait_set.texture_paths[key] = "%s/%s_%s.png" % [base, pose, expression]
	return portrait_set


# --- topics / steps ---------------------------------------------------------

static func _parse_topics(
	p_json_data: Dictionary, p_book: AdvScenarioBook, p_result: AdvParseResult
) -> void:
	var raw_list: Array = _get_array(p_json_data, "topics")
	for index: int in raw_list.size():
		var location: String = "topics[%d]" % index
		var raw: Dictionary = _as_dict(raw_list[index])
		if raw.is_empty():
			p_result.add_issue(AdvIssue.error(
				CODE_INVALID_JSON, location, "話題の要素がオブジェクトではありません"))
			continue
		var id := StringName(_get_string(raw, "id"))
		if String(id).is_empty():
			p_result.add_issue(AdvIssue.error(
				CODE_INVALID_JSON, location, "話題の id が空です"))
			continue
		if p_book.topics.has(id):
			p_result.add_issue(AdvIssue.error(
				CODE_DUPLICATE_TOPIC_ID, location, "topic_id \"%s\" が重複しています" % id))
			continue
		var topic := AdvTopic.new()
		topic.id = id
		topic.title = _get_string(raw, "title")
		topic.tags = _get_packed_strings(raw, "tags")
		_parse_steps(raw, topic, p_result)
		p_book.topics[id] = topic


static func _parse_steps(
	p_raw_topic: Dictionary, p_topic: AdvTopic, p_result: AdvParseResult
) -> void:
	var raw_list: Array = _get_array(p_raw_topic, "steps")
	var parsed: Array[AdvStep] = []
	var seen_orders: Dictionary = {}

	for index: int in raw_list.size():
		var location: String = "topics/%s/steps[%d]" % [p_topic.id, index]
		var raw: Dictionary = _as_dict(raw_list[index])
		if raw.is_empty():
			p_result.add_issue(AdvIssue.error(
				CODE_INVALID_JSON, location, "ステップの要素がオブジェクトではありません"))
			continue

		var order: int = _read_order(raw)
		if order == ORDER_INVALID:
			p_result.add_issue(AdvIssue.error(
				CODE_MISSING_STEP_ORDER, location,
				"order が欠落しているか、整数として解釈できません"))
			continue

		if seen_orders.has(order):
			p_result.add_issue(AdvIssue.error(
				CODE_DUPLICATE_STEP_ORDER, location,
				"order=%d が同一 topic 内で重複しています（uid が衝突するため、この行は捨てます）" % order))
			continue
		seen_orders[order] = true

		var type_text: String = _get_string(raw, "type").strip_edges().to_lower()
		var step: AdvStep = _build_step(type_text, raw, location, p_result)
		if step == null:
			continue
		step.order = order
		step.uid = StringName("%s:%d" % [p_topic.id, order])
		parsed.append(step)

	parsed.sort_custom(func(a: AdvStep, b: AdvStep) -> bool: return a.order < b.order)
	p_topic.steps = _fold(parsed, p_topic, p_result)
	for i: int in p_topic.steps.size():
		p_topic.steps[i].step_index = i


static func _build_step(
	p_type: String, p_raw: Dictionary, p_location: String, p_result: AdvParseResult
) -> AdvStep:
	match p_type:
		"line":
			var line_step := AdvLineStep.new()
			line_step.speaker_id = StringName(_get_string(p_raw, "speaker"))
			line_step.expression = StringName(_get_string(p_raw, "expression"))
			line_step.pose = StringName(_get_string(p_raw, "pose"))
			line_step.slot = StringName(_get_string(p_raw, "slot"))
			line_step.text = _get_string(p_raw, "text")
			line_step.voice_path = _get_string(p_raw, "voice")
			return line_step
		"effect":
			var effect_step := AdvEffectStep.new()
			effect_step.effect_id = StringName(_get_string(p_raw, "effect_id"))
			effect_step.sync_mode = AdvEffectStep.sync_mode_from_string(_get_string(p_raw, "sync"))
			effect_step.auto_advance = _get_bool(p_raw, "auto_advance")
			var issues: Array[AdvIssue] = []
			effect_step.params = AdvEffectSchema.convert_params(
				effect_step.effect_id, _get_dict(p_raw, "params"), p_location, issues)
			p_result.add_issues(issues)
			return effect_step
		"choice":
			var choice_step := AdvChoiceStep.new()
			choice_step.prompt = _get_string(p_raw, "prompt")
			return choice_step
		"option":
			var option_step := AdvOptionStep.new()
			option_step.label = _get_string(p_raw, "label")
			option_step.goto = StringName(_get_string(p_raw, "goto"))
			option_step.flag = _get_string(p_raw, "flag")
			option_step.condition = _get_string(p_raw, "condition")
			return option_step
		"jump":
			var jump_step := AdvJumpStep.new()
			jump_step.goto = StringName(_get_string(p_raw, "goto"))
			jump_step.condition = _get_string(p_raw, "condition")
			return jump_step
	p_result.add_issue(AdvIssue.error(
		CODE_UNKNOWN_STEP_TYPE, p_location,
		"type \"%s\" は %s のいずれでもありません（この行は捨てて残りを続行します）" % [
			p_type, ", ".join(STEP_TYPES)]))
	return null


## 畳み込み（仕様書 §4.8）。
## [br]・sync=parallel の AdvEffectStep → 直前のステップの parallel_effects
## [br]・AdvOptionStep → 直前の AdvChoiceStep.options
## [br]畳み込み先は AdvLineStep に限らない（blocking 演出や choice の直後でもよい）。
static func _fold(
	p_steps: Array[AdvStep], p_topic: AdvTopic, p_result: AdvParseResult
) -> Array[AdvStep]:
	var folded: Array[AdvStep] = []
	for step: AdvStep in p_steps:
		var location: String = "topics/%s/steps(order=%d)" % [p_topic.id, step.order]

		if step is AdvEffectStep and (step as AdvEffectStep).is_parallel():
			if folded.is_empty():
				p_result.add_issue(AdvIssue.error(
					CODE_DANGLING_PARALLEL, location,
					"topic の先頭ステップが parallel 演出です。畳み込み先がありません"))
				continue
			folded[folded.size() - 1].parallel_effects.append(step)
			continue

		if step is AdvOptionStep:
			var target: AdvStep = null
			if not folded.is_empty():
				target = folded[folded.size() - 1]
			if not (target is AdvChoiceStep):
				p_result.add_issue(AdvIssue.error(
					CODE_DANGLING_OPTION, location,
					"直前が choice ではない option 行です。畳み込み先がありません"))
				continue
			var option := step as AdvOptionStep
			(target as AdvChoiceStep).add_option(
				option.label, option.goto, option.flag, option.condition)
			continue

		folded.append(step)
	return folded


# --- helpers ----------------------------------------------------------------

static func _failed(p_code: StringName, p_location: String, p_message: String) -> AdvParseResult:
	var result := AdvParseResult.new()
	result.book = AdvScenarioBook.new()
	result.add_issue(AdvIssue.error(p_code, p_location, p_message))
	return result


## order を整数として読む。読めなければ ORDER_INVALID を返す。
static func _read_order(p_raw: Dictionary) -> int:
	var value: Variant = p_raw.get("order", null)
	if value == null:
		return ORDER_INVALID
	if value is int:
		return value
	if value is float:
		var number: float = value
		if is_equal_approx(number, roundf(number)):
			return int(roundf(number))
		return ORDER_INVALID
	if value is String:
		var text: String = (value as String).strip_edges()
		if text.is_valid_int():
			return text.to_int()
	return ORDER_INVALID


static func _as_dict(p_value: Variant) -> Dictionary:
	if p_value is Dictionary:
		return p_value
	return {}


static func _get_array(p_dict: Dictionary, p_key: String) -> Array:
	var value: Variant = p_dict.get(p_key, null)
	if value is Array:
		return value
	return []


static func _get_dict(p_dict: Dictionary, p_key: String) -> Dictionary:
	return _as_dict(p_dict.get(p_key, null))


static func _get_string(p_dict: Dictionary, p_key: String) -> String:
	var value: Variant = p_dict.get(p_key, null)
	if value == null:
		return ""
	if value is String:
		return value
	if value is StringName:
		return String(value)
	return str(value)


static func _get_bool(p_dict: Dictionary, p_key: String) -> bool:
	var value: Variant = p_dict.get(p_key, null)
	if value == null:
		return false
	if value is bool:
		return value
	if value is int:
		return (value as int) != 0
	if value is String:
		var text: String = (value as String).strip_edges().to_lower()
		return text == "true" or text == "1" or text == "yes" or text == "on"
	return false


static func _get_packed_strings(p_dict: Dictionary, p_key: String) -> PackedStringArray:
	var result := PackedStringArray()
	for entry: Variant in _get_array(p_dict, p_key):
		if entry == null:
			continue
		result.append(str(entry))
	return result


static func _parse_color(
	p_text: String, p_location: String, p_result: AdvParseResult
) -> Color:
	var text: String = p_text.strip_edges()
	if text.is_empty():
		return Color.WHITE
	if Color.html_is_valid(text):
		return Color.html(text)
	p_result.add_issue(AdvIssue.warning(
		CODE_INVALID_JSON, p_location,
		"name_color \"%s\" は #rrggbb として解釈できません。白を使います" % text))
	return Color.WHITE
