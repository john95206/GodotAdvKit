# 実装計画書: フェーズ01 foundation-and-data-model

## 1. フェーズ概要

- **ゴール**: `res://addons/adv_kit/` としてアドオンの骨格が立ち、シナリオを表す `Resource` 群と「JSON → Resource」のパーサ・バリデータが揃う。`--headless` でサンプル JSON を読み込んで検証結果を出力できる状態にする。
- **仕様書の該当箇所**: `docs/spec/adv-kit-spec.md` の §3（ディレクトリ構造）、§4（データモデル）、§4.7（condition 文法）、§6.3（JSON スキーマ）
- **前提フェーズ**: なし（初回）

このフェーズには **UI も進行制御も含まない**。データの形とその検証だけを固める。ここが揺れると後続フェーズが全部揺れるため、最初に単独で確定させる。

## 2. スコープ

### 対象

- `addons/adv_kit/` のアドオン骨格（`plugin.cfg` + `EditorPlugin`）
- `resources/` 配下の全 `Resource` クラス定義（仕様書 §4 の全フィールド）
- `core/adv_issue.gd`, `core/adv_parse_result.gd` — 検証結果を表す型
- `core/adv_condition.gd` — `condition` 文字列の**構文解析と評価**（仕様書 §4.7）
- `core/adv_effect_schema.gd` — 演出パラメータの名前・型・既定値の表（仕様書 §7）と、文字列 → 型付き値の変換
- `core/adv_scenario_parser.gd` — `Dictionary`（パース済み JSON）→ `AdvScenarioBook`
- `core/adv_scenario_validator.gd` — 参照整合性と必須項目の検証
- `resources/adv_kit_settings.gd` — 設定 Resource（**定義と既定値のみ。この時点では誰も読まない**）
- `samples/sample_scenario.json` — 仕様書 §6.3 のスキーマを満たすサンプル
- `tests/test_scenario_parse.gd` — `--headless` で走る検証スクリプト
- `addons/adv_kit/README.md` — このフェーズ時点の API とテスト手順

> `condition` の**評価器**を phase-01 に含める理由: 構文解析と評価は同じ木を歩く処理で、分けると同じパーサを2回書くことになる。フラグの供給元（`AdvProgressState`）は phase-05 だが、`AdvCondition.evaluate(expr, flags: Dictionary) -> bool` は辞書を受け取る純関数にできるため、ここで完結する。

### 対象外（今回やらない）

- **UI 一切**（`ui/` 配下を作らない）
- **`AdvPlayer` などのランタイム**（`runtime/` 配下を作らない）
- **演出ハンドラ**（`effects/` を作らない）
- **HTTP 取得 / GAS / エディタ Dock / CLI インポータ**（phase-07。`import/`, `editor/` を作らない）
- **`.tres` のファイル書き出し**（`ResourceSaver` は呼ばない。パースしてメモリ上に組むところまで）
- **立ち絵テクスチャの実ロード**（パス文字列の保持と解決まで。`load()` しない）
- **`AdvProgressState`**（進行位置・フラグ・既読集合の保持は phase-05）
- **`AdvBacklog` / `AdvBacklogEntry`**（phase-06）
- **InputMap の自動登録**（仕様書 §4.6。実際に入力を使う phase-02 で行う）
- **`AdvScenarioBook.merge()`**（U-07 保留のため実装しない。仕様書 §4.5）
- **UI の基底クラス**（`AdvMessageWindow` などは phase-02 以降。`ui/` を作らない）

## 3. 影響範囲

- **アドオン**: `res://addons/adv_kit/` を新規作成。**`res://game/` 配下には一切触れない**
- **ディレクトリ**: `addons/adv_kit/{core,resources,samples,tests}` を作成
- **区分**: 仕様書 §2 の「データ」と「ロジック」のみ。**「実行」「表示」には触れない**
- **`core/` と `resources/` は `Node` / `SceneTree` / `Control` を一切参照しない**

## 4. 新規に定義する契約

### Resource（`addons/adv_kit/resources/`）

