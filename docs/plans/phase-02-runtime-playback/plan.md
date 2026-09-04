# 実装計画書: フェーズ02 runtime-playback

## 1. フェーズ概要

- **ゴール**: `AdvScene.tscn` をゲーム側がインスタンスし、`AdvPlayer.setup()` → `play_topic()` を呼ぶと、
  **立ち絵付きのテキストがタイプライタ表示され、テキスト送りで最後まで進む**状態にする。
  ADV として最低限遊べるところまで。UI は**外観を持たない基底クラス＋無装飾の参照実装**。
- **仕様書の該当箇所**: §5（シーン構成）、§5.1（前後関係）、§5.2（タイプライタ）、§5.3（`AdvPlayer` の公開 API）、§5.4（UI の差し替え契約）、§4.2（立ち絵の解決）、§4.6（入力アクション）、§7 の「暗黙の登場」
- **前提フェーズ**: phase-01（完了）。`AdvScenarioBook` / `AdvTopic` / `AdvLineStep` / `AdvPortraitSet` / `AdvKitSettings` がそのまま使える

このフェーズには**演出も選択肢も進行データも含まない**。「テキストが立ち絵とともに出て、送れる」だけを作る。
phase-01 で `core/` が Node 非依存で固まっているので、ここでは**表示と入力**だけを足す。

## 2. スコープ

### 対象

- `adv_kit_plugin.gd` への **InputMap 自動登録**（仕様書 §4.6。phase-01 から持ち越し）
- `ui/adv_portrait.tscn` / `.gd` — 立ち絵1体。テクスチャの**遅延ロード**、pivot、スケール
- `ui/adv_stage.tscn` / `.gd` — スロット→実座標の解決、立ち絵の生成・取得・退場、**暗黙の登場**
- `ui/adv_message_window.gd` — **外観を持たない基底クラス**（仕様書 §5.4 の契約）
- `ui/adv_scene.tscn` / `.gd` — §5 のノード構成
- `runtime/adv_player.gd` — `setup` / `play_topic` / `advance` / `skip_typing` / `stop`、タイプライタ制御、signal
- `samples/ui/plain_message_window.tscn` / `.gd` — 無装飾の参照実装
- `core/adv_issue.gd` に location 組み立てヘルパを1つ追加（phase-01 からの持ち越し・軽微）
- `tests/test_playback.gd` — `--headless` で走る再生テスト
- `addons/adv_kit/README.md` の更新

### 対象外（今回やらない）

- **演出ハンドラ一切**（`runtime/effects/` を作らない。phase-03）。
  `AdvEffectStep` に出会っても**何もせず次のステップへ進む**（`parallel_effects` も無視する）
- **ボイス**（`AdvVoicePlayer`。phase-03）。`voice_path` は読むだけで再生しない
- **非話者ダーク・話者交代ホップ**（phase-04）。`dim_*` / `hop_*` 設定は読まない
- **選択肢の提示と `goto` の遷移**（phase-05）。
  `AdvChoiceStep` / `AdvJumpStep` に出会っても**素通りする**。`AdvChoiceMenu` の基底クラスも作らない
- **フラグ・条件式の評価**（phase-05）。`AdvPlayer.set_flag` / `has_flag` も作らない
- **`AdvProgressState` / `get_progress` / `restore_progress`**（phase-05）
- **オート・スキップ・バックログ**（phase-06）。`AdvBacklogView` の基底クラスも作らない
- **`FadeLayer` の実際のフェード動作**（phase-03）。ノードは `AdvScene.tscn` に置くが、alpha 0 のまま誰も触らない
- **`ShakeRoot` の揺れ動作**（phase-03）。ノード構成だけ用意する
- インポータ / エディタ Dock / GAS（phase-07）

> **`AdvChoiceMenu` / `AdvBacklogView` を今回作らない理由**: 仕様書 §5.4 に契約はあるが、
> 実際に呼ぶ側（選択肢の提示、バックログの開閉）が phase-05 / 06 にある。
> 基底クラスだけ先に置くと、呼び出し側を書くときに必ず形が変わる。
> `AdvScene.tscn` には**空のプレースホルダを置かず**、phase-05 / 06 でノードごと足す。

