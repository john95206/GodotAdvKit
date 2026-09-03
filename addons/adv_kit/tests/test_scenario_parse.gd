extends SceneTree
## phase-01 の検証スクリプト。
##
## 実行方法（[b]--import を先に1回走らせること[/b]。class_name のグローバル解決に必要）:
## [codeblock]
## godot --headless --import
## godot --headless --script res://addons/adv_kit/tests/test_scenario_parse.gd
## [/codeblock]
## 失敗が1件でもあれば終了コード 1 を返す。

const SAMPLE_PATH := "res://addons/adv_kit/samples/sample_scenario.json"

var _passed: int = 0
var _failed: int = 0
var _executed: int = 0
var _current_case: String = ""


func _initialize() -> void:
	print("=== ADV Kit phase-01 / test_scenario_parse ===")
	_run("T-03 AdvIssue / AdvParseResult", _test_issue_and_result)
	_run("T-05 AdvPortraitSet.resolve", _test_portrait_resolve)
	_run("T-07 AdvCondition", _test_condition)
	_run("T-10 AdvEffectSchema", _test_effect_schema)
	_run("T-08 パース（サンプル）", _test_parse_sample)
	_run("T-09 畳み込み（仕様書 §4.8 の例）", _test_fold_example)
	_run("T-09 dangling_parallel / dangling_option", _test_dangling)
	_run("T-08 パースの検証コード", _test_parse_issue_codes)
	_run("T-11 バリデータの検証コード", _test_validator_codes)
	_run("T-15 同時演出の対象の取り合い", _test_parallel_conflicts)
	_run("T-06/T-11 サンプルは issue 0 件", _test_sample_is_clean)

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

func _test_issue_and_result() -> void:
	var err := AdvIssue.error(&"unknown_speaker", "topics/a/steps[0]", "テスト")
	_assert_true(err.is_error(), "error() は ERROR になる")
	_assert_eq(err.code, &"unknown_speaker", "code が保持される")
	_assert_true(err.to_line().contains("unknown_speaker"), "to_line にコードが出る")

	var warn := AdvIssue.warning(&"empty_topic", "topics/a", "テスト")
	_assert_true(not warn.is_error(), "warning() は WARNING になる")

	var result := AdvParseResult.new()
	_assert_true(result.is_ok(), "issue が無ければ is_ok")
	result.add_issue(warn)
	_assert_true(result.is_ok(), "WARNING だけなら is_ok のまま")
	result.add_issue(err)
	_assert_true(not result.is_ok(), "ERROR が1件でもあれば is_ok でない")
	_assert_eq(result.errors().size(), 1, "errors() は ERROR だけ")
	_assert_eq(result.warnings().size(), 1, "warnings() は WARNING だけ")


func _test_portrait_resolve() -> void:
	var portrait_set := AdvPortraitSet.new()
	portrait_set.default_pose = &"stand"
	portrait_set.default_expression = &"normal"
	portrait_set.texture_paths["stand/normal"] = "res://p/stand_normal.png"
	portrait_set.texture_paths["stand/smile"] = "res://p/stand_smile.png"
	portrait_set.texture_paths["sit/normal"] = "res://p/sit_normal.png"

	# 1段目: <pose>/<expression> が直接ヒット
	_assert_eq(portrait_set.resolve(&"stand", &"smile"), "res://p/stand_smile.png", "1段目でヒット")
	# 2段目: <pose>/<default_expression>
	_assert_eq(portrait_set.resolve(&"sit", &"angry"), "res://p/sit_normal.png", "2段目でヒット")
	# 3段目: <default_pose>/<expression>
	_assert_eq(portrait_set.resolve(&"jump", &"smile"), "res://p/stand_smile.png", "3段目でヒット")
	# 4段目: <default_pose>/<default_expression>
	_assert_eq(portrait_set.resolve(&"jump", &"angry"), "res://p/stand_normal.png", "4段目でヒット")

	# 全滅: 空文字を返す（例外を投げない）
	var empty_set := AdvPortraitSet.new()
	empty_set.default_pose = &"none"
	empty_set.default_expression = &"none"
	_assert_eq(empty_set.resolve(&"a", &"b"), "", "全滅なら空文字")

	# 立ち絵を持たないキャラでも進行を止めない
	var character := AdvCharacter.new()
	character.portrait_set = null
	_assert_eq(character.resolve_portrait(&"stand", &"normal"), "", "portrait_set が null なら空文字")


