extends SceneTree
## phase-05 の選択肢・話題遷移・進行状態テスト。
##
## 実行方法（--import を先に1回走らせること）:
## godot --headless --script res://addons/adv_kit/tests/test_progress.gd

const ADV_SCENE: PackedScene = preload("res://addons/adv_kit/ui/adv_scene.tscn")

var _failed: int = 0
var _passed: int = 0
var _presented_options: Array[Dictionary] = []
var _selected_index: int = -1
var _selected_option: Dictionary = {}
var _started_topics: Array[StringName] = []
var _finished_topics: Array[StringName] = []


func _initialize() -> void:
	print("=== ADV Kit phase-05 / test_progress ===")
	await _test_progress_state()

	var scene: AdvScene = ADV_SCENE.instantiate() as AdvScene
	_check(scene != null, "AdvScene をインスタンス化できる")
	if scene == null:
		quit(1)
		return
	root.add_child(scene)
	await process_frame

	var player: AdvPlayer = scene.player
	var choice_menu: AdvChoiceMenu = scene.get_node("ChoiceMenu") as AdvChoiceMenu
	var stage: AdvStage = scene.get_node("ShakeRoot/Stage") as AdvStage
	_check(player != null, "AdvScene.player が設定される")
	_check(choice_menu != null, "ChoiceMenu が AdvChoiceMenu として取得できる")
	_check(stage != null, "Stage が取得できる")
	if player == null or choice_menu == null or stage == null:
		quit(1)
		return

	player.choice_presented.connect(_on_choice_presented)
	player.choice_selected.connect(_on_choice_selected)
	player.topic_started.connect(_on_topic_started)
	player.topic_finished.connect(_on_topic_finished)

	await _test_choice_filter_and_continue(player)
	await _test_choice_goto_and_jump(player)
	await _test_restore_progress(player, stage)

	player.stop()
	scene.queue_free()
	await process_frame

	print("--- 結果 ---")
	print("%d 件実行 / 成功 %d / 失敗 %d" % [_passed + _failed, _passed, _failed])
	if _failed > 0:
		quit(1)
		return
	print("OK")
	quit(0)


func _test_progress_state() -> void:
	var state := AdvProgressState.new()
	state.set_position(&"topic_a", &"topic_a:20")
	_check(state.set_flag("chosen", true), "初回の flag 設定を変更として受け付ける")
	_check(not state.set_flag("chosen", true), "同じ値の flag 設定は変更にならない")
	state.mark_step_read(&"topic_a:10")
	state.mark_step_read(&"topic_a:10")
	var data: Dictionary = state.to_dictionary()
	var json_text: String = JSON.stringify(data)
	_check(not json_text.is_empty(), "進行辞書を JSON 化できる")
	_check(data["topic_id"] == "topic_a", "進行辞書の topic_id は String である")
	_check(data["step_uid"] == "topic_a:20", "進行辞書の step_uid は String である")
	_check(data["flags"]["chosen"] == true, "進行辞書に flag が含まれる")
	_check(data["read_steps"] is PackedStringArray, "既読集合は PackedStringArray へ変換される")
	_check((data["read_steps"] as PackedStringArray).size() == 1, "既読 UID が重複しない")
	_check(not data.has("step_index"), "進行辞書に step_index を保存しない")

	var restored := AdvProgressState.new()
	restored.restore_from_dictionary({
		"topic_id": "topic_b",
		"step_uid": "topic_b:30",
		"flags": {"chosen": "true"},
	})
	_check(restored.get_topic_id() == &"topic_b", "read_steps 欠損でも topic_id を復元できる")
	_check(restored.has_flag("chosen"), "文字列化された true の flag を復元できる")
	_check(not restored.is_step_read(&"topic_b:30"), "欠損した read_steps は空集合として復元される")


