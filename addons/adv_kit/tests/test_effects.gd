extends SceneTree
## phase-03 の演出・ボイス・進行制御テスト。
##
## 実行方法（[b]--import を先に1回走らせること[/b]）:
## [codeblock]
## godot --headless --import
## godot --headless --script res://addons/adv_kit/tests/test_effects.gd
## [/codeblock]
##
## [b]実素材（立ち絵・音源）が 1 つも無い前提で全部通ること[/b]が要件。
## 実際に音を鳴らす経路だけは、テスト用の極小 AudioStreamWAV（tests/assets/test_tone.tres）で検証する。

const ADV_SCENE: PackedScene = preload("res://addons/adv_kit/ui/adv_scene.tscn")
const TONE_PATH: String = "res://addons/adv_kit/tests/assets/test_tone.tres"
const MISSING_PATH: String = "res://game/assets/adv/se/does_not_exist.ogg"

var _failed: int = 0
var _passed: int = 0

var _scene: AdvScene = null
var _player: AdvPlayer = null
var _stage: AdvStage = null
var _shake_root: Control = null
var _fade_layer: ColorRect = null


## 拡張演出のテスト用。排他ターゲットを自分で宣言する（仕様書 §7 の拡張規約）。
class ProbeEffect extends AdvEffectHandler:
	var play_count: int = 0
	var final_count: int = 0
	var last_params: Dictionary = {}
	var targets: PackedStringArray = PackedStringArray(["probe_target"])
	var frames_to_wait: int = 0
	var tree: SceneTree = null

	func play(_p_ctx: AdvEffectContext, p_params: Dictionary) -> void:
		play_count += 1
		last_params = p_params.duplicate()
		for i: int in frames_to_wait:
			await tree.process_frame

	func apply_final(_p_ctx: AdvEffectContext, p_params: Dictionary) -> void:
		final_count += 1
		last_params = p_params.duplicate()

	func exclusive_targets(_p_params: Dictionary) -> PackedStringArray:
		return targets


func _initialize() -> void:
	print("=== ADV Kit phase-03 / test_effects ===")
	_scene = ADV_SCENE.instantiate() as AdvScene
	root.add_child(_scene)
	await process_frame
	_scene.size = Vector2(800.0, 450.0)
	await process_frame

	_player = _scene.player
	_stage = _scene.get_node("ShakeRoot/Stage") as AdvStage
	_shake_root = _scene.get_node("ShakeRoot") as Control
	_fade_layer = _scene.get_node("FadeLayer") as ColorRect
	if _player == null or _stage == null or _shake_root == null or _fade_layer == null:
		print("FAILED: AdvScene の構成が想定と違います")
		quit(1)
		return

	var settings := AdvKitSettings.new()
	settings.typing_speed = 0.0
	_player.setup(_make_book(), settings)

	await _test_scene_does_not_own_shake_position()
	await _test_tween_ledger()
	await _test_shake()
	await _test_fade()
	await _test_portrait_effects()
	await _test_audio_guard_and_director()
	await _test_voice()
	await _test_blocking_progression()
	await _test_parallel_progression()
	await _test_register_effect()
	await _test_stop_during_effect()

	_scene.queue_free()
	await process_frame

	print("--- 結果 ---")
	print("%d 件実行 / 成功 %d / 失敗 %d" % [_passed + _failed, _passed, _failed])
	if _failed > 0:
		quit(1)
		return
	print("OK")
	quit(0)


# --- T-01: AdvScene は ShakeRoot.position を書かない -------------------------

func _test_scene_does_not_own_shake_position() -> void:
	_shake_root.position = Vector2(13.0, 7.0)
	_scene.size = Vector2(1024.0, 576.0)
	await process_frame
	_check(_shake_root.size == _scene.size, "リサイズで ShakeRoot のサイズが追従する")
	_check(_stage.size == _shake_root.size, "Stage が ShakeRoot の full-rect に追従する")
	_check(
		_shake_root.position == Vector2(13.0, 7.0),
		"リサイズしても ShakeRoot.position が書き換えられない")
	_shake_root.position = Vector2.ZERO


# --- T-04: 排他ターゲットの Tween 台帳 ---------------------------------------

