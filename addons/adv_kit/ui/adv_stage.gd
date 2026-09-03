class_name AdvStage
extends Control
## 立ち絵の配置とライフサイクルを管理するステージ（仕様書 §5）。
##
## [b]このクラスは runtime/ を知らない。[/b] 演出ハンドラは AdvEffectContext 経由で
## ここのメソッドを呼び、返ってきた Tween を排他ターゲットの台帳へ載せる。
##
## 保持しているのは「[b]いま画面に何が出ているか[/b]」だけ。
## 「空なら維持」というシナリオ解釈の規則は AdvPlayer の責務。

const PORTRAIT_SCENE: PackedScene = preload("res://addons/adv_kit/ui/adv_portrait.tscn")
const VALID_SLOTS: Array[StringName] = [
	&"left", &"center_left", &"center", &"center_right", &"right",
]
const DEFAULT_SLOT := &"center"

## スロット名 -> ステージ幅に対する基準点の比率。
@export var slot_ratios: Dictionary[StringName, float] = {
	&"left": 0.15,
	&"center_left": 0.325,
	&"center": 0.5,
	&"center_right": 0.675,
	&"right": 0.85,
}

var _portraits: Dictionary[StringName, AdvPortrait] = {}
var _portrait_slots: Dictionary[StringName, StringName] = {}
var _portrait_poses: Dictionary[StringName, StringName] = {}
var _portrait_expressions: Dictionary[StringName, StringName] = {}


func _ready() -> void:
	if not resized.is_connected(_on_stage_resized):
		resized.connect(_on_stage_resized)
	_reposition_all()


## キャラクターを生成または既存ノードへ適用し、指定スロットへ表示する。
## [param p_pose] / [param p_expression] が空なら[b]現在の表示値[/b]（無ければ既定値）を使う。
## 戻り値はフェードの Tween。即時表示だった場合は null。
func show_character(
	p_character: AdvCharacter,
	p_pose: StringName,
	p_expression: StringName,
	p_slot: StringName,
	p_duration: float
) -> Tween:
	if p_character == null:
		return null

	var character_id: StringName = p_character.id
	var portrait: AdvPortrait = get_portrait(character_id)
	var is_new: bool = portrait == null
	if is_new:
		portrait = PORTRAIT_SCENE.instantiate() as AdvPortrait
		if portrait == null:
			push_error("AdvStage: AdvPortrait の生成に失敗しました")
			return null
		portrait.character_id = character_id
		_portraits[character_id] = portrait
		add_child(portrait)

	_apply_character(portrait, p_character, p_pose, p_expression, _normalize_slot(p_slot))
	if is_new or p_duration > 0.0:
		return portrait.fade_in(p_duration)
	portrait.modulate.a = 1.0
	return null


## 既に居るキャラクターの差分と位置を更新する（フェード無し）。
func update_character(
	p_character: AdvCharacter,
	p_pose: StringName,
	p_expression: StringName,
	p_slot: StringName
) -> void:
	if p_character == null:
		return
	var portrait: AdvPortrait = get_portrait(p_character.id)
	if portrait == null:
		return
	_apply_character(portrait, p_character, p_pose, p_expression, _normalize_slot(p_slot))


## キャラクターを退場させる。duration が 0 以下なら即時解放する。
## 戻り値はフェードアウトの Tween。即時解放だった場合は null。
func hide_character(p_character_id: StringName, p_duration: float) -> Tween:
	var portrait: AdvPortrait = get_portrait(p_character_id)
	if portrait == null:
		return null
	_forget(p_character_id)
	return portrait.fade_out_and_free(p_duration)


func has_character(p_character_id: StringName) -> bool:
	return get_portrait(p_character_id) != null


## ステージ上に現在表示されているキャラクター ID の一覧を返す。
## AdvPlayer の汎用演出が全立ち絵へ適用するための読み取り API。
func get_character_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for character_id: StringName in _portraits.keys():
		if get_portrait(character_id) != null:
			result.append(character_id)
	return result


func get_portrait(p_character_id: StringName) -> AdvPortrait:
	if not _portraits.has(p_character_id):
		return null
	var portrait: AdvPortrait = _portraits[p_character_id]
	if not is_instance_valid(portrait):
		_forget(p_character_id)
		return null
	return portrait


## スロットの基準点（ステージ座標系）。縦は常にステージ下端。
func get_slot_base_position(p_slot: StringName) -> Vector2:
	var ratio: float = float(slot_ratios.get(_normalize_slot(p_slot), 0.5))
	return Vector2(size.x * ratio, size.y)


