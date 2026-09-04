# 引継ぎ資料: フェーズ02 runtime-playback

- 対象計画書: [plan-phase-02.md](plan-phase-02.md)
- 実装日 / セッション: 2026-09-03 / phase02実装セッション
- 対象リポジトリ: `C:\Users\kzr12\Root\MyProjects\AdvKit`
- エンジン: Godot 4.7.2-stable / Compatibility / GDScript

## 1. タスク別の結果

| ID | 結果 | 実装内容・受入条件の確認 |
|----|------|--------------------------|
| T-01 | 完了 | `adv_kit_plugin.gd` の `_enter_tree()` で `adv_advance` / `adv_skip` / `adv_auto` / `adv_backlog` を既定バインド付きで登録。既存の InputMap アクションは変更せず、`ProjectSettings` にも保存する。 |
| T-02 | 完了（API名差異） | `AdvIssue.make_location()` を追加し、`AdvScenarioValidator` が利用。計画書指定の `location()` は、`AdvIssue` のインスタンスフィールド `location` と同名にできないため採用不可だった。返却形式は指定どおり。 |
| T-03 | 完了 | `AdvPortrait` とシーンを追加。`apply()` 内でのみ `ResourceLoader.exists()` 後に `load()` し、空パスを安全に処理。pivot、スケール、フェード、退場後の解放を実装。 |
| T-04 | 完了 | `AdvStage` とシーンを追加。5スロットの比率配置、キャラクターごと1体制約、表示・更新・退場・取得・全消去、リサイズ追従を実装。 |
| T-05 | 完了 | 外観・Themeを持たない `AdvMessageWindow` 基底クラスを追加。4メソッドは基底では `push_error`、2 signalを宣言。 |
| T-06 | 完了 | 無装飾の `PlainMessageWindow` を追加。話者名 `Label` と BBCode 対応 `RichTextLabel`、`VC_CHARS_AFTER_SHAPING`、マウス・InputMap入力を実装。 |
| T-07 | 完了 | `AdvScene` のノード構成を追加。`ShakeRoot` はアンカー無しの中間ノード、`Background` / `Stage` は full-rect、`FadeLayer` は `MessageWindow` より前、`AdvPlayer` は別ノードとして配置。 |
| T-08 | 完了 | `AdvPlayer.setup()` / `play_topic()` / `stop()` / 状態取得と topic 終了処理、`topic_started` / `topic_finished` / `scenario_finished` を実装。存在しない topic はエラーで安全に終了。 |
| T-09 | 完了 | 話者を `book.characters` から解決し、暗黙の登場・更新を `AdvStage` 経由で実行。地の文は名前を空にし、ステージを変更しない。pose / expression / slot はキャラクターごとに保持。 |
| T-10 | 完了 | BBCodeタグを除いた表示文字数でタイプライタ時間を算出。`visible_ratio` を Tween で更新し、速度0・空文字・スキップ時は即時完了。`line_completed` の二重発火を防止。 |
| T-11 | 完了 | 表示中の `advance()` はタイプ完了、完了後は次ステップへ進む。MessageWindow signal と `settings.advance_action` / skip action を購読。入力連打で行が飛ばない構造。 |
| T-12 | 完了 | `AdvEffectStep` / `AdvChoiceStep` / `AdvJumpStep` と `parallel_effects` は今回無視して次へ進む。無視したことと実装予定 phase-03 / phase-05 を `push_warning` で通知。 |
| T-13 | 完了 | `tests/test_playback.gd` を追加。シーン構成、リサイズ、UI設定、立ち絵の暗黙登場、重複防止、全ステップ、signal回数、Tweenタイプライタを検証。 |
| T-14 | 完了 | `addons/adv_kit/README.md` とルート `README.md` に、インスタンス → `setup()` → `play_topic()` の利用方法、差し替え契約、未実装範囲、テスト手順を追記。 |

### DoD

- [x] T-01〜T-14 を実装・確認済み
- [x] `res://game/` 配下を変更していない
- [x] `core/` / `resources/` は Node 系に依存していない（`AdvIssue` のヘルパ追加を除きデータモデルは変更なし）
- [x] phase-01 テスト 157 件が全通過
- [x] `ui/` と参照実装に Theme を追加していない
- [x] 実行時の `reparent()` を使用していない
- [x] `load()` は `AdvPortrait.apply()` のみで使用し、事前に `ResourceLoader.exists()` を確認
- [x] `Thread` / `WorkerThreadPool` を使用していない
- [x] `AdvPlayer` は基底型の UI 参照だけを持ち、`get_parent()` を使用していない
- [x] 新規 GDScript は静的型注釈付き
- [x] import、phase-01 / phase-02 テスト、エディタ起動、Web export を確認

## 2. 特に報告してほしかった観点への回答

### 2.1 R-08: ヘッドレスで Tween / await が回るか — **回る**

