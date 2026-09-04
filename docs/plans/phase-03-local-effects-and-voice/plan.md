# 実装計画書: フェーズ03 local-effects-and-voice

## 1. フェーズ概要

- **ゴール**: シナリオに書いた**局所演出が実際に動く**。揺れ・フェード・立ち絵の登場／退場／移動・SE・BGM が
  `PARALLEL` / `BLOCKING` の意味どおりに進行制御され、`register_effect()` でゲーム側が演出を足せる。
  あわせて**ボイスが鳴る**（`voice_path` 未指定でも進行は止まらない）。
- **仕様書の該当箇所**: §7（局所演出・排他ターゲット・拡張規約）、§4.3（`AdvEffectStep`）、§4.8（畳み込み）、
  §5.1（揺れの対象）、§5.3（`register_effect`）、§9.4（ボイス）、§10（autoplay ガード）
- **前提フェーズ**: phase-02（完了）。`AdvPlayer` / `AdvStage` / `AdvPortrait` / `AdvScene` がそのまま使える

phase-02 は「1 本の topic をテキスト送りで最後まで進める」ところまで。
phase-03 は**そのステップ列に演出を差し込む**。選択肢・話題遷移・フラグ・オート／スキップ／バックログには手を出さない。

## 2. スコープ

### 対象

- `runtime/adv_effect_context.gd` — 演出ハンドラに渡す実行文脈。**排他ターゲットごとの Tween 台帳**を持つ
- `runtime/effects/adv_effect_handler.gd` — `@abstract` 基底。`play` / `apply_final` / `exclusive_targets`
- `runtime/effects/adv_shake_effect.gd` — `shake`
- `runtime/effects/adv_fade_effect.gd` — `fade_out` / `fade_in`
- `runtime/effects/adv_portrait_effect.gd` — `show_portrait` / `hide_portrait` / `move_portrait`
- `runtime/effects/adv_audio_effect.gd` — `play_se` / `play_bgm` / `stop_bgm`
- `runtime/adv_audio_director.gd` — SE / BGM のチャンネル（BGM は 2 本でクロスフェード）
- `runtime/adv_voice_player.gd` — ボイス 1 チャンネル。バス `voice_bus` → 無ければ `Master`
- `runtime/adv_player.gd` — 演出の起動と `BLOCKING` の完了待ち、`register_effect()`、ボイス再生、**autoplay ガード**
- `ui/adv_stage.gd` — スロット座標の公開（`get_slot_position` / `set_character_slot`）。演出が位置を Tween できるようにする
- `ui/adv_portrait.gd` — `fade_in` / `fade_out_and_free` を「Tween を返す」形に変更（台帳へ載せるため）
- `ui/adv_scene.gd` / `.tscn` — **`ShakeRoot.position` を書かないよう修正**（phase-02 差分レポートの是正項目）、
  `AdvPlayer` へ `shake_root` / `fade_layer` を `@export` で配線
- `tests/test_effects.gd` — 演出とボイスのヘッドレステスト（新規）
- `tests/test_playback.gd` — 演出が入ったことによる期待値の更新
- `addons/adv_kit/README.md` の更新

### 対象外（今回やらない）

- **非話者ダーク・話者交代ホップ**（phase-04）。`dim_*` / `hop_*` 設定は読まない
- **選択肢の提示と `goto` の遷移・フラグ・条件式の評価**（phase-05）。`AdvChoiceStep` / `AdvJumpStep` は**引き続き素通り**
- **オート・スキップ・バックログ**（phase-06）。`apply_final()` は**実装するが呼び出し側は作らない**
- **`AdvEffectSchema.register()`（拡張演出のパラメータスキーマ登録）**。
  未知の `effect_id` は `unknown_effect_id` の WARNING で通り、**params は文字列のまま全部保持される**（phase-01 実測）。
  拡張ハンドラは自分で型変換すればよく、スキーマ登録が無くても runtime は成立する。
  必要になるのは「拡張演出のパラメータも検証したい」と思ったときで、それは phase-07（インポータ）の話
- **`.tres` の書き出し・インポータ・エディタ Dock**（phase-07）
- **実素材の用意**。音源も立ち絵も 1 つも無い前提で作る（下記）

