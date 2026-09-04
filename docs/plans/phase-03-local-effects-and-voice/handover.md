# 引継ぎ資料: フェーズ03 local-effects-and-voice

- **対象計画書**: `docs/plans/phase-03-local-effects-and-voice/plan.md`
- **実装者**: Claude（Codex ではない）
- **完了日**: 2026-09-03
- **配置先**: `C:\Users\kzr12\Root\MyProjects\AdvKit\`
- **検証環境**: Godot **4.7-stable**（5b4e0cb0f）Linux headless / **4.7.2-stable**（ed1daf0bf）**Windows 実機**。
  **両方で結果は同一。**
- **テスト結果**（すべて終了コード 0）:
  - `test_scenario_parse.gd` … **157 件 / 成功 157 / 失敗 0**（phase-01 から不変）
  - `test_playback.gd` … **32 アサーション全通過**
  - `test_effects.gd` … **88 アサーション全通過**（新規）
- **新規コード**: 約 1,360 行（`runtime/` 9 ファイル）＋ テスト 617 行

---

## 1. 実装済み内容（タスクID対応）

| ID | 状態 | 実装した内容 / 変更したファイル |
|----|------|--------------------------------|
| T-01 | 完了 | `ui/adv_scene.gd` の `_sync_shake_root_size()` から `position = Vector2.ZERO` を削除。サイズのみ同期 |
| T-02 | 完了 | `ui/adv_stage.gd` に `get_slot_base_position` / `get_portrait_position_for` / `set_character_slot` / `get_character_slot` / `get_character_pose` / `get_character_expression` |
| T-03 | 完了 | `ui/adv_portrait.gd` の `fade_in` / `fade_out_and_free` が `Tween` を返す。`position_for_base()` と公開 `kill_fade_tween()` を追加 |
| T-04 | 完了 | `runtime/adv_effect_context.gd`。台帳は `Dictionary[String, Tween]`。`acquire_tween` / **`adopt_tween`** / `kill_targets` / `kill_all` / `active_targets` |
| T-05 | 完了 | `runtime/effects/adv_effect_handler.gd`（`@abstract`）。`effect_id` フィールド、`exclusive_targets()` の既定実装、params 取り出しの静的ヘルパ 4 種 |
| T-06 | 完了 | `runtime/adv_audio_director.gd`。SE ワンショット（多重可・自動解放）、BGM 2 本クロスフェード、autoplay ガード、テスト用の要求カウンタ |
| T-07 | 完了 | `runtime/adv_voice_player.gd`。単一チャンネル、`Voice` → `Master` フォールバック（警告 1 回）、`get_remaining_time()` |
| T-08 | 完了 | `runtime/effects/adv_shake_effect.gd`。`tween_method` + 減衰サイン波。終了・中断とも `Vector2.ZERO` |
| T-09 | 完了 | `runtime/effects/adv_fade_effect.gd`。`fade_out` / `fade_in` を 1 クラス。`color` 省略時は現在色を維持 |
| T-10 | 完了 | `runtime/effects/adv_portrait_effect.gd`。show / hide / move。alpha は `AdvPortrait` の Tween を `adopt_tween` |
| T-11 | 完了 | `runtime/effects/adv_audio_effect.gd`。3 id を `AdvAudioDirector` へ委譲。`apply_final()` は何もしない |
| T-12 | 完了 | `AdvPlayer` に `register_effect` / 組み込み 9 演出の登録 / `AdvEffectContext` 構築 / 音声ノードの子生成 / `shake_root`・`fade_layer` の `@export`。`adv_scene.tscn` を配線 |
| T-13 | 完了 | 進行制御を書き換え。`while` を分解し `BLOCKING` を `await`。`is_busy()`、世代番号 `_run_id`、`stop()` の全停止 |
| T-14 | 完了 | ボイス再生を `_show_line` に。ステップ送りで停止。初回 `advance()` / `skip_typing()` で `unlock_audio()` |
| T-15 | 完了 | `tests/test_effects.gd`（88 アサーション）＋ `tests/assets/test_tone.tres`（0.3 秒の極小 WAV） |
| T-16 | 完了 | `test_playback.gd` を演出込みに更新（`is_busy()` を見て待つ）。`README.md` 2 本を更新 |

> **phase-07 で `test_effects.gd` に 5 アサーションを追加した**（U-08 の B 案）。現在は 93 件。

### DoD

| 項目 | 結果 |
|------|------|
| T-01〜T-16 の受け入れ条件 | ✅ |
| `res://game/` にファイルを作っていない | ✅ |
| `core/` と `resources/` を変更していない | ✅ 1 バイトも触っていない |
| `core/` / `resources/` が Node を参照していない | ✅ |
| `ui/` から `runtime/` への依存が無い | ⚠️ **`AdvStage` / `AdvPortrait` は完全に無依存**。ただし `AdvScene.player: AdvPlayer` は phase-02 からの配線用 `@export` として残っている（下記の逸脱） |
| `ui/` に `Theme` が無い | ✅ |
| `reparent()` を呼んでいない | ✅ |
| `load()` の前に `ResourceLoader.exists()` | ✅ テクスチャ・音源・ボイスとも |
| 音源・立ち絵が無くても進行が止まらない | ✅ テストが実素材ゼロで全通過 |
| `Thread` / `WorkerThreadPool` 不使用 | ✅ |
| 演出ハンドラが直接 `create_tween()` を呼んでいない | ✅ grep で 0 件 |
| 引数名に `name` を使っていない / 全静的型注釈 | ✅ |
| 3 本のテストが終了コード 0 | ✅ **Linux headless と Windows 実機の両方で** |
| 警告なし | ✅ **全 `.gd` を `--check-only` にかけて 0 件**（`REDUNDANT_AWAIT` も出ない） |

