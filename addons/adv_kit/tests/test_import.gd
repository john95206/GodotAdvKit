extends SceneTree
## phase-07 の検証スクリプト（シナリオパイプライン）。
##
## 実行方法（[b]--import を先に1回走らせること[/b]。class_name のグローバル解決に必要）:
## [codeblock]
## godot --headless --import
## godot --headless --script res://addons/adv_kit/tests/test_import.gd
## [/codeblock]
## 失敗が1件でもあれば終了コード 1 を返す。
##
## [b]書き出し先は user:// にする。[/b] res://game/ を汚さないため。
## 出力レイアウトの検証としてはこれで十分（res:// と user:// で ResourceSaver の挙動は同じ）。

const SAMPLE_PATH := "res://addons/adv_kit/samples/sample_scenario.json"
const DOCK_SCENE := "res://addons/adv_kit/editor/adv_import_dock.tscn"
const OUT_DIR := "user://adv_kit_test_import/"

## 参照整合性が壊れた JSON（unknown_topic の ERROR が出る）。
const BROKEN_JSON := """{
  "schema_version": 1,
  "content_hash": "broken-0001",
  "characters": [{ "id": "a", "display_name": "A" }],
  "topics": [{
    "id": "t1", "title": "T1", "tags": ["entry"],
    "steps": [{ "order": 10, "type": "jump", "goto": "does_not_exist" }]
  }]
}"""

## 立ち絵を持たないキャラだけの、issue が 1 件も出ない JSON。
const CLEAN_JSON := """{
  "schema_version": 3,
  "content_hash": "clean-0001",
  "characters": [{ "id": "a", "display_name": "A", "name_color": "#ff0000" }],
  "topics": [{
    "id": "t1", "title": "T1", "tags": ["entry"],
    "steps": [
      { "order": 10, "type": "line", "speaker": "a", "text": "ひとこと" },
      { "order": 20, "type": "effect", "effect_id": "shake",
        "params": { "strength": "6" }, "sync": "parallel" }
    ]
  }]
}"""

var _passed: int = 0
var _failed: int = 0
var _executed: int = 0
var _current_case: String = ""


func _initialize() -> void:
	print("=== ADV Kit phase-07 / test_import ===")
	# import_from_url を通すテストがあるので、root がツリーに入るまで 1 フレーム待つ（R-20）
	await process_frame
	_purge_output_dir()

	await _run("T-04 出力先の解決", _test_output_dir)
	await _run("T-09 CLI 引数", _test_cli_args)
	await _run("U-05 URL がログに出ない", _test_url_redaction)
	await _run("T-01/T-02 schema_version と content_hash", _test_book_metadata)
	await _run("T-05 立ち絵の検査", _test_portrait_check)
	await _run("T-06/T-07 サンプルの書き出し", _test_write_sample)
	await _run("T-07 書き出した .tres の往復", _test_round_trip)
	await _run("T-06 content_hash による差分スキップ", _test_skip_and_force)
	await _run("T-07 stale の検出", _test_stale)
	await _run("T-06 ERROR があれば書き出さない", _test_no_write_on_error)
	await _run("T-06 ドライラン / 壊れた JSON", _test_dry_run_and_invalid)
	await _run("T-06 ローカルファイルからの取り込み", _test_import_from_file)
	await _run("T-11 Dock のシーンが読める", _test_dock_scene)

	_purge_output_dir()
	print("")
	print("--- 結果 ---")
	print("%d 件実行 / 成功 %d / 失敗 %d" % [_executed, _passed, _failed])
	if _failed > 0:
		print("FAILED")
		quit(1)
		return
	print("OK")
	quit(0)


# --- テスト本体 --------------------------------------------------------------

