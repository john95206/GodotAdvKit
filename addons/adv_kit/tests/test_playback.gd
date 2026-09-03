extends SceneTree
## phase-02 の再生テスト。
##
## 実行方法（[b]--import を先に1回走らせること[/b]）:
## [codeblock]
## godot --headless --import
## godot --headless --script res://addons/adv_kit/tests/test_playback.gd
## [/codeblock]

const SAMPLE_PATH: String = "res://addons/adv_kit/samples/sample_scenario.json"
const ADV_SCENE: PackedScene = preload("res://addons/adv_kit/ui/adv_scene.tscn")

var _failed: int = 0
var _step_shown_count: int = 0
var _line_completed_count: int = 0
var _topic_finished_count: int = 0
var _scenario_finished_count: int = 0


func _initialize() -> void:
	print("=== ADV Kit phase-02 / test_playback ===")
	var parse_result: AdvParseResult = AdvScenarioParser.parse_file(SAMPLE_PATH)
	_check(parse_result.is_ok(), "サンプルのパースが成功する")
	if parse_result.book == null:
		print("FAILED: Book が生成されませんでした")
		quit(1)
		return

	var validation_issues: Array[AdvIssue] = AdvScenarioValidator.validate(parse_result.book)
	_check(validation_issues.is_empty(), "サンプルの検証が issue 0 件")

	var adv_scene: AdvScene = ADV_SCENE.instantiate() as AdvScene
	_check(adv_scene != null, "AdvScene をインスタンス化できる")
	if adv_scene == null:
		quit(1)
		return
	root.add_child(adv_scene)
	# SceneTree スクリプトの _initialize() 中は、追加した子の _ready() が
	# 次のフレームまで遅延するため、onready 参照が解決するまで待つ。
	await process_frame

	var player: AdvPlayer = adv_scene.player
	var stage: AdvStage = adv_scene.get_node("ShakeRoot/Stage") as AdvStage
	var shake_root: Control = adv_scene.get_node("ShakeRoot") as Control
	var message_window: AdvMessageWindow = adv_scene.get_node("MessageWindow") as AdvMessageWindow
	_check(player != null, "AdvScene.player が設定される")
	_check(stage != null, "AdvScene.Stage が AdvStage である")
	_check(shake_root != null, "ShakeRoot が存在する")
	_check(message_window != null, "MessageWindow が基底型で取得できる")
	if player == null or stage == null or shake_root == null or message_window == null:
		quit(1)
		return

	adv_scene.size = Vector2(800.0, 450.0)
	await process_frame
	_check(shake_root.size == adv_scene.size, "リサイズ後も ShakeRoot が画面サイズに追従する")
	_check(stage.size == shake_root.size, "Stage が ShakeRoot の full-rect に追従する")
	_check(
		adv_scene.get_node("FadeLayer").get_index() < message_window.get_index(),
		"FadeLayer が MessageWindow より前にある")

	message_window.show_line("ユウ", Color.WHITE, "[b]こんにちは[/b]、世界")
	message_window.set_typing_progress(0.5)
	var body_label: RichTextLabel = message_window.get_node("BodyLabel") as RichTextLabel
	_check(body_label.visible_characters_behavior == TextServer.VC_CHARS_AFTER_SHAPING,
		"参照 UI が shaping 後の可視文字数を使う")
	_check(is_equal_approx(body_label.visible_ratio, 0.5), "参照 UI が typing 比率をそのまま使う")

	player.step_shown.connect(_on_step_shown)
	player.line_completed.connect(_on_line_completed)
	player.topic_finished.connect(_on_topic_finished)
	player.scenario_finished.connect(_on_scenario_finished)

	var settings := AdvKitSettings.new()
	settings.typing_speed = 0.0
	player.setup(parse_result.book, settings)
	player.play_topic(&"prologue_01")
	_check(player.is_playing(), "play_topic() 直後は再生中である")
	_check(player.is_typing() == false, "typing_speed=0 は即時完了する")
	_check(stage.has_character(&"yuu"), "最初の line で yuu が暗黙に登場する")
	var yuu: AdvCharacter = parse_result.book.get_character(&"yuu")
	stage.show_character(yuu, &"stand", &"smile", &"center", 0.0)
	_check(stage.get_child_count() == 1, "同じキャラクターを show しても二重生成しない")

	# phase-03 以降、BLOCKING 演出はフレームを回さないと完了しない。
	# is_busy() の間は送らずに待つ（実ゲームの入力と同じ扱い）。
	var advance_count: int = 0
	var frame_guard: int = 0
	while player.is_playing() and advance_count < 32 and frame_guard < 600:
		frame_guard += 1
		if player.is_choice_open():
			player.choose_option(0)
			await process_frame
			continue
		if player.is_busy():
			await process_frame
			continue
		player.advance()
		advance_count += 1
		await process_frame
	_check(not player.is_playing(), "サンプル topic を最後まで送れる")
	_check(advance_count < 32, "非 line ステップで停止しない")
	_check(frame_guard < 600, "演出の完了待ちが無限にならない")
	_check(_step_shown_count == 16, "遷移した 3 topic の全 16 ステップで step_shown が出る")
	_check(_line_completed_count == 8, "遷移した 3 topic の line 8 行が完了する")
	_check(_topic_finished_count == 3, "topic_finished が 3 回出る")
	_check(_scenario_finished_count == 1, "scenario_finished が 1 回出る")
	_check(stage.has_character(&"yuu"), "地の文と非 line で yuu が残る")
	_check(stage.has_character(&"rin"), "rin の line で rin が登場する")
	_check(stage.has_character(&"kaze"), "立ち絵無しキャラでも進行が止まらない")
	_check(stage.get_child_count() == 3, "地の文では立ち絵が増えない")

	await _test_tween_typing(player)
	adv_scene.queue_free()
	await process_frame

	print("--- 結果 ---")
	if _failed > 0:
		print("FAILED: %d 件" % _failed)
		quit(1)
		return
	print("OK")
	quit(0)


