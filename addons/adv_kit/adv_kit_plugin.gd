@tool
extends EditorPlugin
## ADV Kit のエディタプラグインエントリ。
##
## phase-01 で行うのは ProjectSettings への出力先登録だけ。
## InputMap の自動登録（仕様書 §4.6）は、実際に入力を使う phase-02 で追加する。

const OUTPUT_DIR_SETTING := "adv_kit/import/output_dir"
const OUTPUT_DIR_DEFAULT := "res://game/resources/adv/scenario/"


func _enter_tree() -> void:
	if not ProjectSettings.has_setting(OUTPUT_DIR_SETTING):
		ProjectSettings.set_setting(OUTPUT_DIR_SETTING, OUTPUT_DIR_DEFAULT)
	# 既存値は上書きしない。既定値と型情報だけを毎回登録し直す。
	ProjectSettings.set_initial_value(OUTPUT_DIR_SETTING, OUTPUT_DIR_DEFAULT)
	ProjectSettings.add_property_info({
		"name": OUTPUT_DIR_SETTING,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_DIR,
		"hint_string": "",
	})
	ProjectSettings.set_as_basic(OUTPUT_DIR_SETTING, true)
	var err: int = ProjectSettings.save()
	if err != OK:
		push_warning("ADV Kit: ProjectSettings の保存に失敗しました (error %d)" % err)


func _exit_tree() -> void:
	# プラグインを無効化しても設定は消さない。
	# 出力先はプロジェクトの設定であって、プラグインの内部状態ではないため。
	pass