| クラス | 継承 | 責務 |
|--------|------|------|
| `AdvCharacter` | `Resource` | 話者の同一性と表示情報。`portrait_set` は null 可 |
| `AdvPortraitSet` | `Resource` | 立ち絵**パス文字列**の表引きと解決順（仕様書 §4.2） |
| `AdvStep` | `@abstract Resource` | 全ステップの抽象基底。`order: int` / `uid: StringName` / `step_index: int` / `parallel_effects: Array[AdvStep]` を持つ（**`Array[AdvEffectStep]` と書かない**。循環参照になる。仕様書 §4.3） |
| `AdvLineStep` | `AdvStep` | 立ち絵情報付きテキスト。`speaker_id` は `AdvCharacter.id` への参照 |
| `AdvEffectStep` | `AdvStep` | 演出。`sync_mode: SyncMode`、`auto_advance: bool` |
| `AdvChoiceStep` | `AdvStep` | 選択肢 |
| `AdvJumpStep` | `AdvStep` | 話題遷移 |
| `AdvTopic` | `Resource` | ステップ列と `tags` |
| `AdvScenarioBook` | `Resource` | `topics` / `characters` の集約。**`merge()` は実装しない**（仕様書 §4.5 / U-07 保留） |
| `AdvKitSettings` | `Resource` | 仕様書 §4.6 の全フィールド（汎用演出・プレイ支援・入力アクション）。既定値まで入れる |

全フィールドに `@export` と**静的型注釈**を付ける。`Array` は `Array[AdvStep]` のように要素型付きで宣言する。

### ロジック（`addons/adv_kit/core/`）

```gdscript
class_name AdvIssue extends RefCounted
enum Severity { ERROR, WARNING }
var severity: Severity
var code: StringName      # "unknown_speaker" など
var location: String      # "topics/prologue_01/steps[3]" 形式
var message: String
static func error(code: StringName, location: String, message: String) -> AdvIssue
static func warning(code: StringName, location: String, message: String) -> AdvIssue
func to_line() -> String  # ログ出力用の1行表現
```

```gdscript
class_name AdvParseResult extends RefCounted
var book: AdvScenarioBook
var issues: Array[AdvIssue]
func is_ok() -> bool          # ERROR が 0 件なら true
func errors() -> Array[AdvIssue]
func warnings() -> Array[AdvIssue]
```

```gdscript
class_name AdvCondition extends RefCounted
# 構文検証のみ。問題があれば issues に積む
static func validate(expr: String, location: String) -> Array[AdvIssue]
# 評価。未定義フラグは false 扱い。構文エラー時は false を返し push_warning
static func evaluate(expr: String, flags: Dictionary) -> bool
```

```gdscript
class_name AdvScenarioParser extends RefCounted
static func parse(json_data: Dictionary) -> AdvParseResult
```

```gdscript
class_name AdvScenarioValidator extends RefCounted
# 単一 Book 前提。章分割（複数 Book のマージ）は U-07 保留のため実装しない
static func validate(book: AdvScenarioBook) -> Array[AdvIssue]
```

**パーサは例外を投げない。** 問題は必ず `AdvIssue` として返す。

## 5. タスク分解