## 3. 影響範囲

- **新規**: `addons/adv_kit/ui/`、`addons/adv_kit/runtime/`、`addons/adv_kit/samples/ui/`
- **変更**: `adv_kit_plugin.gd`（InputMap 登録）、`core/adv_issue.gd`（ヘルパ追加）、`README.md`
- **`res://game/` 配下には一切触れない**
- **`core/` と `resources/` は今回も変更しない**（`adv_issue.gd` のヘルパ追加を除く）。
  phase-01 で固めたデータモデルは**このフェーズで変えない**。変えたくなったら、それは設計の誤りなので handover に書く
- **`ui/` と `runtime/` は `core/` に依存してよい。逆は禁止**（`core/` は `Node` を知らないまま保つ）

## 4. 新規に定義する契約

### `AdvMessageWindow`（`ui/adv_message_window.gd`）

仕様書 §5.4 のとおり。**外観を持たない。`Theme` を持たない。**

```gdscript
class_name AdvMessageWindow extends Control
# 派生クラスが実装する（基底は push_error して何もしない）
func show_line(speaker_name: String, name_color: Color, text: String) -> void
func set_typing_progress(ratio: float) -> void
func complete_typing() -> void
func clear() -> void
# 派生クラスが出す
signal advance_requested()
signal skip_typing_requested()
```

### `AdvStage`（`ui/adv_stage.gd`）

```gdscript
class_name AdvStage extends Control
enum Slot { LEFT, CENTER_LEFT, CENTER, CENTER_RIGHT, RIGHT }

## スロット名 -> ステージ幅に対する比率。@export で差し替え可能
@export var slot_ratios: Dictionary[StringName, float]

func show_character(character: AdvCharacter, pose: StringName, expression: StringName,
        slot: StringName, duration: float) -> void
func update_character(character: AdvCharacter, pose: StringName, expression: StringName,
        slot: StringName) -> void   # 既に居るキャラの差分・位置を更新する（フェード無し）
func hide_character(character_id: StringName, duration: float) -> void
func has_character(character_id: StringName) -> bool
func get_portrait(character_id: StringName) -> AdvPortrait
func clear() -> void
static func is_valid_slot(slot: StringName) -> bool
```

- **スロットの既定比率**: `left=0.15` / `center_left=0.325` / `center=0.5` / `center_right=0.675` / `right=0.85`。
  実座標は `size.x * ratio`。**縦は常にステージ下端**（`AdvPortraitSet.pivot_offset_ratio` が足元中央を指す前提）
- `AdvStage` は `AdvPortrait` を**生成・保持・破棄する**。`AdvPlayer` はノードを直接触らない

### `AdvPortrait`（`ui/adv_portrait.gd`）

```gdscript
class_name AdvPortrait extends Control
var character_id: StringName
func apply(texture_path: String, pivot_offset_ratio: Vector2, portrait_scale: float) -> void
func set_slot_position(position_x: float, base_y: float) -> void
func fade_in(duration: float) -> void
func fade_out_and_free(duration: float) -> void
```

- **テクスチャは `AdvPortrait.apply()` の中でだけ `load()` する。** `Resource` 側は絶対にロードしない
- `texture_path` が空文字なら**何も表示せず、エラーも出さない**（立ち絵無しキャラ。進行は止めない）

### `AdvPlayer`（`runtime/adv_player.gd`）

phase-02 で実装するのは仕様書 §5.3 のうち以下だけ。

```gdscript
class_name AdvPlayer extends Node
@export var stage: AdvStage
@export var message_window: AdvMessageWindow

func setup(book: AdvScenarioBook, settings: AdvKitSettings) -> void
func play_topic(topic_id: StringName) -> void
func advance() -> void
func skip_typing() -> void
func stop() -> void
func is_playing() -> bool
func is_typing() -> bool

signal topic_started(topic_id: StringName)
signal topic_finished(topic_id: StringName)
signal step_shown(topic_id: StringName, step_uid: StringName)
signal line_completed(topic_id: StringName, step_uid: StringName)
signal scenario_finished()
```

