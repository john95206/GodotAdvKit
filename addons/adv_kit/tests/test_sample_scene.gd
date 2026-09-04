extends SceneTree
## phase08 サンプルシーンの構成と開始導線を確認する smoke test。

const MAIN_SCENE: PackedScene = preload("res://game/scenes/sample_main.tscn")
const BOOK_PATH: String = "res://game/resources/adv/scenario/scenario_book.tres"
const BACKGROUND_PATH: String = "res://game/assets/adv/backgrounds/sample_ruins.png"
const AUDIO_PATHS: Array[String] = [
	"res://game/assets/adv/audio/sample_bgm.tres",
	"res://game/assets/adv/audio/sample_voice.tres",
	"res://game/assets/adv/audio/sample_se.tres",
]
const PORTRAIT_PATHS: Array[String] = [
	"res://game/assets/adv/portraits/yuu/stand_smile.png",
	"res://game/assets/adv/portraits/yuu/stand_worried.png",
	"res://game/assets/adv/portraits/rin/stand_angry.png",
]

var _failed: int = 0
var _passed: int = 0


func _initialize() -> void:
	print("=== ADV Kit phase-08 / test_sample_scene ===")
	_check(MAIN_SCENE != null, "サンプルメインシーンをロードできる")
	_check(ResourceLoader.exists(BOOK_PATH), "サンプル Book が存在する")
	_check(ResourceLoader.exists(BACKGROUND_PATH), "サンプル背景が存在する")
	for path: String in AUDIO_PATHS:
		_check(ResourceLoader.exists(path), "サンプル音源が存在する: %s" % path)
	for path: String in PORTRAIT_PATHS:
		_check(ResourceLoader.exists(path), "サンプル立ち絵が存在する: %s" % path)

	var main := MAIN_SCENE.instantiate() as Control
	_check(main != null, "サンプルメインシーンを instantiate できる")
	if main == null:
		quit(1)
		return
	root.add_child(main)
	await process_frame
	var adv_scene := main.get_node_or_null("AdvScene") as AdvScene
	var player: AdvPlayer = adv_scene.player if adv_scene != null else null
	var stage: AdvStage = main.get_node_or_null("AdvScene/ShakeRoot/Stage") as AdvStage
	var fade_layer: ColorRect = main.get_node_or_null("AdvScene/FadeLayer") as ColorRect
	var message_window: AdvMessageWindow = main.get_node_or_null(
		"AdvScene/MessageWindow") as AdvMessageWindow
	var choice_menu: AdvChoiceMenu = main.get_node_or_null("AdvScene/ChoiceMenu") as AdvChoiceMenu
	var backlog_view: AdvBacklogView = main.get_node_or_null(
		"AdvScene/BacklogView") as AdvBacklogView
	_check(adv_scene != null, "サンプル AdvScene が存在する")
	_check(player != null, "サンプル AdvPlayer が配線されている")
	_check(stage != null, "サンプル Stage が配線されている")
	_check(fade_layer != null, "FadeLayer が存在する")
	_check(message_window != null, "ゲーム側 MessageWindow が配線されている")
	_check(choice_menu != null, "ゲーム側 ChoiceMenu が配線されている")
	_check(backlog_view != null, "ゲーム側 BacklogView が配線されている")
	if adv_scene != null and fade_layer != null and message_window != null:
		_check(
			fade_layer.get_index() < message_window.get_index(),
			"FadeLayer が MessageWindow より手前にある")
	if player == null or stage == null:
		main.queue_free()
		await process_frame
		quit(1 if _failed > 0 else 0)
		return

	_check(not player.is_audio_unlocked(), "タイトル表示中は autoplay ガードが閉じている")
	_check(main.get_node("TitleOverlay").visible, "起動時にタイトルオーバーレイが表示される")
	_check(not main.get_node("EndOverlay").visible, "起動時に終了オーバーレイが隠れている")
	var start_button := main.get_node_or_null(
		"TitleOverlay/Panel/Margin/Content/StartButton") as Button
	_check(start_button != null, "タイトルの開始ボタンが存在する")
	if start_button != null:
		start_button.emit_signal("pressed")
	await process_frame
	_check(player.is_audio_unlocked(), "開始操作で autoplay ガードが解除される")
	_check(stage.has_character(&"yuu"), "開始後に最初の話者がステージへ表示される")
	_check(message_window.visible, "開始後にメッセージ窓が表示される")
	_check(not main.get_node("TitleOverlay").visible, "開始後にタイトルが閉じる")
	_check(main.get_node("EndOverlay").visible == false, "開始直後に終了オーバーレイは出ない")
	_check(fade_layer.color.a == 0.0, "開始直後の FadeLayer は透明")
	player.stop()
	main.queue_free()
	await process_frame

	print("--- 結果 ---")
	print("%d 件実行 / 成功 %d / 失敗 %d" % [_passed + _failed, _passed, _failed])
	if _failed > 0:
		quit(1)
		return
	print("OK")
	quit(0)


func _check(p_condition: bool, p_message: String) -> void:
	if p_condition:
		_passed += 1
		return
	_failed += 1
	print("FAIL: %s" % p_message)