func _test_tween_ledger() -> void:
	var ctx: AdvEffectContext = _player.get_effect_context()
	_check(ctx != null, "AdvEffectContext が構築されている")
	if ctx == null:
		return

	var interrupted: Array[int] = [0]
	var first: Tween = ctx.acquire_tween(
		PackedStringArray(["target_a"]), func() -> void: interrupted[0] += 1)
	first.tween_interval(10.0)
	var other: Tween = ctx.acquire_tween(PackedStringArray(["target_b"]))
	other.tween_interval(10.0)
	_check(first.is_running() and other.is_running(), "別ターゲットの Tween は共存する")
	_check(
		ctx.active_targets() == PackedStringArray(["target_a", "target_b"]),
		"占有中のターゲットが台帳に載る")

	var second: Tween = ctx.acquire_tween(PackedStringArray(["target_a"]))
	second.tween_interval(10.0)
	_check(not first.is_valid(), "同じターゲットを取り直すと前の Tween が kill される")
	_check(interrupted[0] == 1, "中断された Tween の後始末が呼ばれる")
	_check(other.is_valid(), "無関係なターゲットの Tween は生き残る")

	# 自然完了では後始末を呼ばない。
	var finished_interrupts: Array[int] = [0]
	var quick: Tween = ctx.acquire_tween(
		PackedStringArray(["target_c"]), func() -> void: finished_interrupts[0] += 1)
	quick.tween_interval(0.01)
	await quick.finished
	await process_frame
	_check(finished_interrupts[0] == 0, "自然完了では中断後始末を呼ばない")
	_check(
		not ctx.active_targets().has("target_c"),
		"完了した Tween は台帳から自動で外れる")

	ctx.kill_all()
	_check(ctx.active_targets().is_empty(), "kill_all() で台帳が空になる")


# --- T-08: shake ------------------------------------------------------------

func _test_shake() -> void:
	var ctx: AdvEffectContext = _player.get_effect_context()
	var handler: AdvEffectHandler = _player.get_effect_handler(&"shake")
	_check(handler != null, "shake が組み込みで登録されている")
	_check(
		handler.exclusive_targets({}) == PackedStringArray(["shake_root_position"]),
		"shake の排他ターゲットが §7 の表と一致する")

	var params: Dictionary = {&"strength": 8.0, &"duration": 0.2, &"frequency": 24.0}
	var moved: Array[bool] = [false]
	var play_done: Array[bool] = [false]
	_run_effect(handler, ctx, params, play_done)
	for i: int in 12:
		await process_frame
		if _shake_root.position != Vector2.ZERO:
			moved[0] = true
	_check(moved[0], "shake が ShakeRoot.position を動かす")

	var guard: int = 0
	while not play_done[0] and guard < 120:
		await process_frame
		guard += 1
	_check(play_done[0], "shake が完了する")
	_check(_shake_root.position == Vector2.ZERO, "shake 完了後に position が原点へ戻る")

	# 中断されても原点へ戻る。
	_run_effect(handler, ctx, params, [false])
	await process_frame
	ctx.kill_targets(PackedStringArray(["shake_root_position"]))
	_check(_shake_root.position == Vector2.ZERO, "shake を中断しても position が原点へ戻る")

	_shake_root.position = Vector2(5.0, 5.0)
	handler.apply_final(ctx, params)
	_check(_shake_root.position == Vector2.ZERO, "shake の apply_final() が即座に原点へ戻す")


# --- T-09: fade -------------------------------------------------------------

