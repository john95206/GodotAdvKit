class_name AdvEffectStep
extends AdvStep
## 局所演出（仕様書 §4.3 / §7）。

## 直前のステップと同時に走るか、独立した1ステップとして待たれるか。
enum SyncMode {
	## 直前のステップの開始と同時に再生を開始する。テキスト送りを妨げず、完了も待たない。
	PARALLEL,
	## この演出を独立した1ステップとして扱う。完了までテキスト送り入力を受け付けない。
	BLOCKING,
}

## 演出ID。仕様書 §7 の表を参照。
@export var effect_id: StringName = &""

## 演出ごとのパラメータ。キーと値の型は §7 の表（AdvEffectSchema）が定義する。
## [b]仕様上ここだけは Variant を許容する。[/b]
@export var params: Dictionary = {}

## 同期モード。
@export var sync_mode: SyncMode = SyncMode.BLOCKING

## BLOCKING のときのみ有効。true なら演出完了後に自動で次ステップへ進む。
@export var auto_advance: bool = false


func is_parallel() -> bool:
	return sync_mode == SyncMode.PARALLEL


## "parallel" / "blocking" 文字列から SyncMode へ。
## 空文字と未知の値は BLOCKING（仕様書 §6.1: 空なら blocking）。
static func sync_mode_from_string(p_value: String) -> SyncMode:
	if p_value.strip_edges().to_lower() == "parallel":
		return SyncMode.PARALLEL
	return SyncMode.BLOCKING


func get_class_label() -> String:
	return "effect"


func describe() -> String:
	var mode: String = "parallel" if is_parallel() else "blocking"
	return "effect(order=%d, id=%s, sync=%s)" % [order, effect_id, mode]
