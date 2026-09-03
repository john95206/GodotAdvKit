class_name AdvFadeEffect
extends AdvEffectHandler
## 画面フェード（仕様書 §7）。fade_out / fade_in の 2 つの effect_id を 1 クラスで扱う。
## 排他ターゲット: fade_layer_alpha。
##
## FadeLayer は MessageWindow より前の兄弟なので、フェードしてもダイアログは隠れない（§5.1）。

const EFFECT_FADE_OUT := &"fade_out"
const EFFECT_FADE_IN := &"fade_in"
const DEFAULT_DURATION: float = 0.5


func is_fade_in() -> bool:
	return effect_id == EFFECT_FADE_IN


func play(p_ctx: AdvEffectContext, p_params: Dictionary) -> void:
	var fade_layer: ColorRect = p_ctx.fade_layer
	if fade_layer == null:
		push_warning("AdvFadeEffect: fade_layer が接続されていません。フェードをスキップします")
		return

	var duration: float = get_float(p_params, &"duration", DEFAULT_DURATION)
	var target_alpha: float = 0.0 if is_fade_in() else 1.0
	_apply_color(fade_layer, p_params)

	if duration <= 0.0:
		p_ctx.kill_targets(exclusive_targets(p_params))
		_set_alpha(fade_layer, target_alpha)
		return

	var tween: Tween = p_ctx.acquire_tween(exclusive_targets(p_params))
	if tween == null:
		_set_alpha(fade_layer, target_alpha)
		return
	tween.tween_property(fade_layer, "color:a", target_alpha, duration)
	await tween.finished


func apply_final(p_ctx: AdvEffectContext, p_params: Dictionary) -> void:
	var fade_layer: ColorRect = p_ctx.fade_layer
	if fade_layer == null:
		return
	p_ctx.kill_targets(exclusive_targets(p_params))
	_apply_color(fade_layer, p_params)
	_set_alpha(fade_layer, 0.0 if is_fade_in() else 1.0)


## fade_out は color を必ず反映する。fade_in の color は「省略可・実行時解決」なので、
## 指定が無ければ現在の色を維持する（仕様書 §7）。
func _apply_color(p_fade_layer: ColorRect, p_params: Dictionary) -> void:
	if not has_param(p_params, &"color"):
		return
	var color: Color = get_color(p_params, &"color", p_fade_layer.color)
	var current_alpha: float = p_fade_layer.color.a
	color.a = current_alpha
	p_fade_layer.color = color


func _set_alpha(p_fade_layer: ColorRect, p_alpha: float) -> void:
	var color: Color = p_fade_layer.color
	color.a = p_alpha
	p_fade_layer.color = color
