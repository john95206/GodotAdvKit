class_name AdvCharacter
extends Resource
## 話者エンティティ（仕様書 §4.1）。

## 話者ID。シナリオから参照される一意キー。
@export var id: StringName = &""

## 名前欄に表示される話者名。
@export var display_name: String = ""

## 名前欄の色。
@export var name_color: Color = Color.WHITE

## 立ち絵定義。[b]null 可[/b]（立ち絵を持たないキャラクター）。
@export var portrait_set: AdvPortraitSet = null


## 立ち絵パスを解決する。portrait_set が null なら空文字を返す。
func resolve_portrait(p_pose: StringName, p_expression: StringName) -> String:
	if portrait_set == null:
		return ""
	return portrait_set.resolve(p_pose, p_expression)
