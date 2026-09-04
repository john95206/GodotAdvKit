extends Control
## AdvKit の実素材サンプル。タイトル操作で音声を unlock してから本編を開始する。

@export var book: AdvScenarioBook
@export var settings: AdvKitSettings
## 立ち絵・音声は Kit の設計どおりパス文字列で遅延ロードする。
## Web の scenes export でも PCK に含めるため、サンプル側で依存だけを明示する。
@export var sample_assets: Array[Resource] = []

@onready var _adv_scene: AdvScene = get_node("AdvScene") as AdvScene
@onready var _player: AdvPlayer = _adv_scene.player
@onready var _title_overlay: Control = get_node("TitleOverlay") as Control
@onready var _end_overlay: Control = get_node("EndOverlay") as Control
@onready var _start_button: Button = get_node("TitleOverlay/Panel/Margin/Content/StartButton") as Button
@onready var _restart_button: Button = get_node("EndOverlay/Panel/Margin/Content/RestartButton") as Button
@onready var _status_label: Label = get_node("Hud/Status") as Label
@onready var _mode_label: Label = get_node("Hud/Mode") as Label


func _ready() -> void:
	if _player == null:
		push_error("sample_main: AdvPlayer が見つかりません")
		return
	_player.setup(book, settings)
	_player.scenario_finished.connect(_on_scenario_finished)
	_player.auto_mode_changed.connect(_on_auto_mode_changed)
	_player.skip_stopped.connect(_on_skip_stopped)
	_start_button.pressed.connect(_start_scenario)
	_restart_button.pressed.connect(_restart_scenario)
	_end_overlay.hide()
	_status_label.text = "TITLE / READY"
	_mode_label.text = ""


func _start_scenario() -> void:
	# 最初のユーザー操作で autoplay ガードを解除してから、最初の行を開始する。
	_player.unlock_audio()
	_title_overlay.hide()
	_status_label.text = "PROLOGUE / PLAYING"
	_player.play_topic(&"prologue_01")


func _restart_scenario() -> void:
	_end_overlay.hide()
	_player.setup(book, settings)
	_player.unlock_audio()
	_status_label.text = "PROLOGUE / PLAYING"
	_player.play_topic(&"prologue_01")


func _on_scenario_finished() -> void:
	_status_label.text = "SCENARIO / COMPLETE"
	_mode_label.text = ""
	_end_overlay.show()


func _on_auto_mode_changed(p_enabled: bool) -> void:
	_mode_label.text = "AUTO ON" if p_enabled else ""


func _on_skip_stopped(p_reason: StringName) -> void:
	if p_reason == &"finished":
		return
	_status_label.text = "PLAYING / %s" % String(p_reason).to_upper()
