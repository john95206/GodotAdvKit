class_name AdvStage
extends Control
## 立ち絵の配置とライフサイクルを管理するステージ（仕様書 §5）。

const PORTRAIT_SCENE: PackedScene = preload("res://addons/adv_kit/ui/adv_portrait.tscn")
const VALID_SLOTS: Array[StringName] = [
	&"left", &"center_left", &"center", &"center_right", &"right",
]

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


func _ready() -> void:
	if not resized.is_connected(_on_stage_resized):
		resized.connect(_on_stage_resized)
	_reposition_all()


## キャラクターを生成または既存ノードへ適用し、指定スロットへ表示する。
func show_character(
	p_character: AdvCharacter,
	p_pose: StringName,
	p_expression: StringName,
	p_slot: StringName,
	p_duration: float
) -> void:
	if p_character == null:
		return

	var character_id: StringName = p_character.id
	var portrait: AdvPortrait = get_portrait(character_id)
	var is_new: bool = portrait == null
	if is_new:
		portrait = PORTRAIT_SCENE.instantiate() as AdvPortrait
		if portrait == null:
			push_error("AdvStage: AdvPortrait の生成に失敗しました")
			return
		portrait.character_id = character_id
		_portraits[character_id] = portrait
		add_child(portrait)

	var slot: StringName = _normalize_slot(p_slot)
	_portrait_slots[character_id] = slot
	_apply_character(portrait, p_character, p_pose, p_expression, slot)
	if is_new:
		portrait.fade_in(p_duration)


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
	var slot: StringName = _normalize_slot(p_slot)
	_portrait_slots[p_character.id] = slot
	_apply_character(portrait, p_character, p_pose, p_expression, slot)


## キャラクターを退場させる。duration が 0 以下なら即時解放する。
func hide_character(p_character_id: StringName, p_duration: float) -> void:
	var portrait: AdvPortrait = get_portrait(p_character_id)
	if portrait == null:
		return
	_portraits.erase(p_character_id)
	_portrait_slots.erase(p_character_id)
	portrait.fade_out_and_free(p_duration)


func has_character(p_character_id: StringName) -> bool:
	return get_portrait(p_character_id) != null


func get_portrait(p_character_id: StringName) -> AdvPortrait:
	if not _portraits.has(p_character_id):
		return null
	var portrait: AdvPortrait = _portraits[p_character_id]
	if not is_instance_valid(portrait):
		_portraits.erase(p_character_id)
		_portrait_slots.erase(p_character_id)
		return null
	return portrait


## ステージ上の立ち絵をすべて即時に退場させる。
func clear() -> void:
	for character_id: StringName in _portraits.keys():
		var portrait: AdvPortrait = _portraits[character_id]
		if is_instance_valid(portrait):
			portrait.queue_free()
	_portraits.clear()
	_portrait_slots.clear()


static func is_valid_slot(p_slot: StringName) -> bool:
	return VALID_SLOTS.has(p_slot)


func _apply_character(
	p_portrait: AdvPortrait,
	p_character: AdvCharacter,
	p_pose: StringName,
	p_expression: StringName,
	p_slot: StringName
) -> void:
	var texture_path: String = p_character.resolve_portrait(p_pose, p_expression)
	var pivot_ratio: Vector2 = Vector2(0.5, 1.0)
	var portrait_scale: float = 1.0
	if p_character.portrait_set != null:
		pivot_ratio = p_character.portrait_set.pivot_offset_ratio
		portrait_scale = p_character.portrait_set.scale
	p_portrait.apply(texture_path, pivot_ratio, portrait_scale)
	_position_portrait(p_portrait, p_slot)


func _position_portrait(p_portrait: AdvPortrait, p_slot: StringName) -> void:
	var ratio: float = float(slot_ratios.get(p_slot, 0.5))
	p_portrait.set_slot_position(size.x * ratio, size.y)


func _reposition_all() -> void:
	for character_id: StringName in _portraits.keys():
		var portrait: AdvPortrait = get_portrait(character_id)
		if portrait != null:
			_position_portrait(portrait, _portrait_slots.get(character_id, &"center"))


func _normalize_slot(p_slot: StringName) -> StringName:
	if is_valid_slot(p_slot):
		return p_slot
	return &"center"


func _on_stage_resized() -> void:
	_reposition_all()
