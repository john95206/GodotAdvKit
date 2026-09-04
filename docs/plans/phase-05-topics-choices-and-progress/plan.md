# 実装計画: phase-05 topics-choices-and-progress

- **対象仕様**: `adv-kit-spec.md` §4.3 / §4.7 / §4.8 / §5.3 / §5.4 / §9.1
- **目的**: 選択肢と話題遷移を実際の再生へ接続し、フラグ・条件式・既読集合を扱える進行状態と、UID ベースの保存・復元を提供する。
- **前提**: phase-04 の `AdvPlayer`、`AdvStage`、`AdvScene`、`AdvKitSettings`、`AdvCondition` が利用できること。unityroom/Web 前提のため、GDScript・Compatibility・単一スレッドの制約を維持する。

## 着手前の判断

### U-04（条件式の括弧）

phase-05 では括弧を追加せず、既存の `!` / `&&` / `||` / 識別子だけの文法を維持する。phase-01 で確定した `&&` 優先の評価と、既存のシナリオ互換性を優先する。現時点の phase05 受入条件に括弧を必要とする具体的なシナリオがなく、文法を拡張する場合は別フェーズで仕様・移行・エラー表示をまとめて見直す。

### 進行データと立ち絵状態

`get_progress()` の既存4項目（`topic_id`、`step_uid`、`flags`、`read_steps`）を維持し、前フェーズの申し送りに従って任意の `portrait_states` を追加する。`portrait_states` はキャラクター ID をキーとし、現在表示中の pose / expression / slot / modulate を素の `String`・`float`・配列で保持する。これにより、新しい `step_index` を永続化せず、別シーンへロードしても表示状態を復元できる。

## タスク

| 計画タスクID | 内容 | 完了条件 |
|--------------|------|----------|
| T-01 | `AdvProgressState`（`RefCounted`）を追加し、topic / step UID / flags / read steps を保持・JSON 化可能な辞書へ変換する | 既読集合は内部で `Dictionary[StringName, bool]`、境界でのみ `PackedStringArray` と `String` キーへ変換され、欠損した `read_steps` を含む入力を安全に復元できる |
| T-02 | `AdvChoiceMenu` 基底クラスと無装飾の参照 UI を追加し、`AdvScene` と `AdvPlayer` へ注入点を用意する | `present(prompt, options)` / `close()` / `option_chosen` の契約が成立し、条件を通過した選択肢だけが UI へ渡る |
| T-03 | `AdvPlayer` にフラグ・条件評価・choice 選択・jump・topic 間遷移を実装する | 選択時の flag 設定、空 goto の同一 topic 継続、goto 指定時の topic 遷移、条件偽の jump の素通り、topic/scenario signal が正しく発火する |
| T-04 | `AdvPlayer` に line の既読記録と UID ベースの `get_progress()` / `restore_progress()` を実装する | タイプライタ完了時だけ line UID が既読になり、`step_index` を保存せず、復元後に保存位置から再生できる。立ち絵状態も復元できる |
| T-05 | phase05 のヘッドレステストを追加し、既存テストを新しい choice / goto の挙動へ追従させる | 条件フィルタ、選択、flag、jump、複数 topic、既読・保存・復元、ChoiceMenu 契約を検証して終了コード 0 |
| T-06 | 仕様書・README・フェーズ台帳・引継ぎ資料を更新する | phase05 の API、保存形式、制限、U-04 判断、確認結果が事実ベースで記録される |

## 実装上の方針

- `AdvProgressState` は `core/` に置き、`Node` / `SceneTree` / `await` に依存させない。
- `AdvPlayer` は `AdvChoiceMenu` の基底型だけを参照し、UI へ条件判定を漏らさない。UI からの通知は signal で受ける。
- choice は選択肢表示中に進行を止め、選択結果を検証してから `choice_selected` を発火する。対象外の index は無視して進行を壊さない。
- line の `line_completed` 発火直前に既読を記録する。途中の `advance()` でタイプライタを完了した場合も同じ経路にする。
- topic の遷移先は単一 `AdvScenarioBook` 内で解決し、見つからない場合は警告・安全終了とする。シーン遷移はゲーム側へ任せる。
- `restore_progress()` は現在の Book がある場合に保存 topic を再生し、step UID が存在すればその step から再開する。未知の topic / UID でも例外を投げず、flags / read_steps は復元する。
- `portrait_states` は追加フィールドとして扱い、存在しない旧形式の進行データも受け入れる。`step_index` は保存しない。
- 新しい UI に Theme や外部依存を追加しない。Web での動作確認は phase04 と同じく一時 export を使い、正式サンプルと preset は phase08 の範囲に残す。