func _test_condition() -> void:
	# && が || より強く結合する
	var flags_a: Dictionary = {"a": true, "b": false, "c": true}
	_assert_true(AdvCondition.evaluate("a && b || c", flags_a), "a && b || c は (a && b) || c")
	var flags_b: Dictionary = {"a": true, "b": false, "c": false}
	_assert_true(not AdvCondition.evaluate("a && b || c", flags_b), "c が偽なら全体も偽")

	_assert_true(AdvCondition.evaluate("!b", flags_a), "! が効く")
	_assert_true(not AdvCondition.evaluate("undefined_flag", flags_a), "未定義フラグは false")
	_assert_true(AdvCondition.evaluate("!undefined_flag", flags_a), "未定義フラグの否定は true")

	# 空文字は「常に真」で issue なし
	_assert_true(AdvCondition.evaluate("", flags_a), "空文字は常に真")
	_assert_eq(AdvCondition.validate("", "loc").size(), 0, "空文字は検証しない")
	_assert_eq(AdvCondition.validate("   ", "loc").size(), 0, "空白のみも検証しない")

	# 正しい構文は issue が出ない
	for expr: String in ["a", "!a", "a && b", "a || b", "a && !b || c", "_x1 && y_2"]:
		_assert_eq(AdvCondition.validate(expr, "loc").size(), 0, "正しい構文: %s" % expr)

	# 不正構文は invalid_condition の ERROR になる
	for expr: String in ["a & b", "a == 1", "&& a", "a &&", "1abc", "a | b", "!!a", "a b"]:
		var issues: Array[AdvIssue] = AdvCondition.validate(expr, "loc")
		_assert_eq(issues.size(), 1, "不正構文は1件: %s" % expr)
		if issues.size() == 1:
			_assert_eq(issues[0].code, &"invalid_condition", "コードは invalid_condition: %s" % expr)
			_assert_true(issues[0].is_error(), "ERROR である: %s" % expr)

	# 未定義フラグは構文検証の対象外
	_assert_eq(AdvCondition.validate("never_defined_flag", "loc").size(), 0, "未定義フラグは検出しない")


