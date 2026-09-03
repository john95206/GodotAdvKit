# ADV Kit

Godot 4.7 向けの ADV（ノベルゲーム）共通パッケージ（4.5 でも動作を確認済み）。
シナリオのデータモデル、JSON パーサ、検証、最小の再生ランタイムを提供する。

> **現在のフェーズ: phase-06 (play-assist)**
> 立ち絵付きの行をタイプライタ表示してテキスト送りでき、揺れ・フェード・立ち絵の
> 登場／退場／移動・SE・BGM・ボイスが動きます。話者交代時の非話者ダークとホップも
> 設定で制御できます。選択肢・話題遷移・フラグ・既読・進行復元にも対応しています。
> オートモード、既読連動スキップ、バックログ、バックログからのボイス再生にも対応しています。

---

## 使えるもの

| クラス | 役割 |
|--------|------|
| `AdvScenarioParser` | JSON（`Dictionary`）→ `AdvScenarioBook` |
| `AdvScenarioValidator` | Book 全体の参照整合性チェック |
| `AdvCondition` | `condition` 文字列の構文検証と評価 |
| `AdvEffectSchema` | 演出パラメータの型・既定値表と型変換 |
| `AdvParseResult` / `AdvIssue` | 結果と問題の1件 |
| `AdvProgressState` | topic / step UID / フラグ / 既読集合の Node 非依存状態 |
| `AdvBacklog` / `AdvBacklogEntry` | 上限付きバックログと line の表示情報 |
| `AdvPlayer` | 進行制御。演出の起動と BLOCKING の完了待ち |
| `AdvEffectHandler` / `AdvEffectContext` | 演出の拡張点と実行文脈 |
| `AdvAudioDirector` / `AdvVoicePlayer` | SE / BGM / ボイスのチャンネル |
| `AdvChoiceMenu` | ゲーム側が外観を実装する選択肢 UI の基底クラス |
| `AdvBacklogView` | ゲーム側が外観を実装するバックログ UI の基底クラス |

### 最短の使い方

```gdscript
var result: AdvParseResult = AdvScenarioParser.parse_file("res://path/to/scenario.json")
var issues: Array[AdvIssue] = AdvScenarioValidator.validate(result.book)

for issue: AdvIssue in result.issues + issues:
    print(issue.to_line())

if result.is_ok() and AdvScenarioValidator.is_ok(issues):
    var book: AdvScenarioBook = result.book
    var topic: AdvTopic = book.get_topic(&"prologue_01")
```

**パーサもバリデータも例外を投げない。** 問題は必ず `AdvIssue` として返る。
`AdvParseResult.is_ok()` は ERROR が 0 件かどうかだけを見る（WARNING は無視する）。

### 条件式

```gdscript
AdvCondition.evaluate("chose_go && !ended", {"chose_go": true})  # -> true
AdvCondition.validate("a & b", "topics/t1/steps[0]")             # -> invalid_condition の ERROR
```

文法は `!` / `&&` / `||` のみ。`&&` が `||` より強く結合する。**括弧は使えない。**
未定義フラグは `false`。空文字は「条件指定なし」で常に真、構文検証もしない。

### 演出パラメータ

```gdscript
var issues: Array[AdvIssue] = []
var params := AdvEffectSchema.convert_params(
    &"shake", {"strength": "8", "duration": "0.4"}, "topics/t1/steps[3]", issues)
# params[&"strength"] は float の 8.0、params[&"frequency"] は既定値 24.0
```

JSON の `params` は**値がすべて文字列でよい**。型付けはここが行う。

---

## 最小再生

`AdvScene.tscn` をゲーム側のシーンへインスタンスし、`player` に設定された
`AdvPlayer` へ Book と設定 Resource を渡します。

```gdscript
var adv_scene: AdvScene = preload(
    "res://addons/adv_kit/ui/adv_scene.tscn").instantiate()
add_child(adv_scene)

var result: AdvParseResult = AdvScenarioParser.parse_file(
    "res://path/to/scenario.json")
var settings := AdvKitSettings.new()
settings.typing_speed = 40.0
adv_scene.player.setup(result.book, settings)
adv_scene.player.play_topic(&"prologue_01")
```

### 選択肢と話題遷移

`AdvScene.tscn` には無装飾の `PlainChoiceMenu` が参照実装として接続されています。
ゲーム側では `AdvChoiceMenu` を継承したシーンを `player.choice_menu` に設定してください。
条件式が真の選択肢だけが `present()` に渡されます。

```gdscript
adv_scene.player.choice_selected.connect(_on_choice_selected)

func _on_choice_selected(_index: int, _option: Dictionary) -> void:
    pass # flag は選択前に設定済み。goto があれば自動で次の topic へ進む
```

