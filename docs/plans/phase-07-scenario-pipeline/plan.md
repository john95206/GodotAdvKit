# 実装計画書: フェーズ07 scenario-pipeline

- **作成日**: 2026-09-03
- **実装者**: Claude（Codex ではない）
- **対象リポジトリ**: `C:\Users\kzr12\Root\MyProjects\AdvKit\`（Godot 4.7 系 / Compatibility）

## 1. フェーズ概要

- **ゴール**: スプレッドシート → GAS → JSON → `.tres` の経路が、**エディタ Dock と CLI の両方から通る**。
  検証エラーがあれば書き出さず、終了コードで CI から判定できる。
- **仕様書の該当箇所**: §6（シナリオパイプライン）全体、§4.5（`schema_version` / `content_hash`）、
  §4.2（`missing_portrait_texture` の検査対象）、§4.9（検証コード）、§10（エクスポート除外）
- **前提フェーズ**: phase-01（`AdvScenarioParser` / `AdvScenarioValidator` / 全 Resource）。依存は **01 → 07**。
  phase-04〜06 の成果物には触れない。

## 2. スコープ

**対象**

- `import/adv_scenario_importer.gd` … 取得・パース・検証・立ち絵検査・`.tres` 書き出しの共通ロジック（`RefCounted`）
- `import/adv_import_result.gd` … インポート1回分の結果（`AdvParseResult` を継承）
- `import/adv_import_cli.gd` … `extends SceneTree` の CLI 入口。終了コードで成否を返す
- `import/gas/adv_scenario_export.gs` … GAS の `doGet(e)`。3 シート → 仕様書 §6.3 の JSON
- `editor/adv_import_dock.gd` / `.tscn` … 右ドックのパネル
- `resources/adv_scenario_book.gd` に `schema_version` / `content_hash` を追加（phase-01 からの持ち越し）
- `core/adv_scenario_parser.gd` が上記 2 つを JSON から Book へ写す
- `adv_kit_plugin.gd` に Dock の追加・削除
- `tests/test_import.gd`

**対象外（今回やらない）**

- **複数 Book のマージ**（U-07。2026-09-03 に「単一 Book のまま」で確定。`merge()` は実装しない）
- **`AdvEffectSchema.register()`**（拡張演出のスキーマ登録）。phase-03 の残タスクだが §6 の要件ではない
- **実際のスプレッドシート作成・GAS のデプロイ**（Yuu さんが手動で行う）
- **`export_presets.cfg` への除外パターン追加**（`.gitignore` 済みでリポジトリに無いため、README に手順を書くに留める）
- `runtime/` `ui/` `core/`（`adv_scenario_parser.gd` を除く）への変更
- Web ビルド・実素材での目視確認（phase-08）

## 3. 影響範囲

| 区分 | 置き場所 | Node 参照 | 今回の扱い |
|------|----------|-----------|-----------|
| データ | `resources/` | 不可 | `adv_scenario_book.gd` に 2 フィールド追加 |
| ロジック | `core/` | **不可** | `adv_scenario_parser.gd` のみ変更 |
| 実行 | `runtime/` | 可 | **触らない** |
| 表示 | `ui/` | 可 | **触らない** |
| ツール | `import/`, `editor/` | 可 | **新規** |

- `import/` と `editor/` は**エクスポート除外対象**（仕様書 §10）。ランタイムから参照されてはならない。
- `AdvScenarioImporter` は `RefCounted`。**HTTP 取得だけは Node が要る**ので、
  ホスト Node を引数で受け取り、`HTTPRequest` をその子として一時的に生やして即座に解放する。

## 4. 新規に定義する契約

```gdscript
class_name AdvImportResult extends AdvParseResult
	var written_paths: PackedStringArray   # 書き出した .tres
	var stale_paths: PackedStringArray     # JSON から消えた既存 .tres（削除しない）
	var skipped: bool                      # content_hash 一致で書き出しを省いた
	var source_label: String               # URL またはファイルパス
	func summary() -> String

class_name AdvScenarioImporter extends RefCounted
	static func resolve_output_dir() -> String
	static func import_from_text(text, source_label, output_dir, options) -> AdvImportResult
	static func import_from_file(path, output_dir, options) -> AdvImportResult
	static func import_from_url(host: Node, url, output_dir, options) -> AdvImportResult  # await
	static func check_portrait_textures(book) -> Array[AdvIssue]
	static func parse_cli_args(args) -> Dictionary
```

`options`: `{force: bool, write: bool, check_textures: bool, book_name: String}`。

**出力レイアウト**（`<out>` は `adv_kit/import/output_dir`、既定 `res://game/resources/adv/scenario/`）:

```text
<out>/scenario_book.tres        # AdvScenarioBook。topics / characters は ExtResource 参照
<out>/characters/<id>.tres
<out>/topics/<id>.tres
```

id 単位のファイルに分けるのは、仕様書 §6.4 の「**既存 `.tres` と同一 `id` のものを上書きし、
JSON に存在しなくなったものは削除せず警告のみ**」を素直に実装できる形がこれだけだから。

**新規の検証コード**（仕様書 §4.9 に無い。実装後に追記を提案する）:

| code | severity | 内容 |
|------|----------|------|
| `fetch_failed` | ERROR | GAS API の取得に失敗（HTTP エラー・タイムアウト・空レスポンス） |
| `write_failed` | ERROR | `.tres` の書き出しに失敗（ディレクトリ作成失敗を含む） |
| `stale_resource` | WARNING | JSON に存在しなくなった既存 `.tres`。**削除せず警告のみ** |