---

## 2. 計画との差分

| 項目 | 計画 | 実際 | 理由 |
|------|------|------|------|
| Tween 台帳の API | `acquire_tween` / `kill_targets` | **`adopt_tween()` を追加** | 立ち絵の alpha は `AdvPortrait` が Tween を作るのが正しい（R-15）。演出側で作り直すと二重書きになるので、既存の Tween を台帳へ載せる口を足した |
| 中断時の後始末 | 計画に記述なし（R-16 で判断） | `acquire_tween(targets, on_interrupt: Callable)` を追加。**中断時のみ呼ぶ**（自然完了では呼ばない） | `kill()` は `finished` を出さないので、`shake` の「原点へ戻す」が実行されないままになる |
| `AdvEffectHandler` の形 | `play` / `apply_final` / `exclusive_targets` | 加えて **`effect_id` フィールド**と params 取り出しの**静的ヘルパ 4 種**（`get_float` 等） | `play()` のシグネチャ（仕様書 §7）を変えずに 1 クラスで複数 id を扱うため。ヘルパは 4 ハンドラで同じコードを書かないため |
| `AdvStage` の保持情報 | スロットのみ | **pose / expression も記録する** | 演出（`show_portrait`）は「いま何が表示されているか」を知らないと差分を維持できない。`AdvPlayer` の保持はシナリオ解釈用として残した（§5.8） |
| `AdvAudioDirector` の API | 計画どおり | **`se_request_count()` / `requested_bgm_path()` を追加** | R-18 の答え。実素材ゼロでも「何を再生しようとしたか」を検証できるようにする |
| テスト用アセット | 計画に記述なし | **`tests/assets/test_tone.tres`（0.3 秒 / 8kHz / 6.4KB）を追加** | 「音が鳴る経路」を実際に通すため。`.tres` なのでバイナリを持ち込まずに済み、`tests/` はエクスポート除外対象（仕様書 §10） |
| `_process_next_step()` の再入防止 | `is_busy()` | 加えて**世代番号 `_run_id`** | `await` をまたいで `stop()` / `play_topic()` が呼ばれると、古い進行がカーソルを進めてしまう |

**「対象外」への越境はなし。** 選択肢・`goto`・フラグ・ダーク／ホップ・オート／スキップ／バックログ・インポータのいずれにも手を出していない。`AdvEffectSchema` も無変更。

---

## 3. 未完了・残タスク