func _test_output_dir() -> void:
	_assert_eq(
		AdvScenarioImporter.normalize_dir("res://a/b"), "res://a/b/", "末尾に / を足す")
	_assert_eq(
		AdvScenarioImporter.normalize_dir("res://a/b/"), "res://a/b/", "既に / なら足さない")
	_assert_eq(
		AdvScenarioImporter.normalize_dir("  "),
		AdvScenarioImporter.OUTPUT_DIR_DEFAULT, "空なら既定値")

	# R-02: --import では EditorPlugin._enter_tree() が走らないため、
	# ProjectSettings にキーが無い状態でも既定値へ落ちること
	var resolved: String = AdvScenarioImporter.resolve_output_dir()
	_assert_true(resolved.ends_with("/"), "resolve_output_dir は / 終わり")
	if not ProjectSettings.has_setting(AdvScenarioImporter.OUTPUT_DIR_SETTING):
		_assert_eq(
			resolved, AdvScenarioImporter.OUTPUT_DIR_DEFAULT,
			"設定が無ければ既定値へフォールバックする")
	else:
		_assert_true(not resolved.is_empty(), "設定があればその値を使う")


func _test_cli_args() -> void:
	var with_file: Dictionary = AdvScenarioImporter.parse_cli_args(
		PackedStringArray(["--file=res://a.json", "--out=user://x/", "--force"]))
	_assert_eq(with_file["file"], "res://a.json", "--file= を読む")
	_assert_eq(with_file["out"], "user://x/", "--out= を読む")
	_assert_true(bool(with_file["force"]), "--force を読む")
	_assert_true(bool(with_file["write"]), "既定では書き出す")
	_assert_true(bool(with_file["check_textures"]), "既定では立ち絵を検査する")
	_assert_eq(
		(with_file["errors"] as PackedStringArray).size(), 0, "正しい引数ならエラー 0 件")

	var flags: Dictionary = AdvScenarioImporter.parse_cli_args(PackedStringArray([
		"--url=https://example.test/exec", "--no-write", "--no-texture-check",
		"--book-name=chapter1.tres"]))
	_assert_true(not bool(flags["write"]), "--no-write が効く")
	_assert_true(not bool(flags["check_textures"]), "--no-texture-check が効く")
	_assert_eq(flags["book_name"], "chapter1.tres", "--book-name= を読む")

	var both: Dictionary = AdvScenarioImporter.parse_cli_args(
		PackedStringArray(["--url=https://example.test/exec", "--file=res://a.json"]))
	_assert_true(
		(both["errors"] as PackedStringArray).size() > 0, "--url と --file の同時指定はエラー")

	var unknown: Dictionary = AdvScenarioImporter.parse_cli_args(
		PackedStringArray(["--file=res://a.json", "--nope"]))
	_assert_true(
		(unknown["errors"] as PackedStringArray).size() > 0, "不明な引数はエラー")

	var help: Dictionary = AdvScenarioImporter.parse_cli_args(PackedStringArray(["--help"]))
	_assert_true(bool(help["help"]), "--help を読む")
	_assert_eq(
		(help["errors"] as PackedStringArray).size(), 0,
		"--help のときは入力元が無くてもエラーにしない")

	_assert_true(
		AdvScenarioImporter.cli_usage().contains("--url="), "usage に --url= が載っている")


## URL の秘匿が唯一の認証手段（仕様書 §6.2 / U-05）。
## デプロイ ID を含むパスが、結果のどこからもログへ漏れないことを見る。
func _test_url_redaction() -> void:
	const SECRET := "AKfycbSECRETDEPLOYMENTID0123456789"
	var url: String = "https://script.google.com/macros/s/%s/exec" % SECRET

	var redacted: String = AdvScenarioImporter.redact_url(url)
	_assert_true(not redacted.contains(SECRET), "ホストから先を落とす")
	_assert_true(not redacted.contains("/macros/"), "パスを残さない")
	_assert_true(redacted.contains("script.google.com"), "ホスト名は残す（どこへ繋いだかは分かる）")

	_assert_eq(
		AdvScenarioImporter.redact_url("res://a/b.json"), "res://a/b.json",
		"URL でない取得元はそのまま")
	_assert_eq(
		AdvScenarioImporter.redact_url("http://127.0.0.1:8765/exec"),
		"127.0.0.1:8765 (以降は伏せています)", "http もポートごとホストは残す")

	# summary() は CLI のログにも Dock にも出る。ここに URL が載ると秘匿が破れる
	var result := AdvImportResult.new()
	result.book = AdvScenarioBook.new()
	result.source_label = redacted
	_assert_true(not result.summary().contains(SECRET), "summary() に URL が出ない")

	result.book.content_hash = "abc"
	result.skipped = true
	_assert_true(
		not result.summary().contains(SECRET), "skip 時の summary() にも URL が出ない")

	# 取得に失敗したときの issue も同じ。location は丸めた表記でなければならない
	var failed: AdvImportResult = AdvScenarioImporter.import_from_text(
		"これは JSON ではない", redacted, OUT_DIR, {"write": false})
	for line: String in failed.to_lines():
		_assert_true(not line.contains(SECRET), "issue の 1 行表現に URL が出ない")

	# [b]実際の取得経路そのものを通す。[/b] redact_url() 単体を見るだけでは、
	# import_from_url() が生 URL を渡す実装に戻っても気づけない（実際に一度そうなっていた）。
	# 到達不能なポートへ投げて即座に失敗させる
	var dead_url: String = "http://127.0.0.1:9/macros/s/%s/exec" % SECRET
	var fetched: AdvImportResult = await AdvScenarioImporter.import_from_url(
		root, dead_url, OUT_DIR, {"write": false})
	_assert_true(not fetched.is_ok(), "到達不能な URL は ERROR になる")
	_assert_issue_code(
		fetched.issues, AdvScenarioImporter.CODE_FETCH_FAILED, "fetch_failed を出す")
	_assert_true(
		not fetched.source_label.contains(SECRET),
		"import_from_url() が source_label に生 URL を残さない")
	_assert_true(
		not fetched.summary().contains(SECRET), "取得失敗時の summary() にも残らない")
	for line: String in fetched.to_lines():
		_assert_true(not line.contains(SECRET), "取得失敗の issue にも残らない")


