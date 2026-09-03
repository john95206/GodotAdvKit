extends SceneTree
## phase-04 の汎用演出テスト。
##
## 実行方法（[b]--import を先に1回走らせること[/b]）:
## [codeblock]
## godot --headless --script res://addons/adv_kit/tests/test_auto_direction.gd
## [/codeblock]
##
## 立ち絵テクスチャ無しで、話者の明暗・ホップ・地の文・設定のオンオフを検証する。

const ADV_SCENE: PackedScene = preload("res://addons/adv_kit/ui/adv_scene.tscn")

var _failed: int = 0
var _passed: int = 0
var _scene: AdvScene = null
var _player: AdvPlayer = null
var _stage: AdvStage = null


func _initialize() -> void:
	print("=== ADV Kit phase-04 / test_auto_direction ===")
	_scene = ADV_SCENE.instantiate() as AdvScene
	root.add_child(_scene)
	await process_frame
	_scene.size = Vector2(800.0, 450.0)
	await process_frame

	_player = _scene.player
	_stage = _scene.get_node("ShakeRoot/Stage") as AdvStage
	if _player == null or _stage == null:
		print("FAILED: AdvScene の構成が想定と違います")
		quit(1)
		return

	await _test_dim_and_hop()
	await _test_same_speaker_and_narration()
	await _test_disabled_settings()

	_player.stop()
	_scene.queue_free()
	await process_frame

	print("--- 結果 ---")
	print("%d 件実行 / 成功 %d / 失敗 %d" % [_passed + _failed, _passed, _failed])
	if _failed > 0:
		quit(1)
		return
	print("OK")
	quit(0)


func _test_dim_and_hop() -> void:
	var settings := _make_settings()
	settings.dim_color = Color(0.2, 0.3, 0.4)
	settings.dim_duration = 0.08
	settings.hop_height = 24.0
	settings.hop_duration = 0.4
	_player.setup(_make_book(), settings)
	_player.play_topic(&"switch")
	await process_frame

	var alice: AdvPortrait = _stage.get_portrait(&"alice")
	_check(alice != null, "最初の話者が暗黙に登場する")
	if alice == null:
		return
	var alice_rest: Vector2 = _stage.get_portrait_position_for(&"alice", &"left")
	_check(
		_stage.get_character_ids().has(&"alice"),
		"Stage が現在表示中のキャラクター一覧を返す")
	_check(not _player.is_busy(), "汎用演出が進行を BLOCKING にしない")
	_check(_color_matches(alice.modulate, Color.WHITE), "最初の話者は白")
	_check(alice.position.y < alice_rest.y, "最初の話者が上方向へホップする")
	_check(
		_player.get_effect_context().active_targets().has("portrait_position:alice"),
		"ホップが立ち絵位置の排他ターゲットを占有する")
	await _wait_for_position(alice, alice_rest, 120)
	_check(alice.position.is_equal_approx(alice_rest), "ホップ完了後に元の位置へ戻る")

	# A -> B: A は暗くなり、B は白くなる。B のホップも同時に始まる。
	var alice_alpha: float = 0.37
	alice.modulate.a = alice_alpha
	_player.advance()
	await process_frame
	var bob: AdvPortrait = _stage.get_portrait(&"bob")
	_check(bob != null, "交代先の話者が暗黙に登場する")
	if bob == null:
		return
	var bob_rest: Vector2 = _stage.get_portrait_position_for(&"bob", &"right")
	_check(bob.position.y < bob_rest.y, "交代先の話者が上方向へホップする")
	await _wait_for_position(bob, bob_rest, 120)
	_check(
		_color_matches(alice.modulate, settings.dim_color),
		"非話者が設定された dim_color になる")
	_check(is_equal_approx(alice.modulate.a, alice_alpha), "非話者ダークが alpha を維持する")
	_check(
		_color_matches(bob.modulate, Color.WHITE),
		"現在の話者が白になる")
	_check(bob.position.is_equal_approx(bob_rest), "交代先のホップ完了後に元の位置へ戻る")
	_player.stop()


