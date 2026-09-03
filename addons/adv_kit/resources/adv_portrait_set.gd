class_name AdvPortraitSet
extends Resource
## 立ち絵差分の定義（仕様書 §4.2）。
##
## 差分は「ポーズ × 表情」の 2 軸。全組み合わせを用意する必要はなく、
## 欠けている組み合わせは [method resolve] が既定値へフォールバックする。
##
## [b]Texture2D を直接持たない。[/b] @export var t: Texture2D を持つと
## .tres のロード時に Godot が全テクスチャを自動で読み込み、未登場キャラの
## 立ち絵まで一括ロードされて Web の初期ロードが伸びる。
## ここではパス文字列だけを保持し、実ロードは AdvStage が必要になった時点で行う。

## キー "<pose>/<expression>" → テクスチャのリソースパス文字列。
@export var texture_paths: Dictionary[String, String] = {}

## 表情が未指定のときに使うポーズ。
@export var default_pose: StringName = &""

## ポーズが未指定のときに使う表情。
@export var default_expression: StringName = &""

## 立ち絵の基準点。(0.5, 1.0) = 足元中央。
@export var pivot_offset_ratio: Vector2 = Vector2(0.5, 1.0)

## 個別のスケール補正。
@export var scale: float = 1.0


## テクスチャパスの辞書キーを組み立てる。
## どちらかが空なら空文字を返す（＝探索対象にならない）。
static func make_key(p_pose: StringName, p_expression: StringName) -> String:
	if String(p_pose).is_empty() or String(p_expression).is_empty():
		return ""
	return "%s/%s" % [p_pose, p_expression]


## 仕様書 §4.2 の 4 段フォールバックで立ち絵パスを解決する。
## [br]1. <pose>/<expression>
## [br]2. <pose>/<default_expression>
## [br]3. <default_pose>/<expression>
## [br]4. <default_pose>/<default_expression>
## [br]いずれも無ければ空文字を返す。[b]例外は投げず、load() も呼ばない。[/b]
func resolve(p_pose: StringName, p_expression: StringName) -> String:
	var candidates: PackedStringArray = PackedStringArray([
		make_key(p_pose, p_expression),
		make_key(p_pose, default_expression),
		make_key(default_pose, p_expression),
		make_key(default_pose, default_expression),
	])
	for key: String in candidates:
		if key.is_empty():
			continue
		if not texture_paths.has(key):
			continue
		var path: String = texture_paths[key]
		if not path.is_empty():
			return path
	return ""


## 立ち絵を1件も持たないかどうか。
func is_empty() -> bool:
	return texture_paths.is_empty()
