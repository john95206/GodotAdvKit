extends SceneTree
## phase-06 のオート・スキップ・バックログテスト。
##
## 実行方法（--import を先に1回走らせること）:
## godot --headless --path . --script res://addons/adv_kit/tests/test_play_assist.gd

const ADV_SCENE: PackedScene = preload("res://addons/adv_kit/ui/adv_scene.tscn")
const TONE_PATH: String = "res://addons/adv_kit/tests/assets/test_tone.tres"

var _failed: int = 0
var _passed: int = 0
var _scene: AdvScene = null
var _player: AdvPlayer = null
var _backlog_view: AdvBacklogView = null
var _skip_reasons: Array[StringName] = []
var _auto_events: Array[bool] = []


class ProbeEffect extends AdvEffectHandler:
    var play_count: int = 0
    var final_count: int = 0

    func play(_p_ctx: AdvEffectContext, _p_params: Dictionary) -> void:
        play_count += 1

    func apply_final(_p_ctx: AdvEffectContext, _p_params: Dictionary) -> void:
        final_count += 1


func _initialize() -> void:
    print("=== ADV Kit phase-06 / test_play_assist ===")
    _scene = ADV_SCENE.instantiate() as AdvScene
    _check(_scene != null, "AdvScene をインスタンス化できる")
    if _scene == null:
        quit(1)
        return
    root.add_child(_scene)
    await process_frame
    _player = _scene.player
    _backlog_view = _scene.get_node("BacklogView") as AdvBacklogView
    _check(_player != null, "AdvScene.player が設定される")
    _check(_backlog_view != null, "BacklogView が基底型で取得できる")
    if _player == null:
        quit(1)
        return
    _player.skip_stopped.connect(_on_skip_stopped)
    _player.auto_mode_changed.connect(_on_auto_mode_changed)

    await _test_backlog_data_and_recording()
    await _test_auto_mode()
    await _test_skip_read_and_unread()
    await _test_skip_final_effect_and_choice()
    await _test_backlog_open_and_voice_replay()

    _scene.queue_free()
    await process_frame
    print("--- 結果 ---")
    print("%d 件実行 / 成功 %d / 失敗 %d" % [_passed + _failed, _passed, _failed])
    if _failed > 0:
        quit(1)
        return
    print("OK")
    quit(0)


func _test_backlog_data_and_recording() -> void:
    var backlog := AdvBacklog.new()
    backlog.set_max_entries(2)
    backlog.append(AdvBacklogEntry.new(&"a:10", "A", Color.RED, "one", ""))
    backlog.append(AdvBacklogEntry.new(&"a:20", "A", Color.GREEN, "two", ""))
    backlog.append(AdvBacklogEntry.new(&"a:30", "A", Color.BLUE, "three", ""))
    var entries: Array[AdvBacklogEntry] = backlog.get_entries()
    _check(entries.size() == 2, "バックログの上限を超えた項目を捨てる")
    _check(entries[0].uid == &"a:20" and entries[1].uid == &"a:30", "古いバックログから捨てる")
    backlog.set_max_entries(0)
    backlog.append(AdvBacklogEntry.new(&"a:40"))
    _check(backlog.is_empty(), "バックログ上限 0 を安全に扱う")

    var settings := _make_settings()
    settings.backlog_max_entries = 2
    _player.setup(_make_line_book(3), settings)
    _player.play_topic(&"lines")
    _check(_player.get_backlog().size() == 1, "line 完了時にバックログへ記録する")
    _player.advance()
    _player.advance()
    entries = _player.get_backlog()
    _check(entries.size() == 2, "バックログを設定上限まで保持する")
    _check(entries[0].text == "line 2" and entries[1].text == "line 3", "line の順序を保持する")
    _check(entries[1].speaker_name == "Alice", "バックログに話者名を保持する")
    _player.stop()
    _check(_player.get_backlog().is_empty(), "stop() でバックログをクリアする")