テスト用 UI や独自の入力から選ぶ場合は `choose_option(index)` を呼べます。
選択肢の `goto` が空なら現在の topic を続け、指定があれば同じ Book 内の topic へ遷移します。
`jump` の条件が偽の場合は、その step だけを素通りします。

### 既読と進行データ

line がタイプライタ完了した時点で `uid` が既読になります。`get_progress()` はゲーム側の
Autoload などで `user://` に保存し、`restore_progress()` へ渡してください。Kit はファイルへ
直接書き込みません。

```gdscript
var progress: Dictionary = adv_scene.player.get_progress()
# progress: {topic_id, step_uid, flags, read_steps, portrait_states}
adv_scene.player.restore_progress(progress) # 現在の Book の保存位置から再生
```

`step_index` は保存しません。`portrait_states` には現在表示中のキャラクターの pose /
expression / slot / modulate が含まれ、旧形式でこのキーが無いデータも復元できます。

`AdvScene` の標準構成は `ShakeRoot`（背景＋ステージ）、`FadeLayer`、
`MessageWindow`、`AdvPlayer` です。入力アクション `adv_advance`（マウス左・
Enter・Space）、`adv_skip`（Ctrl）、`adv_auto`（A）、`adv_backlog`（ホイール上・B）が、
アドオン有効化時に未定義の場合だけ登録されます。
既存の InputMap 設定は変更しません。

### オート・スキップ・バックログ

AdvPlayer.set_auto_mode(true) で、line のタイプライタ完了後に auto_wait_time 待って
次へ進みます。auto_wait_for_voice が有効なら、ボイスの残り時間との最大値を待ちます。
advance()、選択肢、バックログ表示、シナリオ終端で解除されます。

start_skip() / stop_skip() は skip_action の押下中だけ継続するスキップです。既定では
未読 line に到達すると停止し、skip_unread = true なら未読も進みます。スキップ中は
タイプライタ・ボイス・演出の再生を行わず、演出の apply_final() だけを適用します。
選択肢停止は skip_stops_at_choice で制御できます。

open_backlog() / close_backlog() は AdvBacklogView を開閉し、開いている間の進行を止めます。
バックログは topic をまたいで保持し、stop() でクリアされます。backlog_voice_replay が
有効なら replay_voice(entry) または UI の voice_replay_requested で同じボイスチャンネル
から再生できます。バックログは get_progress() には含まれません。

### 話者交代の汎用演出

`AdvKitSettings` の設定で、シナリオに演出行を追加せずに話者交代の見せ方を調整できます。

```gdscript
settings.dim_non_speakers = true
settings.dim_color = Color(0.55, 0.55, 0.6)
settings.dim_duration = 0.15
settings.hop_on_speaker_change = true
settings.hop_height = 18.0
settings.hop_duration = 0.22
```

- 話者は白、非話者は `dim_color` へ RGB のみ Tween されます。立ち絵の alpha は保持します。
- 話者が変わったときだけ、対象の立ち絵が `hop_height` px 上へ跳ねて元の位置へ戻ります。
- 地の文（`speaker` が空の行）は直前話者の明暗状態を維持し、ホップもしません。
- どちらも進行を止めない非同期演出です。新しい話者の暗黙の登場にもホップが適用されます。

### メッセージ窓の差し替え

Kit は Theme を持ちません。ゲーム側で `AdvMessageWindow` を継承したシーンを作り、
次の4メソッドを実装して `AdvPlayer.message_window` に設定してください。

```gdscript
extends AdvMessageWindow

func show_line(p_speaker_name: String, p_name_color: Color, p_text: String) -> void:
    pass

func set_typing_progress(p_ratio: float) -> void:
    pass

func complete_typing() -> void:
    pass

func clear() -> void:
    pass
```

`advance_requested` と `skip_typing_requested` を、クリックや UI ボタンの signal
から emit すると `AdvPlayer` がそれぞれテキスト送り／タイプライタ完了として扱います。
無装飾の参照実装は `samples/ui/plain_message_window.tscn` です。

---

## 演出

シナリオの `effect` 行がそのまま動きます。`AdvScene.tscn` を使っていれば配線は不要です。

| effect_id | params |
|-----------|--------|
| `shake` | `strength=8.0` / `duration=0.4` / `frequency=24.0` |
| `fade_out` | `duration=0.5` / `color=#000000` |
| `fade_in` | `duration=0.5` / `color`（省略時は現在色を維持） |
| `show_portrait` | `speaker`（必須） / `slot=center` / `duration=0.2` |
| `hide_portrait` | `speaker`（必須） / `duration=0.2` |
| `move_portrait` | `speaker`（必須） / `to_slot`（必須） / `duration=0.4` / `ease=out` |
| `play_se` | `stream`（必須） / `volume_db=0.0` |
| `play_bgm` | `stream`（必須） / `fade_in_time=0.0` / `loop=true` |
| `stop_bgm` | `fade_out_time=0.0` |