func _test_book_metadata() -> void:
	var result: AdvParseResult = AdvScenarioParser.parse_file(SAMPLE_PATH)
	_assert_eq(result.book.schema_version, 1, "schema_version を Book へ写す")
	_assert_eq(result.book.content_hash, _sample_content_hash(), "content_hash を Book へ写す")

	var bare: AdvParseResult = AdvScenarioParser.parse({"topics": [], "characters": []})
	_assert_eq(bare.book.schema_version, 0, "欠落時の schema_version は 0")
	_assert_eq(bare.book.content_hash, "", "欠落時の content_hash は空文字")

	var a := AdvScenarioBook.new()
	var b := AdvScenarioBook.new()
	a.content_hash = "x"
	b.content_hash = "x"
	_assert_true(a.has_same_content(b), "同じ hash なら同じ内容")
	b.content_hash = "y"
	_assert_true(not a.has_same_content(b), "違う hash なら違う内容")
	b.content_hash = ""
	_assert_true(not a.has_same_content(b), "片方が空なら「分からない」＝違う扱い")
	_assert_true(not a.has_same_content(null), "null 相手は違う扱い")


func _test_portrait_check() -> void:
	# phase-08 では sample JSON に実素材があるため、旧 phase-07 の欠損検査は
	# パスを一時的に壊した入力で検証する。実サンプル自体は warning 0 件を維持する。
	var missing_text: String = _sample_text().replace(
		"res://game/assets/adv/portraits/", "res://game/assets/adv/portraits_missing/")
	var missing_result: AdvImportResult = AdvScenarioImporter.import_from_text(
		missing_text, "missing-portrait-fixture", OUT_DIR, {"write": false})
	var issues: Array[AdvIssue] = missing_result.issues
	_assert_issue_code(
		issues, AdvScenarioImporter.CODE_MISSING_PORTRAIT,
		"実素材が無いので missing_portrait_texture が出る")
	for issue: AdvIssue in issues:
		_assert_true(not issue.is_error(), "missing_portrait_texture は WARNING")
		break

	# 立ち絵を持たないキャラ（kaze）については警告を出さない。
	# 「立ち絵が無くても成立する」（仕様書 §1）と矛盾するため
	for issue: AdvIssue in issues:
		_assert_true(not issue.message.contains("kaze"), "立ち絵なしキャラは対象外")

	# 同じ (speaker, pose, expression) は何度参照されても 1 件に畳む
	var seen: Dictionary = {}
	var duplicated: bool = false
	for issue: AdvIssue in issues:
		if seen.has(issue.message):
			duplicated = true
		seen[issue.message] = true
	_assert_true(not duplicated, "同じ組み合わせの警告は重複しない")

	# 存在するテクスチャなら警告は出ない（テスト用の .tres を立ち絵に見立てる）
	var book := AdvScenarioBook.new()
	var character := AdvCharacter.new()
	character.id = &"a"
	var portrait_set := AdvPortraitSet.new()
	portrait_set.default_pose = &"stand"
	portrait_set.default_expression = &"normal"
	portrait_set.texture_paths["stand/normal"] = "res://addons/adv_kit/tests/assets/test_tone.tres"
	character.portrait_set = portrait_set
	book.characters[&"a"] = character
	var topic := AdvTopic.new()
	topic.id = &"t"
	var line := AdvLineStep.new()
	line.speaker_id = &"a"
	topic.steps = [line] as Array[AdvStep]
	book.topics[&"t"] = topic
	_assert_eq(
		AdvScenarioImporter.check_portrait_textures(book).size(), 0,
		"解決先が実在すれば警告なし")

	# 解決できない（表に無い）場合は警告
	portrait_set.texture_paths.clear()
	_assert_eq(
		AdvScenarioImporter.check_portrait_textures(book).size(), 1,
		"解決結果が空なら警告")