func _test_auto_mode() -> void:
    _skip_reasons.clear()
    _auto_events.clear()
    var settings := _make_settings()
    settings.auto_wait_time = 0.03
    settings.auto_wait_for_voice = false
    _player.setup(_make_line_book(2), settings)
    _player.play_topic(&"lines")
    _player.set_auto_mode(true)
    _check(_player.is_auto_mode(), "set_auto_mode(true) でオートを有効にする")
    _check(_get_body_text() == "line 1", "オート開始時に最初の line を表示する")
    await _wait_for_body("line 2", 30)
    _check(_get_body_text() == "line 2", "auto_wait_time 後に次の line へ進む")
    _check(_auto_events.has(true), "auto_mode_changed(true) を発火する")

    var manual_settings := _make_settings()
    manual_settings.auto_wait_time = 1.0
    _player.setup(_make_line_book(2), manual_settings)
    _player.play_topic(&"lines")
    _player.set_auto_mode(true)
    _player.advance()
    _check(not _player.is_auto_mode(), "ユーザーの advance でオートを解除する")
    _check(_get_body_text() == "line 2", "オート解除後の advance を通常どおり処理する")

    var voice_settings := _make_settings()
    voice_settings.auto_wait_time = 0.0
    voice_settings.auto_wait_for_voice = true
    var voice_book: AdvScenarioBook = _make_line_book(2)
    var first: AdvLineStep = voice_book.get_topic(&"lines").steps[0] as AdvLineStep
    first.voice_path = TONE_PATH
    _player.setup(voice_book, voice_settings)
    _player.unlock_audio()
    _player.play_topic(&"lines")
    _player.set_auto_mode(true)
    var voice_remaining: float = _player.get_voice_player().get_remaining_time()
    _check(voice_remaining > 0.0, "line 表示時にボイス残時間を取得できる")
    await process_frame
    if voice_remaining > 0.05:
        _check(_get_body_text() == "line 1", "ボイス待機中は auto が先へ進まない")
    await _wait_for_body("line 2", 120)
    _check(_get_body_text() == "line 2", "ボイス終了後に auto が次へ進む")
    _player.stop()


func _test_skip_read_and_unread() -> void:
    var settings := _make_settings()
    settings.skip_interval = 0.0
    settings.skip_unread = false
    var book: AdvScenarioBook = _make_line_book(3)
    _player.setup(book, settings)
    _player.restore_progress({
        "topic_id": "lines",
        "step_uid": "lines:10",
        "flags": {},
        "read_steps": PackedStringArray(["lines:10", "lines:20"]),
    })
    _skip_reasons.clear()
    _player.start_skip()
    await _wait_until_not_skipping(30)
    _check(not _player.is_skipping(), "未読 line 到達時にスキップを解除する")
    _check(_skip_reasons.has(&"unread"), "未読停止の理由を通知する")
    _check(_get_body_text() == "line 3", "未読 line を表示して停止する")
    _check(_player.is_step_read(&"lines:10") and _player.is_step_read(&"lines:20"),
        "スキップ中も既読 line を保持する")

    var force_settings := _make_settings()
    force_settings.skip_interval = 0.0
    force_settings.skip_unread = true
    _player.setup(book, force_settings)
    _player.restore_progress({
        "topic_id": "lines",
        "step_uid": "lines:10",
        "flags": {},
        "read_steps": PackedStringArray(["lines:10"]),
    })
    _skip_reasons.clear()
    _player.start_skip()
    await _wait_until_not_skipping(60)
    _check(not _player.is_playing(), "skip_unread=true で未読も最後まで進む")
    _check(_skip_reasons.has(&"finished"), "終端停止の理由を通知する")
    _check(_player.is_step_read(&"lines:20") and _player.is_step_read(&"lines:30"),
        "強制スキップした line も既読にする")


func _test_skip_final_effect_and_choice() -> void:
    var settings := _make_settings()
    settings.skip_interval = 0.0
    var book := AdvScenarioBook.new()
    book.topics[&"effect"] = _make_topic(&"effect", [
        _line(10, "line 1"),
        _effect(20),
        _line(30, "line 3"),
    ])
    var probe := ProbeEffect.new()
    _player.setup(book, settings)
    _player.register_effect(&"probe", probe)
    _player.restore_progress({
        "topic_id": "effect",
        "step_uid": "effect:10",
        "flags": {},
        "read_steps": PackedStringArray(["effect:10"]),
    })
    _player.start_skip()
    await _wait_until_not_skipping(30)
    _check(probe.play_count == 0, "スキップ中は演出の play() を呼ばない")
    _check(probe.final_count == 1, "スキップ中は演出の apply_final() を呼ぶ")

    var choice_book := AdvScenarioBook.new()
    choice_book.topics[&"choice"] = _make_topic(&"choice", [
        _line(10, "before choice"),
        _choice(20),
        _line(30, "after choice"),
    ])
    var choice_settings := _make_settings()
    choice_settings.skip_interval = 0.0
    _player.setup(choice_book, choice_settings)
    _player.restore_progress({
        "topic_id": "choice",
        "step_uid": "choice:10",
        "flags": {},
        "read_steps": PackedStringArray(["choice:10"]),
    })
    _skip_reasons.clear()
    _player.start_skip()
    await _wait_until_not_skipping(30)
    _check(_skip_reasons.has(&"choice"), "選択肢停止の理由を通知する")
    _check(_player.is_choice_open(), "選択肢到達時に入力待ちへ戻る")


