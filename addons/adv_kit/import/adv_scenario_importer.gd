class_name AdvScenarioImporter
extends RefCounted
## GAS の JSON → 検証 → `.tres` 書き出し（仕様書 §6.4）。
##
## [b]エディタ Dock と CLI の共通ロジック。[/b] 入口はどちらも薄く、処理はすべてここにある。
##
## [b]この経路はデスクトップ（エディタ／CLI）でしか動かない。[/b]
## ランタイムから GAS API は叩かない（CORS 制約。仕様書 §6 冒頭）。
## `import/` はエクスポート除外対象（仕様書 §10）なので、ランタイムから参照してはならない。
##
## [b]例外を投げない。[/b] 取得失敗も書き出し失敗も AdvIssue として AdvImportResult に積む。

## 出力先の ProjectSettings キー。
const OUTPUT_DIR_SETTING := "adv_kit/import/output_dir"

## 出力先の既定値。
## [b]CLI はこのフォールバックを必ず持つ。[/b] `--import` では EditorPlugin._enter_tree()
## が走らないため、ProjectSettings にキーが無い状態で CLI が動くことがある（R-02）。
const OUTPUT_DIR_DEFAULT := "res://game/resources/adv/scenario/"

## Book のファイル名（既定）。
const BOOK_FILE_NAME := "scenario_book.tres"

## id 単位のファイルを置くサブディレクトリ。
const CHARACTERS_SUBDIR := "characters"
const TOPICS_SUBDIR := "topics"

## URL を環境変数から拾うときのキー。
## URL はリポジトリに置かない（仕様書 §6.2 / U-05）。
const URL_ENV_KEY := "ADV_KIT_SCENARIO_URL"

## HTTP 取得のタイムアウト（秒）。
const FETCH_TIMEOUT_SEC := 30.0

## 仕様書 §4.9 の表にあるコード。
const CODE_INVALID_JSON := &"invalid_json"
const CODE_MISSING_PORTRAIT := &"missing_portrait_texture"

## [b]仕様書 §4.9 の表に無いコード（phase-07 で追加）。[/b]
## パイプライン自体の失敗はシナリオの誤りではないが、
## 同じ AdvIssue の流れに乗せないと Dock と CLI で表示経路が二重になる。
## 引継ぎ資料で仕様書への追記を提案する。
const CODE_FETCH_FAILED := &"fetch_failed"
const CODE_WRITE_FAILED := &"write_failed"
const CODE_STALE_RESOURCE := &"stale_resource"


# --- 出力先 -------------------------------------------------------------------

## 出力先ディレクトリを決める。
## ProjectSettings に無ければ既定値へフォールバックする（R-02）。
static func resolve_output_dir() -> String:
	if ProjectSettings.has_setting(OUTPUT_DIR_SETTING):
		var value: Variant = ProjectSettings.get_setting(OUTPUT_DIR_SETTING)
		if value is String:
			var text: String = (value as String).strip_edges()
			if not text.is_empty():
				return normalize_dir(text)
	return normalize_dir(OUTPUT_DIR_DEFAULT)


## 末尾を "/" に揃える。
static func normalize_dir(p_dir: String) -> String:
	var text: String = p_dir.strip_edges()
	if text.is_empty():
		return normalize_dir(OUTPUT_DIR_DEFAULT)
	if text.ends_with("/"):
		return text
	return text + "/"


## options の欠けているキーを既定値で埋める。
static func default_options() -> Dictionary:
	return {
		"force": false,          # content_hash が一致しても書き出す
		"write": true,           # false なら検証だけ行う（ドライラン）
		"check_textures": true,  # missing_portrait_texture を検査する
		"book_name": BOOK_FILE_NAME,
	}


static func _merged_options(p_options: Dictionary) -> Dictionary:
	var merged: Dictionary = default_options()
	for key: Variant in p_options.keys():
		merged[key] = p_options[key]
	return merged


# --- 入口 ---------------------------------------------------------------------