- **`register_effect` / フラグ / プレイ支援 / セーブ / 選択肢の signal は今回作らない。**
  シグネチャだけ先に置くこともしない（空実装は「動くように見えて動かない」ので害の方が大きい）

## 5. タスク分解

| ID | タスク | 受け入れ条件 | 依存 |
|----|--------|--------------|------|
| T-01 | `adv_kit_plugin.gd` の `_enter_tree()` で InputMap の4アクション（`adv_advance` / `adv_skip` / `adv_auto` / `adv_backlog`）を既定バインド付きで登録する。**既に定義済みなら触らない**（仕様書 §4.6） | エディタでプラグインを有効化するとプロジェクト設定の InputMap に4アクションが現れる。既存のバインドを手で足した状態で再度有効化しても、そのバインドが消えない。無効化しても消さない | - |
| T-02 | `core/adv_issue.gd` に `static func location(topic_id: StringName, step_index: int, suffix: String = "") -> String` を足す。`"topics/<id>/steps[<i>]<suffix>"` を返す | 既存の呼び出し側（`AdvScenarioValidator`）を置き換えても phase-01 のテスト 145 件が全通過する | - |
| T-03 | `ui/adv_portrait.tscn` / `.gd` を作る。中身は `TextureRect` 1枚。`apply()` で `ResourceLoader.exists()` を確認してから `load()` する。空パスは何も表示しない。`fade_in` / `fade_out_and_free` は `Tween` で `modulate.a` を動かす | 空パスを渡してもエラーが出ず、ノードは残る（サイズ 0）。`fade_out_and_free()` 完了後にノードが解放されている。`pivot_offset_ratio` が `(0.5, 1.0)` のとき、指定した x 座標に立ち絵の**中央下端**が来る | - |
| T-04 | `ui/adv_stage.tscn` / `.gd` を作る。スロット比率表、`show_character` / `update_character` / `hide_character` / `has_character` / `get_portrait` / `clear`。立ち絵は `character_id` をキーに 1 体まで | 5 スロットすべてで期待した x 座標に置かれる。同じキャラを 2 回 `show_character` しても 2 体にならない。ステージのリサイズ後も比率どおりの位置に追従する（`resized` を購読して再配置する） | T-03 |
| T-05 | `ui/adv_message_window.gd`（基底クラス）を作る。4 メソッドは**基底では `push_error` して何もしない**。2 signal を宣言する。**`Theme` を持たない。`.tscn` も作らない** | 基底のまま `show_line()` を呼ぶと `push_error` が出る。派生クラスが 4 メソッドを実装すれば `AdvPlayer` から使える | - |
| T-06 | `samples/ui/plain_message_window.tscn` / `.gd` を作る。`RichTextLabel`（`bbcode_enabled = true`、`visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING`）と話者名の `Label` だけ。`set_typing_progress(ratio)` は `visible_ratio` に代入。`_gui_input` / `_unhandled_input` で `advance_requested` を出す | 無装飾のまま日本語と BBCode が表示され、`set_typing_progress(0.5)` でおよそ半分が見える。**Kit 側の `Theme` を参照していない** | T-05 |
| T-07 | `ui/adv_scene.tscn` / `.gd` を作る。仕様書 §5 のノード構成。`ShakeRoot` は**アンカー無しの中間ノード**、その子を full-rect にする。`FadeLayer` は `MessageWindow` より前の兄弟。`MessageWindow` には `samples/ui/plain_message_window.tscn` を差しておく（ゲーム側が差し替える） | ウィンドウをリサイズしても背景とステージが全画面に追従する。`FadeLayer` の alpha を 1 にするとメッセージウィンドウは隠れない。`AdvScene.gd` は `AdvPlayer` への参照を `@export` で持つだけで、UI の子構成を組み替えない | T-04, T-06 |
| T-08 | `runtime/adv_player.gd` の骨格を作る。`setup` / `play_topic` / `stop` / `is_playing`、ステップの取り出し、`topic_started` / `topic_finished` / `scenario_finished` の発火。**この時点では `AdvLineStep` を「表示せずに数えるだけ」でよい** | `play_topic()` で `topic_started` が 1 回、topic の末尾で `topic_finished` と `scenario_finished` が 1 回ずつ出る。存在しない topic_id を渡すと `push_error` して何も起きない（クラッシュしない） | T-02 |
| T-09 | `AdvPlayer` に `AdvLineStep` の表示を足す。話者の解決（`book.characters`）、`AdvStage` への反映（**暗黙の登場**: 未登場なら `show_character`、登場済みなら `update_character`）、`AdvMessageWindow.show_line()` の呼び出し、`step_shown` の発火。**`slot` が空なら現在位置を維持し、初出なら `center`**。`expression` / `pose` が空なら現在値を維持する（`AdvPlayer` がキャラごとの現在値を持つ） | 立ち絵付きの行で `AdvStage` に立ち絵が 1 体増える。地の文（`speaker_id` 空）では名前欄に空文字が渡り、ステージは変化しない。立ち絵無しキャラでも進行が止まらない | T-04, T-08 |
| T-10 | タイプライタ表示を足す。`duration = BBCode 除去後の表示文字数 / typing_speed`。`typing_speed == 0` なら `Tween` を使わず即 `complete_typing()`。`set_typing_progress(ratio)` を毎フレーム渡す。完了時に `line_completed` を発火。`skip_typing()` で即時完了 | `typing_speed = 40` で 20 文字の行がおよそ 0.5 秒かけて表示される。表示中に `skip_typing()` を呼ぶと即座に全文が出て `line_completed` が 1 回だけ出る。**BBCode タグは文字数に数えない** | T-09 |
| T-11 | `advance()` と入力処理を足す。表示中なら `skip_typing()`、表示完了後なら次ステップへ。`AdvMessageWindow` の `advance_requested` / `skip_typing_requested` を購読する。`AdvPlayer` は `_unhandled_input` で `settings.advance_action` も受ける | テキスト送り 1 回で「表示完了 → 次の行」の 2 段階が正しく進む。入力を連打しても行が飛ばない | T-10 |
| T-12 | 非 `line` ステップの扱いを足す。`AdvEffectStep` / `AdvChoiceStep` / `AdvJumpStep` は**何もせず次のステップへ進む**。`parallel_effects` も無視する。**素通りしたことを `push_warning` で 1 回だけ知らせる**（phase-03 / 05 で実装されることを明示する文言） | サンプルシナリオ（`prologue_01`）を通しで再生でき、effect と choice で止まらない。警告文に「phase-03 で実装」等の行き先が書いてある | T-11 |
| T-13 | `tests/test_playback.gd`（`extends SceneTree`）を作る。`AdvScene.tscn` を `root` に足し、サンプルの `prologue_01` を頭から末尾まで `advance()` で進める。`typing_speed = 0`（即時表示）で走らせて `await` を最小にする | `godot --headless --script res://addons/adv_kit/tests/test_playback.gd` が終了コード 0。行数・`step_shown` の発火回数・立ち絵の増減・`scenario_finished` の 1 回発火を検証する | T-12 |
| T-14 | `README.md` を更新する。`AdvScene` の使い方（インスタンス → `setup` → `play_topic`）、`AdvMessageWindow` の差し替え方、この時点で動かないもの（演出・選択肢・ボイス）を明記する | 仕様書を読まなくても、ゲーム側が `AdvScene` を組み込んで1本の topic を再生できる | T-13 |

