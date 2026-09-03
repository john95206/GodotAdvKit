@abstract
class_name AdvEffectHandler
extends RefCounted
## 局所演出の抽象基底（仕様書 §7）。
##
## ゲーム側はこれを継承したクラスを [method AdvPlayer.register_effect] へ登録することで
## 演出を追加できる。Kit のコアに手を入れさせない。
##
## [b]effect_id はハンドラのフィールドにする。[/b] register_effect() が代入するので、
## 1 クラスで複数の演出（fade_out / fade_in など）を扱える。同じクラスを 2 つの id に
## 登録するときは[b]別インスタンス[/b]にすること。

## register_effect() が代入する。
var effect_id: StringName = &""


## 通常再生。[b]完了まで await できること。[/b]
@abstract func play(p_ctx: AdvEffectContext, p_params: Dictionary) -> void


## スキップ時（phase-06）。再生せず「完了後の状態」だけを即座に適用する（仕様書 §9.3）。
## [b]音声系は何もしない実装にする。[/b]
@abstract func apply_final(p_ctx: AdvEffectContext, p_params: Dictionary) -> void


## この演出が占有する排他ターゲット（仕様書 §7）。
## 既定は §7 の表を引く。[b]拡張演出はこれを override して自分のターゲットを宣言する。[/b]
## 宣言しなければ空集合＝衝突検査の対象外。
func exclusive_targets(p_params: Dictionary) -> PackedStringArray:
	return AdvEffectSchema.exclusive_targets(effect_id, p_params)


## params から float を取り出す。未指定・型違いなら既定値。
static func get_float(p_params: Dictionary, p_key: StringName, p_default: float) -> float:
	if not p_params.has(p_key):
		return p_default
	var converted: Variant = AdvEffectSchema.convert_value(
		p_params[p_key], AdvEffectSchema.ParamType.FLOAT)
	if converted == null:
		return p_default
	return converted


## params から String を取り出す。
static func get_string(p_params: Dictionary, p_key: StringName, p_default: String) -> String:
	if not p_params.has(p_key):
		return p_default
	var converted: Variant = AdvEffectSchema.convert_value(
		p_params[p_key], AdvEffectSchema.ParamType.STRING)
	if converted == null:
		return p_default
	return converted


## params から bool を取り出す。
static func get_bool(p_params: Dictionary, p_key: StringName, p_default: bool) -> bool:
	if not p_params.has(p_key):
		return p_default
	var converted: Variant = AdvEffectSchema.convert_value(
		p_params[p_key], AdvEffectSchema.ParamType.BOOL)
	if converted == null:
		return p_default
	return converted


## params から Color を取り出す。[b]省略可・実行時解決（fade_in の color）を判別できるよう、
## has_color() と併用する。[/b]
static func get_color(p_params: Dictionary, p_key: StringName, p_default: Color) -> Color:
	if not p_params.has(p_key):
		return p_default
	var converted: Variant = AdvEffectSchema.convert_value(
		p_params[p_key], AdvEffectSchema.ParamType.COLOR)
	if converted == null:
		return p_default
	return converted


static func has_param(p_params: Dictionary, p_key: StringName) -> bool:
	return p_params.has(p_key)
