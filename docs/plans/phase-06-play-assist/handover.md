# 引継ぎ資料: フェーズ06 play-assist

- **対象計画書**: `InProgress/plan-phase-06.md`
- **実装日 / セッション**: 2026-09-04 / phase06 実装セッション

## 1. 実装済み内容（タスクID対応）
| 計画タスクID | 状態 | 実装した内容 / 変更したファイル |
|--------------|------|--------------------------------|
| T-01 | 完了 | `AdvBacklogEntry` と上限付き `AdvBacklog` を追加。`uid`、話者名、名前色、本文、voice_path を保持し、上限超過時は古い項目を破棄、上限 0 も安全に処理。`addons/adv_kit/core/adv_backlog_entry.gd`、`addons/adv_kit/core/adv_backlog.gd` |
| T-02 | 完了 | `AdvBacklogView` の基底契約と `PlainBacklogView` を追加。`present` / `close`、`closed` / `voice_replay_requested` を実装し、標準 `AdvScene` に差し替え可能な BacklogView として注入。`addons/adv_kit/ui/adv_backlog_view.gd`、`addons/adv_kit/samples/ui/plain_backlog_view.gd`、`addons/adv_kit/samples/ui/plain_backlog_view.tscn`、`addons/adv_kit/ui/adv_scene.tscn` |
| T-03 | 完了 | `AdvPlayer` に `set_auto_mode` / `is_auto_mode`、`auto_mode_changed` を追加。line 完了後に `auto_wait_time` と voice 残時間の最大値を待ち、通常 advance、choice、backlog 開閉、終端で待機を解除。`addons/adv_kit/runtime/adv_player.gd` |
| T-04 | 完了 | `start_skip` / `stop_skip` / `is_skipping`、開始・停止 signal、既読連動、未読停止、choice 停止、`apply_final()` による演出適用、音声無再生を実装。入力の press / release は `AdvPlayer` に集約。`addons/adv_kit/runtime/adv_player.gd`、`addons/adv_kit/samples/ui/plain_message_window.gd` |
| T-05 | 完了 | line 完了時のみバックログへ記録し、話題をまたいで保持。`stop()` でクリア、表示中の advance を抑止、設定有効時のみ同じ Voice チャンネルで replay。`addons/adv_kit/runtime/adv_player.gd` |
| T-06 | 完了 | `addons/adv_kit/tests/test_play_assist.gd` を追加。backlog 上限・記録、auto 待機・voice 待機、skip の既読 / 未読 / choice / 演出、backlog 開閉 / replay を検証し、既存テストと合わせて全件終了コード 0 を確認。 |
| T-07 | 完了 | ルート README、アドオン README、仕様変更履歴、フェーズ台帳を更新。phase06 の計画書と本引継ぎ資料を `InProgress/` に追加。 |

## 2. 計画との差分
| 項目 | 計画 | 実際 | 理由 |
|------|------|------|------|
| 計画書・引継ぎ資料の配置 | リポジトリ内 `Docs/` | Obsidian 側 `InProgress/` | リポジトリに `Docs/` がなく、既存の仕様書・計画書・台帳が同ディレクトリに集約されているため。 |
| 標準バックログ UI | 無装飾の参照実装 | ScrollContainer、行ラベル、voice replay ボタン、閉じるボタンを持つ最小 UI | 標準シーンで API 接続を実際に確認できる差し替え可能なサンプルが必要なため。 |
| Web export 検証 | unityroom / Web 前提 | Godot 4.7.2 の公式 Web template を導入し、`build/phase06_web_smoke/Build.html` を export | 環境に Web export template が未導入だったため、公式 template を導入して検証した。 |

## 3. 未完了・残タスク
| 内容 | 未完了の理由 | 次フェーズで必要か |
|------|--------------|--------------------|
| ブラウザ上での実操作確認 | このセッションではブラウザ操作用コントロール機能が利用できず、ローカル HTTP 配信物の取得確認まで実施 | 要。unityroom へ公開する前に、Web 起動、auto / skip / backlog の実操作を確認する。 |
| phase06 の機能追加 | 該当なし | 不要 |

