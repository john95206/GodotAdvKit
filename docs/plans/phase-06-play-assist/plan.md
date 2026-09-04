# 実装計画: phase-06 play-assist

- **対象仕様**: `adv-kit-spec.md` §4.6 / §5.3 / §5.4 / §9.1〜§9.5
- **目的**: 既読集合を利用したオートモード・ホールド式スキップ・バックログを `AdvPlayer` の公開 API と差し替え可能な UI へ接続する。
- **前提**: phase-05 の `AdvPlayer`、`AdvProgressState`、`AdvChoiceMenu`、phase-03 の `AdvVoicePlayer` / `AdvEffectHandler.apply_final()` が利用できること。unityroom/Web 前提の GDScript・Compatibility・単一スレッド制約を維持する。

## 着手前の判断

- 計画書と引継ぎ資料は、リポジトリ内に `Docs/` が無く既存資料が集約されている Obsidian 側 `InProgress/` に置く。
- `AdvBacklog` は上限管理だけを担当する `RefCounted`、`AdvBacklogEntry` は line の表示情報を保持する `RefCounted` とする。セーブ進行には含めない。
- `AdvPlayer` がオート・スキップ・バックログの状態を一元管理し、UI は `AdvBacklogView` の基底契約と signal だけを提供する。

## タスク

| 計画タスクID | 内容 | 完了条件 |
|--------------|------|----------|
| T-01 | `AdvBacklogEntry` と上限付き `AdvBacklog` を追加する | line の uid / 話者名 / 色 / 本文 / voice_path を保持でき、`backlog_max_entries` を超えた古い項目が捨てられ、上限 0 も安全に扱える |
| T-02 | `AdvBacklogView` 基底クラスと無装飾の参照実装を追加し、`AdvScene` / `AdvPlayer` に注入する | `present()` / `close()`、`closed` / `voice_replay_requested` の契約が成立し、標準シーンから差し替え可能な状態で取得できる |
| T-03 | `AdvPlayer` にオートモードを実装する | `set_auto_mode()` / `is_auto_mode()` と `auto_mode_changed` が成立し、line 完了後に `auto_wait_time` とボイス残時間の最大値を待って進み、advance / choice / backlog / 終端で解除される |
| T-04 | `AdvPlayer` に既読連動スキップを実装する | `start_skip()` / `stop_skip()` / `is_skipping()` と開始・停止 signal が成立し、押下中だけ継続、未読停止、選択肢停止、`apply_final()`、ボイス無再生、既読記録を満たす |
| T-05 | `AdvPlayer` にバックログ記録・開閉・ボイス再生を実装する | line 完了時だけ記録し、話題をまたいで保持し、`stop()` でクリアし、開いている間は advance を抑止し、設定が有効なときだけ同じ voice channel で replay できる |
| T-06 | phase06 のヘッドレステストと既存テストを追加・更新する | backlog 上限・line 記録・auto 待機・voice 待機・skip の既読/未読/choice/演出・backlog 開閉/replay を終了コード 0 で検証する |
| T-07 | 仕様書・README・フェーズ台帳・引継ぎ資料を更新する | phase06 の API、入力、制限、確認結果、未完了事項が事実ベースで記録される |

## 実装上の方針

- 入力は `AdvPlayer._unhandled_input()` に集約し、skip は `is_action_pressed` / `is_action_released` でホールド状態を管理する。UI は画面クリックを semantic signal として送るだけにする。
- スキップ中はタイプライタと音声を開始せず、各演出の `apply_final()` だけを適用する。`skip_interval` ごとに 1 ステップずつ処理し、既読連動で未読 line を表示した時点で停止する。
- オート待機・スキップ処理は `run_id` / 待機 token で中断後の古い await を無効化し、`Thread` / `WorkerThreadPool` は使用しない。
- バックログは `get_progress()` に入れない。`AdvBacklogView` が未接続でも進行を止めず、API と signal は利用できるようにする。
