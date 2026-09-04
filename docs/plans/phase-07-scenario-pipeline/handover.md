# 引継ぎ資料: フェーズ07 scenario-pipeline

- **対象計画書**: `ADV Kit phase-07 実装計画書.md`
- **実装者**: Claude
- **完了日**: 2026-09-03
- **配置先**: `C:\Users\kzr12\Root\MyProjects\AdvKit\`
- **検証環境**: Godot **4.7-stable**（5b4e0cb0f）Linux headless と
  **4.7.2-stable**（ed1daf0bf）**Windows 実機**。**結果は同一**（2026-09-03 確認）
- **テスト結果**（すべて終了コード 0 / `.godot` を消してからの通し）:

  | テスト | 件数 | 結果 |
  |--------|------|------|
  | `test_scenario_parse.gd` | 157 | 全通過 |
  | `test_playback.gd` | 32 | 全通過 |
  | `test_effects.gd` | **93** | 全通過（U-08 の 5 件を追加） |
  | `test_auto_direction.gd` | 24 | 全通過 |
  | `test_progress.gd` | 50 | 全通過 |
  | `test_play_assist.gd` | 44 | 全通過 |
  | **`test_import.gd`（新規）** | **113** | **全通過**（U-05 の 13 件を含む） |

- **新規コード**: `import/` 4 ファイル + `editor/` 2 ファイル（約 750 行）＋ テスト 470 行
- 全 `.gd` の `--check-only` で**警告 0 件**

---

## 1. 実装済み内容（タスクID対応）

| ID | 状態 | 実装した内容 / 変更したファイル |
|----|------|--------------------------------|
| T-01 | 完了 | `resources/adv_scenario_book.gd` に `schema_version: int` / `content_hash: String` と `has_same_content()` |
| T-02 | 完了 | `core/adv_scenario_parser.gd` の `parse()` が両方を Book へ写す。`_read_int()` を追加。**欠落は 0 / 空文字にして issue は立てない** |
| T-03 | 完了 | `import/adv_import_result.gd`。**`AdvParseResult` を継承**したので `is_ok` / `errors` / `warnings` / `to_lines` はそのまま |
| T-04 | 完了 | `AdvScenarioImporter.resolve_output_dir()` / `normalize_dir()`。ProjectSettings 無しなら既定値（R-02） |
| T-05 | 完了 | `check_portrait_textures()`。参照された組み合わせのみ・`portrait_set` 無しは対象外・**解決結果で重複排除** |
| T-06 | 完了 | `import_from_text()`。パース → 検証 → 立ち絵検査 → ERROR なら中断 → hash 一致なら skip → 書き出し |
| T-07 | 完了 | `_write_book()` / `_collect_stale()`。`take_over_path()` → `ResourceSaver.save()`。消えた id は WARNING のみ |
| T-08 | 完了 | `fetch_json_text()` / `import_from_url()`。`HTTPRequest` を一時生成し完了後に解放。**1 フレーム待ちが必須**（下記 R-20） |
| T-09 | 完了 | `parse_cli_args()` / `cli_usage()`。static なのでテストから直接叩ける |
| T-10 | 完了 | `import/adv_import_cli.gd`。終了コード 0 / 1 / 2。`ADV_KIT_SCENARIO_URL` フォールバック。**URL をログに出さない** |
| T-11 | 完了 | `editor/adv_import_dock.gd` / `.tscn`。入力値は `user://adv_kit_import.cfg` へ |
| T-12 | 完了 | `adv_kit_plugin.gd` に `_add_import_dock()` と `_exit_tree()` での撤去 |
| T-13 | 完了 | `import/gas/adv_scenario_export.gs` と `import/gas/README.md` |
| T-14 | 完了 | `tests/test_import.gd`（113 アサーション） |
| T-15 | 完了 | `README.md` 2 本を更新。「シナリオパイプライン」節を新設 |
| **追加** | 完了 | **URL 漏れの修正**（2026-09-03、実 GAS で発覚）。`import_from_url()` の入口で `redact_url()` を通し、`source_label` も issue の location もホスト名までに丸める。§4 と §5.7 を参照 |
| **追加** | 完了 | **U-08 の B 案を実装**（Yuu さんの判断・2026-09-03）。`AdvAudioEffect.apply_final()` が `stop_bgm` のときだけ `AdvAudioDirector.stop_bgm(0.0)` を呼ぶ。`play_se` / `play_bgm` は従来どおり何もしない。`test_effects.gd` に 5 アサーション追加（88 → 93） |

### DoD