## R-08: SceneTree スクリプトでも Player の Tween がフレームで完了することを確認する。
func _test_tween_typing(p_player: AdvPlayer) -> void:
	var book := AdvScenarioBook.new()
	var topic := AdvTopic.new()
	topic.id = &"tween_topic"
	var line := AdvLineStep.new()
	line.uid = &"tween_topic:10"
	line.order = 10
	line.text = "abcdefghij"
	topic.steps.append(line)
	book.topics[topic.id] = topic

	var settings := AdvKitSettings.new()
	settings.typing_speed = 100.0
	p_player.setup(book, settings)
	var completed_before: int = _line_completed_count
	p_player.play_topic(&"tween_topic")
	_check(p_player.is_typing(), "typing_speed>0 では Tween 中になる")

	var frame_count: int = 0
	while p_player.is_typing() and frame_count < 120:
		await process_frame
		frame_count += 1
	_check(not p_player.is_typing(), "headless のフレーム進行で Tween が完了する")
	_check(_line_completed_count == completed_before + 1, "Tween 完了時に line_completed が 1 回出る")
	p_player.advance()
	_check(not p_player.is_playing(), "Tween テスト topic も送れる")


func _on_step_shown(p_topic_id: StringName, p_step_uid: StringName) -> void:
	_step_shown_count += 1


func _on_line_completed(p_topic_id: StringName, p_step_uid: StringName) -> void:
	_line_completed_count += 1


func _on_topic_finished(p_topic_id: StringName) -> void:
	_topic_finished_count += 1


func _on_scenario_finished() -> void:
	_scenario_finished_count += 1


func _check(p_condition: bool, p_message: String) -> void:
	if p_condition:
		return
	_failed += 1
	print("FAIL: %s" % p_message)
