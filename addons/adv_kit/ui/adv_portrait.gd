class_name AdvPortrait
extends Control
## 立ち絵1体の表示ノード（仕様書 §4.2 / §5）。
##
## Resource 側にはパス文字列だけを持たせ、実テクスチャのロードはこのクラスの
## apply() に限定する。立ち絵が無いキャラクターも、空のまま安全に保持できる。
##
## [b]modulate.a の Tween を作るのはこのクラスだけ。[/b] 演出ハンドラは fade_in() /
## fade_out_and_free() が返した Tween を排他ターゲットの台帳へ載せる。
## こうしないと、暗黙の登場（line 起因）と show_portrait が同じ alpha を二重に書く。

@onready var _texture_rect: TextureRect = get_node("Texture") as TextureRect

var character_id: StringName = &""
var _fade_tween: Tween = null


## パスを解決済みのテクスチャとして適用する。空または存在しないパスは非表示にする。
func apply(
	p_texture_path: String, p_pivot_offset_ratio: Vector2, p_portrait_scale: float
) -> void:
	var texture_rect: TextureRect = _get_texture_rect()
	if texture_rect == null:
		return
	kill_fade_tween()
	texture_rect.texture = null
	size = Vector2.ZERO
	pivot_offset = Vector2.ZERO
	scale = Vector2.ONE

	if p_texture_path.is_empty():
		return
	if not ResourceLoader.exists(p_texture_path):
		return

	var loaded_texture: Texture2D = load(p_texture_path) as Texture2D
	if loaded_texture == null:
		return

	texture_rect.texture = loaded_texture
	size = loaded_texture.get_size()
	pivot_offset = size * p_pivot_offset_ratio
	scale = Vector2.ONE * maxf(p_portrait_scale, 0.0)


## 基準点（スロット位置）を渡したときに position になる値。
## 移動演出はこれを Tween の目標にする。
func position_for_base(p_base: Vector2) -> Vector2:
	var transformed_pivot: Vector2 = Vector2(
		pivot_offset.x * scale.x, pivot_offset.y * scale.y)
	return p_base - transformed_pivot


## 立ち絵の基準点を指定座標へ置く。
func set_slot_position_from_base(p_base: Vector2) -> void:
	position = position_for_base(p_base)


## 表示開始時のフェードイン。即時表示だった場合は null を返す。
func fade_in(p_duration: float) -> Tween:
	kill_fade_tween()
	if p_duration <= 0.0 or not is_inside_tree():
		modulate.a = 1.0
		return null
	modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, p_duration)
	return _fade_tween


## フェードアウト後にノードを解放する。即時解放だった場合は null を返す。
func fade_out_and_free(p_duration: float) -> Tween:
	kill_fade_tween()
	if p_duration <= 0.0 or not is_inside_tree():
		queue_free()
		return null
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, p_duration)
	_fade_tween.tween_callback(_queue_free_after_fade)
	return _fade_tween


## 走っているフェードを止める。
## [b]中断されたフェードアウトはノードを解放しない[/b]（仕様書 §7「後から始まった方が勝つ」）。
func kill_fade_tween() -> void:
	if _fade_tween != null and is_instance_valid(_fade_tween):
		_fade_tween.kill()
	_fade_tween = null


func _queue_free_after_fade() -> void:
	queue_free()


## SceneTree の初期化途中でも apply() を安全に呼べるようにする。
func _get_texture_rect() -> TextureRect:
	if _texture_rect != null:
		return _texture_rect
	_texture_rect = get_node_or_null("Texture") as TextureRect
	return _texture_rect