> **`AdvChoiceMenu` / `AdvBacklogView` は今回も作らない**（phase-02 の決定を維持）。

### スコープに入れた判断: **autoplay ガードは phase-03 で入れる**

仕様書 §10 の「初回の `advance()` までは音を鳴らさない」は phase-08（Web 堅牢化）の項目だが、
**音を鳴らす箇所を作るのが phase-03**。後から全ハンドラとボイス再生に後付けするより、
`AdvAudioDirector` と `AdvVoicePlayer` の入口 1 箇所ずつに最初から置く方が安い。
phase-08 では**実 Web での検証**だけを行う。

## 3. 影響範囲

- **新規**: `runtime/adv_effect_context.gd`、`runtime/adv_audio_director.gd`、`runtime/adv_voice_player.gd`、
  `runtime/effects/`（5 ファイル）、`tests/test_effects.gd`
- **変更**: `runtime/adv_player.gd`、`ui/adv_stage.gd`、`ui/adv_portrait.gd`、`ui/adv_scene.gd` / `.tscn`、
  `tests/test_playback.gd`、`README.md`
- **`core/` と `resources/` は変更しない。** `AdvEffectSchema.exclusive_targets()` は phase-01 のまま使う。
  変えたくなったら設計の誤りなので handover に書く
- **`res://game/` 配下には一切触れない**
- `runtime/` は `core/` `resources/` `ui/` に依存してよい。**`ui/` から `runtime/` への依存は禁止**
- **`AdvPlayer` は自分の子として `AdvAudioDirector` / `AdvVoicePlayer` を実行時に生成する。**
  他ノードの子構成は組み替えない（仕様書 §5.4 の禁止事項に抵触しない）

## 4. 新規に定義する契約

### `AdvEffectHandler`（`runtime/effects/adv_effect_handler.gd`）

```gdscript
@abstract
class_name AdvEffectHandler extends RefCounted

## register_effect() が代入する。1 クラスで複数の effect_id を扱えるようにするため。
var effect_id: StringName = &""

@abstract func play(ctx: AdvEffectContext, params: Dictionary) -> void
@abstract func apply_final(ctx: AdvEffectContext, params: Dictionary) -> void

## 排他ターゲット（仕様書 §7）。既定は §7 の表を引く。
## 拡張演出はこれを override して自分のターゲットを宣言する。
func exclusive_targets(p_params: Dictionary) -> PackedStringArray:
	return AdvEffectSchema.exclusive_targets(effect_id, p_params)
```

- **`effect_id` をハンドラのフィールドにする**ことで、`play()` のシグネチャ（仕様書 §7）を変えずに
  `fade_out` / `fade_in` を 1 クラスで扱える。同じクラスを 2 つの id に登録するときは**別インスタンスにする**。
- **排他ターゲットの宣言は仮想メソッド**（2026-09-03 決定）。`register_effect()` の引数では渡さない。
  `{speaker}` のような params 依存を登録時の固定文字列では表現できないため。
- `play()` は**完了まで `await` できる**こと。呼び出し側（`AdvPlayer`）は `await handler.play(...)` する。

### `AdvEffectContext`（`runtime/adv_effect_context.gd`）

**仕様書 §3 のディレクトリ表に無い型を足す**（§7 の `play(ctx: AdvEffectContext, ...)` では名前だけ出ている）。
handover で仕様書 §3 への追記を提案する。

```gdscript
class_name AdvEffectContext extends RefCounted

var host: Node                    ## Tween の生成元（= AdvPlayer）
var stage: AdvStage
var shake_root: Control
var fade_layer: ColorRect
var book: AdvScenarioBook
var settings: AdvKitSettings
var audio: AdvAudioDirector
var voice: AdvVoicePlayer

## 排他ターゲットを占有して Tween を作る。
## 同じターゲットで走っている Tween は kill() してから作る（仕様書 §7 のランタイム規約）。
func acquire_tween(p_targets: PackedStringArray) -> Tween
## Tween を作らない演出（play_se 等）が占有だけ宣言する場合。
func kill_targets(p_targets: PackedStringArray) -> void
func get_character(p_id: StringName) -> AdvCharacter
func get_portrait(p_id: StringName) -> AdvPortrait
```

