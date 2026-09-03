extends AdvBacklogView
## Theme を持たない最小の参照バックログ UI。

@onready var _entries_box: VBoxContainer = get_node_or_null("Panel/Scroll/Entries") as VBoxContainer
@onready var _close_button: Button = get_node_or_null("Panel/CloseButton") as Button

var _is_presented: bool = false


func _ready() -> void:
    if _close_button != null and not _close_button.pressed.is_connected(_on_close_pressed):
        _close_button.pressed.connect(_on_close_pressed)
    hide()


func present(p_entries: Array[AdvBacklogEntry]) -> void:
    _clear_entries()
    if _entries_box == null:
        return
    for entry: AdvBacklogEntry in p_entries:
        var row := HBoxContainer.new()
        var label := Label.new()
        label.text = _format_entry(entry)
        label.modulate = entry.name_color
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(label)
        var replay_button := Button.new()
        replay_button.text = "Replay voice"
        replay_button.disabled = entry.voice_path.is_empty()
        replay_button.pressed.connect(_on_replay_pressed.bind(entry))
        row.add_child(replay_button)
        _entries_box.add_child(row)
    _is_presented = true
    show()


func close() -> void:
    _is_presented = false
    _clear_entries()
    hide()


func _on_close_pressed() -> void:
    if not _is_presented:
        return
    close()
    closed.emit()


func _on_replay_pressed(p_entry: AdvBacklogEntry) -> void:
    if _is_presented and p_entry != null:
        voice_replay_requested.emit(p_entry)


func _clear_entries() -> void:
    if _entries_box == null:
        return
    for child: Node in _entries_box.get_children():
        child.free()


func _format_entry(p_entry: AdvBacklogEntry) -> String:
    var prefix: String = p_entry.speaker_name
    if prefix.is_empty():
        return p_entry.text
    return "%s: %s" % [prefix, p_entry.text]