| ID | タスク | 受け入れ条件 | 依存 |
|----|--------|--------------|------|
| T-01 | `addons/adv_kit/plugin.cfg` と `adv_kit_plugin.gd` を作成する。`_enter_tree()` で `ProjectSettings` に `adv_kit/import/output_dir`（既定 `res://game/resources/adv/scenario/`）を登録する。`_exit_tree()` では設定を消さない | エディタのプラグイン一覧で有効／無効を切り替えてもエラーが出ない。有効化後、プロジェクト設定に `adv_kit/import/output_dir` が現れる | - |
| T-02 | `tests/test_scenario_parse.gd`（`extends SceneTree`）のハーネス骨組みを作る。アサーション関数（`_assert_eq` / `_assert_true` / `_assert_issue_code`）、結果集計、終了コード制御（失敗が1件でもあれば非0）まで。**テスト本体は空でよい** | `godot --headless --import` を1回走らせた後、`godot --headless --script res://addons/adv_kit/tests/test_scenario_parse.gd` が終了コード 0 で走り、「0 件実行」と出力する | - |
| T-03 | `core/adv_issue.gd` と `core/adv_parse_result.gd` を実装する | `AdvIssue.error(...)` / `.warning(...)` で生成でき、`AdvParseResult.is_ok()` が ERROR 有無で正しく分岐する。T-02 のハーネスからテストが通る | T-02 |
| T-04 | `resources/` の全 Resource クラスを定義する。`AdvStep` は `@abstract`、`class_name` は `Adv` 接頭、ファイル名は `snake_case` | 全クラスが `class_name` で参照できる。**具象クラス**はエディタの Resource 作成メニューから生成できる（`AdvStep` は抽象なので対象外）。全 `@export` に型注釈がある | T-01 |
| T-05 | `AdvPortraitSet.resolve(pose: StringName, expression: StringName) -> String` を実装する。解決順は仕様書 §4.2 の 4 段の探索。全滅時は**空文字を返す** | 5 パターン（4 段の各段でヒット／全滅）を網羅するテストが通る。**例外を投げない**。`load()` を呼ばない | T-03, T-04 |
| T-06 | `samples/sample_scenario.json` を作成する。**3 topic 以上・20 ステップ以上**（畳み込み前）。全ステップに `order` を **10 刻み**で振る。全 5 種の `type`（`line` / `effect` / `choice` / `option` / `jump`）、`sync` の `parallel` / `blocking` 両方、`auto_advance` の true / false、**`blocking` 演出の直後に置いた `parallel` 演出**（畳み込み先が line 以外のケース）、立ち絵無しキャラ、地の文（speaker 空）、**`voice` 指定ありの行となしの行の両方**、条件付き option、`goto` の連鎖、先頭 topic に `entry` タグを含める。**`auto_advance=true` は `blocking` 行にのみ付ける**（`parallel` に付けると `invalid_auto_advance` WARNING になる） | 仕様書 §6.3 のスキーマに適合し、`steps` が flat（`options` のネストを含まない）で、全ステップに一意な `order` がある。**なお「`validate()` が ERROR 0 件・WARNING 0 件」の判定は T-11 完了時点で行う**（validator がまだ無いため、この時点では判定できない） | - |
| T-07 | `core/adv_condition.gd` を実装する。文法は仕様書 §4.7（`!` / `&&` / `||`、`&&` 優先、括弧なし、識別子は `[A-Za-z_][A-Za-z0-9_]*`）。**`Expression` クラスを使わない** | `a && b \|\| c` が `(a && b) \|\| c` として評価される。不正構文（`a & b`、`a == 1`、`&& a`、`a &&`、`1abc`）が ERROR issue になる。空文字は「常に真」で issue なし。**未定義フラグの検出は行わない** | T-03 |
| T-08 | `AdvScenarioParser.parse()` を実装する。JSON の `order` を `AdvStep.order` に写し、**安定ステップID `uid = "<topic_id>:<order>"` を生成する**（仕様書 §4.3）。文字列 → 型の変換をここで行う: `goto` / `speaker` / topic・character の id は `StringName`、`name_color` の `#rrggbb` は `Color`。未知の `type` は `unknown_step_type` の ERROR issue にして**そのステップを飛ばし、残りのパースは続行する**。この時点では畳み込みを行わない | `sample_scenario.json` を読んで `is_ok() == true` の book が返る。topic 数・character 数がサンプルと一致し、**各 topic の steps 数が JSON の生ステップ数と一致する**（畳み込み前）。全ステップの `uid` が `"<topic_id>:<order>"` になっている。`name_color` が `Color` に、`goto` と各 id が `StringName` になっている。**JSON の読み込みは `FileAccess.get_file_as_string()` + `JSON.parse_string()` で行う**（`load()` は DoD で禁止） | T-04, T-06 |
| T-09 | `parse()` に**畳み込み**を追加する（仕様書 §4.8）。`sync=parallel` の `AdvEffectStep` を直前のステップの `parallel_effects` へ、`type=option` を直前の `AdvChoiceStep.options` へ移し、`AdvTopic.steps` から除去する。除去後に全ステップの `step_index` を**0 起点で振り直す**（`uid` と `order` は振り直さない） | 仕様書 §4.8 の記述例と同じ入力が **2 ステップ**（line + choice）になり、SE と揺れが line の `parallel_effects`、2 選択肢が choice の `options` に入る。**畳み込み先は `AdvLineStep` に限らない**（blocking effect や choice の直後の parallel も畳み込まれる）。topic の**先頭**が parallel の場合のみ `dangling_parallel`、直前が choice でない option は `dangling_option` の ERROR issue | T-08 |
| T-10 | `core/adv_effect_schema.gd` を実装する。仕様書 §7 の表を静的な辞書として持ち、`params` の文字列値を `float` / `bool` / `String` / `Color` へ変換する。必須欠落と未知キーを issue にする | `strength=8` が `float` の 8.0 に、`loop=true` が `bool` に、`color=#112233` が `Color` になる。必須欠落が `missing_effect_param` の ERROR、スキーマ外のキーが `unknown_effect_param` の WARNING になり、**未知キーの値は捨てずに文字列のまま保持される** | T-03 |
| T-11 | `AdvScenarioValidator.validate(book)` を実装する。検証コードは**仕様書 §4.9 の表**に従う（下記の担当表も参照）。**単一 Book 前提**（章分割は U-07 保留のため `is_complete` のような引数を設けない） | §4.9 の全 code が該当する不正データで検出される（`missing_portrait_texture` を除く）。**`sample_scenario.json` では issue が 0 件**（T-06 の受け入れ判定をここで行う） | T-07, T-09, T-10 |
| T-12 | `addons/adv_kit/README.md` に、このフェーズ時点で使える API（`AdvScenarioParser.parse` / `AdvScenarioValidator.validate` / `AdvCondition` / `AdvEffectSchema`）、JSON スキーマの要約、テストの走らせ方（`--import` を先に走らせることを含む）を書く | 仕様書を読まなくても、パーサの入出力とテスト手順が分かる | T-11 |