func _test_write_sample() -> void:
	var result: AdvImportResult = _import_sample({"force": true})
	_assert_true(result.is_ok(), "サンプルは ERROR なしで書き出せる")
	_assert_true(not result.skipped, "force なので skip しない")
	# characters 3 + topics 4 + book 1
	_assert_eq(result.written_paths.size(), 8, "8 ファイル書き出す")
	_assert_true(
		FileAccess.file_exists(OUT_DIR + AdvScenarioImporter.BOOK_FILE_NAME),
		"Book の .tres がある")
	_assert_true(
		FileAccess.file_exists(OUT_DIR + "characters/yuu.tres"), "characters/yuu.tres がある")
	_assert_true(
		FileAccess.file_exists(OUT_DIR + "topics/prologue_01.tres"),
		"topics/prologue_01.tres がある")
	_assert_eq(result.warnings().size(), 0, "実素材が揃ったサンプルは WARNING 0 件")
	_assert_true(result.summary().contains("成功"), "summary が成功を示す")

	# Book は topics / characters を ExtResource として参照する（インライン化されない）
	var text: String = FileAccess.get_file_as_string(
		OUT_DIR + AdvScenarioImporter.BOOK_FILE_NAME)
	_assert_true(
		text.contains("topics/prologue_01.tres"),
		"Book が topic を外部リソースとして参照する")
	_assert_true(
		not text.contains("[sub_resource type=\"Resource\""),
		"Book に topic が埋め込まれていない")


func _test_round_trip() -> void:
	var book := ResourceLoader.load(
		OUT_DIR + AdvScenarioImporter.BOOK_FILE_NAME, "",
		ResourceLoader.CACHE_MODE_IGNORE_DEEP) as AdvScenarioBook
	_assert_true(book != null, "書き出した Book を読み戻せる")
	if book == null:
		return
	_assert_eq(book.schema_version, 1, "schema_version が往復で保たれる")
	_assert_eq(book.content_hash, _sample_content_hash(), "content_hash が往復で保たれる")
	_assert_eq(book.topics.size(), 4, "topic が 4 件")
	_assert_eq(book.characters.size(), 3, "character が 3 件")

	var topic: AdvTopic = book.get_topic(&"prologue_01")
	_assert_true(topic != null, "topic を id で引ける")
	if topic == null:
		return
	# 畳み込み後: line / line / effect(blocking) / line / effect(blocking) / line / choice
	_assert_eq(topic.steps.size(), 7, "畳み込み後のステップ数が保たれる")
	_assert_true(topic.steps[0] is AdvLineStep, "派生型 AdvLineStep が保たれる")
	_assert_eq(topic.steps[0].uid, &"prologue_01:10", "uid が保たれる")
	_assert_eq(
		topic.steps[0].parallel_effects.size(), 1, "parallel_effects が保たれる")
	_assert_true(
		topic.steps[0].parallel_effects[0] is AdvEffectStep,
		"parallel_effects の要素型が保たれる")

	var choice := topic.steps[6] as AdvChoiceStep
	_assert_true(choice != null, "最後のステップは AdvChoiceStep")
	if choice != null:
		_assert_eq(choice.options.size(), 2, "options が保たれる")

	var character: AdvCharacter = book.get_character(&"yuu")
	_assert_true(character != null, "character を id で引ける")
	if character != null:
		_assert_true(character.portrait_set != null, "portrait_set が保たれる")
		_assert_eq(character.display_name, "ユウ", "display_name が保たれる")


