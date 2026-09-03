class_name AdvScenarioValidator
extends RefCounted
## 参照整合性と必須項目の検証（仕様書 §4.9）。
##
## [b]単一 Book 前提。[/b] 章分割（複数 Book のマージ）は未決のため
## is_complete のような引数は設けない（仕様書 §13 U-07）。
##
## パーサ側で検出するコード（unknown_step_type / duplicate_* /
## dangling_* / *_effect_param）はここでは再検出しない。
## ここが担当するのは、[b]Book 全体を見ないと分からない参照の整合性[/b]と
## 条件式の構文検証。

const CODE_UNKNOWN_SPEAKER := &"unknown_speaker"
const CODE_UNKNOWN_TOPIC := &"unknown_topic"
const CODE_UNKNOWN_SLOT := &"unknown_slot"
const CODE_EMPTY_CHOICE := &"empty_choice"
const CODE_EMPTY_TOPIC := &"empty_topic"
const CODE_UNREACHABLE_TOPIC := &"unreachable_topic"
const CODE_INVALID_AUTO_ADVANCE := &"invalid_auto_advance"
const CODE_CONFLICTING_PARALLEL := &"conflicting_parallel_effects"


static func validate(p_book: AdvScenarioBook) -> Array[AdvIssue]:
	var issues: Array[AdvIssue] = []
	if p_book == null:
		return issues

	var referenced: Dictionary = {}

	for topic_id: StringName in p_book.topics.keys():
		var topic: AdvTopic = p_book.topics[topic_id]
		if topic == null:
			continue
		if topic.steps.is_empty():
			issues.append(AdvIssue.warning(
				CODE_EMPTY_TOPIC, "topics/%s" % topic_id, "steps が 0 件の話題です"))
		for index: int in topic.steps.size():
			var step: AdvStep = topic.steps[index]
			var location: String = AdvIssue.make_location(topic_id, index)
			_validate_step(step, p_book, location, referenced, issues)
			for sub_index: int in step.parallel_effects.size():
				var sub_location: String = "%s/parallel_effects[%d]" % [location, sub_index]
				_validate_step(
					step.parallel_effects[sub_index], p_book, sub_location, referenced, issues)
			_validate_parallel_conflicts(step, location, issues)

	_validate_reachability(p_book, referenced, issues)
	return issues


## ERROR が 0 件かどうか。
static func is_ok(p_issues: Array[AdvIssue]) -> bool:
	for issue: AdvIssue in p_issues:
		if issue.is_error():
			return false
	return true


static func _validate_step(
	p_step: AdvStep,
	p_book: AdvScenarioBook,
	p_location: String,
	p_referenced: Dictionary,
	p_issues: Array[AdvIssue]
) -> void:
	if p_step == null:
		return

	if p_step is AdvLineStep:
		var line := p_step as AdvLineStep
		_check_speaker(line.speaker_id, p_book, p_location, "speaker", p_issues)
		if not String(line.slot).is_empty() and not AdvLineStep.VALID_SLOTS.has(line.slot):
			p_issues.append(AdvIssue.error(
				CODE_UNKNOWN_SLOT, p_location,
				"slot \"%s\" は %s のいずれでもありません" % [
					line.slot, _join_names(AdvLineStep.VALID_SLOTS)]))
		return

	if p_step is AdvEffectStep:
		var effect := p_step as AdvEffectStep
		if effect.is_parallel() and effect.auto_advance:
			p_issues.append(AdvIssue.warning(
				CODE_INVALID_AUTO_ADVANCE, p_location,
				"sync=parallel に auto_advance=true を指定しても意味がありません"))
		for key: StringName in AdvEffectSchema.SPEAKER_PARAM_KEYS:
			if not effect.params.has(key):
				continue
			var speaker := StringName(str(effect.params[key]))
			_check_speaker(speaker, p_book, "%s/params/%s" % [p_location, key], "speaker", p_issues)
		return

	if p_step is AdvChoiceStep:
		var choice := p_step as AdvChoiceStep
		if choice.options.is_empty():
			p_issues.append(AdvIssue.error(
				CODE_EMPTY_CHOICE, p_location,
				"選択肢が 0 件です。進行が詰まります"))
		for index: int in choice.options.size():
			var option: Dictionary = choice.options[index]
			var location: String = "%s/options[%d]" % [p_location, index]
			var goto := StringName(str(option.get(AdvChoiceStep.KEY_GOTO, &"")))
			_check_goto(goto, p_book, location, p_referenced, p_issues)
			var condition: String = str(option.get(AdvChoiceStep.KEY_CONDITION, ""))
			p_issues.append_array(AdvCondition.validate(condition, location))
		return

	if p_step is AdvJumpStep:
		var jump := p_step as AdvJumpStep
		_check_goto(jump.goto, p_book, p_location, p_referenced, p_issues)
		p_issues.append_array(AdvCondition.validate(jump.condition, p_location))
		return


