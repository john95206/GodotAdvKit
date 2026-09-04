# 引継ぎ資料: フェーズ01 foundation-and-data-model

- **実装者**: Claude（Codex ではない）
- **完了日**: 2026-09-03
- **配置先**: `C:\Users\kzr12\Root\MyProjects\AdvKit\`
- **検証環境**: Godot **4.5-stable**（876b29033）/ **4.7-stable**（5b4e0cb0f）/ **4.7.2-stable**（ed1daf0bf）の Linux headless。
  **いずれも `--import` → テスト実行 → `.tres` 往復まで通した**（結果は同一）。
  さらに **Windows 実機（4.7.2-stable）でもテスト 157 件全通過を確認済み**。採用は 4.7 系
- **テスト結果**: **157 件実行 / 成功 157 / 失敗 0**、終了コード 0
  （初回 145 件 + レビュー指摘の反映で 12 件追加。§7 を参照）

---

## 1. タスク別の結果

| ID | 状態 | 備考 |
|----|------|------|
| T-01 | 完了 | `plugin.cfg` + `adv_kit_plugin.gd`。`_enter_tree()` で `adv_kit/import/output_dir` を登録。`_exit_tree()` では消さない |
| T-02 | 完了 | `tests/test_scenario_parse.gd`（`extends SceneTree`）。`_assert_true` / `_assert_eq` / `_assert_issue_code` / `_assert_no_issue_code` |
| T-03 | 完了 | `AdvIssue` / `AdvParseResult` |
| T-04 | 完了 | Resource 9 種 + **`AdvOptionStep`**（後述の逸脱1） |
| T-05 | 完了 | `AdvPortraitSet.resolve()` の 4 段フォールバック。5 パターン網羅済み。`load()` 不使用、例外なし |
| T-06 | 完了 | `sample_scenario.json`。**4 topic / 26 生ステップ**（畳み込み後 20） |
| T-07 | 完了 | `AdvCondition`。自前トークナイザ＋再帰下降。`Expression` 不使用 |
| T-08 | 完了 | `AdvScenarioParser.parse()` / `parse_file()`。`FileAccess` + `JSON.parse_string` |
| T-09 | 完了 | 畳み込みと `step_index` の振り直し |
| T-10 | 完了 | `AdvEffectSchema`。§7 の 9 演出をすべて実装 |
| T-11 | 完了 | `AdvScenarioValidator`。サンプルは **ERROR 0 / WARNING 0** |
| T-12 | 完了 | `addons/adv_kit/README.md` |

### DoD

| 項目 | 結果 |
|------|------|
| `res://game/` に一切ファイルを作っていない | ✅ ディレクトリごと存在しない |
| `core/` `resources/` が `Node` / `Control` / `SceneTree` を参照していない | ✅ |
| 全 GDScript が静的型注釈付き。Variant は `params` と `options` のみ | ✅（`AdvEffectSchema` の内部スキーマ表だけ素の `Dictionary`。後述） |
| `topics` / `characters` が型付き辞書 | ✅ `Dictionary[StringName, AdvTopic]` / `[StringName, AdvCharacter]` |
| `Thread` / `WorkerThreadPool` 不使用 | ✅ |
| `load()` / `ResourceSaver.save()` 不使用 | ✅ アドオン内では未使用（R-01 検証は使い捨てスクリプトで行い、破棄した） |
| `--import` 後にテストが終了コード 0 | ✅ |
| エディタ警告なし | ✅ `--import` 時に GDScript の警告出力なし |
| `class_name` が全て `Adv` 接頭・衝突なし | ✅ 17 クラス登録 |

---

## 2. 特に報告してほしかった観点への回答

### 2.1 R-01: `@abstract` + `Array[AdvStep]` の `.tres` 往復 — **問題なし**

使い捨てスクリプト（`ResourceSaver.save()` → `ResourceLoader.load(CACHE_MODE_IGNORE)`）で
サンプルの Book を往復させ、`get_script().get_global_name()` で復元後の実型を確認した。