func _test_fade() -> void:
	var ctx: AdvEffectContext = _player.get_effect_context()
	var fade_out: AdvEffectHandler = _player.get_effect_handler(&"fade_out")
	var fade_in: AdvEffectHandler = _player.get_effect_handler(&"fade_in")
	_check(fade_out != null and fade_in != null, "fade_out / fade_in が登録されている")
	_check(
		fade_out.exclusive_targets({}) == fade_in.exclusive_targets({}),
		"fade_out と fade_in が同じ排他ターゲットを持つ")

	_fade_layer.color = Color(0.0, 0.0, 0.0, 0.0)
	var out_done: Array[bool] = [false]
	_run_effect(
		fade_out, ctx, {&"duration": 0.15, &"color": Color(1.0, 0.0, 0.0)}, out_done)
	await _wait_until(out_done, 120)
	_check(out_done[0], "fade_out が完了する")
	_check(is_equal_approx(_fade_layer.color.a, 1.0), "fade_out 完了後に alpha が 1")
	_check(
		is_equal_approx(_fade_layer.color.r, 1.0),
		"fade_out の color がそのまま反映される")

	var in_done: Array[bool] = [false]
	_run_effect(fade_in, ctx, {&"duration": 0.15}, in_done)
	await _wait_until(in_done, 120)
	_check(is_equal_approx(_fade_layer.color.a, 0.0), "fade_in 完了後に alpha が 0")
	_check(
		is_equal_approx(_fade_layer.color.r, 1.0),
		"fade_in で color を省略すると直前の色が保たれる")

	fade_out.apply_final(ctx, {&"color": Color(0.0, 0.0, 1.0)})
	_check(
		is_equal_approx(_fade_layer.color.a, 1.0) and is_equal_approx(_fade_layer.color.b, 1.0),
		"fade_out の apply_final() が到達状態を即座に適用する")
	fade_in.apply_final(ctx, {})
	_check(is_equal_approx(_fade_layer.color.a, 0.0), "fade_in の apply_final() が alpha 0 にする")


# --- T-10: 立ち絵演出 --------------------------------------------------------

func _test_portrait_effects() -> void:
	var ctx: AdvEffectContext = _player.get_effect_context()
	var show_handler: AdvEffectHandler = _player.get_effect_handler(&"show_portrait")
	var move_handler: AdvEffectHandler = _player.get_effect_handler(&"move_portrait")
	var hide_handler: AdvEffectHandler = _player.get_effect_handler(&"hide_portrait")
	_stage.clear()
	await process_frame

	_check(
		show_handler.exclusive_targets({&"speaker": "yuu"})
			== PackedStringArray(["portrait_alpha:yuu"]),
		"show_portrait の排他ターゲットに speaker が入る")
	_check(
		hide_handler.exclusive_targets({&"speaker": "yuu"}).size() == 2,
		"hide_portrait はそのキャラの全ターゲットを占有する")

	var show_done: Array[bool] = [false]
	_run_effect(
		show_handler, ctx, {&"speaker": "yuu", &"slot": "left", &"duration": 0.1}, show_done)
	await _wait_until(show_done, 120)
	_check(_stage.has_character(&"yuu"), "show_portrait で立ち絵が登場する")
	_check(
		is_equal_approx(_stage.get_portrait(&"yuu").modulate.a, 1.0),
		"show_portrait 完了後に alpha が 1")
	_check(_stage.get_character_slot(&"yuu") == &"left", "指定スロットが記録される")

	# 未知の speaker でも落ちない。
	_run_effect(show_handler, ctx, {&"speaker": "nobody"}, [false])
	await process_frame
	_check(not _stage.has_character(&"nobody"), "未知の speaker では立ち絵が増えない")
	_check(_stage.get_child_count() == 1, "未知の speaker で進行が壊れない")

	# 移動。
	var move_done: Array[bool] = [false]
	_run_effect(
		move_handler, ctx, {&"speaker": "yuu", &"to_slot": "right", &"duration": 0.15}, move_done)
	await _wait_until(move_done, 120)
	_check(_stage.get_character_slot(&"yuu") == &"right", "move_portrait でスロット記録が更新される")
	_check(
		is_equal_approx(
			_stage.get_portrait(&"yuu").position.x,
			_stage.get_portrait_position_for(&"yuu", &"right").x),
		"move_portrait が移動先の座標へ到達する")

	# 移動後にリサイズしても新しいスロットの比率に追従する。
	_scene.size = Vector2(1200.0, 675.0)
	await process_frame
	_check(
		is_equal_approx(
			_stage.get_portrait(&"yuu").position.x,
			_stage.get_portrait_position_for(&"yuu", &"right").x),
		"移動後のリサイズで新スロットの比率に追従する")

	# 退場。
	var hide_done: Array[bool] = [false]
	_run_effect(hide_handler, ctx, {&"speaker": "yuu", &"duration": 0.1}, hide_done)
	await _wait_until(hide_done, 120)
	await process_frame
	_check(not _stage.has_character(&"yuu"), "hide_portrait で立ち絵が退場する")
	_check(_stage.get_child_count() == 0, "hide_portrait 完了後にノードが解放される")

	# 「後から始まった方が勝つ」: フェードアウト中に show すると解放されない。
	_run_effect(show_handler, ctx, {&"speaker": "yuu", &"duration": 0.0}, [false])
	await process_frame
	_run_effect(hide_handler, ctx, {&"speaker": "yuu", &"duration": 1.0}, [false])
	await process_frame
	_run_effect(show_handler, ctx, {&"speaker": "yuu", &"duration": 0.05}, [false])
	for i: int in 20:
		await process_frame
	_check(_stage.has_character(&"yuu"), "退場の途中で show すると解放されず残る")
	_stage.clear()
	await process_frame