## ローカル JSON ファイルから取り込む。オフライン検証用。
static func import_from_file(
	p_path: String, p_output_dir: String = "", p_options: Dictionary = {}
) -> AdvImportResult:
	if not FileAccess.file_exists(p_path):
		return _failed(CODE_INVALID_JSON, p_path, "ファイルが見つかりません: %s" % p_path)
	var text: String = FileAccess.get_file_as_string(p_path)
	if text.is_empty():
		var err: int = FileAccess.get_open_error()
		if err != OK:
			return _failed(CODE_INVALID_JSON, p_path, "読み込みに失敗しました (error %d)" % err)
		return _failed(CODE_INVALID_JSON, p_path, "ファイルが空です")
	return import_from_text(text, p_path, p_output_dir, p_options)


## GAS API から取得して取り込む。
## [b]await が要る。[/b] p_host は HTTPRequest を一時的にぶら下げる Node
## （エディタなら Dock、CLI なら SceneTree.root）。
##
## [b]生の URL は AdvImportResult に入れない。[/b] `source_label` も issue の location も
## [method redact_url] を通す。結果はログにも Dock にも出るため、
## ここで落とさないと秘匿（仕様書 §6.2 / U-05）が破れる。
static func import_from_url(
	p_host: Node, p_url: String, p_output_dir: String = "", p_options: Dictionary = {}
) -> AdvImportResult:
	var label: String = redact_url(p_url)
	var fetched: Dictionary = await fetch_json_text(p_host, p_url)
	if not bool(fetched.get("ok", false)):
		return _failed(CODE_FETCH_FAILED, label, str(fetched.get("message", "取得に失敗しました")))
	return import_from_text(str(fetched.get("text", "")), label, p_output_dir, p_options)


## ログに出してよい取得元の表記へ丸める。
##
## [b]URL の秘匿が唯一の認証手段なので（仕様書 §6.2 / U-05）、ホスト名から先は落とす。[/b]
## パスにデプロイ ID が入っており、それだけで API を叩けてしまうため。
## URL でない文字列（ローカルパスなど）はそのまま返す。
static func redact_url(p_source: String) -> String:
	var text: String = p_source.strip_edges()
	if not (text.begins_with("http://") or text.begins_with("https://")):
		return text
	var without_scheme: String = text.trim_prefix("https://").trim_prefix("http://")
	var host: String = without_scheme.split("/")[0]
	if host.is_empty():
		return "(URL は伏せています)"
	return "%s (以降は伏せています)" % host


## JSON テキストから取り込む。全処理の本体。
static func import_from_text(
	p_text: String,
	p_source_label: String,
	p_output_dir: String = "",
	p_options: Dictionary = {}
) -> AdvImportResult:
	var options: Dictionary = _merged_options(p_options)
	var output_dir: String = normalize_dir(p_output_dir) if not p_output_dir.strip_edges().is_empty() \
		else resolve_output_dir()

	# JSON.parse_string ではなく JSON.parse を使う。
	# 前者は失敗時にエンジンのエラーログを吐くので、
	# 「壊れた JSON を投げたら invalid_json が返る」という正常系がログを汚す。
	var json := JSON.new()
	var parse_error: int = json.parse(p_text)
	if parse_error != OK:
		return _failed(CODE_INVALID_JSON, p_source_label, "JSON を解釈できません: %s (%d 行目)" % [
			json.get_error_message(), json.get_error_line()])
	var data: Variant = json.data
	if not (data is Dictionary):
		return _failed(
			CODE_INVALID_JSON, p_source_label, "JSON のルートがオブジェクトではありません")

	# 1. パース（畳み込み・型変換・uid 生成まで）
	var parsed: AdvParseResult = AdvScenarioParser.parse(data as Dictionary)
	var result := AdvImportResult.new()
	result.source_label = p_source_label
	result.book = parsed.book
	result.add_issues(parsed.issues)

	# 2. 参照整合性と条件式の構文検証
	#    parse() だけでは invalid_condition が出ないので必ず併せて呼ぶ（仕様書 §4.9）
	result.add_issues(AdvScenarioValidator.validate(result.book))

	# 3. 立ち絵の解決結果を検査（インポート時のみ。仕様書 §4.2）
	if bool(options.get("check_textures", true)):
		result.add_issues(check_portrait_textures(result.book))

	# 4. ERROR が 1 件でもあれば書き出さない
	if not result.is_ok():
		return result
	if not bool(options.get("write", true)):
		return result

	# 5. content_hash が既存と一致するなら書き出しを省く（仕様書 §6.4）
	var book_path: String = output_dir + str(options.get("book_name", BOOK_FILE_NAME))
	if not bool(options.get("force", false)):
		var existing_hash: String = read_content_hash(book_path)
		if not existing_hash.is_empty() and existing_hash == result.book.content_hash:
			result.skipped = true
			return result

	_write_book(result, output_dir, book_path)
	return result


