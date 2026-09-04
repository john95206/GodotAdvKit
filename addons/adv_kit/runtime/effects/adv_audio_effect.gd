class_name AdvAudioEffect
extends AdvEffectHandler
## SE と BGM（仕様書 §7）。play_se / play_bgm / stop_bgm の 3 つを 1 クラスで扱う。
##
## 実処理は [AdvAudioDirector] が持つ。ここは params の取り出しと委譲だけ。
##
## [b]apply_final() は play_se / play_bgm では何もしない[/b]（スキップ中に音を鳴らさないため。仕様書 §9.3）。
## [b]stop_bgm だけは即座に止める[/b]（U-08 の B 案。2026-09-03 確定）。
## 「スキップ中に音を鳴らさない」を破らずに、
## 「スキップで停止を飛ばすと BGM が鳴り続ける」穴だけを塞ぐ。

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


## スキップ時の即時適用（仕様書 §9.3 / U-08 の B 案）。
##
## [br]・`play_se` / `play_bgm` … 何もしない。スキップ中に音を鳴らさないため
## [br]・`stop_bgm` … [b]フェード時間を無視して即座に止める[/b]。
##   「完了後の状態」＝無音なので、これを適用するのが §9.3 の主旨に合う。
##   何もしないと、スキップで停止を飛ばした BGM が鳴り続ける
func apply_final(p_ctx: AdvEffectContext, _p_params: Dictionary) -> void:
	if effect_id != EFFECT_STOP_BGM:
		return
	var audio: AdvAudioDirector = p_ctx.audio
	if audio == null:
		return
	audio.stop_bgm(0.0)