func _test_same_speaker_and_narration() -> void:
	var settings := _make_settings()
	settings.dim_duration = 0.0
	settings.hop_duration = 0.3
	_player.setup(_make_book(), settings)

	# 同じ話者の連続発話ではホップしない。
	_player.play_topic(&"same_speaker")
	await process_frame
	var alice: AdvPortrait = _stage.get_portrait(&"alice")
	_check(alice != null, "同一話者 topic の立ち絵が登場する")
	if alice == null:
		return
	var alice_rest: Vector2 = _stage.get_portrait_position_for(&"alice", &"left")
	await _wait_for_position(alice, alice_rest, 120)
	_player.advance()
	await process_frame
	_check(alice.position.is_equal_approx(alice_rest), "同じ話者の連続発話ではホップしない")
	_player.stop()

	# A -> B のあと地の文へ進んでも、直前の明暗を維持する。
	_player.setup(_make_book(), settings)
	_player.play_topic(&"narration")
	await process_frame
	_player.advance()
	await process_frame
	var bob: AdvPortrait = _stage.get_portrait(&"bob")
	_check(bob != null, "地の文テストの交代先が登場する")
	if bob == null:
		return
	var alice_before: Color = _stage.get_portrait(&"alice").modulate
	var bob_before: Color = bob.modulate
	_player.advance()
	await process_frame
	_check(
		_color_matches(_stage.get_portrait(&"alice").modulate, alice_before),
		"地の文で非話者の明暗を変更しない")
	_check(
		_color_matches(bob.modulate, bob_before),
		"地の文で直前話者の明暗を維持する")
	_player.stop()


func _test_disabled_settings() -> void:
	var settings := _make_settings()
	settings.dim_non_speakers = false
	settings.hop_on_speaker_change = false
	settings.dim_duration = 0.0
	_player.setup(_make_book(), settings)
	_player.play_topic(&"switch")
	await process_frame
	var alice: AdvPortrait = _stage.get_portrait(&"alice")
	_check(alice != null, "無効化テストの最初の話者が登場する")
	if alice == null:
		return
	var alice_rest: Vector2 = _stage.get_portrait_position_for(&"alice", &"left")
	_check(alice.position.is_equal_approx(alice_rest), "ホップ無効時は最初の話者が動かない")
	_player.advance()
	await process_frame
	var bob: AdvPortrait = _stage.get_portrait(&"bob")
	_check(bob != null, "無効化テストの交代先が登場する")
	if bob == null:
		return
	_check(
		_color_matches(alice.modulate, Color.WHITE),
		"非話者ダーク無効時も既存の立ち絵が白のまま")
	var bob_rest: Vector2 = _stage.get_portrait_position_for(&"bob", &"right")
	_check(bob.position.is_equal_approx(bob_rest), "ホップ無効時は交代先が動かない")
	_check(
		_player.get_effect_context().active_targets().is_empty(),
		"汎用演出を無効にすると Tween を登録しない")


func _make_settings() -> AdvKitSettings:
	var settings := AdvKitSettings.new()
	settings.typing_speed = 0.0
	return settings


func _make_book() -> AdvScenarioBook:
	var book := AdvScenarioBook.new()
	var alice := _make_character(&"alice", "Alice")
	var bob := _make_character(&"bob", "Bob")
	book.characters[alice.id] = alice
	book.characters[bob.id] = bob

	book.topics[&"switch"] = _make_topic(&"switch", [
		_line(10, &"alice", "A"),
		_line(20, &"bob", "B"),
	])
	book.topics[&"same_speaker"] = _make_topic(&"same_speaker", [
		_line(10, &"alice", "A1"),
		_line(20, &"alice", "A2"),
	])
	book.topics[&"narration"] = _make_topic(&"narration", [
		_line(10, &"alice", "A"),
		_line(20, &"bob", "B"),
		_line(30, &"", "地の文"),
	])
	return book


func _make_character(p_id: StringName, p_name: String) -> AdvCharacter:
	var character := AdvCharacter.new()
	character.id = p_id
	character.display_name = p_name
	return character


func _make_topic(p_id: StringName, p_steps: Array) -> AdvTopic:
	var topic := AdvTopic.new()
	topic.id = p_id
	for index: int in p_steps.size():
		var step: AdvStep = p_steps[index]
		step.uid = StringName("%s:%d" % [p_id, step.order])
		step.step_index = index
		topic.steps.append(step)
	return topic


func _line(p_order: int, p_speaker_id: StringName, p_text: String) -> AdvLineStep:
	var line := AdvLineStep.new()
	line.order = p_order
	line.speaker_id = p_speaker_id
	line.slot = &"left" if p_speaker_id == &"alice" else &"right"
	line.text = p_text
	return line


func _wait_for_position(p_portrait: AdvPortrait, p_position: Vector2, p_max_frames: int) -> void:
	var frames: int = 0
	while not p_portrait.position.is_equal_approx(p_position) and frames < p_max_frames:
		await process_frame
		frames += 1


func _color_matches(p_actual: Color, p_expected: Color) -> bool:
	return (
		is_equal_approx(p_actual.r, p_expected.r)
		and is_equal_approx(p_actual.g, p_expected.g)
		and is_equal_approx(p_actual.b, p_expected.b))


func _check(p_condition: bool, p_message: String) -> void:
	if p_condition:
		_passed += 1
		return
	_failed += 1
	print("FAIL: %s" % p_message)