```
prologue steps = 7
  steps[0] uid=prologue_01:10 class=AdvLineStep   parallel=1
  steps[1] uid=prologue_01:30 class=AdvLineStep   parallel=0
  steps[2] uid=prologue_01:40 class=AdvEffectStep parallel=1
  steps[3] uid=prologue_01:60 class=AdvLineStep   parallel=0
  steps[4] uid=prologue_01:70 class=AdvEffectStep parallel=0
  steps[5] uid=prologue_01:80 class=AdvLineStep   parallel=0
  steps[6] uid=prologue_01:90 class=AdvChoiceStep parallel=0
parallel_effects[0] class = AdvEffectStep (is AdvEffectStep: true)
choice options = 2, options[0] = { "condition": "", "flag": "chose_go", "goto": &"route_a", "label": "奥へ進む" }
yuu.name_color = (1.0, 0.8235, 0.498, 1.0)
typed dict round-trip key type ok: true
```

**保たれたもの**: `Array[AdvStep]` 内の派生型、ネストした `parallel_effects` の派生型、
`options` の `Dictionary` とその中の `StringName`（`&"route_a"` として復元）、`Color`、
型付き辞書のキー型（`StringName`）、`uid` / `order` / `step_index`。

**結論: 「単一 `AdvStep` クラス + `type` フィールド」への設計変更は不要。**
`@abstract` は 4.5 で期待どおり動き、抽象クラスの直接 `new()` は禁止され、
エディタの Resource 作成メニューにも `AdvStep` は出ない。

### 2.2 R-07: `AdvStep` ⇄ `AdvEffectStep` の循環参照 — **循環は起きない。ただし別の副作用がある**

`parallel_effects` の宣言型を 3 通り試した。

| 宣言 | クラス解決 | テスト | 終了時のリーク |
|------|-----------|--------|--------------|
| `Array[AdvStep]`（仕様書どおり・**採用**） | 通る | 145/145 | `adv_step.gd` が 1 件 |
| `Array[AdvEffectStep]` | **通る**（循環エラーは出ない） | 145/145 | `adv_step.gd` + `adv_effect_step.gd` の 2 件 |
| `Array[Resource]` | 通る | 145/145 | **なし** |

**仕様書 §4.3 が心配していた「`class_name` のグローバル解決が循環する」は、Godot 4.5 では起きなかった。**
`Array[AdvEffectStep]` でも普通に解決され、`.tres` 往復も通る。

代わりに見つかったのが、**スクリプト型の自己参照によるエンジン終了時のリーク**。

```
WARNING: ObjectDB instances leaked at exit
Leaked instance: GDScript - Resource path: res://addons/adv_kit/resources/adv_step.gd
ERROR: 1 resources still in use at exit.
```

- 実害は今のところ**終了時のログだけ**。テストは通り、**終了コードは 0**。ゲーム実行中に何かが漏れるわけではない。
- ただし `--headless` の CI（phase-07 の CLI インポータ）で **stderr に ERROR 行が出続ける**。
  「エラー出力があったら失敗」という CI 判定を書くと引っかかる。**終了コードで判定すること。**
- `Array[Resource]` にすると消えるが、型安全を失うので採らなかった。

**提案（phase-02 で判断してほしい）**: R-07 の「解決できるなら型を絞る」に従うなら
`Array[AdvEffectStep]` へ寄せられる。リーク件数が 1→2 に増えるだけで質は変わらない。
ただし読み出し側の `as AdvEffectStep` が要らなくなる分、phase-03 の演出再生コードが素直になる。
**今回は仕様書どおり `Array[AdvStep]` のまま出した。**

### 2.3 `AdvParseResult` / `AdvIssue` を `RefCounted` にした是非 — **辞書より明確に良い**

- `issue.is_error()` / `result.is_ok()` / `errors()` / `warnings()` がメソッドで書けるので、
  呼び出し側に `if issue["severity"] == 0` のようなマジックナンバーが出ない。