- **Tween 台帳は `Dictionary[String, Tween]`**（キー = 排他ターゲット文字列）。
  `acquire_tween()` は該当キーの生存 Tween を `kill()` → 消去してから新規作成し、全キーへ登録する。
  Tween の `finished` で自分の登録を外す。
- **`ctx` は `RefCounted`。ノードを所有しない。** `create_tween()` は `host.create_tween()` に委譲する。

### `AdvAudioDirector`（`runtime/adv_audio_director.gd`）

```gdscript
class_name AdvAudioDirector extends Node
func play_se(stream_path: String, volume_db: float) -> void
func play_bgm(stream_path: String, fade_in_time: float, loop: bool) -> void
func stop_bgm(fade_out_time: float) -> void
func stop_all() -> void
func set_audio_unlocked(unlocked: bool) -> void
func is_bgm_playing() -> bool
func current_bgm_path() -> String
```

- **BGM は `AudioStreamPlayer` を 2 本持ち、切り替え時にクロスフェードする**（仕様書 §7）。
- **SE はワンショット。多重再生可**。再生ごとに `AudioStreamPlayer` を生成し、`finished` で `queue_free()`。
  同時発音数の上限は設けない（ADV の用途で溢れない）。
- **`stream_path` が解決できない場合は `push_warning` して何もしない。進行は止めない。**
  `ResourceLoader.exists()` で確認してから `load()` する。
- **`set_audio_unlocked(false)` の間は一切鳴らさず、保留もしない**（仕様書 §10「保留した音は破棄する」）。
  ただし `play_bgm` の**「いま何が鳴るべきか」の記録だけは保持しない**。破棄は破棄で通す。

### `AdvVoicePlayer`（`runtime/adv_voice_player.gd`）

```gdscript
class_name AdvVoicePlayer extends Node
func setup(bus_name: StringName) -> void
func play_voice(voice_path: String) -> void
func stop() -> void
func is_playing() -> bool
func get_remaining_time() -> float   ## phase-06 のオートモードが使う
signal voice_finished()
```

- **同時に鳴るボイスは 1 つ。** 次のステップへ進んだ時点で前のボイスを停止する。
- バスは `voice_bus`（既定 `Voice`）。`AudioServer.get_bus_index()` が -1 なら `Master` にフォールバックし、
  **`push_warning` は 1 回だけ**出す（毎行出すとログが埋まる）。
- `voice_path` が空 → 何もしない。解決できない → `push_warning` して進行は続ける。

### `AdvPlayer` の追加 API（仕様書 §5.3 のうち今回作る分）

```gdscript
@export var shake_root: Control      ## 追加
@export var fade_layer: ColorRect    ## 追加

func register_effect(effect_id: StringName, handler: AdvEffectHandler) -> void
func unlock_audio() -> void          ## Web autoplay ガードの解除。初回 advance() でも自動で解除される
func is_audio_unlocked() -> bool
```

- **`register_effect()` は同じ id を上書きできる。** ゲーム側が組み込み演出を差し替えられる。
- 組み込み 9 演出は `setup()` の中で登録する（未登録なら）。

### 進行制御の規則（今回の中核）

| ステップ | 挙動 |
|----------|------|
| `AdvLineStep` | `parallel_effects` を**起動だけして待たない** → ボイス再生 → 立ち絵反映 → 本文表示 → タイプライタ |
| `AdvEffectStep`（`BLOCKING`） | `parallel_effects` を起動 → 自身を `await` で完了まで待つ → `auto_advance` なら続行、偽ならテキスト送り待ち |
| `AdvEffectStep`（`PARALLEL` が単独で残っている） | 畳み込み漏れ。起動だけして次へ進む（`dangling_parallel` は検証側の担当） |
| `AdvChoiceStep` / `AdvJumpStep` | 引き続き素通り（`push_warning` に phase-05 と書く） |

- **`BLOCKING` 演出の実行中は `advance()` を受け付けない。** `is_busy()` で弾く。
- 演出の起動順は `parallel_effects` の配列順（= `order` 順）。
- **`AdvPlayer.stop()` は走っている Tween と音をすべて止める。**

## 5. タスク分解