## そのスロットに置いたとき、立ち絵ノードの position になる値。
## move_portrait はここを Tween の目標にする。
func get_portrait_position_for(p_character_id: StringName, p_slot: StringName) -> Vector2:
	var portrait: AdvPortrait = get_portrait(p_character_id)
	var base: Vector2 = get_slot_base_position(p_slot)
	if portrait == null:
		return base
	return portrait.position_for_base(base)


## スロットの記録だけを更新する（立ち絵は動かさない）。
## 移動 Tween の開始前に呼ぶと、途中でリサイズされても移動先の比率で再配置される。
func set_character_slot(p_character_id: StringName, p_slot: StringName) -> void:
	if not _portraits.has(p_character_id):
		return
	_portrait_slots[p_character_id] = _normalize_slot(p_slot)


func get_character_slot(p_character_id: StringName) -> StringName:
	return _portrait_slots.get(p_character_id, DEFAULT_SLOT)


func get_character_pose(p_character_id: StringName) -> StringName:
	return _portrait_poses.get(p_character_id, &"")


func get_character_expression(p_character_id: StringName) -> StringName:
	return _portrait_expressions.get(p_character_id, &"")


## ステージ上の立ち絵をすべて即時に退場させる。
func clear() -> void:
	for character_id: StringName in _portraits.keys():
		var portrait: AdvPortrait = _portraits[character_id]
		if is_instance_valid(portrait):
			portrait.queue_free()
	_portraits.clear()
	_portrait_slots.clear()
	_portrait_poses.clear()
	_portrait_expressions.clear()


static func is_valid_slot(p_slot: StringName) -> bool:
	return VALID_SLOTS.has(p_slot)


func _apply_character(
	p_portrait: AdvPortrait,
	p_character: AdvCharacter,
	p_pose: StringName,
	p_expression: StringName,
	p_slot: StringName
) -> void:
	var character_id: StringName = p_character.id
	var pose: StringName = _resolve_pose(p_character, p_pose)
	var expression: StringName = _resolve_expression(p_character, p_expression)
	_portrait_slots[character_id] = p_slot
	_portrait_poses[character_id] = pose
	_portrait_expressions[character_id] = expression

	var texture_path: String = p_character.resolve_portrait(pose, expression)
	var pivot_ratio: Vector2 = Vector2(0.5, 1.0)
	var portrait_scale: float = 1.0
	if p_character.portrait_set != null:
		pivot_ratio = p_character.portrait_set.pivot_offset_ratio
		portrait_scale = p_character.portrait_set.scale
	p_portrait.apply(texture_path, pivot_ratio, portrait_scale)
	_position_portrait(p_portrait, p_slot)


## 空指定は「現在の表示値 → キャラクターの既定値」の順で埋める。
func _resolve_pose(p_character: AdvCharacter, p_pose: StringName) -> StringName:
	if not String(p_pose).is_empty():
		return p_pose
	var current: StringName = get_character_pose(p_character.id)
	if not String(current).is_empty():
		return current
	if p_character.portrait_set != null:
		return p_character.portrait_set.default_pose
	return &""


func _resolve_expression(p_character: AdvCharacter, p_expression: StringName) -> StringName:
	if not String(p_expression).is_empty():
		return p_expression
	var current: StringName = get_character_expression(p_character.id)
	if not String(current).is_empty():
		return current
	if p_character.portrait_set != null:
		return p_character.portrait_set.default_expression
	return &""


func _position_portrait(p_portrait: AdvPortrait, p_slot: StringName) -> void:
	p_portrait.set_slot_position_from_base(get_slot_base_position(p_slot))


func _reposition_all() -> void:
	for character_id: StringName in _portraits.keys():
		var portrait: AdvPortrait = get_portrait(character_id)
		if portrait != null:
			_position_portrait(portrait, get_character_slot(character_id))


func _forget(p_character_id: StringName) -> void:
	_portraits.erase(p_character_id)
	_portrait_slots.erase(p_character_id)
	_portrait_poses.erase(p_character_id)
	_portrait_expressions.erase(p_character_id)


func _normalize_slot(p_slot: StringName) -> StringName:
	if is_valid_slot(p_slot):
		return p_slot
	return DEFAULT_SLOT


func _on_stage_resized() -> void:
	_reposition_all()
