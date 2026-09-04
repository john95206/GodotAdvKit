# 引継ぎ資料: フェーズ05 topics-choices-and-progress

- **対象計画書**: `InProgress/plan-phase-05.md`
- **実装日 / セッション**: 2026-09-04 / 1

## 1. 実装済み内容（タスクID対応）

| 計画タスクID | 状態 | 実装した内容 / 変更したファイル |
|--------------|------|--------------------------------|
| T-01 | 完了 | `AdvProgressState`（`RefCounted`）を追加し、topic ID、step UID、flags、既読 UID 集合を保持・復元できるようにした。内部既読集合は `Dictionary[StringName, bool]`、保存境界では `PackedStringArray` と `String` へ変換する。変更: `addons/adv_kit/core/adv_progress_state.gd`, `.uid` |
| T-02 | 完了 | `AdvChoiceMenu` の外観なし基底クラス、無装飾の `PlainChoiceMenu` 参照実装、`AdvScene` への ChoiceMenu 配置、`AdvPlayer.choice_menu` 注入点を追加した。変更: `addons/adv_kit/ui/adv_choice_menu.gd`, `.uid`, `addons/adv_kit/samples/ui/plain_choice_menu.gd`, `.uid`, `.tscn`, `addons/adv_kit/ui/adv_scene.tscn` |
| T-03 | 完了 | `AdvPlayer` に条件付き選択肢の表示、選択結果の flag 設定、空 `goto` の同一 topic 継続、`goto` / `jump` の topic 遷移、`choice_presented` / `choice_selected` / `flag_changed` signal を実装した。変更: `addons/adv_kit/runtime/adv_player.gd` |
| T-04 | 完了 | line 完了時の既読記録、UID ベースの `get_progress()` / `restore_progress()`、旧形式（`read_steps` 欠損）の復元、任意の `portrait_states` 保存・復元を実装した。`step_index` は保存しない。変更: `addons/adv_kit/runtime/adv_player.gd`, `addons/adv_kit/core/adv_progress_state.gd` |
| T-05 | 完了 | 条件フィルタ、busy 中の入力抑止、flag、choice、goto、jump、topic signal、既読、保存・復元、立ち絵状態を検証するテストを追加し、既存 playback テストを choice 対応に更新した。変更: `addons/adv_kit/tests/test_progress.gd`, `addons/adv_kit/tests/test_playback.gd` |
| T-06 | 完了 | ルート README、アドオン README、仕様書、フェーズ台帳、phase05 計画書、引継ぎ資料を更新した。変更: `README.md`, `addons/adv_kit/README.md`, `InProgress/adv-kit-spec.md`, `InProgress/INDEX.md`, `InProgress/plan-phase-05.md`, 本ファイル |

## 2. 計画との差分

計画した phase05 の機能要件はすべて実装した。差分は以下のとおり。

| 項目 | 計画 | 実際 | 理由 |
|------|------|------|------|
| 計画書・引継ぎ資料の配置 | リポジトリ内 `Docs/plans/...` | README と先行フェーズに合わせ、Obsidian 側 `InProgress/plan-phase-05.md` / `handover-phase-05.md` を使用 | リポジトリには `Docs/` がなく、既存の source of truth と計画・引継ぎ資料が同じ外部置き場にあるため |
| 保存辞書の立ち絵状態 | 既存4項目を基本とし、前フェーズの申し送りで検討 | `portrait_states` を任意の追加項目として実装し、pose / expression / slot / modulate を保存・復元 | topic をまたぐ復元でも表示状態を再現できるようにするため。旧形式では省略可能 |
| ChoiceMenu の選択入口 | UI signal から選択 | `AdvChoiceMenu.option_chosen` に加え、`AdvPlayer.choose_option(index)` を公開 | UI を差し替えない構成とヘッドレステストでも同じ選択処理を利用できるため |

## 3. 未完了・残タスク

| 内容 | 未完了の理由 | 次フェーズで必要か |
|------|--------------|--------------------|
| オートモード・既読連動スキップ・バックログ | phase05 の対象外 | 要（phase06） |
| 正式な Web export preset / main scene / 素材付きサンプル | フェーズ計画どおり phase08 の対象 | 要（phase08） |
| 条件式の括弧・数値比較・`visited()` | U-04 の判断により phase05 では追加しない | 不要（別フェーズで再判断） |
| 章分割と `AdvScenarioBook.merge` | U-07 を保留し、単一 Book の前提を維持 | 要否を phase07 着手前に判断 |

## 4. 発生した問題・既知の不具合

| 症状 | 再現条件 | 暫定対応 / 未対応 |
|------|----------|-------------------|
| Godot CLI が `user://logs/godot.log` と root certificate store を開けない旨を出力する | この実行環境で `godot --headless` を実行 | 各テストと Web export の終了コードは 0。環境由来の警告として未対応 |
| `ObjectDB instances leaked` / `resources still in use` が終了時に出る | phase01 以降の headless テスト終了時 | 既知の Godot / 型自己参照由来の終了時メッセージ。テスト結果と終了コードには影響しない |
| `Voice` バスが無いため `Master` へフォールバックする警告 | 開発プロジェクトのオーディオバスで playback / phase05 テストを実行 | 仕様どおりのフォールバック。ゲーム側で `Voice` バスを用意すれば解消する |
| サンプルの BGM / voice / portrait 素材が無いため警告が出る | 既存 sample scenario を playback テストで再生 | 欠損しても進行を止めない既存仕様どおり。実素材は phase08 で追加する |