| ID | タスク | 受け入れ条件 | 依存 |
|----|--------|--------------|------|
| T-01 | `ui/adv_scene.gd` の `_sync_shake_root_size()` から `position = Vector2.ZERO` を外す。サイズのみ同期する | リサイズ後も `ShakeRoot.size == AdvScene.size` が保たれ、**`ShakeRoot.position` は誰にも書き換えられない**。phase-02 の `test_playback.gd` のリサイズ検証がそのまま通る | - |
| T-02 | `ui/adv_stage.gd` にスロット座標の公開を足す。`get_slot_position(slot) -> Vector2`（ステージ座標系の基準点）、`get_portrait_position_for(character_id, slot) -> Vector2`（その立ち絵の `position` になる値）、`set_character_slot(character_id, slot)`（記録のみ・移動しない） | `move_portrait` の Tween 先を `AdvStage` に問い合わせられる。`set_character_slot()` した後にステージをリサイズすると、新しいスロットの比率で再配置される | - |
| T-03 | `ui/adv_portrait.gd` の `fade_in` / `fade_out_and_free` が**生成した `Tween` を返す**ようにする（duration 0 のときは `null`）。既存の即時パスは変えない | phase-02 の `test_playback.gd` が変更なしで通る。戻り値を使わない呼び出し側で警告が出ない | - |
| T-04 | `runtime/adv_effect_context.gd` を作る。ノード参照と**排他ターゲットの Tween 台帳**、`acquire_tween` / `kill_targets` / `get_character` / `get_portrait` | 同じターゲットで `acquire_tween()` を 2 回呼ぶと、1 回目の Tween が `kill()` されている。別ターゲットなら両方生きている。完了した Tween は台帳から自動で外れる | T-02 |
| T-05 | `runtime/effects/adv_effect_handler.gd`（`@abstract`）を作る。`effect_id` フィールド、`play` / `apply_final` の抽象宣言、`exclusive_targets()` の既定実装（`AdvEffectSchema` へ委譲） | 派生を作らずに `new()` できない。`exclusive_targets()` が §7 の表と一致する（`show_portrait` は `portrait_alpha:<speaker>` を返す） | - |
| T-06 | `runtime/adv_audio_director.gd` を作る。SE ワンショット、BGM 2 本クロスフェード、`stop_all`、autoplay ガード | 存在しないパスを渡しても `push_warning` だけで例外にならない。`set_audio_unlocked(false)` の間は `AudioStreamPlayer` が 1 つも `playing` にならない。BGM を切り替えると前の BGM が段階的に止まる | - |
| T-07 | `runtime/adv_voice_player.gd` を作る。1 チャンネル、バスのフォールバック（警告は 1 回だけ）、`get_remaining_time()` | 空パスで何も起きない。存在しないパスで `push_warning` して進行が続く。`play_voice()` を続けて 2 回呼ぶと前が止まる。`Voice` バスが無い環境で `Master` に落ちる | - |
| T-08 | `runtime/effects/adv_shake_effect.gd`。`Tween.tween_method()` + サイン波減衰で `shake_root.position` を振動させ、**終了時に必ず `Vector2.ZERO` へ戻す**。`apply_final()` は即座に `Vector2.ZERO` | `strength=8, duration=0.4, frequency=24` で `position` が動き、完了後にちょうど `Vector2.ZERO`。途中で `stop()` されても最終的に `Vector2.ZERO` に戻る（`kill()` 時のクリーンアップ） | T-04, T-05 |
| T-09 | `runtime/effects/adv_fade_effect.gd`。`fade_out` は `fade_layer.color = color` にしてから alpha 0→1、`fade_in` は alpha 1→0（`color` 省略時は現在色を維持）。`apply_final()` は到達 alpha を即座に代入 | `fade_out` 完了後に `fade_layer.color.a == 1.0`、`fade_in` 完了後に `0.0`。`fade_in` で `color` を省略しても直前の色が保たれる。`FadeLayer` が `MessageWindow` を隠さない（ノード順は phase-02 のまま） | T-04, T-05 |
| T-10 | `runtime/effects/adv_portrait_effect.gd`。`show_portrait` / `hide_portrait` / `move_portrait` を `effect_id` で分岐。位置は T-02 の API から取る。**Tween は必ず `ctx.acquire_tween()` 経由**。`hide` は完了後に `AdvStage.hide_character(id, 0.0)` | `show_portrait` でステージに 1 体増え alpha が 1 になる。`hide_portrait` 完了後にノードが解放されている。`move_portrait` 後にステージをリサイズしても新スロットの比率に追従する。`speaker` が book に無い場合は `push_warning` して**進行を止めない** | T-02, T-03, T-04, T-05 |
| T-11 | `runtime/effects/adv_audio_effect.gd`。`play_se` / `play_bgm` / `stop_bgm` を `AdvAudioDirector` へ委譲。**`apply_final()` は 3 つとも何もしない**（仕様書 §7: スキップ中に音を鳴らさない） | 3 つの id が正しく委譲される。`play_se` は `await` してもすぐ返る（完了を待たない）。`play_bgm` の `fade_in_time` が効く | T-05, T-06 |
| T-12 | `AdvPlayer` に `register_effect()` と組み込み 9 演出の登録、`AdvEffectContext` の構築、`AdvAudioDirector` / `AdvVoicePlayer` の子生成、`shake_root` / `fade_layer` の `@export` を足す。`adv_scene.tscn` を配線し直す | `setup()` 後に `register_effect()` で同じ id を登録すると、そちらが呼ばれる。`AdvScene.tscn` をインスタンスするだけで演出が動く。`shake_root` / `fade_layer` が未接続でも `push_warning` して**クラッシュしない** | T-08〜T-11 |
| T-13 | `AdvPlayer` の進行制御を §4 の表どおりに書き換える。`_process_next_step()` の `while` を分解し、`BLOCKING` を `await` する。`is_busy()` で `advance()` を弾く。`stop()` で Tween と音を止める | `auto_advance=true` の `BLOCKING` 演出が入力なしで次へ進む。`false` なら演出完了後にテキスト送りを待つ。演出中の `advance()` 連打で行が飛ばない。`PARALLEL` 演出が本文表示をブロックしない | T-12 |
| T-14 | ボイスの再生を `AdvPlayer` に足す。`AdvLineStep.voice_path` を `_show_line` で再生し、次のステップへ進む時点で停止する。**初回 `advance()` で `unlock_audio()`**（`play_topic()` では解除しない） | `voice_path` が空でも進行が変わらない。行を送ると前のボイスが止まる。`play_topic()` 直後は音が鳴らず、最初の `advance()` 以降は鳴る | T-07, T-13 |
| T-15 | `tests/test_effects.gd`（`extends SceneTree`）を作る。台帳・9 演出・進行制御・ボイス・autoplay ガード・`register_effect` の拡張演出を検証する | `godot --headless --script res://addons/adv_kit/tests/test_effects.gd` が終了コード 0。**音源・立ち絵の実ファイルが 1 つも無い状態で全部通る** | T-13, T-14 |
| T-16 | `tests/test_playback.gd` を演出込みの期待値へ更新し、`README.md` に演出・ボイス・`register_effect` の使い方を書く | 3 本のテスト（parse / playback / effects）がすべて終了コード 0。README を読めばゲーム側が独自演出を登録できる | T-15 |

