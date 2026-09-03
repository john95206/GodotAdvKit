class_name AdvShakeEffect
extends AdvEffectHandler
## 画面揺れ（仕様書 §7）。排他ターゲット: shake_root_position。
##
## 揺らすのは ShakeRoot（背景＋立ち絵）だけ。FadeLayer と MessageWindow は揺れない（§5.1）。
## [b]tween_property では周波数を表現できない[/b]ため、tween_method + 自前のサイン波減衰を使う。
## pivot_offset は使わない（回転ではなく平行移動）。

const DEFAULT_STRENGTH: float = 8.0
const DEFAULT_DURATION: float = 0.4
const DEFAULT_FREQUENCY: float = 24.0


func play(p_ctx: AdvEffectContext, p_params: Dictionary) -> void:
	var shake_root: Control = p_ctx.shake_root
	if shake_root == null:
		push_warning("AdvShakeEffect: shake_root が接続されていません。揺れをスキップします")
		return

	var strength: float = get_float(p_params, &"strength", DEFAULT_STRENGTH)
	var duration: float = get_float(p_params, &"duration", DEFAULT_DURATION)
	var frequency: float = get_float(p_params, &"frequency", DEFAULT_FREQUENCY)
	if duration <= 0.0 or strength <= 0.0:
		shake_root.position = Vector2.ZERO
		return

	# 中断されたときも必ず原点へ戻す（仕様書 §7: 終了時に必ず Vector2.ZERO へ戻す）。
	var tween: Tween = p_ctx.acquire_tween(
		exclusive_targets(p_params), _reset.bind(shake_root))
	if tween == null:
		shake_root.position = Vector2.ZERO
		return

	tween.tween_method(
		_apply_offset.bind(shake_root, strength, frequency, duration), 0.0, duration, duration)
	tween.tween_callback(_reset.bind(shake_root))
	await tween.finished


func apply_final(p_ctx: AdvEffectContext, p_params: Dictionary) -> void:
	p_ctx.kill_targets(exclusive_targets(p_params))
	if p_ctx.shake_root != null:
		p_ctx.shake_root.position = Vector2.ZERO


## 経過時間 t から減衰したサイン波のオフセットを作る。
func _apply_offset(
	p_elapsed: float,
	p_shake_root: Control,
	p_strength: float,
	p_frequency: float,
	p_duration: float
) -> void:
	if not is_instance_valid(p_shake_root):
		return
	var decay: float = maxf(1.0 - p_elapsed / p_duration, 0.0)
	var amplitude: float = p_strength * decay
	var phase: float = p_elapsed * p_frequency * TAU
	p_shake_root.position = Vector2(
		sin(phase) * amplitude,
		# 縦は横の半分・位相をずらして、単純な往復に見えないようにする。
		cos(phase * 0.7) * amplitude * 0.5)


func _reset(p_shake_root: Control) -> void:
	if is_instance_valid(p_shake_root):
		p_shake_root.position = Vector2.ZERO