## 6. 完了定義（DoD）

- [ ] T-01〜T-14 の全受け入れ条件を満たす
- [ ] `res://game/` 配下に一切ファイルを作っていない
- [ ] **`core/` と `resources/` が `Node` / `Control` / `SceneTree` を参照していない**（phase-01 から維持）
- [ ] **phase-01 のテスト（`test_scenario_parse.gd`）が 145 件そのまま通る**（データモデルを壊していない）
- [ ] `ui/` に `Theme` が 1 つも無い。`samples/ui/` の参照実装も無装飾
- [ ] **実行時の `reparent()` を呼んでいない**（仕様書 §5.1）
- [ ] `load()` を呼ぶのは `AdvPortrait.apply()` の中だけ。`ResourceLoader.exists()` で確認してから呼ぶ
- [ ] `Thread` / `WorkerThreadPool` を使っていない
- [ ] `AdvPlayer` が UI ノードを**基底型でのみ**参照している。`get_parent()` を辿っている箇所が無い
- [ ] 引数名に `name` を使っていない（`SHADOWED_VARIABLE_BASE_CLASS` 回避）
- [ ] 全 GDScript が静的型注釈付き
- [ ] `godot --headless --import` の後、`test_scenario_parse.gd` と `test_playback.gd` が**両方とも終了コード 0**
- [ ] エディタで警告が出ていない