func _test_choice_filter_and_continue(p_player: AdvPlayer) -> void:
	_clear_events()
	var book: AdvScenarioBook = _make_choice_book()
	var settings := _make_settings()
	p_player.setup(book, settings)
	p_player.play_topic(&"choice")
	_check(p_player.is_step_read(&"choice:10"), "line 完了時に既読 UID が記録される")
	p_player.advance()
	_check(p_player.is_choice_open(), "choice 到達時に選択肢入力を待つ")
	_check(p_player.is_busy(), "choice 表示中は busy になる")
	_check(_presented_options.size() == 1, "条件偽の選択肢を UI へ渡さない")
	if _presented_options.size() == 1:
		_check(
			_presented_options[0][AdvChoiceStep.KEY_LABEL] == "その場に残る",
			"表示条件を通過した選択肢だけが残る")
	p_player.advance()
	_check(p_player.is_choice_open(), "choice 表示中の advance() を無視する")
	p_player.choose_option(0)
	_check(p_player.has_flag("stay"), "選択した option の flag を立てる")
	_check(_selected_index == 0, "choice_selected の index が正しい")
	_check(_selected_option[AdvChoiceStep.KEY_GOTO] == &"", "空 goto の option を選択できる")
	_check(not p_player.is_choice_open(), "option 選択後に choice を閉じる")
	_check(
		_get_body_text(p_player) == "選択後も同じ topic を続ける。",
		"空 goto で現在 topic の次の step へ進む")
	p_player.advance()
	_check(not p_player.is_playing(), "topic の末尾で scenario を完了する")


func _test_choice_goto_and_jump(p_player: AdvPlayer) -> void:
	_clear_events()
	var choice_book: AdvScenarioBook = _make_choice_book()
	var settings := _make_settings()
	p_player.setup(choice_book, settings)
	p_player.set_flag("enabled", true)
	p_player.play_topic(&"choice")
	p_player.advance()
	_check(_presented_options.size() == 1, "条件真の選択肢だけを表示する")
	if _presented_options.size() == 1:
		_check(
			_presented_options[0][AdvChoiceStep.KEY_LABEL] == "奥へ進む",
			"条件評価が flag の変更を反映する")
	p_player.choose_option(0)
	_check(p_player.has_flag("go"), "goto option の flag を立てる")
	_check(_started_topics == [&"choice", &"route"], "option の goto で topic を遷移する")
	_check(
		_get_body_text(p_player) == "別 topic の本文。",
		"goto 先の先頭 line を表示する")
	p_player.advance()
	_check(not p_player.is_playing(), "goto 先の末尾で scenario を完了する")

	_clear_events()
	var jump_book: AdvScenarioBook = _make_jump_book()
	p_player.setup(jump_book, settings)
	p_player.play_topic(&"entry")
	p_player.advance()
	_check(
		_get_body_text(p_player) == "条件偽なので同じ topic の次へ進む。",
		"条件偽の jump を素通りする")
	p_player.advance()
	_check(not p_player.is_playing(), "条件偽 jump の後も通常終了できる")

	_clear_events()
	p_player.setup(jump_book, settings)
	p_player.set_flag("go", true)
	p_player.play_topic(&"entry")
	p_player.advance()
	_check(_started_topics == [&"entry", &"route"], "条件真の jump で topic を遷移する")
	_check(
		_get_body_text(p_player) == "jump 先の本文。",
		"条件真の jump 先を表示する")
	p_player.advance()
	_check(not p_player.is_playing(), "jump 先の末尾で scenario を完了する")


func _test_restore_progress(p_player: AdvPlayer, p_stage: AdvStage) -> void:
	var book: AdvScenarioBook = _make_restore_book()
	var settings := _make_settings()
	p_player.setup(book, settings)
	p_player.play_topic(&"restore")
	p_player.advance()
	var saved: Dictionary = p_player.get_progress()
	_check(saved["topic_id"] == "restore", "保存時に現在 topic を取得できる")
	_check(saved["step_uid"] == "restore:20", "保存位置は安定 UID で取得できる")
	_check((saved["read_steps"] as PackedStringArray).has("restore:10"), "保存時に既読 line を含む")
	_check(saved.has("portrait_states"), "保存時に立ち絵状態を含む")
	_check(
		saved["portrait_states"]["alice"]["slot"] == "right",
		"保存時に立ち絵の slot を含む")

	p_player.setup(book, settings)
	p_player.restore_progress(saved)
	_check(p_player.is_playing(), "進行復元後に保存位置から再生する")
	_check(
		_get_body_text(p_player) == "復元される二つ目の本文。",
		"step UID から保存位置の line を再表示する")
	_check(p_stage.has_character(&"alice"), "進行復元時に立ち絵を復元する")
	_check(p_stage.get_character_slot(&"alice") == &"right", "立ち絵の slot を復元する")
	_check(p_player.is_step_read(&"restore:10"), "復元後も既読集合を保持する")
	p_player.advance()
	p_player.advance()
	_check(not p_player.is_playing(), "復元後も通常どおり末尾へ進める")