# --- T-06 / T-11: 音声と autoplay ガード -------------------------------------

func _test_audio_guard_and_director() -> void:
	var audio: AdvAudioDirector = _player.get_audio_director()
	_check(audio != null, "AdvAudioDirector が AdvPlayer の子として生成されている")
	_check(not _player.is_audio_unlocked(), "setup() 直後は autoplay ガードが閉じている")

	audio.play_se(TONE_PATH, 0.0)
	_check(audio.se_request_count() == 0, "ガードが閉じている間は SE を要求しない")
	_check(not audio.is_bgm_playing(), "ガードが閉じている間は BGM が鳴らない")

	_player.unlock_audio()
	_check(_player.is_audio_unlocked(), "unlock_audio() でガードが開く")

	# 存在しない音源でも例外にならず、要求だけが記録される。
	audio.play_se(MISSING_PATH, 0.0)
	_check(audio.se_request_count() == 1, "存在しない音源でも要求は記録される")
	_check(audio.se_play_count() == 0, "存在しない音源は再生されない")

	audio.play_se(TONE_PATH, -6.0)
	audio.play_se(TONE_PATH, -6.0)
	await process_frame
	_check(audio.se_play_count() == 2, "SE は多重再生できる")

	audio.play_bgm(MISSING_PATH, 0.0, true)
	_check(audio.requested_bgm_path() == MISSING_PATH, "存在しない BGM でも要求は記録される")
	_check(not audio.is_bgm_playing(), "存在しない BGM は鳴らない")

	audio.play_bgm(TONE_PATH, 0.0, true)
	await process_frame
	_check(audio.is_bgm_playing(), "BGM が再生される")
	_check(audio.current_bgm_path() == TONE_PATH, "現在の BGM パスが記録される")

	audio.stop_bgm(0.0)
	await process_frame
	_check(not audio.is_bgm_playing(), "stop_bgm(0) で即座に止まる")
	_check(audio.current_bgm_path().is_empty(), "停止後は現在の BGM パスが空になる")

	# クロスフェードの途中で止めても片方だけ残らない。
	audio.play_bgm(TONE_PATH, 0.3, true)
	await process_frame
	audio.stop_bgm(0.05)
	var guard: int = 0
	while audio.is_bgm_playing() and guard < 120:
		await process_frame
		guard += 1
	_check(not audio.is_bgm_playing(), "クロスフェード中に stop_bgm しても全チャンネルが止まる")

	audio.stop_all()
	await process_frame


# --- T-07 / T-14: ボイス -----------------------------------------------------

func _test_voice() -> void:
	var voice: AdvVoicePlayer = _player.get_voice_player()
	_check(voice != null, "AdvVoicePlayer が AdvPlayer の子として生成されている")

	voice.play_voice("")
	_check(not voice.is_playing(), "空の voice_path では何も再生しない")

	voice.play_voice(MISSING_PATH)
	_check(not voice.is_playing(), "存在しないボイスでも例外にならない")

	voice.play_voice(TONE_PATH)
	await process_frame
	_check(voice.is_playing(), "ボイスが再生される")
	_check(voice.get_remaining_time() > 0.0, "残り再生時間が取れる")
	_check(voice.current_path() == TONE_PATH, "再生中のパスが取れる")

	voice.play_voice(TONE_PATH)
	await process_frame
	_check(voice.is_playing(), "続けて再生しても鳴り続ける（前は停止済み）")

	voice.stop()
	_check(not voice.is_playing(), "stop() でボイスが止まる")
	_check(voice.get_remaining_time() == 0.0, "停止後の残り時間は 0")


