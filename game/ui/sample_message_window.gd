extends AdvMessageWindow
## サンプルゲーム用の差し替えメッセージ窓。Kit 側は外観を持たない。

@onready var _speaker_label: Label = get_node("Panel/Margin/Content/SpeakerLabel") as Label
@onready var _body_label: RichTextLabel = get_node("Panel/Margin/Content/BodyLabel") as RichTextLabel


func _ready() -> void:
	if _body_label != null:
		_body_label.bbcode_enabled = true
		_body_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	hide()


func show_line(p_speaker_name: String, p_name_color: Color, p_text: String) -> void:
	if _speaker_label == null or _body_label == null:
		return
	_speaker_label.text = p_speaker_name if not p_speaker_name.is_empty() else ""
	_speaker_label.modulate = p_name_color
	_body_label.text = p_text
	_body_label.visible_ratio = 0.0
	show()


func set_typing_progress(p_ratio: float) -> void:
	if _body_label != null:
		_body_label.visible_ratio = clampf(p_ratio, 0.0, 1.0)


func complete_typing() -> void:
	if _body_label != null:
		_body_label.visible_ratio = 1.0


func clear() -> void:
	if _speaker_label != null:
		_speaker_label.text = ""
	if _body_label != null:
		_body_label.text = ""
		_body_label.visible_ratio = 1.0
	hide()