| 項目 | 結果 |
|------|------|
| T-01〜T-15 の受け入れ条件 | ✅ |
| U-08（B 案）の追加実装 | ✅ スキップ経路で stop_bgm が即時に効く |
| `runtime/` `ui/` を 1 バイトも変更していない | ⚠️ **U-08 の追加実装で `runtime/effects/adv_audio_effect.gd` の `apply_final()` だけ変更**（ユーザー判断による計画外の追加）。それ以外は無変更 |
| `core/` の変更は `adv_scenario_parser.gd` のみ | ✅ |
| `core/` / `resources/` が `Node` を参照していない | ✅ |
| `import/` `editor/` がランタイムから参照されていない | ✅ `runtime/` `ui/` に `AdvScenarioImporter` / `AdvImportDock` の出現 0 件 |
| `Thread` / `WorkerThreadPool` 不使用 | ✅ |
| 引数名に `name` を使っていない / 全静的型注釈 | ✅ |
| テスト 7 本が終了コード 0 | ✅ `.godot` 削除 → `--import` からの通しで確認 |
| 全 `.gd` の `--check-only` で警告 0 件 | ✅ |
| ERROR のあるシナリオで `.tres` が 1 つも書かれない | ✅ テスト＋ミューテーションで確認 |
| 書き出した `.tres` の往復で型が保たれる | ✅ 派生ステップ型・`parallel_effects`・`options`・`uid`・型付き辞書すべて |

### ミューテーションテスト（新テストが本当に噛むか）

6 か所を壊して、該当アサーションが確実に落ちることを確認した。

| 壊した箇所 | 落ちたアサーション |
|-----------|------------------|
| `import_from_url()` の `redact_url()` を外す | 3 件（U-05） |
| `stop_bgm` の `apply_final()` を元の「何もしない」へ戻す | 2 件（U-08） |
| ERROR ガード（`if not result.is_ok(): return`）を無効化 | 2 件（書き出し 0 件 / Book が作られていない） |
| 立ち絵警告の重複排除を無効化 | 1 件 |
| `take_over_path()` を無効化 | 2 件（ExtResource 参照 / インライン化されていない） |
| stale 検出を無効化 | 2 件（`stale_resource` / `stale_paths`） |

---

## 2. 計画との差分

| 項目 | 計画 | 実際 | 理由 |
|------|------|------|------|
| `AdvImportResult` の作り | 独立した `RefCounted` | **`AdvParseResult` を継承** | `is_ok` / `errors` / `warnings` / `to_lines` を書き直す理由が無い。書き出し結果 4 つを足すだけで済む |
| `written_paths` への追加 | 直接 `append` | **`add_written()` / `add_stale()` を経由** | `PackedStringArray` は値型で、**プロパティ越しに得たものへ `append` しても書き戻らない**。クラス内のメンバとして触る必要がある |
| JSON のパース | `JSON.parse_string` | **`JSON.new().parse()`** | `parse_string` は失敗時にエンジンのエラーログを吐く。「壊れた JSON を渡したら `invalid_json` が返る」という**正常系がログを汚す**。あわせて JSON 側のエラー行とメッセージを issue に載せられるようになった |
| `.tres` のパス確定 | `ResourceSaver.FLAG_CHANGE_PATH` | **`Resource.take_over_path()`** | R-19 の答え。詳細は §5.1 |
| 立ち絵警告の重複排除 | `(speaker, pose, expression)` で畳む | **解決結果（`speaker` + 解決後のパス）で畳む** | 別々の `(pose, expression)` が同じパスへフォールバックするため、入力側で畳むと**同じ警告が 2 回出た**。実際にテストが落ちて気づいた |
| `portrait_set` 無しキャラの扱い | 計画に記述なし | **検査対象外にした** | 立ち絵無しキャラは設計上の正常な形（仕様書 §1 の芯 4）。サンプルの `kaze` で毎行警告が出るのは誤り |
| 出力レイアウト | 計画どおり id 単位の 3 階層 | 同左 | — |
| GAS の置き場所 | 計画どおり `import/gas/` | 同左。`.gdignore` は置かなかった | Godot は `.gs` を無視するだけで警告も出さない。FileSystem ドックから見える方が運用しやすい |
| CLI の `--url` ログ | 計画に記述なし | **URL を標準出力に出さない** | 秘匿が唯一の認証手段（U-05）。CI ログに残るのは避けたい |

**「対象外」への越境はなし。** `runtime/` `ui/` `samples/` には手を出していない。
`AdvEffectSchema` も無変更。`merge()` も実装していない。

---

## 3. 未完了・残タスク