# --- T-13: BLOCKING の進行制御 ----------------------------------------------

func _test_blocking_progression() -> void:
	var shown: Array[int] = [0]
	var callback: Callable = func(_topic_id: StringName, _uid: StringName) -> void:
		shown[0] += 1
	_player.step_shown.connect(callback)

	# auto_advance = true: 入力なしで次の line まで進む。
	shown[0] = 0
	_player.play_topic(&"blocking_auto")
	_player.advance()  # 1 行目 -> 演出
	var guard: int = 0
	while _player.is_busy() and guard < 200:
		await process_frame
		guard += 1
	await process_frame
	_check(not _player.is_busy(), "BLOCKING 演出が完了して busy が解ける")
	_check(shown[0] == 3, "auto_advance=true は入力なしで次の line まで進む")
	_player.stop()

	# auto_advance = false: 演出完了後にテキスト送りを待つ。
	shown[0] = 0
	_player.play_topic(&"blocking_wait")
	_player.advance()
	guard = 0
	while _player.is_busy() and guard < 200:
		await process_frame
		guard += 1
	await process_frame
	_check(shown[0] == 2, "auto_advance=false は演出完了後に止まる")
	_player.advance()
	await process_frame
	_check(shown[0] == 3, "テキスト送りで次の line へ進む")
	_player.stop()

	# 演出中の advance() は無視される。
	shown[0] = 0
	_player.play_topic(&"blocking_wait")
	_player.advance()
	await process_frame
	_check(_player.is_busy(), "BLOCKING 演出の実行中は busy になる")
	_player.advance()
	_player.advance()
	_check(shown[0] == 2, "演出中の advance() 連打で行が飛ばない")
	guard = 0
	while _player.is_busy() and guard < 200:
		await process_frame
		guard += 1
	_player.stop()

	_player.step_shown.disconnect(callback)


# --- PARALLEL の進行 --------------------------------------------------------

func _test_parallel_progression() -> void:
	var audio: AdvAudioDirector = _player.get_audio_director()
	var before: int = audio.se_request_count()
	_player.play_topic(&"parallel_line")
	# 1 行目の parallel はガード解除前でも「要求」までは通す必要がないので、
	# 明示的に unlock 済みの状態で 2 行目を出す。
	_player.advance()
	await process_frame
	_check(not _player.is_busy(), "PARALLEL 演出は進行をブロックしない")
	_check(
		audio.se_request_count() > before,
		"line に畳み込まれた PARALLEL 演出が本文と同時に起動する")
	_player.advance()
	await process_frame
	_check(not _player.is_playing(), "PARALLEL だけの topic を最後まで送れる")


# --- T-12: register_effect --------------------------------------------------

func _test_register_effect() -> void:
	var probe := ProbeEffect.new()
	probe.tree = self
	probe.frames_to_wait = 3
	_player.register_effect(&"probe_effect", probe)
	_check(probe.effect_id == &"probe_effect", "register_effect() が effect_id を代入する")
	_check(
		_player.get_effect_handler(&"probe_effect") == probe,
		"登録したハンドラが引ける")
	_check(
		probe.exclusive_targets({}) == PackedStringArray(["probe_target"]),
		"拡張演出が自分で排他ターゲットを宣言できる")

	_player.play_topic(&"custom_effect")
	_player.advance()
	_check(_player.is_busy(), "拡張演出も BLOCKING として待たれる")
	var guard: int = 0
	while _player.is_busy() and guard < 120:
		await process_frame
		guard += 1
	_check(probe.play_count == 1, "拡張演出の play() が呼ばれる")
	_check(
		float(probe.last_params.get(&"amount", 0.0)) == 2.5,
		"拡張演出に params がそのまま渡る")
	_player.stop()

	# 組み込み演出の差し替え。
	var replacement := ProbeEffect.new()
	replacement.tree = self
	_player.register_effect(&"shake", replacement)
	_check(
		_player.get_effect_handler(&"shake") == replacement,
		"同じ id を登録すると組み込み演出を差し替えられる")
	replacement.apply_final(_player.get_effect_context(), {})
	_check(replacement.final_count == 1, "差し替えたハンドラの apply_final() が呼べる")
	# 組み込みへ戻す。
	_player.register_effect(&"shake", AdvShakeEffect.new())


