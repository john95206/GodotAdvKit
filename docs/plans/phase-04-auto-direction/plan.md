# 実装計画: phase-04 auto-direction

- **対象仕様**: `adv-kit-spec.md` §4.6 / §8
- **目的**: シナリオデータに依存しない汎用演出として、話者交代時の非話者ダークと話者交代ホップを `AdvKitSettings` で制御できるようにする。
- **前提**: phase-03 の `AdvPlayer`、`AdvStage`、`AdvPortrait`、`AdvEffectContext` が利用できること。

## タスク

| 計画タスクID | 内容 | 完了条件 |
|--------------|------|----------|
| T-01 | `AdvStage` / `AdvPortrait` に、ステージ上の立ち絵列挙と RGB 色適用に必要な最小 API を追加する | 立ち絵の alpha を壊さずに色だけを変更でき、話者一覧を `AdvPlayer` から取得できる |
| T-02 | `AdvPlayer` に話者変化の追跡を追加し、`dim_non_speakers` / `dim_color` / `dim_duration` を使った非話者ダークを実装する | 話者は白、非話者は設定色へ Tween。地の文では明暗を変更せず、同一話者の連続発話でも再適用しない |
| T-03 | `AdvPlayer` に `hop_on_speaker_change` / `hop_height` / `hop_duration` を使った話者交代ホップを実装する | 話者交代時だけ対象立ち絵が上方向へ移動して元位置へ戻り、BLOCKING にならない。暗黙の登場にも適用される |
| T-04 | phase04 専用のヘッドレステストを追加し、既存テストと合わせて実行する | 有効化・無効化、同一話者、地の文、交代、Tween 完了、位置排他を検証して終了コード 0 |
| T-05 | アドオン README、フェーズ台帳、引継ぎ資料を更新する | phase04 の使い方・制限・確認結果が事実ベースで記録される |

## 実装上の方針

- 色 Tween は `modulate` 全体ではなく RGB のみを書き換え、暗黙の登場・退場が管理する alpha を維持する。
- 汎用演出の Tween も `AdvEffectContext.acquire_tween()` に登録し、色は `portrait_modulate:{character_id}`、位置は既存の `portrait_position:{character_id}` を排他ターゲットにする。
- 地の文（`speaker_id == ""`）は直前話者を保持し、話者変化として扱わない。
- 未知の話者は既存の phase-03 方針どおり警告のみとし、汎用演出で進行を止めない。