# --- 立ち絵の検査 --------------------------------------------------------------

## シナリオ中で実際に参照された (speaker, pose, expression) の解決結果だけを検査する。
##
## [b]texture_paths の総当たりは検査しない。[/b] 全組み合わせを用意する必要が無い以上、
## 存在しないパスが表に入るのは正常であり、総当たりを見ると正常なプロジェクトが
## 警告まみれになる（仕様書 §4.2）。
##
## [b]portrait_set を持たないキャラクターは対象外。[/b] 立ち絵無しキャラは設計上の正常な形で、
## 警告を出すと「立ち絵が無くても成立する」（仕様書 §1）という芯と矛盾する。
static func check_portrait_textures(p_book: AdvScenarioBook) -> Array[AdvIssue]:
	var issues: Array[AdvIssue] = []
	if p_book == null:
		return issues
	var seen: Dictionary = {}
	for topic_id: StringName in p_book.topics.keys():
		var topic: AdvTopic = p_book.topics[topic_id]
		if topic == null:
			continue
		for index: int in topic.steps.size():
			var line := topic.steps[index] as AdvLineStep
			if line == null:
				continue
			if String(line.speaker_id).is_empty():
				continue  # 地の文
			var character: AdvCharacter = p_book.get_character(line.speaker_id)
			if character == null:
				continue  # unknown_speaker はバリデータが ERROR で出す
			if character.portrait_set == null:
				continue  # 立ち絵を持たないキャラクター
			var location: String = AdvIssue.make_location(topic_id, index)
			var path: String = character.resolve_portrait(line.pose, line.expression)
			# 重複は「解決結果」で畳む。別々の (pose, expression) が同じパスへ
			# フォールバックすることがあるので、入力側で畳むと同じ警告が 2 回出る
			var key: String = "unresolved:%s|%s|%s" % [line.speaker_id, line.pose, line.expression] \
				if path.is_empty() else "missing:%s|%s" % [line.speaker_id, path]
			if seen.has(key):
				continue
			seen[key] = true
			if path.is_empty():
				issues.append(AdvIssue.warning(
					CODE_MISSING_PORTRAIT, location,
					"%s の pose=\"%s\" / expression=\"%s\" が解決できません（立ち絵なしで進行します）" % [
						line.speaker_id, line.pose, line.expression]))
				continue
			# .png はインポート後 .ctex になるため FileAccess ではなく ResourceLoader で見る
			if not ResourceLoader.exists(path):
				issues.append(AdvIssue.warning(
					CODE_MISSING_PORTRAIT, location,
					"%s の立ち絵 \"%s\" が見つかりません（立ち絵なしで進行します）" % [
						line.speaker_id, path]))
	return issues


# --- 取得 ---------------------------------------------------------------------

## GAS API を叩いて本文を返す。戻り値は {ok: bool, text: String, message: String}。
## [b]await が要る。[/b]
static func fetch_json_text(
	p_host: Node, p_url: String, p_timeout_sec: float = FETCH_TIMEOUT_SEC
) -> Dictionary:
	if p_host == null or not is_instance_valid(p_host):
		return {"ok": false, "text": "", "message": "HTTPRequest を置くホスト Node がありません"}
	if p_url.strip_edges().is_empty():
		return {"ok": false, "text": "", "message": "URL が空です"}

	var http := HTTPRequest.new()
	http.timeout = p_timeout_sec
	# GAS のウェブアプリは script.googleusercontent.com へ 302 する
	http.max_redirects = 8
	p_host.add_child(http)
	# R-08 と同じ理由で 1 フレーム待つ。SceneTree スクリプトの _initialize() 内で
	# add_child() した子は、次のフレームまで is_inside_tree() が偽で、
	# HTTPRequest.request() が ERR_UNCONFIGURED を返す。
	# p_host 自身がまだツリーに入っていないと get_tree() は null を返すので、
	# SceneTree は Engine から取る。
	if not http.is_inside_tree():
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null:
			http.queue_free()
			return {"ok": false, "text": "", "message": "SceneTree が取得できません"}
		await tree.process_frame

	var request_error: int = http.request(p_url)
	if request_error != OK:
		http.queue_free()
		return {
			"ok": false, "text": "",
			"message": "リクエストを開始できませんでした (error %d)" % request_error,
		}

	var response: Array = await http.request_completed
	http.queue_free()

	var result_code: int = response[0]
	var status: int = response[1]
	var body: PackedByteArray = response[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false, "text": "",
			"message": "取得に失敗しました (HTTPRequest result %d)" % result_code,
		}
	if status < 200 or status >= 300:
		return {"ok": false, "text": "", "message": "HTTP %d が返りました" % status}
	var text: String = body.get_string_from_utf8()
	if text.strip_edges().is_empty():
		return {"ok": false, "text": "", "message": "レスポンスが空です"}
	return {"ok": true, "text": text, "message": ""}


