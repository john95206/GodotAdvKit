# 引継ぎ資料: フェーズ04 auto-direction

- **対象計画書**: `InProgress/plan-phase-04.md`
- **実装日 / セッション**: 2026-09-04 / 1

## 1. 実装済み内容（タスクID対応）

| 計画タスクID | 状態 | 実装した内容 / 変更したファイル |
|--------------|------|--------------------------------|
| T-01 | 完了 | `AdvStage.get_character_ids()` を追加し、`AdvPortrait.set_modulate_rgb()` で alpha を保持した RGB 色変更を可能にした。変更: `addons/adv_kit/ui/adv_stage.gd`, `addons/adv_kit/ui/adv_portrait.gd` |
| T-02 | 完了 | `AdvPlayer` が `_last_speaker_id` を保持し、話者交代時に全立ち絵を話者=白／非話者=`dim_color` へ Tween する処理を追加した。`dim_non_speakers`、`dim_duration`、`dim_color` を使用する。変更: `addons/adv_kit/runtime/adv_player.gd` |
| T-03 | 完了 | 話者交代時に対象立ち絵を `hop_height` だけ上へ移動して元位置へ戻す非同期 Tween を追加した。`hop_on_speaker_change`、`hop_height`、`hop_duration` を使用し、`portrait_position:{character_id}` を既存の立ち絵移動演出と共有する。変更: `addons/adv_kit/runtime/adv_player.gd` |
| T-04 | 完了 | `test_auto_direction.gd` を追加し、暗黙の登場、非話者ダーク、ホップ、Tween 排他、同一話者、地の文、設定無効化を検証した。変更: `addons/adv_kit/tests/test_auto_direction.gd`, `.uid` |
| T-05 | 完了 | ルート README、アドオン README、フェーズ台帳、phase04 計画書、引継ぎ資料を更新した。変更: `README.md`, `addons/adv_kit/README.md`, `InProgress/INDEX.md`, `InProgress/plan-phase-04.md`, 本ファイル |

## 2. 計画との差分

計画で想定した API と動作は実装した。差分は以下のとおり。

| 項目 | 計画 | 実際 | 理由 |
|------|------|------|------|
| 計画書の配置 | phase04 計画書を用意して着手 | 既存の `Docs/` ではなく、README が source of truth と示す Obsidian 側 `InProgress/plan-phase-04.md` を追加 | このリポジトリには `Docs/` が存在せず、先行フェーズの計画・引継ぎも同じ資料置き場にあるため |
| 色 Tween の所有 | RGB 色変更 API を追加 | `AdvPlayer` が `AdvEffectContext.acquire_tween()` で Tween を生成し、`AdvPortrait.set_modulate_rgb()` を呼ぶ | alpha は暗黙の登場・退場と共有するため、`modulate` 全体を書き換えない必要がある。既存の Tween 排他台帳も利用できる |
| ホップの Tween 所有 | 話者交代時にホップ | `AdvPlayer` が位置 Tween を生成し、既存の `portrait_position:{character_id}` ターゲットに登録 | `move_portrait` と位置を共有し、後から始まった演出が勝つという phase03 の規約に合わせるため |

## 3. 未完了・残タスク

| 内容 | 未完了の理由 | 次フェーズで必要か |
|------|--------------|--------------------|
| 実素材の立ち絵を含む見た目の通し確認 | テスト用シナリオは意図的にテクスチャを持たず、Web スモークも無素材で実行した | 不要（phase08 のサンプル整備時に確認） |
| 正式な Web export preset / main scene の追加 | phase02 からの方針どおり、今回の Web 確認は一時ファイルだけで実施し、正式サンプルは phase08 のスコープに残した | 要（phase08） |

## 4. 発生した問題・既知の不具合