## 5. タスク分解

| ID | タスク | 受け入れ条件 | 依存 |
|----|--------|--------------|------|
| T-01 | `AdvScenarioBook` に `schema_version: int` / `content_hash: String` を追加 | `.tres` 往復で保たれる | - |
| T-02 | `AdvScenarioParser.parse()` が JSON の `schema_version` / `content_hash` を Book へ写す | 欠落時は 0 / 空文字。既存 157 件のテストが通る | T-01 |
| T-03 | `AdvImportResult` | `AdvParseResult` の `is_ok` / `errors` / `warnings` をそのまま使える | - |
| T-04 | `AdvScenarioImporter.resolve_output_dir()` | ProjectSettings に無ければ既定値を返す（**R-02**。`--import` では `EditorPlugin._enter_tree()` が走らない） | - |
| T-05 | `check_portrait_textures()` | **シナリオ中で実際に参照された `(speaker, pose, expression)` の解決結果だけ**を検査（§4.2）。`portrait_set == null` のキャラは対象外。重複は 1 件に畳む | T-03 |
| T-06 | `import_from_text()` … パース → 検証 → 立ち絵検査 → 書き出し | ERROR が 1 件でもあれば**書き出さない**。`content_hash` が既存 Book と一致し `force` でなければ `skipped` | T-03,T-04,T-05 |
| T-07 | `.tres` の書き出しと stale 検出 | ディレクトリを再帰生成。`ResourceSaver.FLAG_CHANGE_PATH` で Book が ExtResource 参照になる。消えた id は `stale_resource` の WARNING | T-06 |
| T-08 | `fetch_json()` / `import_from_url()` | ホスト Node に `HTTPRequest` を一時生成し、完了後に必ず解放。リダイレクトを追う。失敗は `fetch_failed` | T-06 |
| T-09 | `parse_cli_args()` | `--url= --file= --out= --force --no-write --no-texture-check --book-name= --help`。テストから直接呼べる static | - |
| T-10 | `import/adv_import_cli.gd` | `OS.get_cmdline_user_args()` を読む。ERROR 0 件で 0、あれば 1、引数不正で 2。`ADV_KIT_SCENARIO_URL` を環境変数フォールバックにする | T-08,T-09 |
| T-11 | `editor/adv_import_dock.gd` / `.tscn` | URL 入力・出力先・force・[取得]・[ローカル JSON]・結果表示。URL は `user://adv_kit_import.cfg` に保存し**リポジトリに出さない**（§6.2 U-05） | T-08 |
| T-12 | `adv_kit_plugin.gd` に Dock の追加・削除 | `_exit_tree()` で確実に外す。ProjectSettings の既存登録は壊さない | T-11 |
| T-13 | `import/gas/adv_scenario_export.gs` と `import/gas/README.md` | 3 シートをヘッダ行で判定して読み、§6.3 の JSON を返す。`content_hash` を含む。`params` は `key=value;` を分解した文字列辞書 | - |
| T-14 | `tests/test_import.gd` | 下記 DoD の項目を網羅。終了コード 0 | T-07,T-09 |
| T-15 | README 2 本の更新 | CLI の使い方・Dock の使い方・エクスポート除外の手順 | T-10,T-11 |

## 6. 完了定義（DoD）

- [ ] T-01〜T-15 の受け入れ条件を満たす
- [ ] `runtime/` `ui/` を 1 バイトも変更していない
- [ ] `core/` の変更は `adv_scenario_parser.gd` のみ
- [ ] `core/` / `resources/` が `Node` を参照していない
- [ ] `import/` `editor/` がランタイムのどこからも参照されていない
- [ ] `Thread` / `WorkerThreadPool` 不使用
- [ ] 引数名に `name` を使っていない / 全静的型注釈
- [ ] **テスト 7 本すべてが終了コード 0**（既存 6 本の回帰を含む）
- [ ] 全 `.gd` の `--check-only` で**警告 0 件**
- [ ] ERROR のあるシナリオで `.tres` が 1 つも書かれないことをテストで確認
- [ ] 書き出した `.tres` を `load()` して派生ステップ型・`parallel_effects`・`options` が保たれる

## 7. 報告してほしい観点（引継ぎ資料）

- 計画から外れた判断とその理由
- **`ResourceSaver` の挙動**: `FLAG_CHANGE_PATH` を付けたときの `resource_path` と ExtResource 参照
- **`HTTPRequest` をヘッドレスの `SceneTree` で使えるか**（CLI の成立条件）
- **`ResourceLoader.exists()` が CLI（`--script`）でどう振る舞うか**（立ち絵検査の信頼度）
- 仕様書 §4.9 へ追記すべき検証コード

## 8. リスク・不確実性

| ID | 内容 |
|----|------|
| R-19 | `ResourceSaver.save()` で Book の `topics` / `characters` が **SubResource として埋め込まれてしまう**可能性。`resource_path` が空のままだとインライン化される |
| R-20 | ヘッドレスの `SceneTree` で `HTTPRequest` が動くか。動かないなら CLI の URL 取得を別手段（`HTTPClient` の同期ループ）にする必要がある |
| R-21 | `--script` 実行時に `ResourceLoader.exists()` が `.png` を正しく判定するか。`.godot/` のインポートキャッシュに依存する |
| R-22 | `@tool` の Dock スクリプトを**エディタ外で `instantiate()`** できるか（テストで .tscn を読むため）。`Engine.is_editor_hint()` のガードが要る |
| R-23 | 出力先 `res://game/resources/adv/scenario/` は現在存在しない。再帰生成が要る |
