extends SceneTree
## シナリオインポータの CLI 入口（仕様書 §6.4）。
##
## [codeblock]
## godot --headless --import
## godot --headless --script res://addons/adv_kit/import/adv_import_cli.gd -- \
##     --url=<GAS のウェブアプリ URL> --out=res://game/resources/adv/scenario/
## [/codeblock]
##
## [b]処理はすべて AdvScenarioImporter にある。[/b] ここは引数と終了コードだけを見る。
##
## [b]書き出した直後は .godot/ のインポートキャッシュが古い。[/b]
## CI や自動化では、この CLI のあとに `godot --headless --import` を 1 回走らせること。
## CLI 自身は import を行わない（責務を分けるため）。
##
## [b]Windows では `_console.exe` を使うこと。[/b] 無印 .exe はコンソールに接続せず、
## 終了コードも実行完了を待たずに 0 を返す。

const EXIT_OK: int = 0
const EXIT_HAS_ERROR: int = 1
const EXIT_BAD_USAGE: int = 2


func _initialize() -> void:
	var options: Dictionary = AdvScenarioImporter.parse_cli_args(OS.get_cmdline_user_args())

	if bool(options.get("help", false)):
		print(AdvScenarioImporter.cli_usage())
		quit(EXIT_OK)
		return

	var arg_errors: PackedStringArray = options.get("errors", PackedStringArray())
	if not arg_errors.is_empty():
		for message: String in arg_errors:
			printerr("引数エラー: %s" % message)
		print("")
		print(AdvScenarioImporter.cli_usage())
		quit(EXIT_BAD_USAGE)
		return

	var output_dir: String = String(options.get("out", ""))
	var url: String = String(options.get("url", ""))
	var file_path: String = String(options.get("file", ""))

	print("=== ADV Kit シナリオインポータ ===")
	print("出力先: %s" % (AdvScenarioImporter.normalize_dir(output_dir) if not output_dir.is_empty()
		else AdvScenarioImporter.resolve_output_dir()))

	var result: AdvImportResult = null
	if not file_path.is_empty():
		print("取得元: %s（ローカル）" % file_path)
		result = AdvScenarioImporter.import_from_file(file_path, output_dir, options)
	else:
		# URL はログに出さない。秘匿が唯一の認証手段のため（仕様書 §6.2 / U-05）
		print("取得元: GAS ウェブアプリ（URL は伏せます）")
		# _initialize() の時点では root がまだツリーに入っていない（R-08 と同根）。
		# HTTPRequest をぶら下げる前に 1 フレーム進める。
		await process_frame
		result = await AdvScenarioImporter.import_from_url(root, url, output_dir, options)

	_report(result)
	quit(EXIT_OK if result.is_ok() else EXIT_HAS_ERROR)


func _report(p_result: AdvImportResult) -> void:
	print("")
	for line: String in p_result.to_lines():
		print("  " + line)
	if not p_result.written_paths.is_empty():
		print("")
		print("--- 書き出し ---")
		for path: String in p_result.written_paths:
			print("  " + path)
	print("")
	print("--- 結果 ---")
	print(p_result.summary())
	if p_result.is_ok() and not p_result.skipped and not p_result.written_paths.is_empty():
		print("")
		print("続けて `godot --headless --import` を 1 回走らせてください。")