| 症状 | 再現条件 | 暫定対応 / 未対応 |
|------|----------|-------------------|
| Godot CLI が `AppData` の editor data / log / root certificate store を開けない旨を出力する | この実行環境で `godot --headless` を実行 | 終了コードは各回 0。テスト判定は終了コードで行う。既存の環境制約として未対応 |
| `ObjectDB instances leaked` / `resources still in use` が終了時に出る | phase01 以降の headless テスト終了時 | `AdvStep` の型自己参照に由来する既知の挙動。実行中のテストには影響せず、終了コードは 0 |
| `Voice` オーディオバスが無いため `Master` にフォールバックする警告 | 開発プロジェクトの既定オーディオバスでテストを実行 | 仕様どおりのフォールバック。ゲーム側で `Voice` バスを用意すれば警告は出ない |

## 5. 設計・実装上の判断

- 話者交代は `speaker_id != _last_speaker_id` で判定し、`play_topic()`、`setup()`、`stop()` で直前話者をリセットした — topic の先頭話者を新しい話者として扱い、topic 間の状態を持ち越さないため。
- 地の文（空の `speaker_id`）では `_last_speaker_id` を更新せず、ダークとホップを開始しない — 仕様書 §8 の「直前の話者の明暗状態を維持」に合わせるため。
- 非話者ダークは `modulate` の RGB だけを補間し alpha を維持する — 暗黙の登場・退場の alpha Tween と競合させないため。
- 色 Tween の排他ターゲットを `portrait_modulate:{character_id}`、ホップを `portrait_position:{character_id}` とした — 同一対象の Tween を `AdvEffectContext` が停止・後始末でき、移動演出との競合も「後から始まった方が勝つ」に統一できるため。
- 未知の話者では汎用演出を開始しない — 既存の unknown speaker の警告のみで進行を止めない方針を維持するため。

## 6. 依存・環境・前提の変化

- 追加した外部依存: 該当なし。
- Godot 4.7.2-stable / Compatibility / GDScript の前提に変更なし。
- Web 確認では Godot 4.7.2 の `web_nothreads_release` template がホスト側に存在したため、一時 preset で export できた。正式な `export_presets.cfg` は追加していない。

## 7. 動作確認状況

- **確認済み**:
  - `godot --headless --path . --import` — 終了コード 0。
  - `test_scenario_parse.gd` — 157 件実行 / 成功 157 / 失敗 0 / 終了コード 0。
  - `test_playback.gd` — `OK` / 終了コード 0。
  - `test_effects.gd` — 88 件実行 / 成功 88 / 失敗 0 / 終了コード 0。
  - `test_auto_direction.gd` — 24 件実行 / 成功 24 / 失敗 0 / 終了コード 0。
  - 一時 `Build.html` を Godot 4.7.2 / Web / Compatibility / single-threaded で export。ローカル HTTP 経由の Codex ブラウザーで起動し、Alice の表示、クリック後の Bob へのテキスト送り、起動ログの WebGL Compatibility と single-threaded を確認した。
  - `git diff --check` — 問題なし。
- **未確認**: 実素材の立ち絵を用いた視覚的な暗転量・ホップ量の最終調整、正式サンプルの Web 通しプレイ。いずれも phase08 の対象。

## 8. 次フェーズへの申し送り

- phase05 では `AdvPlayer` の `_last_speaker_id` と Stage の表示状態を、話題遷移・進行保存との整合を確認する。`get_progress()` に `step_index` を入れず、必要なら立ち絵状態を別途保存する phase02/03 の方針を維持する。
- `AdvEffectContext` のターゲット名 `portrait_position:{character_id}` は `move_portrait` と共有している。ホップや立ち絵移動を追加変更する際も、同じ対象を書き換える Tween は `acquire_tween()` 経由にする。
- `AdvPortrait.set_modulate_rgb()` は alpha を意図的に維持する API である。退場・暗黙の登場の alpha を変更する処理へ流用しない。
- 正式な Web export preset と main scene は phase08 で整備する。今回のスモーク用ファイルはすべて削除済みで、`project.godot` に main scene の変更は残っていない。