### T-11 の検証項目

**検証コードの定義は仕様書 §4.9 が正。** ここでは重複させず、phase-01 で**どのタスクが検出責任を持つか**だけを示す。

| 検出タスク | 担当する code |
|-----------|--------------|
| T-07（条件式） | `invalid_condition` |
| T-08（パース） | `unknown_step_type`, `missing_step_order`, `duplicate_step_order`, `duplicate_topic_id`, `duplicate_character_id` |
| T-09（畳み込み） | `dangling_parallel`, `dangling_option` |
| T-10（演出スキーマ） | `missing_effect_param`, `invalid_effect_param`, `unknown_effect_id`, `unknown_effect_param` |
| T-11（バリデータ） | `unknown_speaker`, `unknown_topic`, `unknown_slot`, `empty_choice`, `empty_topic`, `unreachable_topic`, `invalid_auto_advance` |

`missing_portrait_texture`（§4.9）は**このフェーズの対象外**（インポート時のみ検査するもので、phase-07 で実装する）。

仕様書 §4.9 の表と実装が食い違った場合、**仕様書が正**。実装を合わせるか、合わせられない理由を handover に書くこと。

## 6. 完了定義（DoD）

- [ ] T-01〜T-12 の全受け入れ条件を満たす
- [ ] `res://game/` 配下に一切ファイルを作っていない
- [ ] `core/` および `resources/` 配下のスクリプトが `Node` / `Control` / `SceneTree` を参照していない（`tests/` を除く）
- [ ] 全 GDScript が静的型注釈付き。Variant 値を許容するのは `AdvEffectStep.params` と `AdvChoiceStep.options` の2つのみ（仕様上そうなっている）
- [ ] `AdvScenarioBook.topics` / `characters` は**型付き辞書** `Dictionary[StringName, AdvTopic]` / `Dictionary[StringName, AdvCharacter]` で宣言する（エンジン帯 4.5+ で利用可）
- [ ] `Thread` / `WorkerThreadPool` を使っていない
- [ ] `load()` / `ResourceSaver.save()` をどこでも呼んでいない
- [ ] `godot --headless --import` の後、`godot --headless --script res://addons/adv_kit/tests/test_scenario_parse.gd` が終了コード 0 で通る
- [ ] エディタで警告が出ていない（特に `SHADOWED_VARIABLE_BASE_CLASS`、未使用変数、型の暗黙変換）
- [ ] `class_name` が全て `Adv` 接頭で、衝突がない

## 7. Codex への指示