| 内容 | 未完了の理由 | 次フェーズで必要か |
|------|--------------|--------------------|
| `AdvEffectSchema.register()`（拡張演出のスキーマ登録） | §6 の要件ではない。未登録 id でも params は文字列のまま通る | 必要になったとき |
| `export_presets.cfg` への除外パターン | `.gitignore` 済みでリポジトリに無い | エクスポート時に手動（README に手順あり） |
| 実素材での目視確認 / Web の autoplay 検証 | 素材が 1 つも無い | phase-08 |

---

## 4. 発生した問題・既知の不具合

| 症状 | 再現条件 | 暫定対応 / 未対応 |
|------|----------|-------------------|
| **`content_hash` が空の JSON は毎回書き出す** | GAS を使わず手書き JSON を食わせたとき | **仕様どおり。** 片方でも空なら「分からない」＝書き出す、に倒している |
| **stale の検出は `characters/` と `topics/` だけ** | 出力先の直下に余分な `.tres` を置いたとき | **未対応。** 直下は Book 1 つの置き場所なので、`--book-name` を変えて複数 Book を置く運用をすると検出できない。単一 Book 前提（U-07 確定）では問題にならない |
| Dock の取得中に Dock を閉じるとどうなるか | プラグインを無効化するなど | **未検証。** `HTTPRequest` は Dock の子なので一緒に解放されるが、`await` 中のコルーチンが解放済みノードを触る可能性が残る |
| 終了時に `ObjectDB instances leaked` 2 件 / `resources still in use` 1 件 | 常に | phase-01 からの既知事項。**終了コードは 0**。CI は終了コードで判定する |
| `id` にファイル名として使えない文字が入ると `_` に丸められる | `id` に `/` や `:` を入れたとき | **未対応。** 丸めた結果が衝突しても検出しない。シートの `id` は英数字とアンダースコアで書く運用 |

---

## 5. 特に報告してほしかった観点への回答

### 5.1 R-19: `ResourceSaver` と ExtResource 参照 — **`take_over_path()` が必要**

**`FLAG_CHANGE_PATH` では足りない。** 2 回目以降のインポートで、
既存 `.tres` がリソースキャッシュに載っている状態だと
「同じパスを持つリソースが 2 つある」ことになって保存が弾かれる。

`Resource.take_over_path(path)` は**キャッシュのエントリごと奪う**ので、
上書きインポートで正しく動く。順序も効く:

1. `characters/<id>.tres` を保存（`resource_path` が付く）
2. `topics/<id>.tres` を保存（同上）
3. **最後に** Book を保存 → `topics` / `characters` は **ExtResource 参照**として書かれる

`take_over_path()` を外すと Book に `[sub_resource]` として**全部が埋め込まれる**。
テストで `.tres` のテキストを直接見て確認している（ミューテーションでも落ちる）。

### 5.2 R-20: ヘッドレスの `HTTPRequest` — **動く。ただし 1 フレーム待ちが要る**

ローカル HTTP サーバに対して `--headless --script` から取得 → 検証 → 書き出しまで通った。
200 / 404 / 接続不能の 3 パターンとも期待どおりの終了コードになる。

**ただし `SceneTree._initialize()` の時点では `root` がまだツリーに入っていない。**
そこへ `add_child()` した `HTTPRequest` は `is_inside_tree() == false` で、
`request()` が `ERR_UNCONFIGURED`(3) を返す。**phase-03 の R-08 と同根**。

- CLI 側で `await process_frame` を 1 回入れてから `import_from_url()` を呼ぶ
- インポータ側にも保険を入れたが、**`p_host.get_tree()` は null を返す**（ホスト自身がツリー外のため）。
  `Engine.get_main_loop() as SceneTree` から取る必要がある

### 5.3 R-21: `ResourceLoader.exists()` — **`--script` 実行でも機能する**

実素材ゼロのサンプルに対して `missing_portrait_texture` が 4 件、正しく出た。
存在する側は `tests/assets/test_tone.tres` を立ち絵に見立てて検証し、警告 0 件になることを確認した。

**`FileAccess.file_exists()` は使えない**（`.png` はインポート後 `.ctex` になり、
エクスポート後の `.pck` では元パスが存在しない）。仕様書 §4.2 の指定どおりで正しい。

### 5.4 R-22: `@tool` の Dock — **エディタ外でも `instantiate()` できる**

`Engine.is_editor_hint()` のガードは**要らなかった**。
Dock が `EditorInterface` や `EditorFileDialog` を一切触っていないため
（ファイル選択は素の `FileDialog`）。テストで `.tscn` を読んで
`add_child()` → `_ready()` を通し、子ノードの構成まで検証している。

### 5.5 R-23: 出力先の生成 — `DirAccess.make_dir_recursive_absolute()`

