class_name AdvPortraitEffect
extends AdvEffectHandler
## 立ち絵の登場・退場・移動（仕様書 §7）。
## show_portrait / hide_portrait / move_portrait の 3 つの effect_id を 1 クラスで扱う。
##
## 排他ターゲット: portrait_alpha:{speaker} / portrait_position:{speaker}。
## hide はノードの解放を伴うため、そのキャラの[b]全ターゲットを占有する[/b]。
##
## [b]alpha の Tween は AdvPortrait が作ったものを台帳へ載せる（adopt）。[/b]
## ここで別の Tween を作ると、暗黙の登場（line 起因のフェード）と二重に modulate を書くため。

const EFFECT_SHOW := &"show_portrait"
const EFFECT_HIDE := &"hide_portrait"
const EFFECT_MOVE := &"move_portrait"

const DEFAULT_SHOW_DURATION: float = 0.2
const DEFAULT_HIDE_DURATION: float = 0.2
const DEFAULT_MOVE_DURATION: float = 0.4


func play(p_ctx: AdvEffectContext, p_params: Dictionary) -> void:
	match effect_id:
		EFFECT_SHOW:
			await _play_show(p_ctx, p_params)
		EFFECT_HIDE:
			await _play_hide(p_ctx, p_params)
		EFFECT_MOVE:
			await _play_move(p_ctx, p_params)
		_:
			push_warning("AdvPortraitEffect: 未知の effect_id: %s" % effect_id)


func apply_final(p_ctx: AdvEffectContext, p_params: Dictionary) -> void:
	p_ctx.kill_targets(exclusive_targets(p_params))
	match effect_id:
		EFFECT_SHOW:
			_show_immediate(p_ctx, p_params)
		EFFECT_HIDE:
			var speaker_id: StringName = _speaker_id(p_params)
			if p_ctx.stage != null:
				p_ctx.stage.hide_character(speaker_id, 0.0)
		EFFECT_MOVE:
			_move_immediate(p_ctx, p_params)


func _play_show(p_ctx: AdvEffectContext, p_params: Dictionary) -> void:
	var character: AdvCharacter = _require_character(p_ctx, p_params)
	if character == null or p_ctx.stage == null:
		return
	var slot: StringName = _slot(p_params, &"slot", &"center")
	var duration: float = get_float(p_params, &"duration", DEFAULT_SHOW_DURATION)
	var tween: Tween = p_ctx.stage.show_character(character, &"", &"", slot, duration)
	if tween == null:
		p_ctx.kill_targets(exclusive_targets(p_params))
		return
	p_ctx.adopt_tween(exclusive_targets(p_params), tween)
	await tween.finished


func _play_hide(p_ctx: AdvEffectContext, p_params: Dictionary) -> void:
	var speaker_id: StringName = _speaker_id(p_params)
	if p_ctx.stage == null:
		return
	if not p_ctx.stage.has_character(speaker_id):
		push_warning("AdvPortraitEffect: hide_portrait: ステージに居ません: %s" % speaker_id)
		return
	var duration: float = get_float(p_params, &"duration", DEFAULT_HIDE_DURATION)
	var tween: Tween = p_ctx.stage.hide_character(speaker_id, duration)
	if tween == null:
		p_ctx.kill_targets(exclusive_targets(p_params))
		return
	p_ctx.adopt_tween(exclusive_targets(p_params), tween)
	await tween.finished


func _play_move(p_ctx: AdvEffectContext, p_params: Dictionary) -> void:
	var speaker_id: StringName = _speaker_id(p_params)
	if p_ctx.stage == null:
		return
	var portrait: AdvPortrait = p_ctx.get_portrait(speaker_id)
	if portrait == null:
		push_warning("AdvPortraitEffect: move_portrait: ステージに居ません: %s" % speaker_id)
		return

	var to_slot: StringName = _slot(p_params, &"to_slot", &"center")
	var duration: float = get_float(p_params, &"duration", DEFAULT_MOVE_DURATION)
	# 記録を先に更新する。リサイズ時の再配置が移動先の比率を使うようにするため。
	p_ctx.stage.set_character_slot(speaker_id, to_slot)
	var target: Vector2 = p_ctx.stage.get_portrait_position_for(speaker_id, to_slot)

	if duration <= 0.0:
		p_ctx.kill_targets(exclusive_targets(p_params))
		portrait.position = target
		return

	var tween: Tween = p_ctx.acquire_tween(exclusive_targets(p_params))
	if tween == null:
		portrait.position = target
		return
	tween.set_ease(_ease_from_string(get_string(p_params, &"ease", "out")))
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(portrait, "position", target, duration)
	await tween.finished


func _show_immediate(p_ctx: AdvEffectContext, p_params: Dictionary) -> void:
	var character: AdvCharacter = _require_character(p_ctx, p_params)
	if character == null or p_ctx.stage == null:
		return
	p_ctx.stage.show_character(character, &"", &"", _slot(p_params, &"slot", &"center"), 0.0)


func _move_immediate(p_ctx: AdvEffectContext, p_params: Dictionary) -> void:
	var speaker_id: StringName = _speaker_id(p_params)
	if p_ctx.stage == null:
		return
	var portrait: AdvPortrait = p_ctx.get_portrait(speaker_id)
	if portrait == null:
		return
	var to_slot: StringName = _slot(p_params, &"to_slot", &"center")
	p_ctx.stage.set_character_slot(speaker_id, to_slot)
	portrait.position = p_ctx.stage.get_portrait_position_for(speaker_id, to_slot)


func _speaker_id(p_params: Dictionary) -> StringName:
	return StringName(get_string(p_params, &"speaker", ""))


## speaker が book に無い場合は警告して null。[b]進行は止めない。[/b]
func _require_character(p_ctx: AdvEffectContext, p_params: Dictionary) -> AdvCharacter:
	var speaker_id: StringName = _speaker_id(p_params)
	if String(speaker_id).is_empty():
		push_warning("AdvPortraitEffect: %s に speaker が指定されていません" % effect_id)
		return null
	var character: AdvCharacter = p_ctx.get_character(speaker_id)
	if character == null:
		push_warning("AdvPortraitEffect: 未知の speaker: %s" % speaker_id)
	return character


func _slot(p_params: Dictionary, p_key: StringName, p_default: StringName) -> StringName:
	var raw: StringName = StringName(get_string(p_params, p_key, String(p_default)))
	if AdvStage.is_valid_slot(raw):
		return raw
	push_warning("AdvPortraitEffect: 未知のスロット \"%s\"。%s を使います" % [raw, p_default])
	return p_default


static func _ease_from_string(p_ease: String) -> Tween.EaseType:
	match p_ease.strip_edges().to_lower():
		"in":
			return Tween.EASE_IN
		"in_out":
			return Tween.EASE_IN_OUT
		"out_in":
			return Tween.EASE_OUT_IN
	return Tween.EASE_OUT