| 内容 | 未完了の理由 | 次フェーズで必要か |
|------|--------------|--------------------|
| `AdvEffectSchema.register()`（拡張演出のスキーマ登録） | 計画で対象外にした。runtime は未登録 id でも params を文字列のまま受け取れる | phase-07（検証を効かせたくなったとき）→ **phase-07 でも見送り。必要になるまで持たない** |
| `apply_final()` の呼び出し側 | スキップは phase-06 | phase-06 で要 → **実装済み** |
| `skip_action` の暫定割り当て（タイプライタ即時完了） | phase-02 から持ち越し | phase-06 で差し替え → **実装済み** |
| 実素材での目視確認 | 音源・立ち絵が 1 つも無い | phase-08 のサンプルプロジェクト |
| Web での autoplay 検証 | 実 Web ビルドが無い | phase-08 |

---

## 4. 発生した問題・既知の不具合

| 症状 | 再現条件 | 暫定対応 / 未対応 |
|------|----------|-------------------|
| **スキップで `stop_bgm` を飛ばすと BGM が鳴り続ける** | phase-06 のスキップ実装後 | **U-08 として起票 → 2026-09-03 に B 案で確定し、phase-07 の作業中に修正済み**（`stop_bgm` の `apply_final()` だけ即時停止） |
| **台帳に kill 済み Tween の項目が残ることがある** | `AdvPortrait.kill_fade_tween()` が台帳の外から Tween を止めたとき（暗黙の登場が退場フェードを止める場合など） | 実害なし（次の `acquire_tween` / `adopt_tween` で上書きされ、`kill()` は冪等）。ただし `active_targets()` が一時的に実態より多く見える |
| `AdvAudioDirector._set_stream_loop()` がロード済みリソースを書き換える | `play_bgm` の `loop` 指定 | **未対応。** `load()` はキャッシュを返すので、同じ音源を別の `loop` 値で鳴らすと後勝ちになる。ADV の用途では同じ BGM に別のループ指定をしないため実害なしと判断 |
| 終了時に `ObjectDB instances leaked` 2 件 / `resources still in use` 1 件 | 常に（Linux / Windows とも） | phase-01 からの既知事項。**終了コードは 0**。CI は終了コードで判定する |
| `AdvPlayer._build_context()` が `shake_root` / `fade_layer` 未接続で警告を出す | `AdvScene.tscn` を使わず手組みしたとき | 仕様どおり（警告のみ・クラッシュしない） |

---

## 5. 特に報告してほしかった観点への回答

### 5.1 R-13: 抽象メソッドの `await` — **問題なし。警告も出ない**

`@abstract func play(...) -> void` を `await handler.play(ctx, params)` で呼ぶ形を、
最小コードで先に実測した（同期実装と `await tree.process_frame` を含む非同期実装の両方）。

- 同期実装 → `await` は即座に返る。**`REDUNDANT_AWAIT` は出ない**
- 非同期実装 → 完了まで待つ
- 全 `.gd` を `godot --headless --check-only --script <file>` にかけて**警告 0 件**

**仕様書 §7 の `play()` シグネチャは変更不要。** 「ハンドラが完了シグナルを返す」形への設計変更は要らない。

### 5.2 R-14: ヘッドレスの `AudioStreamPlayer` — **すべて機能する。OS 差もない**

ダミーオーディオドライバでも `play()` / `playing` / `get_playback_position()` /
`finished` シグナルが期待どおり動いた。**Linux headless と Windows 実機で挙動は同一。**

- **ただし `Voice` バスは両 OS とも存在しない**（`AudioServer.bus_count == 1`）。
  つまり**フォールバック経路が常に走る**環境で、それ自体が検証になっている。
  ゲーム側が `Voice` バスを作れば普通に使われる
- 実素材が無い問題は `tests/assets/test_tone.tres`（コード生成した `AudioStreamWAV` を `.tres` 保存）で解いた。
  6.4KB のテキストリソースなので git にもエディタにも優しい

### 5.3 R-15: 立ち絵の alpha の二重管理 — **`adopt_tween` で解消**

**`modulate.a` の Tween を作るのは `AdvPortrait` だけ**という規約にした。
`show_portrait` / `hide_portrait` は `AdvStage.show_character()` / `hide_character()` が返した
Tween を `ctx.adopt_tween()` で台帳へ載せる。これで:

- 暗黙の登場（line 起因）と `show_portrait` が同じ `_fade_tween` を取り合うので、`AdvPortrait` の
  `kill_fade_tween()` だけで整合が取れる
- 台帳は「排他ターゲットの調停役」に徹し、Tween の所有権は持たない

`move_portrait` だけは `position` を書くので `ctx.acquire_tween()` で自前の Tween を作る。
**alpha と position で持ち主が違う**が、排他ターゲットも `portrait_alpha:` と `portrait_position:` で
分かれているので、仕様書 §7 の設計とちょうど対応している。

### 5.4 R-16: `kill()` 時の後始末 — **台帳が中断後始末を呼ぶ**

`acquire_tween(targets, on_interrupt)` の第 2 引数に後始末を渡せるようにし、
**他者に `kill()` されたときだけ**呼ぶ（自然完了では呼ばない。最終状態は Tween の
最後の `tween_callback` が適用しているため）。

- `shake` だけがこれを使う（`ShakeRoot.position = Vector2.ZERO`）
- **`hide_portrait` はあえて後始末を持たない。** 退場フェードが `show_portrait` に
  中断されたときにノードを解放してしまうと、勝ったはずの `show` が解放済みノードを
  触ることになる。「**後から始まった方が勝つ**」を素直に解釈すると、中断された退場は
  「何もしないで諦める」が正しい。テストでこの経路を検証している

### 5.5 R-17: BGM クロスフェード中の `stop_bgm` — **全チャンネルを対象にして解消**

`stop_bgm()` は「いま鳴っている方」ではなく **2 本すべて**を対象にフェードアウトする。
クロスフェードの最中に止めても片方が残らないことをテストで確認した。
`bgm_channel` の排他ターゲットは Tween にしか効かない（`AudioStreamPlayer` には効かない）ので、
**`AdvAudioDirector` 側にも `_current_bgm_path` という状態を持たせた**のが実効的な守り。

### 5.6 autoplay ガードの解除タイミング

- **初回の `advance()` と `skip_typing()` で自動解除**する。`play_topic()` では解除しない
- 加えて **`AdvPlayer.unlock_audio()` を公開**した。タイトル画面のクリックなど、
  ゲーム側がより早いユーザー操作で解除できる
- 結果として、**サンプルの `prologue_01` は 1 行目に畳み込まれた `play_se` が鳴らない**。
  これは仕様書 §10（保留せず破棄する）どおりの挙動で、不具合ではない。
  気になるなら**シナリオ側で 1 行目に音を置かない**か、ゲーム側が先に `unlock_audio()` を呼ぶ

### 5.7 `shake` のパラメータ

`strength=8.0` / `frequency=24.0` / `duration=0.4`（§7 の既定値）で、
`sin(t·f·τ)·strength·(1 − t/duration)` の横揺れと、位相をずらした縦揺れ（振幅は横の半分）にした。
**単純な往復に見せないため縦の周波数を 0.7 倍にしている。**
数値の妥当性は実画面を見ないと決められないので、phase-08 で調整する前提。

### 5.8 その他の設計判断

- **音声ノードは `AdvPlayer` の子として実行時に生成する。** `AdvScene.tscn` に置くと、
  ゲーム側が独自のシーン構成を組んだときに音が鳴らなくなる。
  仕様書 §5.4 の「`AdvPlayer` が他ノードの子構成を組み替えてはならない」には抵触しない（自分の子だから）
- **`AdvStage` は pose / expression / slot を「表示状態」として持つ。**
  `AdvPlayer` が持つ同名の 3 辞書は「シナリオが最後に指定した値」。
  **役割が違うので重複ではない**が、phase-05 のセーブ復元では**どちらを保存するかを決める必要がある**
  （結論としては `AdvStage` 側＝実際に表示されている値の方が正しい → phase-05 で `portrait_states` として決着）

---

## 6. 仕様書への反映提案 — **2026-09-03 に 5 件とも反映済み**