## 7. 実装者への指示

- 実装完了後、`InProgress/handover.md` を phase-01 と同じ構成で **`handover-phase-02.md`** として作成する。
  全セクションを埋め、上記タスクIDに対応づけて報告する。
- **特に報告してほしい観点**:
  - **ヘッドレスでの `Tween` / `await` の挙動**。`SceneTree` スクリプトから `create_tween()` が使えるか、
    フレームを回すために何が必要だったか。**phase-03 の演出テストが全部ここに乗るので、踏んだ罠は全部書く**
  - **`RichTextLabel.visible_ratio` と日本語 + BBCode の組み合わせ**。
    `VC_CHARS_AFTER_SHAPING` で意図どおりになったか。ならなかった場合、
    Kit 側が渡すのを「比率」ではなく「文字数」に変えるべきか（仕様書 §5.2 の見直し）
  - **`AdvStage` のスロット解決**。比率方式で足りたか。立ち絵の実サイズが極端なとき（縦長・横長）に破綻しないか。
    `AdvPortraitSet.scale` と `pivot_offset_ratio` の組み合わせで表現しきれなかったケース
  - **キャラごとの「現在の表情・ポーズ・スロット」を誰が持つべきか**。
    今回は `AdvPlayer` に持たせる想定だが、`AdvStage` に持たせた方が素直だったなら、その理由
  - **非 line ステップの素通り**が、phase-03 / 05 の実装を邪魔しない形になっているか。
    「素通り」を後から「正しく処理」に差し替えるときに、どこを触ることになるか
  - **`AdvScene.tscn` のノード構成**で、仕様書 §5 のとおりに作れなかった箇所
- **禁止事項**: スコープ §2「対象外」に着手しないこと。
  特に**「演出が無いと動きが寂しいから」という理由で `AdvEffectHandler` を作らない**。
  **選択肢が無いと topic が終わってしまうから、という理由で `goto` を実装しない。**
  phase-02 は「1 本の topic を頭から末尾まで送れる」で完成とする。

## 8. リスク・不確実性

| ID | 内容 | 差分分析での確認観点 |
|----|------|---------------------|
| R-08 | **ヘッドレスで `Tween` が回るか。** `SceneTree` スクリプトはフレームを回さないため、`create_tween()` が進まない可能性がある。進まないなら `typing_speed = 0`（即時表示）でしかテストできず、**phase-03 の演出テストの土台が無くなる** | 最優先。ダメだった場合の代替（`_process` を持つ Node を挿す／`process_frame` を明示的に待つ）まで書く |
| R-09 | `RichTextLabel.visible_ratio` が日本語 + BBCode で意図どおり刻まれるか。ずれる場合、仕様書 §5.2 の「Kit は比率を渡すだけ」という責務分担が成立しなくなる | ずれたら §5.2 を「文字数を渡す」に改訂するか判断する |
| R-10 | **リサイズ追従**。`ShakeRoot` をアンカー無しにする構成（§5.1）で、子の full-rect が親のリサイズに正しく追従するか。Web は canvas リサイズが実際に起きる | phase-08 の Web 検証までに潰しておく |
| R-11 | 立ち絵の「現在の表情・ポーズ・スロット」の保持場所。`AdvPlayer` に持たせると、phase-05 のセーブ復元で**この状態も復元する必要が出る**（`uid` だけでは絵が戻らない） | phase-05 の `get_progress()` の設計に直結する。ここで気づいた点を必ず書く |
| R-12 | 非 line ステップを素通りさせることで、**サンプルシナリオの見た目が「途中で何も起きない」状態になる**。動作確認時に不具合と区別がつくか | 素通り時の `push_warning` に行き先（phase-03 / 05）を書くことで区別できるようにする |