`res://game/resources/adv/scenario/` は現在存在しないが、`characters/` `topics/` ごと再帰生成する。
失敗したら `write_failed` の ERROR にして**そこで止める**（半端に書き出さない）。

### 5.6 GAS スクリプトの検証方法

実デプロイができないので、**GAS の API をモックして Node で実行**し、
出力 JSON をそのまま CLI（`--file=`）に食わせて経路全体を通した。

確認できたこと:

- 3 シート（`characters` / `topics` / `steps`）をヘッダ行で読む
- `order` が昇順に並ぶ（シート上でバラバラに書いても）
- `params` の `key=value; key=value` が**文字列辞書**になる（型変換はしない）
- `parallel` 演出と `option` が flat のまま出て、**Godot 側の畳み込みが効く**
- `poses` / `expressions` / `tags` のカンマ区切りが配列になる
- 空セルは**キーごと落ちる**
- `content_hash` が**`generated_at` を含めずに**計算され、2 回呼んでも同じ値になる
- `topics` シートに無い `topic_id` の行は捨て、`warnings` 配列に理由が入る

**実 GAS 環境での動作は未確認。** `SpreadsheetApp` / `Utilities` / `ContentService` の
呼び出し方は素直なので大きな崩れは無いはずだが、初回は `previewScenarioJson` を
エディタから実行して JSON を目視してください。

### 5.7 URL の秘匿 — **一度漏らした。設計を変えた**

初版は「CLI が取得元を表示するときだけ伏せる」形にしていた。
実 GAS で通したところ、**最後の `--- 結果 ---` の行が `source_label` をそのまま印字して
URL を標準出力へ出した**。「取得元: GAS ウェブアプリ（URL は伏せます）」と表示した直後に、
同じ実行の別の行が丸ごと出していた。CI ログにも同じように残る。

**表示側で消す設計は漏れる。** 結果オブジェクトは CLI のログ・Dock・issue の 1 行表現と
複数の経路で表に出るので、どれか 1 つを直しても他が残る。

**修正**: `AdvScenarioImporter.import_from_url()` の入口で `redact_url()` を通し、
**`AdvImportResult` に生の URL を持たせない**。`source_label` も取得失敗時の issue の
location も `script.google.com (以降は伏せています)` になる。
取得失敗の原因は HTTP ステータスとしてメッセージ側に載るので、診断は落ちない。

- **Dock の入力値は `user://adv_kit_import.cfg`**。`res://` にも `ProjectSettings` にも書かない
- CLI は環境変数 `ADV_KIT_SCENARIO_URL` からも読む

**テストの教訓**: 最初に足したテストは `redact_url()` 単体と、
「丸めた文字列を入れた `AdvImportResult`」しか見ておらず、
**`import_from_url()` が実際にそれを通しているか**を見ていなかった。
ミューテーション（`redact_url()` の呼び出しを外す）を当てたら 108 件全部が通ってしまい、
そこで気づいた。到達不能なポートへ実際に `import_from_url()` を投げるテストに直したら、
同じミューテーションで 3 件落ちるようになった。
**純粋関数だけを見るテストは、その関数が呼ばれていないことを検出しない。**

---

## 6. 仕様書への反映提案

| # | 箇所 | 内容 |
|---|------|------|
| 1 | **§4.9 検証コード一覧** | **`fetch_failed`（ERROR）/ `write_failed`（ERROR）/ `stale_resource`（WARNING）を追加**。担当表に `AdvScenarioImporter` の行を作り、`missing_portrait_texture` と合わせて 4 つを載せる |
| 2 | **§3 ディレクトリ構造** | `import/adv_import_result.gd` と `import/gas/`（`adv_scenario_export.gs` / `README.md`）を追加 |
| 3 | **§6.4 インポータ** | **出力レイアウト**（`scenario_book.tres` + `characters/<id>.tres` + `topics/<id>.tres`）と、**CLI のオプション表・終了コード**（0/1/2）を明記 |
| 4 | **§4.2 / §4.9** | `missing_portrait_texture` に「**`portrait_set` を持たないキャラクターは対象外**」を追記 |
| 5 | **§4.5 / §13 U-07** | **U-07 を「2026-09-03 に確定（章分割は行わない）」として確定済みへ移す。** `merge()` は実装しない |
| 6 | **§6.2 GAS API** | Dock の URL 保存先が `user://adv_kit_import.cfg` であることと、CLI の環境変数 `ADV_KIT_SCENARIO_URL` を追記 |
| 7 | **§13 未決事項** | **R-19〜R-23 の解消**を追加（`take_over_path` / ヘッドレス `HTTPRequest` の 1 フレーム待ち / `ResourceLoader.exists` / `@tool` Dock / 再帰生成） |
| 8 | **§11 フェーズ計画** | phase-07 を「完了（2026-09-03）」に更新 |