# --- stop() の後始末 --------------------------------------------------------

func _test_stop_during_effect() -> void:
	_player.play_topic(&"blocking_wait")
	_player.advance()
	await process_frame
	_check(_player.is_busy(), "演出中である")
	_player.stop()
	_check(not _player.is_playing(), "stop() で再生が止まる")
	_check(_shake_root.position == Vector2.ZERO, "stop() で揺れが原点へ戻る")
	_check(
		_player.get_effect_context().active_targets().is_empty(),
		"stop() で排他ターゲットの台帳が空になる")
	_check(
		not _player.get_voice_player().is_playing(),
		"stop() でボイスが止まる")
	# busy はここで解ける（await から戻った時点）。
	var guard: int = 0
	while _player.is_busy() and guard < 60:
		await process_frame
		guard += 1
	_check(not _player.is_busy(), "stop() 後に busy が残らない")


# --- テスト用データ ---------------------------------------------------------

func _make_book() -> AdvScenarioBook:
	var book := AdvScenarioBook.new()

	var yuu := AdvCharacter.new()
	yuu.id = &"yuu"
	yuu.display_name = "ユウ"
	book.characters[yuu.id] = yuu

	book.topics[&"blocking_auto"] = _make_topic(&"blocking_auto", [
		_line(10, "1 行目"),
		_effect(20, &"shake", {&"strength": 6.0, &"duration": 0.1},
			AdvEffectStep.SyncMode.BLOCKING, true),
		_line(30, "2 行目"),
	])
	book.topics[&"blocking_wait"] = _make_topic(&"blocking_wait", [
		_line(10, "1 行目"),
		_effect(20, &"shake", {&"strength": 6.0, &"duration": 0.1},
			AdvEffectStep.SyncMode.BLOCKING, false),
		_line(30, "2 行目"),
	])
	book.topics[&"custom_effect"] = _make_topic(&"custom_effect", [
		_line(10, "1 行目"),
		_effect(20, &"probe_effect", {&"amount": 2.5},
			AdvEffectStep.SyncMode.BLOCKING, false),
	])

	var parallel_line: AdvLineStep = _line(10, "SE 付きの行")
	parallel_line.parallel_effects.append(
		_effect(20, &"play_se", {&"stream": TONE_PATH, &"volume_db": 0.0},
			AdvEffectStep.SyncMode.PARALLEL, false))
	book.topics[&"parallel_line"] = _make_topic(&"parallel_line", [
		_line(5, "先頭の行"),
		parallel_line,
	])
	return book


func _make_topic(p_id: StringName, p_steps: Array) -> AdvTopic:
	var topic := AdvTopic.new()
	topic.id = p_id
	for index: int in p_steps.size():
		var step: AdvStep = p_steps[index]
		step.uid = StringName("%s:%d" % [p_id, step.order])
		step.step_index = index
		topic.steps.append(step)
	return topic


func _line(p_order: int, p_text: String) -> AdvLineStep:
	var line := AdvLineStep.new()
	line.order = p_order
	line.text = p_text
	return line


func _effect(
	p_order: int,
	p_effect_id: StringName,
	p_params: Dictionary,
	p_sync: AdvEffectStep.SyncMode,
	p_auto_advance: bool
) -> AdvEffectStep:
	var effect := AdvEffectStep.new()
	effect.order = p_order
	effect.effect_id = p_effect_id
	effect.params = p_params
	effect.sync_mode = p_sync
	effect.auto_advance = p_auto_advance
	return effect


# --- ユーティリティ ---------------------------------------------------------

## ハンドラを await せずに走らせ、完了を p_done[0] で受け取る。
func _run_effect(
	p_handler: AdvEffectHandler,
	p_ctx: AdvEffectContext,
	p_params: Dictionary,
	p_done: Array
) -> void:
	await p_handler.play(p_ctx, p_params)
	p_done[0] = true


func _wait_until(p_flag: Array, p_max_frames: int) -> void:
	var frames: int = 0
	while not p_flag[0] and frames < p_max_frames:
		await process_frame
		frames += 1


func _check(p_condition: bool, p_message: String) -> void:
	if p_condition:
		_passed += 1
		return
	_failed += 1
	print("FAIL: %s" % p_message)