func _make_choice_book() -> AdvScenarioBook:
	var book := AdvScenarioBook.new()
	var alice := AdvCharacter.new()
	alice.id = &"alice"
	alice.display_name = "Alice"
	book.characters[alice.id] = alice
	book.topics[&"choice"] = _make_topic(&"choice", [
		_line(10, &"alice", "最初の本文。", &"left"),
		_choice(20, [
			{"label": "奥へ進む", "goto": &"route", "flag": "go", "condition": "enabled"},
			{"label": "その場に残る", "goto": &"", "flag": "stay", "condition": "!enabled"},
		]),
		_line(30, &"alice", "選択後も同じ topic を続ける。", &"left"),
	])
	book.topics[&"route"] = _make_topic(&"route", [
		_line(10, &"alice", "別 topic の本文。", &"right"),
	])
	return book


func _make_jump_book() -> AdvScenarioBook:
	var book := AdvScenarioBook.new()
	book.topics[&"entry"] = _make_topic(&"entry", [
		_line(10, &"", "jump の前。", &"center"),
		_jump(20, &"route", "go"),
		_line(30, &"", "条件偽なので同じ topic の次へ進む。", &"center"),
	])
	book.topics[&"route"] = _make_topic(&"route", [
		_line(10, &"", "jump 先の本文。", &"center"),
	])
	return book


func _make_restore_book() -> AdvScenarioBook:
	var book := AdvScenarioBook.new()
	var alice := AdvCharacter.new()
	alice.id = &"alice"
	alice.display_name = "Alice"
	book.characters[alice.id] = alice
	book.topics[&"restore"] = _make_topic(&"restore", [
		_line(10, &"alice", "保存される最初の本文。", &"left"),
		_line(20, &"alice", "復元される二つ目の本文。", &"right"),
		_line(30, &"alice", "復元後の最後の本文。", &"right"),
	])
	return book


func _make_settings() -> AdvKitSettings:
	var settings := AdvKitSettings.new()
	settings.typing_speed = 0.0
	settings.dim_duration = 0.0
	settings.hop_duration = 0.0
	return settings


func _make_topic(p_id: StringName, p_steps: Array) -> AdvTopic:
	var topic := AdvTopic.new()
	topic.id = p_id
	for index: int in p_steps.size():
		var step: AdvStep = p_steps[index] as AdvStep
		step.uid = StringName("%s:%d" % [p_id, step.order])
		step.step_index = index
		topic.steps.append(step)
	return topic


func _line(
	p_order: int, p_speaker_id: StringName, p_text: String, p_slot: StringName
) -> AdvLineStep:
	var line := AdvLineStep.new()
	line.order = p_order
	line.speaker_id = p_speaker_id
	line.slot = p_slot
	line.text = p_text
	return line


func _choice(p_order: int, p_options: Array) -> AdvChoiceStep:
	var choice := AdvChoiceStep.new()
	choice.order = p_order
	for option: Variant in p_options:
		choice.options.append(option as Dictionary)
	return choice


func _jump(p_order: int, p_goto: StringName, p_condition: String) -> AdvJumpStep:
	var jump := AdvJumpStep.new()
	jump.order = p_order
	jump.goto = p_goto
	jump.condition = p_condition
	return jump


func _get_body_text(p_player: AdvPlayer) -> String:
	if p_player.message_window == null:
		return ""
	var body: RichTextLabel = p_player.message_window.get_node_or_null("BodyLabel") as RichTextLabel
	if body == null:
		return ""
	return body.text


func _clear_events() -> void:
	_presented_options.clear()
	_selected_index = -1
	_selected_option = {}
	_started_topics.clear()
	_finished_topics.clear()


func _on_choice_presented(p_options: Array) -> void:
	_presented_options.clear()
	for raw_option: Variant in p_options:
		if raw_option is Dictionary:
			_presented_options.append(raw_option as Dictionary)


func _on_choice_selected(p_index: int, p_option: Dictionary) -> void:
	_selected_index = p_index
	_selected_option = p_option


func _on_topic_started(p_topic_id: StringName) -> void:
	_started_topics.append(p_topic_id)


func _on_topic_finished(p_topic_id: StringName) -> void:
	_finished_topics.append(p_topic_id)


func _check(p_condition: bool, p_message: String) -> void:
	if p_condition:
		_passed += 1
		return
	_failed += 1
	print("FAIL: %s" % p_message)