## 6. 完了定義（DoD）

- [ ] T-01〜T-16 の全受け入れ条件を満たす
- [ ] `res://game/` 配下に一切ファイルを作っていない
- [ ] **`core/` と `resources/` を変更していない**
- [ ] `core/` と `resources/` が `Node` / `Control` / `SceneTree` を参照していない
- [ ] **`ui/` から `runtime/` への依存が無い**（`AdvStage` / `AdvPortrait` が `AdvEffectContext` を知らない）
- [ ] `ui/` に `Theme` が 1 つも無い
- [ ] 実行時の `reparent()` を呼んでいない
- [ ] `load()` を呼ぶ前に必ず `ResourceLoader.exists()` で確認している（テクスチャ・音源とも）
- [ ] **音源・立ち絵が存在しなくても、警告だけで進行が止まらない**
- [ ] `Thread` / `WorkerThreadPool` を使っていない
- [ ] 演出ハンドラが `Tween` を作るのは `ctx.acquire_tween()` 経由だけ（直接 `create_tween()` を呼んでいない）
- [ ] 引数名に `name` を使っていない。全 GDScript が静的型注釈付き
- [ ] `godot --headless --import` の後、**3 本のテストが全部終了コード 0**
- [ ] エディタで警告が出ていない（`REDUNDANT_AWAIT` を含む）

