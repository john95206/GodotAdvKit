class_name AdvScenarioBook
extends Resource
## シナリオの集約 Resource（仕様書 §4.5）。
##
## ゲーム側はこれ1つを AdvPlayer に渡す。
##
## [b]当面は Book を1つだけ扱う。[/b] 章ごとにファイルを分ける運用
## （複数 Book のマージ）は未決のため merge() は実装しない（仕様書 §13 U-07）。
## goto の参照整合性は単一 Book 内で厳密に検証する。

## topic_id → AdvTopic。
@export var topics: Dictionary[StringName, AdvTopic] = {}

## character_id → AdvCharacter。
@export var characters: Dictionary[StringName, AdvCharacter] = {}


func get_topic(p_id: StringName) -> AdvTopic:
	if not topics.has(p_id):
		return null
	return topics[p_id]


func get_character(p_id: StringName) -> AdvCharacter:
	if not characters.has(p_id):
		return null
	return characters[p_id]


func has_topic(p_id: StringName) -> bool:
	return topics.has(p_id)


func has_character(p_id: StringName) -> bool:
	return characters.has(p_id)


## entry タグを持つ topic の id 一覧。
func entry_topic_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in topics.keys():
		var topic: AdvTopic = topics[id]
		if topic != null and topic.is_entry():
			result.append(id)
	return result


## 畳み込み後の総ステップ数（parallel_effects と options は数えない）。
func total_step_count() -> int:
	var total: int = 0
	for id: StringName in topics.keys():
		var topic: AdvTopic = topics[id]
		if topic != null:
			total += topic.steps.size()
	return total
