# ADV Kit

Godot 4.7 向けの ADV（ノベルゲーム）共通パッケージ（4.5 でも動作を確認済み）。
シナリオのデータモデル、JSON パーサ、検証、最小の再生ランタイムを提供する。

> **現在のフェーズ: phase-02 (runtime-playback)**
> `AdvScene` に `AdvPlayer` を組み込み、立ち絵付きの行をタイプライタ表示して
> テキスト送りできます。演出・選択肢・ボイスは後続フェーズです。

---

## 使えるもの

| クラス | 役割 |
|--------|------|
| `AdvScenarioParser` | JSON（`Dictionary`）→ `AdvScenarioBook` |
| `AdvScenarioValidator` | Book 全体の参照整合性チェック |
| `AdvCondition` | `condition` 文字列の構文検証と評価 |
| `AdvEffectSchema` | 演出パラメータの型・既定値表と型変換 |
| `AdvParseResult` / `AdvIssue` | 結果と問題の1件 |

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

`AdvScene` の標準構成は `ShakeRoot`（背景＋ステージ）、`FadeLayer`、
`MessageWindow`、`AdvPlayer` です。入力アクション `adv_advance`（マウス左・
Enter・Space）と `adv_skip`（Ctrl）が、アドオン有効化時に未定義の場合だけ登録されます。
既存の InputMap 設定は変更しません。

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

### phase-02 の制限

- `AdvEffectStep` と `parallel_effects` は警告を出して素通りします（phase-03）。
- `AdvChoiceStep` と `AdvJumpStep` は警告を出して素通りします（phase-05）。
- ボイス、非話者ダーク、話者交代ホップ、オート、スキップ、バックログ、セーブは未実装です。
- 立ち絵テクスチャは `AdvPortrait.apply()` の呼び出し時だけ遅延ロードされます。
  パスが空または存在しない場合も立ち絵無しとして進行します。

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
```

**`--import` を飛ばすと `class_name` が解決できずスクリプトが起動しない。**
`.godot/global_script_class_cache.cfg` が生成されていない状態では、
`--script` で起動したスクリプトからグローバルクラスを参照できないため。

CI では 1) → 2) の順に必ず両方を走らせる。

---

## この時点で意図的にやっていないこと

- 演出ハンドラ（phase-03）
- 選択肢・話題遷移・フラグ・既読・セーブ（phase-05）
- オート・本格的なスキップ・バックログ（phase-06）
- `.tres` の書き出し（`ResourceSaver` を呼ばない）
- ボイス（phase-03）
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
  resources/
    adv_character.gd  adv_portrait_set.gd
    adv_step.gd       adv_line_step.gd   adv_effect_step.gd
    adv_choice_step.gd  adv_option_step.gd  adv_jump_step.gd
    adv_topic.gd  adv_scenario_book.gd  adv_kit_settings.gd
  ui/
    adv_scene.tscn / .gd  adv_stage.tscn / .gd
    adv_portrait.tscn / .gd  adv_message_window.gd
  runtime/
    adv_player.gd
  samples/ui/
    plain_message_window.tscn / .gd
  samples/sample_scenario.json
  tests/test_scenario_parse.gd  test_playback.gd
```

`AdvOptionStep` は**パースの中間表現**で、仕様書 §4 の表には無い。
JSON の 5 種の `type` を 1:1 で Resource に写し、畳み込み前後で
`AdvTopic.steps` の型を `Array[AdvStep]` に保つために置いている。
畳み込み後の `steps` に残ることはない。