`SceneTree` スクリプトの `_initialize()` からシーンを追加した直後は、子ノードの `_ready()` と `@onready` 解決がまだ完了していない。`test_playback.gd` ではシーン追加後に `await process_frame` を1回入れてから `AdvPlayer` を取得・利用している。

その後は `AdvPlayer` が作成した Tween が通常どおり進行し、`process_frame` を待つことでタイプライタが完了することを確認した。速度0の即時表示だけに依存せず、速度100の短い行で Tween 完了と `line_completed` を検証している。phase-03 の演出テストも同じく、シーンツリーへ Node を追加した直後の1フレーム待ちを前提にすること。

### 2.2 R-09: RichTextLabel の visible_ratio — **日本語 + BBCode で採用可能**

参照実装は `bbcode_enabled = true` と `TextServer.VC_CHARS_AFTER_SHAPING` を設定し、Kit側は `set_typing_progress(ratio)` で比率だけを渡している。BBCodeタグを除外した文字数で Tween の時間を計算し、RichTextLabel 側の `visible_ratio` に渡す構成で、phase-02 の日本語サンプルとテストは問題なく完了した。仕様書 §5.2 を文字数渡しへ変更する必要は現時点ではない。

### 2.3 R-10: リサイズ追従 — **問題なし**

`ShakeRoot` は計画どおりアンカー無しだが、`AdvScene.gd` がルートの `resized` 時に `position = Vector2.ZERO` と `size = size` を同期する。`ShakeRoot` の子の `Background` / `Stage` は full-rect のため、ルートサイズ変更後も追従する。`test_playback.gd` でサイズ変更後の寸法と Stage の追従を検証した。

### 2.4 R-11: 立ち絵の現在状態の保持場所 — **AdvPlayer に保持**

`AdvPlayer` がキャラクターごとに pose / expression / slot を保持し、`AdvStage` は表示ノードのライフサイクルと実座標だけを担当する。この分離により、暗黙の登場と同一キャラクターの差分更新を処理しやすかった。

一方、phase-05 の進行保存では uid だけでは絵を復元できない。セーブ・復元時には、現在の topic / step と合わせてキャラクターごとの pose / expression / slot も保存・復元対象にする必要がある。

### 2.5 R-12: 非 line ステップの素通り — **後続実装の差し替え箇所を限定**

非 line の分岐は `AdvPlayer._process_next_step()` に集約し、phase-03 の effect、phase-05 の choice / jump を個別処理へ置き換えられる形にした。現状は `push_warning` で行き先を明示してから次へ進むため、サンプル再生時に何も起きない箇所を未実装仕様と区別できる。

### 2.6 `AdvScene.tscn` の構成差分 — **実質なし**

仕様書 §5 のノード順と役割に合わせた。`ChoiceMenu` / `BacklogView` は計画どおり置いていない。`ShakeRoot` がアンカー無しのため、ルートのリサイズを `AdvScene.gd` で同期する補助処理だけ追加している。`FadeLayer` と ShakeRoot の演出処理は phase-03 の対象なので、phase-02 では FadeLayer の alpha 0 を維持し、ShakeRoot を移動させていない。

## 3. 仕様書・計画書からの逸脱・追加

### 3.1 `AdvIssue.location()` は `AdvIssue.make_location()` に変更

計画書では `static func location(...)` が指定されていたが、既存の `AdvIssue` に `location` というインスタンス変数がある。GDScript では同一クラス内で変数と関数に同じ名前を付けられないため、静的ヘルパーを `make_location()` とした。生成される文字列と Validator の利用目的は同じで、意味上の差異はない。

### 3.2 `project.godot` に InputMap を保存

`InputMap.add_action()` だけではプロジェクト設定ファイルへ永続化されないため、プラグイン登録時に `ProjectSettings.set_setting("input/...", ...)` も行うようにした。既存アクションの再登録はせず、ユーザーが追加したバインドを消さない。

### 3.3 テスト専用の Web smoke はリポジトリに残していない

Web export の実機確認用に一時 main scene、export preset、ローカル HTTP サーバーを用意し、`Build.html` をブラウザで起動して `AdvPlayer is running` まで確認した。一時ファイルと build 出力は削除済みで、製品側の main scene や `export_presets.cfg` は追加していない。phase-08 で正式なサンプルと export 設定を整備する。

## 4. 実装していないもの（スコープどおり）

- 演出ハンドラ、FadeLayer の実フェード、ShakeRoot の揺れ、立ち絵移動
- voice 再生、非話者ダーク、話者交代ホップ
- 選択肢、goto、フラグ、進行保存・復元
- オート、スキップモード、バックログ
- `AdvChoiceMenu` / `AdvBacklogView` の基底クラス
- インポータ、エディタ Dock、GAS、正式な Web サンプル

