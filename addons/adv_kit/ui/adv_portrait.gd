class_name AdvPortrait
extends Control
## 立ち絵1体の表示ノード（仕様書 §4.2 / §5）。
##
## Resource 側にはパス文字列だけを持たせ、実テクスチャのロードはこのクラスの
## apply() に限定する。立ち絵が無いキャラクターも、空のまま安全に保持できる。

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
	_kill_fade_tween()
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


## 立ち絵の基準点を指定座標へ置く。
func set_slot_position(p_position_x: float, p_base_y: float) -> void:
	var transformed_pivot: Vector2 = Vector2(
		pivot_offset.x * scale.x, pivot_offset.y * scale.y)
	position = Vector2(p_position_x, p_base_y) - transformed_pivot


## 表示開始時のフェードイン。
func fade_in(p_duration: float) -> void:
	_kill_fade_tween()
	if p_duration <= 0.0 or not is_inside_tree():
		modulate.a = 1.0
		return
	modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, p_duration)


## フェードアウト後にノードを解放する。
func fade_out_and_free(p_duration: float) -> void:
	_kill_fade_tween()
	if p_duration <= 0.0 or not is_inside_tree():
		queue_free()
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, p_duration)
	_fade_tween.finished.connect(_queue_free_after_fade)


func _queue_free_after_fade() -> void:
	queue_free()


func _kill_fade_tween() -> void:
	if _fade_tween != null and is_instance_valid(_fade_tween):
		_fade_tween.kill()
	_fade_tween = null


## SceneTree の初期化途中でも apply() を安全に呼べるようにする。
func _get_texture_rect() -> TextureRect:
	if _texture_rect != null:
		return _texture_rect
	_texture_rect = get_node_or_null("Texture") as TextureRect
	return _texture_rect
