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


## ShakeRoot はアンカー無しの中間ノードなので、[b]サイズだけ[/b]親へ追従させる。
## 子の Background / Stage は full-rect アンカーでこのサイズに追従する。
##
## [b]position は書かない。[/b] ShakeRoot.position の持ち主は shake 演出であり
## （仕様書 §5.1）、リサイズのたびにここでゼロへ戻すと揺れが打ち消される。
func _sync_shake_root_size() -> void:
	if _shake_root == null:
		return
	_shake_root.size = size