- `Array[AdvIssue]` が型付き配列として通り、`for issue: AdvIssue in ...` で補完が効く。
- `to_line()` を型に持たせられたのが一番大きい。ログ整形が呼び出し側に散らない。
- 冗長になった箇所は**なし**。強いて言えば `AdvIssue.error(...)` の静的ファクトリが 3 引数固定で、
  location を組み立てる `"%s/options[%d]" % [...]` が呼び出し側に散る。
  phase-02 以降で location 組み立てヘルパを 1 つ足すと綺麗になる。

### 2.4 `--headless --script` の罠 — **`--import` の前置だけで足りた**

- `--import` を走らせずに `--script` すると `class_name` が解決できず即死する。
  **`.godot/global_script_class_cache.cfg` の生成が必須**という理解で正しい。
- **それ以外に必要な手順は無かった。** `--path` の明示も不要（プロジェクト直下で走らせるなら）。
- `--import` は `[editor_plugins] enabled` に登録されたプラグインを読むが、
  **EditorPlugin の `_enter_tree()` は走らない**。そのため `adv_kit/import/output_dir` は
  `--import` だけでは `project.godot` に書かれない。**エディタで一度開くと書かれる。**
  phase-07 の CLI が `ProjectSettings` からこの値を読む設計なら、
  **未登録時の既定値フォールバックを CLI 側に必ず持たせること。**
- テストスクリプトは `_initialize()` で全部やって `quit(code)` する形にした。
  `_process()` を使わないので 1 フレームも回らず、実行は 1 秒未満。

### 2.5 `condition` の文法（U-04 の判断材料） — **括弧の不在が最初に効く**

自前パーサを書いてみて、実際に「書けなくて困る」と感じた順に:

1. **括弧が無いこと。** `(a || b) && c` が書けない。`&&` が強いので、
   これを書きたければ `a && c || b && c` と展開するしかない。
   フラグが 3 つを超えると破綻する。**U-04 で最初に足すべきはこれ。**
2. **値の比較が無いこと。** 「好感度が 3 以上」のような数値フラグが一切書けない。
   今の `flags: Dictionary` は `bool` 前提。カウンタ型のフラグを入れるなら
   `>=` と整数リテラルが要る。**選択肢の分岐が「一度でも選んだか」だけで済むうちは不要。**
3. 到達済み判定（`visited(topic_id)` のような組み込み述語）。
   phase-05 で既読集合を持つので、そこから自然に欲しくなるはず。

逆に**不要だと感じたもの**: `!` の多重適用（`!!a`）、`xor`、真偽リテラル（`true` / `false`）。
今回はすべて構文エラーにしたが、誰も困らないと思う。

**実装メモ**: 構文解析と評価を 1 パスに統合し、構文木を作っていない。
`validate()` は空の `flags` で評価して結果を捨てるだけ。仕様が単純なうちはこれで足りる。
括弧や比較演算子を足すなら、そのタイミングで木を作る形に書き直すのが素直。

### 2.6 `AdvKitSettings` のフィールド数 — **`@export_group` で足りる。分割は不要**

全 18 フィールドを 7 グループ（汎用演出 / ホップ / 表示 / オート / スキップ / バックログ /
ボイス / 入力アクション）に分けた。インスペクタで見て破綻していない。

- **分割すべきと感じなかった理由**: これらは全部「1 本のゲームで 1 回決めて、以後触らない値」で、
  ライフサイクルが同じ。分けると `AdvPlayer` の `@export` が 3 本になり、
  ゲーム側が `.tres` を 3 つ管理することになる。**利得より手間が勝つ。**
- ただし**入力アクション 4 つだけは性質が違う**（値ではなく InputMap への参照名）。
  phase-02 で InputMap の自動登録を書くとき、ここだけ別 Resource に切りたくなるかもしれない。
  そのときに判断すればよい。