func _test_skip_and_force() -> void:
	var skipped: AdvImportResult = _import_sample({})
	_assert_true(skipped.skipped, "content_hash が一致すれば書き出しを省く")
	_assert_eq(skipped.written_paths.size(), 0, "skip したら 1 件も書かない")
	_assert_true(skipped.is_ok(), "skip は成功扱い")
	_assert_true(skipped.summary().contains("変更なし"), "summary が「変更なし」を示す")

	var forced: AdvImportResult = _import_sample({"force": true})
	_assert_true(not forced.skipped, "--force なら hash が一致しても書き出す")
	_assert_eq(forced.written_paths.size(), 8, "--force で 8 ファイル書き直す")

	# content_hash が変われば skip しない
	var changed: AdvImportResult = AdvScenarioImporter.import_from_text(
		_sample_text().replace(_sample_content_hash(), "sample-0002"), "changed", OUT_DIR, {})
	_assert_true(not changed.skipped, "hash が変われば書き出す")
	_assert_eq(changed.written_paths.size(), 8, "8 ファイル書き直す")
	# 後続テストのために元へ戻す
	var _restored: AdvImportResult = _import_sample({"force": true})


func _test_stale() -> void:
	var stray_path: String = OUT_DIR + "topics/deleted_topic.tres"
	var stray := AdvTopic.new()
	stray.id = &"deleted_topic"
	stray.take_over_path(stray_path)
	_assert_eq(ResourceSaver.save(stray, stray_path), OK, "取り残し用の .tres を置ける")

	var result: AdvImportResult = _import_sample({"force": true})
	_assert_issue_code(
		result.issues, AdvScenarioImporter.CODE_STALE_RESOURCE,
		"JSON に無い .tres は stale_resource で警告する")
	_assert_true(
		result.stale_paths.has(stray_path), "stale_paths に取り残しが載る")
	_assert_true(
		FileAccess.file_exists(stray_path),
		"stale なファイルを削除しない（参照切れを避けるため）")
	_assert_true(result.is_ok(), "stale は WARNING なので成功扱い")

	DirAccess.remove_absolute(stray_path)


func _test_no_write_on_error() -> void:
	_purge_output_dir()
	var result: AdvImportResult = AdvScenarioImporter.import_from_text(
		BROKEN_JSON, "broken", OUT_DIR, {"force": true})
	_assert_true(not result.is_ok(), "unknown_topic は ERROR")
	_assert_issue_code(result.issues, &"unknown_topic", "unknown_topic を検出する")
	_assert_eq(result.written_paths.size(), 0, "ERROR があれば 1 件も書き出さない")
	_assert_true(
		not FileAccess.file_exists(OUT_DIR + AdvScenarioImporter.BOOK_FILE_NAME),
		"Book のファイルが作られていない")
	_assert_true(result.summary().contains("失敗"), "summary が失敗を示す")


func _test_dry_run_and_invalid() -> void:
	_purge_output_dir()
	var dry: AdvImportResult = AdvScenarioImporter.import_from_text(
		CLEAN_JSON, "clean", OUT_DIR, {"write": false})
	_assert_true(dry.is_ok(), "検証だけなら成功する")
	_assert_eq(dry.issues.size(), 0, "立ち絵なしキャラだけの JSON は issue 0 件")
	_assert_eq(dry.written_paths.size(), 0, "--no-write なら書き出さない")
	_assert_eq(dry.schema_version(), 3, "schema_version を読める")
	_assert_eq(dry.content_hash(), "clean-0001", "content_hash を読める")

	var invalid: AdvImportResult = AdvScenarioImporter.import_from_text(
		"これは JSON ではない", "garbage", OUT_DIR, {})
	_assert_true(not invalid.is_ok(), "壊れた JSON は ERROR")
	_assert_issue_code(invalid.issues, &"invalid_json", "invalid_json を出す")

	var missing: AdvImportResult = AdvScenarioImporter.import_from_file(
		"res://addons/adv_kit/samples/no_such_file.json", OUT_DIR, {})
	_assert_true(not missing.is_ok(), "存在しないファイルは ERROR")
	_assert_issue_code(missing.issues, &"invalid_json", "ファイル欠落も invalid_json")