| 箇所 | 内容 | 状態 |
|------|------|------|
| §3 ディレクトリ表 | `runtime/adv_effect_context.gd` と `runtime/adv_audio_director.gd` を追加 | ✅ 反映済み |
| §7 拡張規約 | `AdvEffectHandler` の **`effect_id` フィールド**と **`exclusive_targets(params)` 仮想メソッド**を明記 | ✅ 反映済み |
| §7 ランタイム規約 | 「`kill()` する側が中断後始末を呼ぶ」を追記 | ✅ 反映済み |
| §7 / §9.3 | **音声系 `apply_final()` の穴**を U-08 として明記。判断は phase-06 着手前 | ✅ 反映済み（U-08 は 2026-09-03 に確定・実装済み） |
| §10 | autoplay ガードの実装フェーズを phase-08 → **phase-03（実装済み）** に更新 | ✅ 反映済み |

> **注意**: この反映は **Claude Project 側の仕様書にだけ**行われ、Obsidian 側の `adv-kit-spec.md` には
> 反映されていなかった。2026-09-03 に `docs/spec/adv-kit-spec.md` へ一本化した際に統合済み。

---

## 7. 動作確認状況

- **確認済み**:
  - **Godot 4.7-stable / Linux headless**（`.godot` 削除 → 再インポート）
    - 3 本のテストが終了コード 0（157 / 32 / 88 アサーション）
    - 全 `.gd` の `--check-only` で警告 0 件
    - **ミューテーションテスト**で新テストの有効性を確認。①`AdvScene` に position リセットを戻す
      ②台帳の `kill_targets` を無効化 ③`_is_busy` を立てない、の 3 か所を壊すと
      **該当する 8 アサーションが確実に落ちる**
  - **Godot 4.7.2-stable / Windows 実機**（`godot.cmd` 経由 = `_console.exe`）
    - `--import` 成功。3 本とも `OK` / 終了コード 0（157 / 32 / 88 アサーション）
    - **Linux headless との差分は無し。** 警告の出方も同じ
    - `Voice` バス不在 → `Master` フォールバックが Windows でも同じように効く
  - 実素材（立ち絵・音源）が 1 つも無い状態で全経路が通ること
  - `tests/assets/test_tone.tres` による実再生（SE 多重・BGM クロスフェード・ボイス）
- **未確認**:
  - **実画面での見た目**（揺れ幅、フェード速度、立ち絵の移動カーブ）— phase-08
  - **Web エクスポートと autoplay ポリシー**の実挙動 — phase-08
  - 実際の `.ogg` / `.mp3` でのループ挙動（テストは `AudioStreamWAV` のみ）— phase-08

> **Windows で CI を組むときの注意**: `Godot_v4.7.2-stable_win64.exe`（無印）は
> コンソールに接続しないため、**出力が出ず、終了コードも実行完了を待たずに 0 を返す**。
> 必ず `_console.exe` を使うこと。リポジトリ外の `GodotEngine/godot.cmd` がこのラッパーになっている。

---

## 8. 次フェーズ（phase-04）への申し送り

> **注記（2026-09-03）**: 下の 1〜3 は「台帳経由にするか、別の書き手にするか」を促したものだが、
> phase-04 の実装は**どちらでもない第三の形**（`modulate` を RGB / alpha の成分で分ける）になった。
> 仕様書 §8 は実装に合わせて確定済み（U-09）。

1. **非話者ダーク／話者交代ホップは `AdvPortrait.modulate` と `position` を書く。**
   これは `portrait_alpha:{speaker}` / `portrait_position:{speaker}` と**同じものを取り合う**。
   汎用演出は排他ターゲットの外に居るので、**台帳経由にするか、専用の Tween を持たせるかを最初に決めること**。
   phase-03 の台帳（`AdvEffectContext`）はそのまま使える形になっている。
2. **ダークは `modulate` 全体、フェードは `modulate.a` を書く。** 同じプロパティの別成分なので、
   単純に両方 Tween すると片方が上書きする。`AdvPortrait` に「基準色」と「alpha」を分けて持たせるのが素直。
3. **ホップは `position` を書くので `move_portrait` と直接ぶつかる。**
   移動中にホップさせない、あるいはホップを `AdvPortrait` の子ノードのオフセットにする、のどちらか。
4. `AdvPlayer._show_line()` の中で話者の変化を検出できる（`_current_slots` などの更新箇所の直前）。
   phase-04 のフックはここに入る。
5. **`AdvStage` に pose / expression / slot の表示状態がある。** phase-05 のセーブ復元はここを見ること。