func _test_effect_schema() -> void:
	var issues: Array[AdvIssue] = []
	var params: Dictionary = AdvEffectSchema.convert_params(
		&"shake", {"strength": "8", "duration": "0.4"}, "loc", issues)
	_assert_eq(issues.size(), 0, "shake は issue なし")
	_assert_true(params[&"strength"] is float, "strength=8 は float になる")
	_assert_eq(params[&"strength"], 8.0, "strength の値は 8.0")
	_assert_eq(params[&"frequency"], 24.0, "欠落した frequency は既定値で補われる")

	issues = []
	params = AdvEffectSchema.convert_params(
		&"play_bgm", {"stream": "res://a.ogg", "loop": "true"}, "loc", issues)
	_assert_eq(issues.size(), 0, "play_bgm は issue なし")
	_assert_true(params[&"loop"] is bool, "loop=true は bool になる")
	_assert_eq(params[&"loop"], true, "loop の値は true")

	issues = []
	params = AdvEffectSchema.convert_params(
		&"fade_out", {"color": "#112233"}, "loc", issues)
	_assert_eq(issues.size(), 0, "fade_out は issue なし")
	_assert_true(params[&"color"] is Color, "color=#112233 は Color になる")
	_assert_eq(params[&"color"], Color.html("#112233"), "color の値が一致する")

	# fade_in の color は runtime 解決。欠落しても issue にならず、値も入らない
	issues = []
	params = AdvEffectSchema.convert_params(&"fade_in", {"duration": "0.5"}, "loc", issues)
	_assert_eq(issues.size(), 0, "fade_in の color 欠落は issue にしない")
	_assert_true(not params.has(&"color"), "runtime パラメータは値を入れない")

	# 必須欠落
	issues = []
	AdvEffectSchema.convert_params(&"play_se", {}, "loc", issues)
	_assert_issue_code(issues, &"missing_effect_param", "stream 欠落は missing_effect_param")

	# 型変換の失敗
	issues = []
	AdvEffectSchema.convert_params(&"shake", {"duration": "abc"}, "loc", issues)
	_assert_issue_code(issues, &"invalid_effect_param", "duration=abc は invalid_effect_param")

	# 未知の effect_id
	issues = []
	params = AdvEffectSchema.convert_params(&"my_custom_effect", {"foo": "bar"}, "loc", issues)
	_assert_issue_code(issues, &"unknown_effect_id", "未知の effect_id は WARNING")
	_assert_eq(params[&"foo"], "bar", "未知演出の値は文字列のまま保持される")

	# スキーマ外のキー
	issues = []
	params = AdvEffectSchema.convert_params(
		&"stop_bgm", {"fade_out_time": "1.0", "nonsense": "42"}, "loc", issues)
	_assert_issue_code(issues, &"unknown_effect_param", "スキーマ外キーは WARNING")
	_assert_eq(params[&"nonsense"], "42", "未知キーの値は捨てずに文字列で保持される")
	_assert_true(params[&"fade_out_time"] is float, "既知キーは型変換される")

	# key=value; 記法の分解（仕様書 §6.2）
	var parsed: Dictionary = AdvEffectSchema.parse_param_string("strength=8; duration=0.4")
	_assert_eq(parsed[&"strength"], "8", "key=value; を分解できる")
	_assert_eq(parsed[&"duration"], "0.4", "空白は無視される")