# --- 書き出し -----------------------------------------------------------------

## 既存 Book の content_hash を読む。読めなければ空文字。
static func read_content_hash(p_book_path: String) -> String:
	if not ResourceLoader.exists(p_book_path):
		return ""
	var existing := ResourceLoader.load(
		p_book_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as AdvScenarioBook
	if existing == null:
		return ""
	return existing.content_hash


## characters / topics / book を書き出し、消えた id を stale として拾う。
static func _write_book(
	p_result: AdvImportResult, p_output_dir: String, p_book_path: String
) -> void:
	var book: AdvScenarioBook = p_result.book
	var characters_dir: String = p_output_dir + CHARACTERS_SUBDIR + "/"
	var topics_dir: String = p_output_dir + TOPICS_SUBDIR + "/"
	for dir: String in [p_output_dir, characters_dir, topics_dir]:
		if not _ensure_dir(dir, p_result):
			return

	var character_files := PackedStringArray()
	for id: StringName in book.characters.keys():
		var character: AdvCharacter = book.characters[id]
		var file_name: String = _safe_file_name(String(id)) + ".tres"
		character_files.append(file_name)
		if not _save_resource(character, characters_dir + file_name, p_result):
			return

	var topic_files := PackedStringArray()
	for id: StringName in book.topics.keys():
		var topic: AdvTopic = book.topics[id]
		var file_name: String = _safe_file_name(String(id)) + ".tres"
		topic_files.append(file_name)
		if not _save_resource(topic, topics_dir + file_name, p_result):
			return

	# characters / topics は resource_path を持った状態になったので、
	# Book 側は ExtResource 参照として書かれる（インライン化されない）。
	if not _save_resource(book, p_book_path, p_result):
		return

	# 「全消し再生成」ではなく差し替え。JSON から消えたものは削除せず警告のみ（仕様書 §6.4）。
	_collect_stale(characters_dir, character_files, p_result)
	_collect_stale(topics_dir, topic_files, p_result)


static func _ensure_dir(p_dir: String, p_result: AdvImportResult) -> bool:
	if DirAccess.dir_exists_absolute(p_dir):
		return true
	var err: int = DirAccess.make_dir_recursive_absolute(p_dir)
	if err != OK:
		p_result.add_issue(AdvIssue.error(
			CODE_WRITE_FAILED, p_dir, "ディレクトリを作成できませんでした (error %d)" % err))
		return false
	return true


## take_over_path でパスを確定してから保存する。
## [b]FLAG_CHANGE_PATH ではなく take_over_path を使う。[/b]
## 既存 .tres がリソースキャッシュに載っていると、同じパスを持つリソースが
## 2 つある状態になって保存が弾かれるため、キャッシュごと奪う。
static func _save_resource(
	p_resource: Resource, p_path: String, p_result: AdvImportResult
) -> bool:
	if p_resource == null:
		return true
	p_resource.take_over_path(p_path)
	var err: int = ResourceSaver.save(p_resource, p_path)
	if err != OK:
		p_result.add_issue(AdvIssue.error(
			CODE_WRITE_FAILED, p_path, "書き出しに失敗しました (error %d)" % err))
		return false
	p_result.add_written(p_path)
	return true


static func _collect_stale(
	p_dir: String, p_expected: PackedStringArray, p_result: AdvImportResult
) -> void:
	if not DirAccess.dir_exists_absolute(p_dir):
		return
	for file_name: String in DirAccess.get_files_at(p_dir):
		if not file_name.ends_with(".tres"):
			continue
		if p_expected.has(file_name):
			continue
		var path: String = p_dir + file_name
		p_result.add_stale(path)
		p_result.add_issue(AdvIssue.warning(
			CODE_STALE_RESOURCE, path,
			"JSON に対応する id がありません。参照切れを避けるため削除していません。手動で確認してください"))


## id をファイル名に使える形へ丸める。
static func _safe_file_name(p_id: String) -> String:
	var text: String = p_id.strip_edges().validate_filename()
	if text.is_empty():
		return "_"
	return text


# --- CLI 引数 -----------------------------------------------------------------

## CLI 引数を解釈する。[b]CLI 本体から切り離して static にしてあるのはテストのため。[/b]
## 戻り値のキー: url / file / out / force / write / check_textures / book_name / help / errors
static func parse_cli_args(p_args: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = default_options()
	parsed["url"] = ""
	parsed["file"] = ""
	parsed["out"] = ""
	parsed["help"] = false
	var errors := PackedStringArray()

	for arg: String in p_args:
		var text: String = arg.strip_edges()
		if text.is_empty():
			continue
		if text == "--help" or text == "-h":
			parsed["help"] = true
		elif text == "--force":
			parsed["force"] = true
		elif text == "--no-write":
			parsed["write"] = false
		elif text == "--no-texture-check":
			parsed["check_textures"] = false
		elif text.begins_with("--url="):
			parsed["url"] = text.trim_prefix("--url=").strip_edges()
		elif text.begins_with("--file="):
			parsed["file"] = text.trim_prefix("--file=").strip_edges()
		elif text.begins_with("--out="):
			parsed["out"] = text.trim_prefix("--out=").strip_edges()
		elif text.begins_with("--book-name="):
			parsed["book_name"] = text.trim_prefix("--book-name=").strip_edges()
		else:
			errors.append("不明な引数: %s" % text)

	if not bool(parsed["help"]):
		if String(parsed["url"]).is_empty() and String(parsed["file"]).is_empty():
			var from_env: String = OS.get_environment(URL_ENV_KEY).strip_edges()
			if from_env.is_empty():
				errors.append("--url= か --file= のどちらかが要ります（環境変数 %s でも可）" % URL_ENV_KEY)
			else:
				parsed["url"] = from_env
		elif not String(parsed["url"]).is_empty() and not String(parsed["file"]).is_empty():
			errors.append("--url= と --file= は同時に指定できません")

	parsed["errors"] = errors
	return parsed


static func cli_usage() -> String:
	return """ADV Kit シナリオインポータ (CLI)

  godot --headless --script res://addons/adv_kit/import/adv_import_cli.gd -- [options]

  --url=<URL>          GAS ウェブアプリの URL から取得する
  --file=<path>        ローカル JSON から取り込む（オフライン検証用）
  --out=<res://dir/>   出力先。既定は ProjectSettings の %s
  --book-name=<name>   Book のファイル名。既定 %s
  --force              content_hash が一致していても書き出す
  --no-write           検証だけ行い、書き出さない
  --no-texture-check   立ち絵の存在検査（%s）を省く
  -h, --help           このヘルプ

  URL は環境変数 %s からも読む。リポジトリに URL を置かないこと。
  書き出し後、CI では続けて `godot --headless --import` を 1 回走らせること。
  終了コード: 0=成功 / 1=ERROR あり / 2=引数が不正""" % [
		OUTPUT_DIR_SETTING, BOOK_FILE_NAME, CODE_MISSING_PORTRAIT, URL_ENV_KEY]


# --- helpers ------------------------------------------------------------------

static func _failed(
	p_code: StringName, p_source_label: String, p_message: String
) -> AdvImportResult:
	var result := AdvImportResult.new()
	result.source_label = p_source_label
	result.book = AdvScenarioBook.new()
	result.add_issue(AdvIssue.error(p_code, p_source_label, p_message))
	return result