## 5. 設計・実装上の判断

- phase05 では条件式に括弧を追加しない — 既存の `!` / `&&` / `||` / 識別子と `&&` 優先順位の互換性を維持し、文法拡張は仕様・移行・エラー表示をまとめて扱える別フェーズへ残すため。
- `AdvProgressState` は `Node` 非依存の `RefCounted` にした — 状態の保存・復元を SceneTree や UI から分離し、ゲーム側の Autoload が保存を担当できるようにするため。
- line のタイプライタ完了時だけ既読 UID を記録する — 仕様書 §9.1 の「最後まで表示」をそのまま `line_completed` と同じ経路へ集約するため。
- `step_index` は保存せず `step_uid` から復元する — `parallel` の畳み込みや行追加で添字が変わっても、`order` 由来の既読と復元位置を壊さないため。
- 条件偽の option は `AdvChoiceMenu.present()` へ渡さない — UI 側へ条件評価の責務を漏らさず、表示された index と選択結果を一致させるため。
- 条件で全 option が非表示になった choice は警告して素通りする — 不正または古い flag 状態でプレイが永久停止するのを避けるため。
- `restore_progress()` は保存 topic / UID を復元後、その位置から自動再生する — 保存辞書を渡した直後にゲーム側が再生開始を組み立てなくても、保存位置の表示状態を一貫して再開できるため。
- `portrait_states` は任意の追加辞書とした — 仕様書の既存4項目と旧セーブデータ互換を維持しながら、立ち絵を持つシーンの表示状態も復元するため。
- topic 遷移では `topic_finished` を発火するが、途中遷移では `scenario_finished` を発火しない — topic の終了とシナリオ全体の終了を区別するため。

## 6. 依存・環境・前提の変化

- 追加した外部依存: 該当なし。
- Godot 4.7.2-stable / Compatibility / GDScript / 単一スレッドの前提に変更なし。
- `AdvChoiceMenu` と `AdvProgressState` の global class が追加された。既存の `.uid` をコミット対象として生成済み。
- Web 確認ではホストにある Godot 4.7.2 Web export template を使い、一時 preset で `AdvKit.html` / `AdvKit.pck` / WASM を生成した。正式な `export_presets.cfg` と main scene は追加していない。

## 7. 動作確認状況

- **確認済み**:
  - `godot --headless --path . --import` — 終了コード 0。
  - `godot --headless --path . --script res://addons/adv_kit/tests/test_scenario_parse.gd` — 157 件実行 / 成功 157 / 失敗 0 / 終了コード 0。
  - `godot --headless --path . --script res://addons/adv_kit/tests/test_playback.gd` — `OK` / 終了コード 0。
  - `godot --headless --path . --script res://addons/adv_kit/tests/test_effects.gd` — 88 件実行 / 成功 88 / 失敗 0 / 終了コード 0。
  - `godot --headless --path . --script res://addons/adv_kit/tests/test_auto_direction.gd` — 24 件実行 / 成功 24 / 失敗 0 / 終了コード 0。
  - `godot --headless --path . --script res://addons/adv_kit/tests/test_progress.gd` — 50 件実行 / 成功 50 / 失敗 0 / 終了コード 0。
  - 一時 Web smoke preset（Godot 4.7.2 / Web / Compatibility / thread support 無効）で HTML / PCK / WASM の export — 終了コード 0。検証後に preset と成果物は削除済み。
  - `git diff --check` — 問題なし。
- **未確認**: 実素材の立ち絵を含む表示の最終調整、正式サンプルの Web 通しプレイ、オート・スキップ・バックログ。phase06 / phase08 の対象。

## 8. 次フェーズへの申し送り

- phase06 は `AdvPlayer.is_step_read(uid)` と `get_progress()` の `read_steps` を利用して既読連動スキップを実装する。内部既読集合の型を外から直接変更せず、`AdvProgressState` の API を使うこと。
- `get_progress()` の標準項目は `topic_id`、`step_uid`、`flags`、`read_steps`。`step_index` は追加しない。`portrait_states` は存在しない旧データを受け入れる任意項目。
- `restore_progress()` は保存位置を検証し、未知の UID なら topic の先頭から再生する。保存データのファイル入出力は引き続きゲーム側の責務。
- `AdvPlayer` の choice 中は `_is_busy` と `is_choice_open()` が真で、`advance()` は無視される。通常は UI の `option_chosen` を使い、ヘッドレスまたは独自 UI では `choose_option(index)` を使える。
- topic 遷移は単一 `AdvScenarioBook` 内で解決する。シーン遷移や Autoload は追加していない。
- UI は `AdvChoiceMenu` 基底型へ差し替える。Kit 側の参照実装は無装飾であり、`Theme` を追加しないこと。