func _test_parse_sample() -> void:
	var result: AdvParseResult = AdvScenarioParser.parse_file(SAMPLE_PATH)
	for line: String in result.to_lines():
		print("    " + line)
	_assert_true(result.is_ok(), "サンプルのパースは is_ok")

	var book: AdvScenarioBook = result.book
	_assert_eq(book.topics.size(), 4, "topic 数は 4")
	_assert_eq(book.characters.size(), 3, "character 数は 3")

	# 型変換
	var yuu: AdvCharacter = book.get_character(&"yuu")
	_assert_true(yuu != null, "yuu が引ける")
	_assert_eq(yuu.name_color, Color.html("#ffd27f"), "name_color が Color になる")
	_assert_true(yuu.id is StringName, "character.id は StringName")
	_assert_true(yuu.portrait_set != null, "yuu は立ち絵を持つ")
	_assert_eq(
		yuu.portrait_set.resolve(&"stand", &"smile"),
		"res://game/assets/adv/portraits/yuu/stand_smile.png",
		"立ち絵パスが規約どおり組まれる")
	var kaze: AdvCharacter = book.get_character(&"kaze")
	_assert_true(kaze.portrait_set == null, "portrait_dir の無いキャラは portrait_set が null")

	# 畳み込み後のステップ数
	var prologue: AdvTopic = book.get_topic(&"prologue_01")
	_assert_eq(prologue.steps.size(), 7, "prologue は 11 行 → 7 ステップ")
	_assert_eq(book.get_topic(&"route_a").steps.size(), 4, "route_a は 5 行 → 4 ステップ")
	_assert_eq(book.get_topic(&"route_b").steps.size(), 4, "route_b は 5 行 → 4 ステップ")
	_assert_eq(book.get_topic(&"epilogue_01").steps.size(), 5, "epilogue は畳み込み無しで 5 ステップ")
	_assert_eq(book.total_step_count(), 20, "畳み込み後の総ステップ数は 20")

	# uid と step_index
	_assert_eq(prologue.steps[0].uid, &"prologue_01:10", "uid は <topic_id>:<order>")
	_assert_eq(prologue.steps[0].order, 10, "order は JSON の値をそのまま保持する")
	for index: int in prologue.steps.size():
		_assert_eq(prologue.steps[index].step_index, index, "step_index が 0 起点で振り直される")

	# 畳み込み先が line 以外のケース（blocking 演出の直後の parallel）
	var shake_step: AdvStep = prologue.steps[2]
	_assert_true(shake_step is AdvEffectStep, "order=40 は effect ステップ")
	_assert_eq(shake_step.parallel_effects.size(), 1, "blocking 演出にも parallel が畳み込まれる")
	var bgm := shake_step.parallel_effects[0] as AdvEffectStep
	_assert_true(bgm != null, "parallel_effects の要素は AdvEffectStep")
	_assert_eq(bgm.effect_id, &"play_bgm", "畳み込まれたのは play_bgm")

	# line への畳み込み
	_assert_eq(prologue.steps[0].parallel_effects.size(), 1, "line にも parallel が畳み込まれる")

	# 選択肢
	var choice := prologue.steps[6] as AdvChoiceStep
	_assert_true(choice != null, "最後は choice ステップ")
	_assert_eq(choice.options.size(), 2, "option 行が 2 件畳み込まれる")
	_assert_eq(choice.options[0][AdvChoiceStep.KEY_GOTO], &"route_a", "goto は StringName")
	_assert_eq(choice.options[1][AdvChoiceStep.KEY_CONDITION], "!chose_go", "condition が保持される")

	# 地の文とボイス
	var narration := prologue.steps[1] as AdvLineStep
	_assert_true(narration.is_narration(), "speaker 空は地の文")
	_assert_eq(narration.voice_path, "", "voice 未指定は空文字")
	var first_line := prologue.steps[0] as AdvLineStep
	_assert_true(not first_line.voice_path.is_empty(), "voice 指定ありの行がある")

	# jump
	var jump := book.get_topic(&"route_a").steps[3] as AdvJumpStep
	_assert_true(jump != null, "route_a の最後は jump")
	_assert_eq(jump.goto, &"epilogue_01", "goto が StringName になる")


func _test_fold_example() -> void:
	# 仕様書 §4.8 の記述例をそのまま入力する
	var data: Dictionary = {
		"characters": [{"id": "yuu", "display_name": "ユウ"}],
		"topics": [{
			"id": "ch1",
			"tags": ["entry"],
			"steps": [
				{"order": 10, "type": "line", "speaker": "yuu", "text": "扉が開いた。"},
				{"order": 20, "type": "effect", "effect_id": "play_se",
					"params": {"stream": "res://door.ogg"}, "sync": "parallel"},
				{"order": 30, "type": "effect", "effect_id": "shake",
					"params": {"strength": "8", "duration": "0.4"}, "sync": "parallel"},
				{"order": 40, "type": "choice"},
				{"order": 50, "type": "option", "label": "入る", "goto": "ch1"},
				{"order": 60, "type": "option", "label": "引き返す", "goto": "ch1"},
			],
		}],
	}
	var result: AdvParseResult = AdvScenarioParser.parse(data)
	_assert_true(result.is_ok(), "§4.8 の例はエラー無くパースできる")
	var topic: AdvTopic = result.book.get_topic(&"ch1")
	_assert_eq(topic.steps.size(), 2, "6 行 → 2 ステップ（line + choice）")
	_assert_true(topic.steps[0] is AdvLineStep, "1つ目は line")
	_assert_eq(topic.steps[0].parallel_effects.size(), 2, "SE と揺れが line に畳み込まれる")
	var se := topic.steps[0].parallel_effects[0] as AdvEffectStep
	var shake := topic.steps[0].parallel_effects[1] as AdvEffectStep
	_assert_eq(se.effect_id, &"play_se", "order 順が保たれる（1つ目は play_se）")
	_assert_eq(shake.effect_id, &"shake", "order 順が保たれる（2つ目は shake）")
	var choice := topic.steps[1] as AdvChoiceStep
	_assert_true(choice != null, "2つ目は choice")
	_assert_eq(choice.options.size(), 2, "2 選択肢が choice に畳み込まれる")


