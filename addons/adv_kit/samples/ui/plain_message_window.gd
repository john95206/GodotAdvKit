extends AdvMessageWindow
## Theme を持たない最小の参照メッセージ窓。

@onready var _speaker_label: Label = get_node("SpeakerLabel") as Label
@onready var _body_label: RichTextLabel = get_node("BodyLabel") as RichTextLabel


func _ready() -> void:
	if _ensure_message_nodes():
		_body_label.bbcode_enabled = true
		_body_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING


func show_line(p_speaker_name: String, p_name_color: Color, p_text: String) -> void:
	if not _ensure_message_nodes():
		return
	_speaker_label.text = p_speaker_name
	_speaker_label.modulate = p_name_color
	_body_label.text = p_text
	_body_label.visible_ratio = 0.0


func set_typing_progress(p_ratio: float) -> void:
	if not _ensure_message_nodes():
		return
	_body_label.visible_ratio = clampf(p_ratio, 0.0, 1.0)


func complete_typing() -> void:
	if not _ensure_message_nodes():
		return
	_body_label.visible_ratio = 1.0


func clear() -> void:
	if not _ensure_message_nodes():
		return
	_speaker_label.text = ""
	_body_label.text = ""
	_body_label.visible_ratio = 1.0


func _gui_input(p_event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = p_event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		advance_requested.emit()
		accept_event()
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		skip_typing_requested.emit()
		accept_event()


func _ensure_message_nodes() -> bool:
	if _speaker_label == null:
		_speaker_label = get_node_or_null("SpeakerLabel") as Label
	if _body_label == null:
		_body_label = get_node_or_null("BodyLabel") as RichTextLabel
	return _speaker_label != null and _body_label != null
