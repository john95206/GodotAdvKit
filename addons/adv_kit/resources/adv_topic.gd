class_name AdvTopic
extends Resource
## 話題（仕様書 §4.4）。

## 到達性検証（unreachable_topic）の対象外にする tag。
const TAG_ENTRY := "entry"

## 一意キー。
@export var id: StringName = &""

## 管理用の表示名。
@export var title: String = ""

## ステップ列（畳み込み後）。
@export var steps: Array[AdvStep] = []

## 分類用のタグ。"entry" を含む topic は
## 「ゲーム側から直接呼ばれるエントリポイント」として扱う。
@export var tags: PackedStringArray = PackedStringArray()


func has_tag(p_tag: String) -> bool:
	return tags.has(p_tag)


func is_entry() -> bool:
	return has_tag(TAG_ENTRY)


## uid でステップを引く。見つからなければ null。
func find_step_by_uid(p_uid: StringName) -> AdvStep:
	for step: AdvStep in steps:
		if step.uid == p_uid:
			return step
	return null