## 5. 設計判断と後続フェーズへの注意

- `AdvPlayer` は UI ノードを直接操作せず、`AdvStage` と `AdvMessageWindow` の基底型 API だけを呼ぶ。
- `AdvStage` は character_id ごとに `AdvPortrait` を1体だけ保持する。表示ノードの生成・更新・退場・破棄は Stage の責務。
- `ShakeRoot` のサイズ同期は、アンカー無し中間ノードと full-rect 子ノードを両立するためのもの。phase-03 の shake はこのノードの position を対象にする。
- `PlainMessageWindow` は Theme を持たず、ゲーム側が `MessageWindow` を差し替える前提。差し替えクラスは4メソッドを実装し、必要に応じて2 signalを発火する。
- `step_shown` は line だけでなく素通りした非 line ステップにも発火する。`line_completed` は line のタイプ完了時だけ発火する。
- 非 line の warning は同一ホストの parallel effect について重複を避ける。phase-03 / phase-05 で処理を実装する際は、この分岐と warning を置き換える。
- phase-03 の演出ハンドラは、仕様書の排他ターゲット規約に従い、自分の対象を操作する前に実行中 Tween を `kill()` すること。これはステップをまたぐ重なりや拡張演出を「後から始まった方が勝つ」に固定するために必要。
- `AdvPlayer` の pose / expression / slot 保持は phase-05 の進行保存設計に直結する。uid だけの保存では画面状態を復元できない。
- 実行時の `load()` は `AdvPortrait.apply()` に限定している。phase-03 以降で動的リソースを追加ロードする場合も、この制約を崩さないこと。

## 6. 既知の問題・制約

- Godot 終了時に phase-01 から継続して `AdvStep` のスクリプト型自己参照に由来する `ObjectDB instances leaked` / `resources still in use` が出る。各テストの終了コードは 0 で、実行中の再生には影響していない。CI は stderr ではなく終了コードで判定すること。
- サンプル `sample_scenario.json` には実テクスチャがないため、ヘッドレスの Stage テストでは立ち絵ノードの存在・状態・配置を検証し、画像の見た目は確認していない。空パス・欠損パスでも進行が止まらない仕様によるもの。
- 開発プロジェクトには正式な main scene がまだない。phase-02 の自動テストは `AdvScene.tscn` を直接追加して実行し、Web確認だけ一時 smoke scene を使用した。
- `AdvIssue.location()` という名前そのものが必要になった場合は、インスタンスフィールド名を変更する設計判断が別途必要。

## 7. テスト結果

実行したコマンドと結果:

```text
godot --headless --path . --import
  exit 0

godot --headless --path . --script res://addons/adv_kit/tests/test_scenario_parse.gd
  157 件実行 / 成功 157 / 失敗 0 / exit 0

godot --headless --path . --script res://addons/adv_kit/tests/test_playback.gd
  OK / exit 0

新規 GDScript 9ファイルの --check-only
  全ファイル exit 0

godot --headless --editor --path . --quit-after 5
  exit 0

git diff --check
  問題なし
```

`test_playback.gd` では、サンプル topic の7ステップ、4行の `line_completed`、7回の `step_shown`、立ち絵3体、重複登場防止、地の文のステージ非変更、Tweenタイプライタを確認した。非 line ステップの warning は計画された挙動。

Web については、Godot 4.7.2 の公式 export template を環境へ導入後、一時 preset で `Build.html` / `Build.pck` を生成し、ローカル HTTP サーバー経由で Codex のブラウザから起動した。画面上の `Web export OK` と `AdvPlayer is running`、WebGL Compatibility の起動ログを確認し、アプリ由来のエラー・警告は無かった。

## 8. phase-03 への申し送り

1. `AdvPlayer._process_next_step()` の非 line 分岐を、`AdvEffectStep` の effect dispatch と `parallel_effects` の同期処理へ置き換える。`AdvEffectStep` / `parallel_effects` の要素型は現状 `AdvStep` なので、読み出し時に `as AdvEffectStep` の確認を行う。
2. `FadeLayer`、`ShakeRoot`、`AdvPortrait` の fade / position API は phase-03 から利用できる。Tween競合時は排他ターゲット単位で先行Tweenを kill する。
3. `voice_path` は `AdvLineStep` に既に存在するが phase-02 では読んでいない。未指定でも行送りを止めない `AdvVoicePlayer` を追加する。
4. phase-05 の `get_progress()` / `restore_progress()` では、現在 step だけでなく `AdvPlayer` が保持するキャラクター別 pose / expression / slot と stage の表示状態を復元する。
5. phase-03 計画書を作成する際は、R-08 の解消方法（シーン追加後の `await process_frame`）を演出テストの前提として記載する。
6. `project.godot` には phase-02 の4 InputMap アクションが入っている。正式な Web export preset と main scene は phase-08 のスコープで追加する。

