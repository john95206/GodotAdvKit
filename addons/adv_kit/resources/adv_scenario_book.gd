class_name AdvScenarioBook
extends Resource
## シナリオの集約 Resource（仕様書 §4.5）。
##
## ゲーム側はこれ1つを AdvPlayer に渡す。
##
## [b]当面は Book を1つだけ扱う。[/b] 章ごとにファイルを分ける運用
## （複数 Book のマージ）は 2026-09-03 に「行わない」で確定したため
## merge() は実装しない（仕様書 §13 U-07）。
## goto の参照整合性は単一 Book 内で厳密に検証する。

## topic_id → AdvTopic。
@export var topics: Dictionary[StringName, AdvTopic] = {}

## character_id → AdvCharacter。
@export var characters: Dictionary[StringName, AdvCharacter] = {}

## JSON の schema_version をそのまま保持する。欠落時は 0（仕様書 §4.5）。
@export var schema_version: int = 0

## JSON の content_hash をそのまま保持する。
## AdvScenarioImporter が「変更なし」を判定する材料（仕様書 §6.4）。
@export var content_hash: String = ""


## 既存 Book と同じ内容かどうか。
## [b]両方の content_hash が非空で一致したときだけ真。[/b]
## 片方でも空なら「分からない」＝書き出す、に倒す。
func has_same_content(p_other: AdvScenarioBook) -> bool:
	if p_other == null:
		return false
	if content_hash.is_empty() or p_other.content_hash.is_empty():
		return false
	return content_hash == p_other.content_hash


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