---

## 7. 動作確認状況

- **確認済み**（Godot **4.7-stable / Linux headless**、`.godot` 削除 → `--import` からの通し）:
  - テスト 7 本が終了コード 0（157 / 32 / 88 / 24 / 50 / 44 / 100）
  - 全 `.gd` の `--check-only` で警告 0 件
  - **ミューテーションテスト 4 種**で新テストが噛むことを確認（§1）
  - CLI: `--help` / 引数エラー（終了コード 2）/ `--file` 書き出し / `--no-write` / `--force` /
    `--url`（ローカル HTTP サーバ）/ 404（終了コード 1）/ 接続不能（同）/ 環境変数フォールバック
  - **GAS → JSON → `.tres` の通し**（GAS はモック実行）
  - 書き出した `.tres` の読み戻しで、派生ステップ型・`parallel_effects`・`options`・`uid`・
    型付き辞書のキー型がすべて保たれること
- **Windows 実機（4.7.2-stable）で確認済み**（2026-09-03）:
  - `test_playback` / `test_effects`(93) / `test_auto_direction`(24) / `test_progress`(50) /
    `test_play_assist`(44) / **`test_import`(100)** が終了コード 0。**Linux headless と件数まで一致**
  - `test_scenario_parse` は出力が流れて未確認（Linux では 157 件全通過）
  - 出た WARNING は想定内のみ（`Voice` バス不在の `Master` フォールバック、
    実素材ゼロの音源・ボイス欠損、`speaker=nobody` の異常系）
- **実 GAS ウェブアプリでの疎通も確認済み**（2026-09-03）:
  - サンプルシートから **9 ファイル書き出し / 終了コード 0**、ERROR 0 / WARNING 5（立ち絵のみ）
  - **`content_hash` が GAS のモック実行と完全一致**（`01c08038cf8d5d4d7f60532cb6c8afed`）。
    GAS 実装が意図どおりであることの裏付け
  - 2 回目で差分スキップが効くことも確認
  - 302 リダイレクト追従（`max_redirects = 8`）も実環境で機能した
- **未確認**:
  - エディタ内での Dock の見た目と操作（ヘッドレスではノード構成しか見ていない）
  - 実際に `res://game/resources/adv/scenario/` へ書き出したときのエディタの取り込み

```powershell
cd C:\Users\kzr12\Root\MyProjects\AdvKit
$godot = "C:\Users\kzr12\Root\GodotEngine\godot.cmd"

& $godot --headless --import
& $godot --headless --script res://addons/adv_kit/tests/test_import.gd; "import  exit=$LASTEXITCODE"

# CLI のオフライン確認（書き出しはしない）
& $godot --headless --script res://addons/adv_kit/import/adv_import_cli.gd -- `
    --file=res://addons/adv_kit/samples/sample_scenario.json --no-write; "cli exit=$LASTEXITCODE"
```

---

## 8. 次フェーズ（phase-08）への申し送り

1. **実素材と実 GAS を通すのが先。** phase-08 は「unityroom チェックリスト適合・autoplay の実 Web 検証・
   演出パラメータの目視調整・サンプルプロジェクト」だが、**どれも実素材が要る**。
   スプレッドシートを 1 枚作って GAS をデプロイし、`.tres` を実際に `res://game/` へ吐くところから。
2. **`export_presets.cfg` の除外設定を忘れないこと。** `samples/` `tests/` `editor/` `import/` の 4 つだけ。
   **`addons/adv_kit/` を一括除外してはならない**（ランタイムが死ぬ）。
3. **U-08 は 2026-09-03 に B 案で確定し、phase-07 の作業中に実装した。**
   スキップで `stop_bgm` を飛ばしても BGM は残らない。**phase-08 での追加作業はない。**
4. **phase-04 / 05 / 06 の引継ぎ資料と差分レポートが Project に無い。** 台帳の「現在地」も
   phase-03 のままだった（phase-07 の実装に合わせて更新済み）。
   Codex 実装分の記録がどこかにあるなら Project へ集約したい。
   なお **U-09 / U-10 / U-04 は phase-07 の作業中にコードを読んで確定させ、仕様書へ反映済み**
   （U-09 は「実装に合わせて仕様書を直す」でユーザー判断済み。差分レポート §6 を参照）。
5. Dock の見た目は無装飾。エディタで開いて幅・並びが破綻していないか一度見てほしい。