### 2.7 `params` の `key=value;` 記法（§6.2）— **今のところ破綻していない**

- `AdvEffectSchema.parse_param_string()` を実装した（**GAS が分解済みの JSON を返す場合は通らない経路**。
  手書き JSON とスプレッドシート直読みのため）。
- **値に `;` や `=` を含めたい演出は §7 の 9 種には出てこなかった。** `stream=res://...` のパスにも出ない。
- 破綻しうるのは **BBCode を演出パラメータに渡したくなったとき**（`text=[color=#f00]!![/color]` など）。
  今は `text` が `line` 行の専用列なので当たらない。「演出で任意テキストを出す」を足すと当たる。
- **`register_effect()` による拡張との相性**: 現状 `_table` は `static var` の遅延初期化で、
  ゲーム側から足す口が無い。**phase-03 で `AdvEffectSchema.register(effect_id, specs)` を足す必要がある。**
  今の設計のまま静的辞書に追記できるので、破綻はしない。
  未知の `effect_id` は `unknown_effect_id` の **WARNING** で通し、**値を文字列のまま全部保持する**ので、
  登録前に検証を走らせても情報は落ちない。ここは設計どおり効いている。

### 2.8 JSON スキーマ（§6.3）で冗長・不足だと感じた箇所（phase-07 の列設計向け）

- **`sync` の既定が `blocking` なのに、実運用では `parallel` の方が多くなりそう。**
  サンプルを書いていて `"sync": "blocking"` を毎行書くのが冗長だった。
  ただし**既定を反転させると「書き忘れると勝手に並列になる」**ので、今のままが安全。
  スプレッドシート側でセルの既定値を `blocking` にしておく運用で吸収したい。
- **`auto_advance` だけが JSON で `bool`、他の演出関連は文字列**という不揃い。
  パーサは `true` / `"TRUE"` / `"1"` のどれでも受けるようにしたが、**GAS 側で `bool` に正規化するのが望ましい**。
- **`characters` の `poses` × `expressions` の総当たりでパスを組む**仕様は、
  存在しない組み合わせのパスまで `texture_paths` に入る。
  今は `load()` しないので実害ゼロだが、**phase-07 の `missing_portrait_texture` 検査が
  「総当たり全部」に対して走ると警告まみれになる。** 実際に参照されている組み合わせだけを
  検査対象にするか、シート側に「存在する組み合わせ」列を持たせるかを phase-07 で決める必要がある。
- **`schema_version` と `content_hash` を `AdvScenarioBook` が保持していない**（仕様書 §4.5 に無いため）。
  phase-07 で「変更なしをスキップ」するには `.tres` 側に `content_hash` が要る。
  **§4.5 に `schema_version: int` と `content_hash: String` を足すことを提案する。**
- `topics[].steps[]` に `topic_id` が無い（親に持たせている）のは JSON としては正しいが、
  **スプレッドシートは flat なので GAS がグループ化を担う**。この非対称は仕様書に明記されていない。

---

## 3. 仕様書からの逸脱・追加（**要判断**）

### 逸脱1: `AdvOptionStep` を追加した（`resources/adv_option_step.gd`）

- **理由**: JSON の `type` は 5 種あるのに、仕様書 §4 の Resource 表には `option` に対応する型が無い。
  畳み込み前の `AdvTopic.steps` を `Array[AdvStep]` に保ったまま option 行を保持する手段が要る。
- **代替案と却下理由**: 中間表現を `Array[Variant]` や `Array[Dictionary]` にすると
  DoD の「Variant は `params` と `options` のみ」に反する。
  `AdvChoiceStep` を流用する案は「choice 行」と「option 行」の区別がつかなくなる。
- **性質**: 純粋な中間表現。**畳み込み後の `steps` に残ることはない**（残る場合は `dangling_option` で ERROR）。
- **提案**: 仕様書 §4.3 に「パース中間表現」として 1 行足す。