## 7. 実装者への指示

- 実装完了後、`handover.md` を phase-02 と同じ構成で作成する。全セクションを埋め、上記タスクIDに対応づける。
- **特に報告してほしい観点**:
  - **`await handler.play(...)` が警告なしで書けたか。** 抽象メソッドを `await` すると
    `REDUNDANT_AWAIT` が出る可能性がある（R-13）。出た場合の回避策と、それが仕様書 §7 の
    `play()` シグネチャの見直しを要求するかどうか
  - **排他ターゲット台帳が「後から始まった方が勝つ」を実現できているか**（仕様書 §7 のランタイム規約）。
    ステップをまたいだ重なり（`auto_advance` の連鎖）で実際に検証できたか
  - **`AdvPortrait` の内部 `_fade_tween` と台帳の Tween が二重管理になっていないか。**
    `apply()` が内部 Tween を `kill()` する挙動と、`show_portrait` の Tween が競合しないか
  - **`apply_final()` の音声系「何もしない」（仕様書 §7）が phase-06 で成立するか。**
    スキップで `stop_bgm` を飛ばすと BGM が鳴り続ける。仕様の穴なら handover に書く
  - **autoplay ガードの解除タイミング。** 「初回 `advance()`」で足りるか、
    ゲーム側がタイトル画面で先に解除したいケースがないか
  - **BGM クロスフェードの実装**（2 本の `AudioStreamPlayer`）が `stop_bgm` / 連続切り替えで破綻しないか
  - **`shake` の `tween_method` + サイン波減衰**の見た目パラメータ。`strength` / `frequency` の既定値が妥当か
- **禁止事項**: §2「対象外」に着手しないこと。特に
  **「演出だけだと確認しづらいから」という理由で選択肢や `goto` を実装しない。**
  **オート／スキップの呼び出し側を作らない**（`apply_final()` の実装までが phase-03）。

## 8. リスク・不確実性

| ID | 内容 | 差分分析での確認観点 |
|----|------|---------------------|
| R-13 | **抽象メソッドの `await`。** `await handler.play(ctx, params)` が `REDUNDANT_AWAIT` 警告になるか、そもそも待ってくれないか。ダメなら「ハンドラが完了シグナルを返す」形へ設計変更が要る | 最優先。**T-05 の時点で最小コードを書いて実測する**。DoD の「警告なし」に直結する |
| R-14 | **ヘッドレスで `AudioStreamPlayer` が機能するか。** ダミーオーディオドライバで `play()` / `finished` / `get_playback_position()` が期待どおり動くか。動かないとボイスと BGM のテストが書けない | ダメだった場合、`AdvAudioDirector` / `AdvVoicePlayer` に「何を再生しようとしたか」の問い合わせ API を足してテストする |
| R-15 | **Tween 台帳のキー衝突。** `portrait_alpha:{speaker}` の `{speaker}` は `params.speaker` から作るが、**暗黙の登場（line 起因）にはこのキーが無い**。line の立ち絵フェードと `show_portrait` が同じ alpha を取り合う | 暗黙の登場も台帳経由にするか、`AdvStage` 側の Tween を別扱いにするか。実装しながら決めて handover に書く |
| R-16 | **`stop()` / `kill()` 時の後始末。** `shake` を途中で `kill()` すると `ShakeRoot.position` が中途半端な値で残る。`hide_portrait` を途中で `kill()` するとノードが解放されず alpha 0 のまま残る | Tween の `kill()` に後始末は付いてこない。**`kill()` する側（台帳）が「最終状態を適用する」責務を持つべきか**を判断して書く |
| R-17 | **BGM クロスフェード中の `stop_bgm`。** 2 本走っている最中に止めると、片方だけ止まる実装になりやすい | `bgm_channel` の排他ターゲットで守られるはずだが、台帳が効くのは Tween であって `AudioStreamPlayer` ではない。`AdvAudioDirector` 側にも状態を持たせるか判断する |
| R-18 | **サンプルシナリオが「音も絵も出ない」通しになる。** 実素材が無いので、テストが通っても見た目の確認にならない | phase-08 のサンプルプロジェクトまで持ち越す。**代わりにテストで「何を再生しようとしたか」を検証する**（R-14 の API がそのまま使える） |