- 実装完了後、必ず `docs/guidelines/codex-handover.md` のフォーマットに従って `docs/plans/phase-01-foundation-and-data-model/handover.md` を作成すること。全セクションを埋め、上記タスクIDに対応づけて報告する。
- **特に報告してほしい観点**:
  - **`@abstract` を付けた `AdvStep` の実際の挙動**（Godot 4.5+）。`Array[AdvStep]` に派生型を入れて `.tres` にシリアライズしたときの往復（保存→読み込み）で、派生型が保たれるか。**ここが崩れると phase-02 以降の全設計が変わる**ので、確認方法と結果を具体的に書く。
  - **`AdvParseResult` / `AdvIssue` を `RefCounted` にしたことの是非**。呼び出し側の記述が辞書より良くなったか、逆に冗長になったか。
  - JSON スキーマ（仕様書 §6.3）で**表現しきれなかった、または冗長だと感じた箇所**。phase-07 でスプレッドシート列設計に反映するため、気づいた時点で書く。
  - `--headless --script` でのテスト実行で踏んだ罠。特に `class_name` のグローバル解決（`.godot/global_script_class_cache.cfg`）まわりで、`--import` を先に走らせる以外に必要だった手順があれば全部書く。
  - `condition` の自前パーサを書いてみて、仕様書 §4.7 の文法に**不足を感じた具体例**（U-04 の判断材料にする）。
  - **`AdvStep` ⇄ `AdvEffectStep` の循環参照（R-07）**。`parallel_effects` をどの型で宣言したか、`Array[AdvEffectStep]` を試したらどうなったか、エラーメッセージも含めて具体的に書く。R-01 と並ぶ最優先の確認事項。
  - **`AdvKitSettings` のフィールド数**（仕様書 §4.6 で汎用演出＋プレイ支援＋入力アクションの3群になった）。1つの Resource に詰め込むのが妥当か、`@export_group` で足りるか、分割すべきと感じたか。
  - **`params` の `key=value;` 記法（仕様書 §6.2）で表現しにくかったケース**。値に `;` や `=` を含めたい演出が出てきたか。`AdvEffectSchema` を静的な辞書で持つ方式が、phase-03 で `register_effect()` による拡張演出を受け入れるときに破綻しないか。
- **禁止事項**: スコープ §2「対象外」の項目に着手しないこと。特に `AdvPlayer` を「あった方が動かしやすいから」という理由で作らない。UI が無いとテストできないと感じたら、それは設計が間違っているサインなので実装せず handover に書く。

## 8. リスク・不確実性

| ID | 内容 | 差分分析での確認観点 |
|----|------|---------------------|
| R-01 | `@abstract` 基底 + `Array[AdvStep]` のシリアライズ往復が想定通りか未検証。崩れる場合は「単一の `AdvStep` クラス + `type` フィールド」への設計変更が必要 | 最優先。ここだけで phase-02 以降の書き方が変わる |
| R-02 | `--headless` でのグローバルクラス解決が CI で安定するか。`--import` の前置で足りるか | phase-07 の CLI インポータが同じ土俵に乗るため、ここで潰しておく |
| R-03 | `condition` の文法（括弧なし、`&&` 優先）が実運用で足りるか未検証（仕様書 U-04） | phase-05 着手前に再検討 |
| R-04 | サンプル JSON を Claude が設計したため、実際のスプレッドシート運用で書きにくい形になっている可能性がある | phase-07 でスプレッドシート列設計を作る際に突き合わせる |
| R-05 | ~~`step_index` の永続化によるズレ~~ → **解消済み**。安定ステップID `uid`（`topic_id:order`）を導入し、永続化は `uid` で行うことにした（仕様書 §4.3 / §9.1） | `uid` が全ステップで一意に振られているかを T-08 で確認する |
| R-07 | **`AdvStep`（基底）が `AdvEffectStep`（派生）を型注釈で参照すると、`class_name` の解決が循環する**可能性がある。仕様書 §4.3 では `parallel_effects: Array[AdvStep]` と宣言して回避する方針にしたが、この回避が効くか、そもそも循環が起きるかは未検証 | R-01 と同格の最優先。もし `Array[AdvEffectStep]` でも問題なく解決されるなら、型を絞れるので仕様書を戻す。逆に `Array[AdvStep]` でも解決できないなら、`parallel_effects` を `AdvStep` から外して `AdvTopic` 側に `uid -> Array` の辞書として持つ設計へ変更する |
| R-06 | `uid` は `order` に依存するため、**シート上で既存行の `order` を書き換えると既読データが壊れる**。これは運用規約でしか守れず、機械的に防げない | 実運用で `order` を触ってしまう頻度を見て、必要なら phase-07 のインポータで「既存 `.tres` と `uid` を突き合わせて消失を警告する」仕組みを足す |