func _test_dangling() -> void:
	var head_parallel: Dictionary = {
		"topics": [{
			"id": "t1", "tags": ["entry"],
			"steps": [
				{"order": 10, "type": "effect", "effect_id": "shake", "sync": "parallel"},
				{"order": 20, "type": "line", "text": "本文"},
			],
		}],
	}
	var result: AdvParseResult = AdvScenarioParser.parse(head_parallel)
	_assert_issue_code(result.issues, &"dangling_parallel", "topic 先頭の parallel は dangling_parallel")
	_assert_eq(result.book.get_topic(&"t1").steps.size(), 1, "畳み込めない parallel は捨てられる")

	var lonely_option: Dictionary = {
		"topics": [{
			"id": "t2", "tags": ["entry"],
			"steps": [
				{"order": 10, "type": "line", "text": "本文"},
				{"order": 20, "type": "option", "label": "孤児"},
			],
		}],
	}
	result = AdvScenarioParser.parse(lonely_option)
	_assert_issue_code(result.issues, &"dangling_option", "choice の直後でない option は dangling_option")
	_assert_eq(result.book.get_topic(&"t2").steps.size(), 1, "畳み込めない option は捨てられる")

	# 2つ目の parallel は「先頭でない」ので畳み込まれる（dangling にしない）
	var chained: Dictionary = {
		"topics": [{
			"id": "t3", "tags": ["entry"],
			"steps": [
				{"order": 10, "type": "line", "text": "本文"},
				{"order": 20, "type": "effect", "effect_id": "shake", "sync": "parallel"},
				{"order": 30, "type": "effect", "effect_id": "shake", "sync": "parallel"},
			],
		}],
	}
	result = AdvScenarioParser.parse(chained)
	_assert_no_issue_code(result.issues, &"dangling_parallel", "連続する parallel は同じステップへ畳み込む")
	_assert_eq(result.book.get_topic(&"t3").steps[0].parallel_effects.size(), 2, "2 件とも畳み込まれる")


func _test_parse_issue_codes() -> void:
	var data: Dictionary = {
		"characters": [
			{"id": "yuu", "display_name": "ユウ"},
			{"id": "yuu", "display_name": "重複"},
		],
		"topics": [
			{
				"id": "t1", "tags": ["entry"],
				"steps": [
					{"order": 10, "type": "line", "text": "本文"},
					{"order": 20, "type": "danceoff", "text": "未知の type"},
					{"type": "line", "text": "order が無い"},
					{"order": 10, "type": "line", "text": "order が重複"},
				],
			},
			{"id": "t1", "title": "重複した topic", "steps": []},
		],
	}
	var result: AdvParseResult = AdvScenarioParser.parse(data)
	_assert_issue_code(result.issues, &"duplicate_character_id", "character_id の重複")
	_assert_issue_code(result.issues, &"duplicate_topic_id", "topic_id の重複")
	_assert_issue_code(result.issues, &"unknown_step_type", "未知の type")
	_assert_issue_code(result.issues, &"missing_step_order", "order の欠落")
	_assert_issue_code(result.issues, &"duplicate_step_order", "order の重複")
	# 未知の type のステップだけを捨てて、残りのパースは続行する
	_assert_eq(result.book.get_topic(&"t1").steps.size(), 1, "壊れた行以外はパースが続く")
	_assert_eq(result.book.characters.size(), 1, "重複した character は 1 件だけ残る")


