# ADV Kit

Godot 4.7 向けの ADV（ノベルゲーム）共通パッケージ（4.5 でも動作を確認済み）。
シナリオのデータモデル、JSON パーサ、検証を提供する。

> **現在のフェーズ: phase-01 (foundation-and-data-model)**
> この時点で動くのは **データの形とその検証だけ**。
> 進行制御（`AdvPlayer`）・UI・演出ハンドラ・インポータはまだ無い。

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

# 2) テスト実行。失敗が1件でもあれば終了コード 1
godot --headless --script res://addons/adv_kit/tests/test_scenario_parse.gd
```

**`--import` を飛ばすと `class_name` が解決できずスクリプトが起動しない。**
`.godot/global_script_class_cache.cfg` が生成されていない状態では、
`--script` で起動したスクリプトからグローバルクラスを参照できないため。

CI では 1) → 2) の順に必ず両方を走らせる。

---

## この時点で意図的にやっていないこと

- `AdvPlayer` などのランタイム、UI、演出ハンドラ（phase-02 以降）
- `.tres` の書き出し（`ResourceSaver` を呼ばない）
- 立ち絵テクスチャの実ロード（`load()` を呼ばない。パス文字列の解決まで）
- 進行状態・フラグ・既読集合（`AdvProgressState`、phase-05）
- HTTP 取得 / GAS / エディタ Dock / CLI インポータ（phase-07）
- `AdvScenarioBook.merge()`（章分割の運用が未決のため。仕様書 §13 U-07）
- InputMap の自動登録（実際に入力を使う phase-02 で行う）
- `missing_portrait_texture` の検査（インポート時のみ行う。phase-07）

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
  samples/sample_scenario.json
  tests/test_scenario_parse.gd
```

`AdvOptionStep` は**パースの中間表現**で、仕様書 §4 の表には無い。
JSON の 5 種の `type` を 1:1 で Resource に写し、畳み込み前後で
`AdvTopic.steps` の型を `Array[AdvStep]` に保つために置いている。
畳み込み後の `steps` に残ることはない。