- `sync=parallel` の演出は**直前のステップと同時に走り、完了を待ちません**。
- `sync=blocking` の演出は**独立した1ステップ**として完了まで待たれます。
  `auto_advance=TRUE` なら完了後に自動で次へ進み、`FALSE` ならテキスト送りを待ちます。
  待っている間 `AdvPlayer.is_busy()` が真になり、`advance()` は無視されます。
- **音源も立ち絵も、無ければ警告だけ出して進行は止まりません。**

### 独自の演出を足す

`AdvEffectHandler` を継承して `AdvPlayer.register_effect()` へ登録します。
組み込みと同じ id を登録すれば差し替えになります。

```gdscript
class MyFlashEffect extends AdvEffectHandler:
    func play(p_ctx: AdvEffectContext, p_params: Dictionary) -> void:
        var duration: float = get_float(p_params, &"duration", 0.2)
        var tween: Tween = p_ctx.acquire_tween(exclusive_targets(p_params))
        tween.tween_property(p_ctx.fade_layer, "color:a", 0.0, duration)
        await tween.finished

    func apply_final(p_ctx: AdvEffectContext, _p_params: Dictionary) -> void:
        p_ctx.fade_layer.color.a = 0.0

    ## 排他ターゲットを宣言すると、同時に走る演出との衝突を検証できる。
    func exclusive_targets(_p_params: Dictionary) -> PackedStringArray:
        return PackedStringArray(["fade_layer_alpha"])

adv_scene.player.register_effect(&"flash", MyFlashEffect.new())
```

- **Tween は必ず `ctx.acquire_tween()` で作ること。** 同じ排他ターゲットで走っている
  Tween を先に `kill()` するので、演出が重なっても「後から始まった方が勝つ」になります。
  直接 `create_tween()` を呼ぶと、この保護から外れます。
- `exclusive_targets()` を実装しない拡張演出は衝突検査の対象外です。
- 未登録の `effect_id` は警告を出して素通りします（進行は止まりません）。

## 音とボイス

- `AdvLineStep.voice_path` は `AdvPlayer` が自動で再生し、次のステップへ進んだ時点で止めます。
  **空でも進行は変わりません。**
- ボイスのバスは `AdvKitSettings.voice_bus`（既定 `Voice`）。無ければ `Master` に落ちます。
- **Web の autoplay ポリシー対応**として、最初のユーザー操作までは BGM・SE・ボイスの
  すべてを再生しません（保留もせず破棄します）。初回の `advance()` / `skip_typing()` で
  自動的に解除されますが、タイトル画面のクリックなどで先に解除したい場合は
  `AdvPlayer.unlock_audio()` を呼んでください。

### phase-06 の制限

- バックログは進行データではないため、get_progress() には含まれません。必要ならゲーム側で別途保存してください。
- skip_stops_at_choice = false のとき、スキップは選択肢を自動選択しません。選択後に継続します。
- AdvBacklogView の外観と、ボイス再生ボタンの配置はゲーム側で差し替えてください。
- 立ち絵テクスチャと音源は使う直前に遅延ロードされます。
  パスが空または存在しない場合も、警告だけ出して進行します。

---

## JSON スキーマ（要約）

完全な定義は仕様書 §6.3。

```json
{
  "schema_version": 1,
  "characters": [
    { "id": "yuu", "display_name": "ユウ", "name_color": "#ffd27f",
      "portrait_dir": "res://.../yuu", "poses": ["stand"], "expressions": ["normal"],
      "default_pose": "stand", "default_expression": "normal" }
  ],
  "topics": [
    { "id": "prologue_01", "title": "プロローグ", "tags": ["entry"],
      "steps": [
        { "order": 10, "type": "line", "speaker": "yuu", "text": "やあ。", "voice": "res://..." },
        { "order": 20, "type": "effect", "effect_id": "play_se",
          "params": { "stream": "res://..." }, "sync": "parallel" },
        { "order": 30, "type": "choice", "prompt": "どうする？" },
        { "order": 40, "type": "option", "label": "行く", "goto": "route_a", "flag": "chose_go" },
        { "order": 50, "type": "jump", "goto": "route_b", "condition": "!chose_go" }
      ] }
  ]
}
```

押さえるところ:

- **`steps` は flat。** `option` も `parallel` 演出も独立した要素として並べる。
  ネストを作るのは Godot 側（畳み込み。仕様書 §4.8）。
- **`order` は 10 刻みで振り、既存行の値は変更しない。**
  `uid = "<topic_id>:<order>"` が既読管理のキーになるため、変えると既読データが壊れる。