func _test_validator_codes() -> void:
	var data: Dictionary = {
		"characters": [{"id": "yuu", "display_name": "ユウ"}],
		"topics": [
			{
				"id": "t1", "tags": ["entry"],
				"steps": [
					{"order": 10, "type": "line", "speaker": "who", "text": "居ない話者"},
					{"order": 20, "type": "line", "speaker": "yuu", "slot": "middle", "text": "変な slot"},
					{"order": 30, "type": "choice", "prompt": "選択肢が無い"},
					{"order": 40, "type": "jump", "goto": "nowhere"},
					{"order": 50, "type": "jump", "goto": "t2", "condition": "a & b"},
					{"order": 60, "type": "effect", "effect_id": "shake",
						"sync": "parallel", "auto_advance": true},
					{"order": 70, "type": "effect", "effect_id": "hide_portrait",
						"params": {"speaker": "ghost"}, "sync": "blocking"},
				],
			},
			{"id": "t2", "steps": []},
			{"id": "t3", "steps": [{"order": 10, "type": "line", "text": "誰からも呼ばれない"}]},
		],
	}
	var result: AdvParseResult = AdvScenarioParser.parse(data)
	var issues: Array[AdvIssue] = AdvScenarioValidator.validate(result.book)

	_assert_issue_code(issues, &"unknown_speaker", "存在しない speaker")
	_assert_issue_code(issues, &"unknown_slot", "5種でない slot")
	_assert_issue_code(issues, &"empty_choice", "options が 0 件の choice")
	_assert_issue_code(issues, &"unknown_topic", "存在しない goto 先")
	_assert_issue_code(issues, &"invalid_condition", "条件式の構文エラー")
	_assert_issue_code(issues, &"invalid_auto_advance", "parallel + auto_advance")
	_assert_issue_code(issues, &"empty_topic", "steps が 0 件の topic")
	_assert_issue_code(issues, &"unreachable_topic", "どこからも参照されない topic")

	# 演出パラメータの speaker も unknown_speaker の対象
	var speaker_issues: int = 0
	for issue: AdvIssue in issues:
		if issue.code == &"unknown_speaker":
			speaker_issues += 1
	_assert_eq(speaker_issues, 2, "line の speaker と params の speaker の両方を見る")

	# entry タグを持つ t1 は参照されていなくても unreachable にしない
	for issue: AdvIssue in issues:
		if issue.code == &"unreachable_topic":
			_assert_true(
				not issue.location.ends_with("t1"),
				"entry タグを持つ topic は到達性検証の対象外")


func _test_parallel_conflicts() -> void:
	# 同じ対象を取り合う組み合わせ
	_assert_conflict(
		[_effect(20, "shake", {}, "parallel"), _effect(30, "shake", {}, "parallel")],
		true, "shake が 2 つ同時（画面の位置を取り合う）")
	_assert_conflict(
		[_effect(20, "fade_out", {}, "parallel"), _effect(30, "fade_in", {}, "parallel")],
		true, "fade_out と fade_in が同時（フェード層の alpha を取り合う）")
	_assert_conflict(
		[_effect(20, "play_bgm", {"stream": "res://a.ogg"}, "parallel"),
			_effect(30, "stop_bgm", {}, "parallel")],
		true, "play_bgm と stop_bgm が同時（BGM チャンネルを取り合う）")
	_assert_conflict(
		[_effect(20, "show_portrait", {"speaker": "yuu"}, "parallel"),
			_effect(30, "hide_portrait", {"speaker": "yuu"}, "parallel")],
		true, "同じキャラの show と hide が同時")
	_assert_conflict(
		[_effect(20, "move_portrait", {"speaker": "yuu", "to_slot": "left"}, "parallel"),
			_effect(30, "move_portrait", {"speaker": "yuu", "to_slot": "right"}, "parallel")],
		true, "同じキャラの move が 2 つ同時")

	# 取り合わない組み合わせ
	_assert_conflict(
		[_effect(20, "play_se", {"stream": "res://a.ogg"}, "parallel"),
			_effect(30, "play_se", {"stream": "res://b.ogg"}, "parallel")],
		false, "play_se は多重再生可なので取り合わない")
	_assert_conflict(
		[_effect(20, "show_portrait", {"speaker": "yuu"}, "parallel"),
			_effect(30, "move_portrait", {"speaker": "yuu", "to_slot": "left"}, "parallel")],
		false, "同じキャラでも alpha と位置なら取り合わない")
	_assert_conflict(
		[_effect(20, "move_portrait", {"speaker": "yuu", "to_slot": "left"}, "parallel"),
			_effect(30, "move_portrait", {"speaker": "rin", "to_slot": "right"}, "parallel")],
		false, "別のキャラの move なら取り合わない")
	_assert_conflict(
		[_effect(20, "shake", {}, "parallel"),
			_effect(30, "play_bgm", {"stream": "res://a.ogg"}, "parallel")],
		false, "対象が違えば同時でよい")

	# ホストのステップ自身が BLOCKING 演出の場合、それも取り合いの対象に含める
	_assert_conflict(
		[_effect(20, "shake", {}, "blocking"), _effect(30, "shake", {}, "parallel")],
		true, "blocking 演出とその直後の parallel 演出も同時に走る")
	_assert_conflict(
		[_effect(20, "shake", {}, "blocking"),
			_effect(30, "play_se", {"stream": "res://a.ogg"}, "parallel")],
		false, "blocking + parallel でも対象が違えばよい")

	# 未知の effect_id は取り合いを判定しない（拡張演出は自分で宣言する。phase-03）
	_assert_conflict(
		[_effect(20, "my_custom", {}, "parallel"), _effect(30, "my_custom", {}, "parallel")],
		false, "未知の演出は排他ターゲットを持たない")