## 4. 発生した問題・既知の不具合
| 症状 | 再現条件 | 暫定対応 / 未対応 |
|------|----------|-------------------|
| ヘッドレス Godot 実行時にユーザー設定・ログ・証明書ディレクトリへのアクセス警告が出る | `godot --headless` をこの環境で実行 | 全テストの終了コードは 0。環境由来の警告として継続記録。 |
| Voice bus が無い場合の fallback 警告、sample 音源不足警告が出る | 既存テストまたは Web export の import 時 | 既存のテスト環境上の警告。実装の失敗ではないが、実ゲーム側で Voice bus と音源を用意する。 |
| プロセス終了時に ObjectDB / resource leak 警告が出る | ヘッドレステスト終了時 | 既存テストにも出る終了時警告。phase06 のアサーションは全件成功。 |

## 5. 設計・実装上の判断
- `AdvBacklog` と `AdvBacklogEntry` は `RefCounted` とした — 理由: バックログはセーブ進行に含めない一時的な再生補助データであり、シーン所有に依存しないため。
- オート・スキップ・バックログの状態は `AdvPlayer` に一元化した — 理由: 通常 advance、choice、voice、進行保存と競合するため、UI 側へ分散させず再生状態機械の境界で制御するため。
- スキップ時は `AdvEffectHandler.apply_final()` を使い、step ごとの待機を作らない — 理由: 仕様 §9.3 の「演出を再生せず最終状態を適用」を満たし、Web 上の待機を避けるため。
- skip interval は `_process` の accumulator で処理し、未読 line は一旦通常表示して停止する — 理由: 押下継続中の複数 step 処理と既読停止を同じフレームへ依存させず、既読を line 完了時に一貫して記録するため。
- 入力処理を `AdvPlayer._unhandled_input()` に集約した — 理由: sample UI と本体の二重反応を避け、差し替え UI でも同じ入力契約を使えるようにするため。

## 6. 依存・環境・前提の変化
- 外部ライブラリ・Godot addon の追加はない。
- Godot 4.7.2 公式 Web export template をユーザー環境へ導入した。リポジトリには export preset を追加していない。
- `project.godot` の Compatibility renderer、単一スレッド Web 前提、既存の input action を維持した。

## 7. 動作確認状況
- **確認済み**:
  - `test_scenario_parse.gd`: 157 / 157 passed
  - `test_playback.gd`: 終了コード 0
  - `test_effects.gd`: 88 / 88 passed
  - `test_auto_direction.gd`: 24 / 24 passed
  - `test_progress.gd`: 50 / 50 passed
  - `test_play_assist.gd`: 44 / 44 passed
  - Godot 4.7.2 で `godot --headless --path . --export-release Web build/phase06_web_smoke/Build.html` が成功。
  - ローカル HTTP サーバー経由で Web export の `/`、`Build.js`、`Build.pck`、`Build.wasm` が HTTP 200 で取得できることを確認。
  - `git diff --check` が成功し、空白エラーがないことを確認。
- **未確認**: ブラウザ画面の実起動後の描画確認、キーボードによる auto / skip / backlog 操作、voice replay の実音声再生。

## 8. 次フェーズへの申し送り
- phase07 は spreadsheet → Google Apps Script → JSON → `.tres` のシナリオ導入パイプラインが対象。phase06 の `AdvPlayer` 公開 API を変更する場合は、auto / skip / backlog の待機解除と `stop()` 時の backlog クリアを壊さないこと。
- `AdvBacklogView` は差し替え契約であり、表示実装が未接続でも `AdvPlayer` の再生は停止しない設計。実ゲーム UI では `BacklogView` の表示中に close signal を必ず返すこと。
- `AdvBacklogEntry.uid` は line の `uid` をそのまま保持する。バックログは `get_progress()` の step_index や既読集合には含めない。
- Web export の一時生成物は `build/phase06_web_smoke/` に残っている。git 管理対象外のスモーク確認用生成物であり、必要に応じて削除してよい。