- `type` は `line` / `effect` / `choice` / `option` / `jump` の 5 種。
- `sync` は `parallel` / `blocking`。空なら `blocking`。
- `auto_advance` は `blocking` にだけ意味がある。

### 畳み込み（fold）

| 行の種類 | 畳み込み先 |
|----------|-----------|
| `type=effect` かつ `sync=parallel` | 直前のステップの `parallel_effects` |
| `type=option` | 直前の `AdvChoiceStep.options` |

畳み込み先は `line` に限らない。`blocking` 演出や `choice` の直後の `parallel` も畳み込まれる。
畳み込み後、`step_index` が 0 起点で振り直される（`uid` と `order` は振り直さない）。

---

## テストの走らせ方

```bash
# 1) class_name のグローバル解決のため、先にインポートを1回走らせる
godot --headless --import

# 2) phase-01 のテスト。失敗が1件でもあれば終了コード 1
godot --headless --script res://addons/adv_kit/tests/test_scenario_parse.gd

# 3) phase-02 の再生テスト
godot --headless --script res://addons/adv_kit/tests/test_playback.gd

# 4) phase-03 の演出・ボイステスト
godot --headless --script res://addons/adv_kit/tests/test_effects.gd

# 5) phase-04 の話者交代演出テスト
godot --headless --script res://addons/adv_kit/tests/test_auto_direction.gd

# 6) phase-05 の選択肢・進行状態テスト
godot --headless --script res://addons/adv_kit/tests/test_progress.gd

# 7) phase-06 のオート・スキップ・バックログテスト
godot --headless --script res://addons/adv_kit/tests/test_play_assist.gd
```

**`--import` を飛ばすと `class_name` が解決できずスクリプトが起動しない。**
`.godot/global_script_class_cache.cfg` が生成されていない状態では、
`--script` で起動したスクリプトからグローバルクラスを参照できないため。

CI では 1) → 2) → 3) → 4) → 5) → 6) の順に必ず全部走らせる。
**判定は終了コードで行うこと。** 終了時に出る `ObjectDB instances leaked` /
`resources still in use` は `AdvStep` の型自己参照による既知のもので、
終了コードには影響しない（仕様書 §4.3）。

---

## この時点で意図的にやっていないこと

- オート・本格的なスキップ・バックログ（phase-06）
- `.tres` の書き出し（`ResourceSaver` を呼ばない）
- 立ち絵テクスチャのインポート時検査（phase-07）
- HTTP 取得 / GAS / エディタ Dock / CLI インポータ（phase-07）
- `AdvScenarioBook.merge()`（章分割の運用が未決のため。仕様書 §13 U-07）

---

## ディレクトリ

```text
addons/adv_kit/
  plugin.cfg
  adv_kit_plugin.gd          # ProjectSettings に adv_kit/import/output_dir を登録
  core/
    adv_issue.gd
    adv_parse_result.gd
    adv_condition.gd
    adv_effect_schema.gd
    adv_scenario_parser.gd
    adv_scenario_validator.gd
    adv_progress_state.gd
    adv_backlog.gd  adv_backlog_entry.gd
  resources/
    adv_character.gd  adv_portrait_set.gd
    adv_step.gd       adv_line_step.gd   adv_effect_step.gd
    adv_choice_step.gd  adv_option_step.gd  adv_jump_step.gd
    adv_topic.gd  adv_scenario_book.gd  adv_kit_settings.gd
  ui/
    adv_scene.tscn / .gd  adv_stage.tscn / .gd
    adv_portrait.tscn / .gd  adv_message_window.gd  adv_choice_menu.gd  adv_backlog_view.gd
  runtime/
    adv_player.gd            # 進行制御
    adv_effect_context.gd    # 演出の実行文脈と排他ターゲットの Tween 台帳
    adv_audio_director.gd    # SE / BGM
    adv_voice_player.gd      # ボイス（単一チャンネル）
    effects/
      adv_effect_handler.gd  # @abstract。拡張点
      adv_shake_effect.gd    adv_fade_effect.gd
      adv_portrait_effect.gd adv_audio_effect.gd
  samples/ui/
    plain_message_window.tscn / .gd
    plain_choice_menu.tscn / .gd
    plain_backlog_view.tscn / .gd
  samples/sample_scenario.json
  tests/
    test_scenario_parse.gd  test_playback.gd  test_effects.gd  test_auto_direction.gd  test_progress.gd  test_play_assist.gd
    assets/test_tone.tres    # テスト専用の極小 WAV（実素材の代わり）
```

`AdvOptionStep` は**パースの中間表現**で、仕様書 §4 の表には無い。
JSON の 5 種の `type` を 1:1 で Resource に写し、畳み込み前後で
`AdvTopic.steps` の型を `Array[AdvStep]` に保つために置いている。
畳み込み後の `steps` に残ることはない。