### 逸脱2: 検証コード `invalid_json` を追加した

- **理由**: 仕様書 §4.9 の表には **JSON そのものが壊れている場合のコードが無い**。
  ファイルが読めない / ルートが辞書でない / 配列要素が辞書でない / `id` が空 / `name_color` が
  `#rrggbb` でない、といったケースを黙って捨てるのは危険だと判断した。
- **提案**: §4.9 に `invalid_json` を **ERROR**（`name_color` の解釈失敗のみ WARNING）として足す。

### 逸脱3: `invalid_condition` の検出をバリデータ側に置いた

- 実装計画書 §5 の担当表は `invalid_condition` を T-07（条件式）に割り当てているが、
  **`AdvCondition` はモジュールであって検出の起点ではない**ため、
  実際に呼ぶのは `AdvScenarioValidator` にした（`AdvScenarioParser` からは呼ばない）。
- **影響**: `parse()` 単独では条件式の構文エラーが出ない。`validate()` を必ず併せて呼ぶ必要がある。
  README の使用例はその順で書いてある。

### 逸脱4: `AdvEffectSchema` の内部スキーマ表だけ素の `Dictionary`

- `Dictionary[StringName, ParamSpec]`（インナークラスを値型にした型付き辞書）と
  `Array[ParamSpec]`（インナークラスの型付き配列）は、エンジンの解決差が読めなかったため使わなかった。
- **`@export` フィールドではない静的な内部表**なので、DoD の意図には反していないと判断した。
- 外向きの API（`convert_params` の戻り値、`p_issues`）はすべて型付き。

### その他の小さな判断

- **`duplicate_step_order` の行は捨てる。** `uid` が衝突したまま Book に入れると
  既読管理が静かに壊れるため、ERROR を出したうえでその行を落とす。仕様書に明記が無い部分。
- **`unknown_step_type` の行も捨てて残りを続行する**（計画書どおり）。
- **`_check_goto` は存在しない `goto` 先も「参照済み」として数える。**
  存在しない topic を指す `goto` があっても、到達性の警告が二重に出ないようにするため。

---

## 4. 実装していないもの（スコープどおり）

`ui/` / `runtime/` / `effects/` / `import/` / `editor/` の各ディレクトリは**作っていない**。
`AdvProgressState` / `AdvBacklog` / `AdvScenarioBook.merge()` / InputMap 自動登録 /
`.tres` 書き出し / 立ち絵の実ロード / `missing_portrait_texture` も未実装。

**「UI が無いとテストできない」と感じた場面は一度も無かった。** `--headless` だけで
パーサ・畳み込み・検証・条件式・演出スキーマの全経路をテストできている。
phase-01 をデータとロジックだけに絞った判断は正しかった。

---

## 5. テストの走らせ方

```bash
cd C:\Users\kzr12\Root\MyProjects\AdvKit
godot --headless --import
godot --headless --script res://addons/adv_kit/tests/test_scenario_parse.gd
```

`--import` の前置は必須。失敗が 1 件でもあれば終了コード 1。
終了時の `ObjectDB instances leaked` / `resources still in use` は **2.2 で説明した既知のもの**で、
終了コードには影響しない。

---

## 6. phase-02 に申し送ること

1. **`parallel_effects` の宣言型を `Array[AdvEffectStep]` に絞るか**を決める（2.2）。
2. **InputMap の自動登録**を `adv_kit_plugin.gd` に足す（仕様書 §4.6。今回スコープ外）。
3. **`AdvScenarioBook` に `schema_version` / `content_hash` を足すか**を決める（2.8）。
4. `AdvIssue` の location 組み立てヘルパを足すと、検証コードの見通しが良くなる（2.3）。
5. `AdvPlayer` は `AdvOptionStep` を**見ない**（畳み込み後には存在しない）。`AdvChoiceStep.options` を読む。
6. `condition` の括弧サポート（U-04）は phase-05 の着手前に判断する（2.5）。