func _test_sample_is_clean() -> void:
	var result: AdvParseResult = AdvScenarioParser.parse_file(SAMPLE_PATH)
	var issues: Array[AdvIssue] = AdvScenarioValidator.validate(result.book)
	for issue: AdvIssue in result.issues:
		print("    parse: " + issue.to_line())
	for issue: AdvIssue in issues:
		print("    validate: " + issue.to_line())
	_assert_eq(result.issues.size(), 0, "サンプルのパースは issue 0 件")
	_assert_eq(issues.size(), 0, "サンプルの検証は issue 0 件（WARNING も含めて）")


func _effect(
	p_order: int, p_effect_id: String, p_params: Dictionary, p_sync: String
) -> Dictionary:
	return {
		"order": p_order, "type": "effect", "effect_id": p_effect_id,
		"params": p_params, "sync": p_sync,
	}


## 先頭に line を1行置いた topic を組み、conflicting_parallel_effects の有無を見る。
func _assert_conflict(p_steps: Array, p_expected: bool, p_message: String) -> void:
	var steps: Array = [{"order": 10, "type": "line", "speaker": "yuu", "text": "本文"}]
	steps.append_array(p_steps)
	var data: Dictionary = {
		"characters": [
			{"id": "yuu", "display_name": "ユウ"},
			{"id": "rin", "display_name": "リン"},
		],
		"topics": [{"id": "t1", "tags": ["entry"], "steps": steps}],
	}
	var result: AdvParseResult = AdvScenarioParser.parse(data)
	var issues: Array[AdvIssue] = AdvScenarioValidator.validate(result.book)
	if p_expected:
		_assert_issue_code(issues, &"conflicting_parallel_effects", p_message)
	else:
		_assert_no_issue_code(issues, &"conflicting_parallel_effects", p_message)


# --- ハーネス ---------------------------------------------------------------

func _run(p_name: String, p_body: Callable) -> void:
	_current_case = p_name
	print("")
	print("[ %s ]" % p_name)
	p_body.call()


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


func _assert_no_issue_code(
	p_issues: Array[AdvIssue], p_code: StringName, p_message: String
) -> void:
	_executed += 1
	for issue: AdvIssue in p_issues:
		if issue.code == p_code:
			_failed += 1
			print("  FAIL: %s — %s（%s が出てしまった）" % [_current_case, p_message, p_code])
			return
	_passed += 1


func _codes_of(p_issues: Array[AdvIssue]) -> PackedStringArray:
	var codes := PackedStringArray()
	for issue: AdvIssue in p_issues:
		codes.append(String(issue.code))
	return codes