func _test_import_from_file() -> void:
	_purge_output_dir()
	var result: AdvImportResult = AdvScenarioImporter.import_from_file(
		SAMPLE_PATH, OUT_DIR, {"check_textures": false})
	_assert_true(result.is_ok(), "ローカル JSON から取り込める")
	_assert_eq(result.written_paths.size(), 8, "8 ファイル書き出す")
	_assert_eq(
		result.warnings().size(), 0,
		"--no-texture-check なら missing_portrait_texture は出ない")
	_assert_eq(result.source_label, SAMPLE_PATH, "source_label に取得元が入る")


func _test_dock_scene() -> void:
	_assert_true(ResourceLoader.exists(DOCK_SCENE), "Dock のシーンがある")
	var scene := load(DOCK_SCENE) as PackedScene
	_assert_true(scene != null, "Dock のシーンを読める")
	if scene == null:
		return
	var dock := scene.instantiate() as Control
	_assert_true(dock != null, "Dock を生成できる")
	if dock == null:
		return
	root.add_child(dock)
	_assert_true(dock.get_node_or_null("UrlEdit") != null, "URL 入力欄がある")
	_assert_true(dock.get_node_or_null("OutEdit") != null, "出力先入力欄がある")
	_assert_true(
		dock.get_node_or_null("Buttons/FetchButton") != null, "取得ボタンがある")
	_assert_true(
		dock.get_node_or_null("Buttons/FileButton") != null, "ローカル JSON ボタンがある")
	root.remove_child(dock)
	dock.free()


# --- ヘルパ -----------------------------------------------------------------

func _sample_text() -> String:
	return FileAccess.get_file_as_string(SAMPLE_PATH)


func _sample_content_hash() -> String:
	var parsed: Variant = JSON.parse_string(_sample_text())
	if parsed is Dictionary:
		return str((parsed as Dictionary).get("content_hash", ""))
	return ""


func _import_sample(p_options: Dictionary) -> AdvImportResult:
	return AdvScenarioImporter.import_from_text(
		_sample_text(), SAMPLE_PATH, OUT_DIR, p_options)


func _purge_output_dir() -> void:
	_purge_dir(OUT_DIR + "characters/")
	_purge_dir(OUT_DIR + "topics/")
	_purge_dir(OUT_DIR)


func _purge_dir(p_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(p_dir):
		return
	for file_name: String in DirAccess.get_files_at(p_dir):
		DirAccess.remove_absolute(p_dir + file_name)
	DirAccess.remove_absolute(p_dir)


# --- ハーネス ---------------------------------------------------------------

func _run(p_name: String, p_body: Callable) -> void:
	_current_case = p_name
	print("")
	print("[ %s ]" % p_name)
	# 本体が await を含む場合があるので必ず待つ。
	# Callable なので静的には同期か判別できず、REDUNDANT_AWAIT も出ない（R-13）。
	await p_body.call()


func _assert_true(p_condition: bool, p_message: String) -> void:
	_executed += 1
	if p_condition:
		_passed += 1
		return
	_failed += 1
	print("  FAIL: %s — %s" % [_current_case, p_message])


func _assert_eq(p_actual: Variant, p_expected: Variant, p_message: String) -> void:
	_executed += 1
	if p_actual == p_expected:
		_passed += 1
		return
	_failed += 1
	print("  FAIL: %s — %s（期待: %s / 実際: %s）" % [
		_current_case, p_message, str(p_expected), str(p_actual)])


func _assert_issue_code(
	p_issues: Array[AdvIssue], p_code: StringName, p_message: String
) -> void:
	_executed += 1
	for issue: AdvIssue in p_issues:
		if issue.code == p_code:
			_passed += 1
			return
	_failed += 1
	print("  FAIL: %s — %s（%s が検出されなかった。検出: %s）" % [
		_current_case, p_message, p_code, str(_codes_of(p_issues))])


func _codes_of(p_issues: Array[AdvIssue]) -> PackedStringArray:
	var codes := PackedStringArray()
	for issue: AdvIssue in p_issues:
		codes.append(String(issue.code))
	return codes
