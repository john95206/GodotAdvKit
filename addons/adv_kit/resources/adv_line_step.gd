class_name AdvLineStep
extends AdvStep
## 立ち絵情報に紐づいたテキスト（仕様書 §4.3）。

## 立ち位置として許される値。空文字（＝現在位置を維持）は含まない。
const VALID_SLOTS: Array[StringName] = [
	&"left", &"center_left", &"center", &"center_right", &"right",
]

## AdvCharacter.id への参照。空文字なら地の文（名前欄非表示）。
@export var speaker_id: StringName = &""

## 表情。空なら現在の表情を維持。
@export var expression: StringName = &""

## ポーズ。空なら現在のポーズを維持。
@export var pose: StringName = &""

## 立ち絵の立ち位置。空なら現在位置を維持し、初出なら center。
@export var slot: StringName = &""

## 本文。BBCode 可。
@export_multiline var text: String = ""

## ボイスのリソースパス。[b]空なら何も再生せずそのまま進行する[/b]（仕様書 §9.4）。
@export var voice_path: String = ""


## 地の文（話者なし）かどうか。
func is_narration() -> bool:
	return String(speaker_id).is_empty()


func get_class_label() -> String:
	return "line"


func describe() -> String:
	var head: String = text.substr(0, 16)
	return "line(order=%d, speaker=%s, text=\"%s\")" % [order, speaker_id, head]
