@tool
class_name AdvImportDock
extends VBoxContainer
## シナリオインポータのエディタパネル（仕様書 §6.4）。
##
## [b]処理はすべて AdvScenarioImporter にある。[/b] ここは入力と表示だけ。
##
## [b]URL はリポジトリに出さない。[/b] 秘匿が唯一の認証手段なので（仕様書 §6.2 / U-05）、
## 入力値は user:// 側の設定ファイルに置く。ProjectSettings には保存しない。

## 入力値の保存先。プロジェクト（res://）ではなくエディタのユーザーデータ側。
const CONFIG_PATH := "user://adv_kit_import.cfg"
const CONFIG_SECTION := "import"

@onready var _url_edit: LineEdit = $UrlEdit
@onready var _out_edit: LineEdit = $OutEdit
@onready var _force_check: CheckBox = $ForceCheck
@onready var _texture_check: CheckBox = $TextureCheck
@onready var _dry_run_check: CheckBox = $DryRunCheck
@onready var _fetch_button: Button = $Buttons/FetchButton
@onready var _file_button: Button = $Buttons/FileButton
@onready var _status_label: Label = $StatusLabel
@onready var _log: RichTextLabel = $Log

var _busy: bool = false
var _file_dialog: FileDialog = null


func _ready() -> void:
	name = "ADV シナリオ"
	_out_edit.placeholder_text = AdvScenarioImporter.OUTPUT_DIR_DEFAULT
	_fetch_button.pressed.connect(_on_fetch_pressed)
	_file_button.pressed.connect(_on_file_pressed)
	_load_config()
	_set_status("待機中")


func _exit_tree() -> void:
	_save_config()


# --- 操作 ---------------------------------------------------------------------

func _on_fetch_pressed() -> void:
	if _busy:
		return
	var url: String = _url_edit.text.strip_edges()
	if url.is_empty():
		_set_status("URL を入力してください")
		return
	_save_config()
	_set_busy(true)
	_set_status("取得中…")
	var result: AdvImportResult = await AdvScenarioImporter.import_from_url(
		self, url, _output_dir(), _options())
	_show_result(result)
	_set_busy(false)


func _on_file_pressed() -> void:
	if _busy:
		return
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.filters = PackedStringArray(["*.json ; シナリオ JSON"])
		_file_dialog.file_selected.connect(_on_file_selected)
		add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.6)


func _on_file_selected(p_path: String) -> void:
	_save_config()
	_set_busy(true)
	_set_status("読み込み中…")
	var result: AdvImportResult = AdvScenarioImporter.import_from_file(
		p_path, _output_dir(), _options())
	_show_result(result)
	_set_busy(false)


# --- 表示 ---------------------------------------------------------------------

func _show_result(p_result: AdvImportResult) -> void:
	_log.clear()
	for issue: AdvIssue in p_result.issues:
		var color: String = "#ff6b6b" if issue.is_error() else "#ffc86b"
		_log.append_text("[color=%s]%s[/color]\n" % [color, issue.to_line()])
	if not p_result.written_paths.is_empty():
		_log.append_text("\n[b]書き出し[/b]\n")
		for path: String in p_result.written_paths:
			_log.append_text("  %s\n" % path)
	if p_result.is_ok() and not p_result.skipped and not p_result.written_paths.is_empty():
		_log.append_text(
			"\n[i]書き出し直後はインポートキャッシュが古いままです。"
			+ "エディタが取り込むまで少し待つか、プロジェクトを再読み込みしてください。[/i]\n")
	_set_status(p_result.summary())


func _set_status(p_text: String) -> void:
	if _status_label != null:
		_status_label.text = p_text


func _set_busy(p_busy: bool) -> void:
	_busy = p_busy
	_fetch_button.disabled = p_busy
	_file_button.disabled = p_busy


# --- 入力値 -------------------------------------------------------------------

func _output_dir() -> String:
	return _out_edit.text.strip_edges()


func _options() -> Dictionary:
	var options: Dictionary = AdvScenarioImporter.default_options()
	options["force"] = _force_check.button_pressed
	options["check_textures"] = _texture_check.button_pressed
	options["write"] = not _dry_run_check.button_pressed
	return options


func _load_config() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		_out_edit.text = AdvScenarioImporter.resolve_output_dir()
		return
	_url_edit.text = str(config.get_value(CONFIG_SECTION, "url", ""))
	_out_edit.text = str(config.get_value(
		CONFIG_SECTION, "output_dir", AdvScenarioImporter.resolve_output_dir()))
	_force_check.button_pressed = bool(config.get_value(CONFIG_SECTION, "force", false))
	_texture_check.button_pressed = bool(config.get_value(CONFIG_SECTION, "check_textures", true))
	_dry_run_check.button_pressed = bool(config.get_value(CONFIG_SECTION, "dry_run", false))


func _save_config() -> void:
	if _url_edit == null:
		return
	var config := ConfigFile.new()
	config.set_value(CONFIG_SECTION, "url", _url_edit.text)
	config.set_value(CONFIG_SECTION, "output_dir", _out_edit.text)
	config.set_value(CONFIG_SECTION, "force", _force_check.button_pressed)
	config.set_value(CONFIG_SECTION, "check_textures", _texture_check.button_pressed)
	config.set_value(CONFIG_SECTION, "dry_run", _dry_run_check.button_pressed)
	var err: int = config.save(CONFIG_PATH)
	if err != OK:
		push_warning("ADV Kit: インポート設定の保存に失敗しました (error %d)" % err)