## 同じステップで同時に走る演出が、同じ対象を取り合っていないかを見る（仕様書 §7 / §4.8）。
##
## 対象になるのは「そのステップの `parallel_effects`」と、
## [b]ホストのステップ自身が BLOCKING 演出ならそれも含む[/b]。
## PARALLEL 演出は直前のステップの開始と同時に走るため、両者は同時に動く。
static func _validate_parallel_conflicts(
	p_step: AdvStep, p_location: String, p_issues: Array[AdvIssue]
) -> void:
	if p_step.parallel_effects.is_empty():
		return
	var owners: Dictionary = {}
	var host := p_step as AdvEffectStep
	if host != null:
		_claim_targets(host, p_location, owners, p_issues)
	for index: int in p_step.parallel_effects.size():
		var effect := p_step.parallel_effects[index] as AdvEffectStep
		if effect == null:
			continue
		_claim_targets(
			effect, "%s/parallel_effects[%d]" % [p_location, index], owners, p_issues)


static func _claim_targets(
	p_effect: AdvEffectStep,
	p_location: String,
	p_owners: Dictionary,
	p_issues: Array[AdvIssue]
) -> void:
	var targets: PackedStringArray = AdvEffectSchema.exclusive_targets(
		p_effect.effect_id, p_effect.params)
	for target: String in targets:
		if p_owners.has(target):
			var previous: String = p_owners[target]
			p_issues.append(AdvIssue.error(
				CODE_CONFLICTING_PARALLEL, p_location,
				"同時に走る %s(order=%d) と %s が対象 \"%s\" を取り合っています。結果が定まりません" % [
					p_effect.effect_id, p_effect.order, previous, target]))
			continue
		p_owners[target] = "%s(order=%d)" % [p_effect.effect_id, p_effect.order]


static func _check_speaker(
	p_speaker_id: StringName,
	p_book: AdvScenarioBook,
	p_location: String,
	p_field: String,
	p_issues: Array[AdvIssue]
) -> void:
	if String(p_speaker_id).is_empty():
		return  # 空文字は地の文。エラーではない
	if p_book.has_character(p_speaker_id):
		return
	p_issues.append(AdvIssue.error(
		CODE_UNKNOWN_SPEAKER, p_location,
		"%s \"%s\" は characters に存在しません" % [p_field, p_speaker_id]))


static func _check_goto(
	p_goto: StringName,
	p_book: AdvScenarioBook,
	p_location: String,
	p_referenced: Dictionary,
	p_issues: Array[AdvIssue]
) -> void:
	if String(p_goto).is_empty():
		return  # 空は「現在の topic を継続」または「topic 終了」
	p_referenced[p_goto] = true
	if p_book.has_topic(p_goto):
		return
	p_issues.append(AdvIssue.error(
		CODE_UNKNOWN_TOPIC, p_location,
		"goto の遷移先 \"%s\" が存在しません" % p_goto))


static func _validate_reachability(
	p_book: AdvScenarioBook, p_referenced: Dictionary, p_issues: Array[AdvIssue]
) -> void:
	for topic_id: StringName in p_book.topics.keys():
		if p_referenced.has(topic_id):
			continue
		var topic: AdvTopic = p_book.topics[topic_id]
		if topic != null and topic.is_entry():
			continue
		p_issues.append(AdvIssue.warning(
			CODE_UNREACHABLE_TOPIC, "topics/%s" % topic_id,
			"どの goto からも参照されず、tags に \"%s\" もありません" % AdvTopic.TAG_ENTRY))


static func _join_names(p_names: Array[StringName]) -> String:
	var parts := PackedStringArray()
	for name_value: StringName in p_names:
		parts.append(String(name_value))
	return ", ".join(parts)