---

## 7. 追記（2026-09-03・レビュー指摘の反映）

**指摘**: 「`parallel_effects` に同じエフェクトが複数格納されていた場合、想定しない動きにならないか」

**結論: なる。しかも「同じ effect_id」より範囲が広い問題だった。**

同時に走る演出が**同じものを書き換える**と、2 つの `Tween` が同じプロパティを取り合い、
先に終わった方が終了時に初期値へ戻すことで、もう片方の途中経過が巻き戻る。
`shake` が 2 本、`fade_out` と `fade_in`、同じキャラの `show_portrait` と `hide_portrait`
（こちらはノードの解放を伴うので、解放済みノードへのアクセスにもなりうる）、
`play_bgm` と `stop_bgm` が該当する。

一方、**同じ effect_id でも問題ない組み合わせがある**。`play_se` は §7 が
「ワンショット。多重再生可」と定めているので、何本並べても正しい。
つまり判定基準は effect_id の重複ではなく、**書き換える対象が重なるかどうか**。

### 入れた対応

1. **仕様書 §7 に「排他ターゲット」の表を追加**。各演出が占有する対象を宣言する
   （`shake` → `shake_root_position`、`move_portrait` → `portrait_position:{speaker}` など）。
   `play_se` は排他ターゲットを持たない。`hide_portrait` は解放を伴うので、そのキャラの全ターゲットを占有する。
2. **仕様書 §4.9 に `conflicting_parallel_effects`（ERROR）を追加。**
3. **`AdvEffectSchema.exclusive_targets(effect_id, params)` を実装。**
4. **`AdvScenarioValidator` に衝突検査を実装。**
   検査対象は `parallel_effects` どうしに加え、**ホストのステップ自身が BLOCKING 演出ならそれも含む**
   （PARALLEL は直前のステップの開始と同時に走るため、両者は同時に動く）。
5. **テストを 12 件追加**（衝突する 5 パターン / 衝突しない 5 パターン / ホストが BLOCKING の 2 パターン）。
   **145 件 → 157 件。全通過・終了コード 0。** サンプルシナリオは引き続き issue 0 件。

### 判定の効き方

| 組み合わせ | 判定 | 理由 |
|-----------|------|------|
| `shake` ×2 | **ERROR** | どちらも `shake_root_position` |
| `fade_out` + `fade_in` | **ERROR** | どちらも `fade_layer_alpha` |
| `play_bgm` + `stop_bgm` | **ERROR** | どちらも `bgm_channel` |
| 同じキャラの `show_portrait` + `hide_portrait` | **ERROR** | `portrait_alpha:<speaker>` |
| 同じキャラの `move_portrait` ×2 | **ERROR** | `portrait_position:<speaker>` |
| `play_se` ×2 | OK | 排他ターゲットなし（多重再生可） |
| 同じキャラの `show_portrait` + `move_portrait` | OK | alpha と位置で対象が違う |
| 別キャラの `move_portrait` ×2 | OK | ターゲットに speaker が入る |
| BLOCKING `shake` + PARALLEL `shake` | **ERROR** | ホストも同時に走る側に数える |
| 未知の effect_id ×2 | OK | 拡張演出は自分でターゲットを宣言する（phase-03） |

### 残る穴（phase-03 で対応）

- **ステップをまたいだ重なり**は検証で防げない。
  ステップ N の演出が終わる前にステップ N+1 の演出が始まるケース（`auto_advance` やスキップ中）。
- **ゲーム側が `register_effect()` で足した拡張演出**は、いま排他ターゲットを宣言する口が無い。

この 2 つに備えて、**ランタイム規約を仕様書 §7 に追加した**:
**演出ハンドラは自分の排他ターゲットに対する実行中の `Tween` を `kill()` してから開始する。**
これで未定義ではなく「後から始まった方が勝つ」という決まった挙動になる。
`register_effect()` にターゲット宣言の引数を足すのは phase-03 の作業。
