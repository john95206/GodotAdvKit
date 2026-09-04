extends AdvChoiceMenu
## サンプルゲーム用の差し替え選択肢 UI。

@onready var _prompt_label: Label = get_node("Panel/Margin/Content/PromptLabel") as Label
@onready var _options_box: VBoxContainer = get_node("Panel/Margin/Content/Options") as VBoxContainer
var _is_presented: bool = false


func _ready() -> void:
	hide()


func present(p_prompt: String, p_options: Array[Dictionary]) -> void:
	_clear_buttons()
	if _prompt_label != null:
		_prompt_label.text = p_prompt
	if _options_box == null:
		return
	for index: int in p_options.size():
		var option: Dictionary = p_options[index]
		var button := Button.new()
		button.text = str(option.get(AdvChoiceStep.KEY_LABEL, ""))
		button.custom_minimum_size = Vector2(0, 48)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_on_option_pressed.bind(index))
		_options_box.add_child(button)
	_is_presented = true
	show()


func close() -> void:
	_is_presented = false
	_clear_buttons()
	hide()


func _on_option_pressed(p_index: int) -> void:
	if _is_presented:
		option_chosen.emit(p_index)


func _clear_buttons() -> void:
	if _options_box == null:
		return
	for child: Node in _options_box.get_children():
		child.free()