func _test_backlog_open_and_voice_replay() -> void:
    var settings := _make_settings()
    settings.auto_wait_time = 1.0
    settings.backlog_voice_replay = true
    _player.setup(_make_line_book(2), settings)
    _player.play_topic(&"lines")
    _player.set_auto_mode(true)
    _player.open_backlog()
    _check(_player.is_backlog_open(), "open_backlog() で状態を保持する")
    _check(_backlog_view != null and _backlog_view.visible, "BacklogView.present() を呼ぶ")
    var body_before: String = _get_body_text()
    _player.advance()
    _check(_get_body_text() == body_before, "バックログ表示中は advance を抑止する")
    _player.close_backlog()
    _check(not _player.is_backlog_open(), "close_backlog() で状態を戻す")
    _player.advance()
    _check(_get_body_text() == "line 2", "バックログを閉じると進行を再開する")

    var entry := AdvBacklogEntry.new(&"lines:10", "Alice", Color.WHITE, "voice", TONE_PATH)
    _player.unlock_audio()
    _player.replay_voice(entry)
    _check(_player.get_voice_player().current_path() == TONE_PATH, "バックログのボイスを replay する")
    _player.stop()
    var disabled_settings := _make_settings()
    disabled_settings.backlog_voice_replay = false
    _player.setup(_make_line_book(1), disabled_settings)
    _player.unlock_audio()
    _player.replay_voice(entry)
    _check(_player.get_voice_player().current_path().is_empty(), "ボイス replay 無効時は再生しない")
    _player.stop()


func _make_settings() -> AdvKitSettings:
    var settings := AdvKitSettings.new()
    settings.typing_speed = 0.0
    settings.dim_duration = 0.0
    settings.hop_duration = 0.0
    return settings


func _make_line_book(p_count: int) -> AdvScenarioBook:
    var book := AdvScenarioBook.new()
    var alice := AdvCharacter.new()
    alice.id = &"alice"
    alice.display_name = "Alice"
    book.characters[alice.id] = alice
    var steps: Array[AdvStep] = []
    for index: int in p_count:
        steps.append(_line((index + 1) * 10, "line %d" % (index + 1), &"alice"))
    book.topics[&"lines"] = _make_topic(&"lines", steps)
    return book


func _line(p_order: int, p_text: String, p_speaker: StringName = &"") -> AdvLineStep:
    var line := AdvLineStep.new()
    line.order = p_order
    line.uid = StringName("lines:%d" % p_order)
    line.speaker_id = p_speaker
    line.text = p_text
    return line


func _effect(p_order: int) -> AdvEffectStep:
    var effect := AdvEffectStep.new()
    effect.order = p_order
    effect.uid = StringName("effect:%d" % p_order)
    effect.effect_id = &"probe"
    effect.sync_mode = AdvEffectStep.SyncMode.BLOCKING
    return effect


func _choice(p_order: int) -> AdvChoiceStep:
    var choice := AdvChoiceStep.new()
    choice.order = p_order
    choice.uid = StringName("choice:%d" % p_order)
    choice.options.append({"label": "Continue", "goto": &"", "flag": ""})
    return choice


func _make_topic(p_id: StringName, p_steps: Array) -> AdvTopic:
    var topic := AdvTopic.new()
    topic.id = p_id
    for index: int in p_steps.size():
        var step: AdvStep = p_steps[index] as AdvStep
        step.uid = StringName("%s:%d" % [p_id, step.order])
        step.step_index = index
        topic.steps.append(step)
    return topic


func _wait_for_body(p_text: String, p_max_frames: int) -> void:
    var guard: int = 0
    while guard < p_max_frames and _get_body_text() != p_text:
        await process_frame
        guard += 1
    _check(_get_body_text() == p_text, "期待した本文へ到達する: %s" % p_text)


func _wait_until_not_skipping(p_max_frames: int) -> void:
    var guard: int = 0
    while _player.is_skipping() and guard < p_max_frames:
        await process_frame
        guard += 1
    _check(not _player.is_skipping(), "スキップが待機上限内に終了する")


func _get_body_text() -> String:
    if _player == null or _player.message_window == null:
        return ""
    var body := _player.message_window.get_node_or_null("BodyLabel") as RichTextLabel
    return "" if body == null else body.text


func _on_skip_stopped(p_reason: StringName) -> void:
    _skip_reasons.append(p_reason)


func _on_auto_mode_changed(p_enabled: bool) -> void:
    _auto_events.append(p_enabled)


func _check(p_condition: bool, p_message: String) -> void:
    if p_condition:
        _passed += 1
        return
    _failed += 1
    print("FAIL: %s" % p_message)
