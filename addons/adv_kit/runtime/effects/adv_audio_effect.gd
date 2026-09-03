class_name AdvAudioEffect
extends AdvEffectHandler
## SE と BGM（仕様書 §7）。play_se / play_bgm / stop_bgm の 3 つを 1 クラスで扱う。
##
## 実処理は [AdvAudioDirector] が持つ。ここは params の取り出しと委譲だけ。
##
## [b]apply_final() は 3 つとも何もしない。[/b] スキップ中に音を鳴らさないため（仕様書 §9.3）。

const EFFECT_PLAY_SE := &"play_se"
const EFFECT_PLAY_BGM := &"play_bgm"
const EFFECT_STOP_BGM := &"stop_bgm"


func play(p_ctx: AdvEffectContext, p_params: Dictionary) -> void:
	var audio: AdvAudioDirector = p_ctx.audio
	if audio == null:
		push_warning("AdvAudioEffect: AdvAudioDirector が接続されていません: %s" % effect_id)
		return
	match effect_id:
		EFFECT_PLAY_SE:
			# ワンショット。完了を待たない（多重再生可・仕様書 §7）。
			audio.play_se(
				get_string(p_params, &"stream", ""),
				get_float(p_params, &"volume_db", 0.0))
		EFFECT_PLAY_BGM:
			audio.play_bgm(
				get_string(p_params, &"stream", ""),
				get_float(p_params, &"fade_in_time", 0.0),
				get_bool(p_params, &"loop", true))
		EFFECT_STOP_BGM:
			audio.stop_bgm(get_float(p_params, &"fade_out_time", 0.0))
		_:
			push_warning("AdvAudioEffect: 未知の effect_id: %s" % effect_id)


## 仕様書 §9.3: 音声系の apply_final() は何もしない。
## [b]既知の穴[/b]: スキップで stop_bgm を飛ばすと BGM が鳴り続ける。
## 仕様どおりに実装し、判断は phase-06 に持ち越す。
func apply_final(_p_ctx: AdvEffectContext, _p_params: Dictionary) -> void:
	pass
