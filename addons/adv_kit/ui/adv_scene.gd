class_name AdvScene
extends Control
## ADV の標準ノード構成。ゲーム側はこのシーンをインスタンスする。

@export var player: AdvPlayer

@onready var _shake_root: Control = get_node("ShakeRoot") as Control


func _ready() -> void:
	if not resized.is_connected(_on_scene_resized):
		resized.connect(_on_scene_resized)
	_sync_shake_root_size()


func _on_scene_resized() -> void:
	_sync_shake_root_size()


## ShakeRoot はアンカー無しの中間ノードなので、サイズだけ親へ追従させる。
## 子の Background / Stage は full-rect アンカーでこのサイズに追従する。
func _sync_shake_root_size() -> void:
	_shake_root.position = Vector2.ZERO
	_shake_root.size = size
