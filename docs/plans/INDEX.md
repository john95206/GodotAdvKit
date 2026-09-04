# フェーズ台帳 — ADV Kit

状態: `未着手` → `計画済` → `実装中` → `引継ぎ済` → `完了`

| フェーズ | 名称 | 状態 | 実装者 | 計画書 | 引継ぎ | 差分レポート |
|----------|------|------|--------|--------|--------|--------------|
| phase-01 | foundation-and-data-model | **完了** | Claude | [plan](phase-01-foundation-and-data-model/plan.md) | [handover](phase-01-foundation-and-data-model/handover.md) | [diff](../diff-reports/phase-01-diff.md) |
| phase-02 | runtime-playback | **完了** | Claude | [plan](phase-02-runtime-playback/plan.md) | [handover](phase-02-runtime-playback/handover.md) | [diff](../diff-reports/phase-02-diff.md) |
| phase-03 | local-effects-and-voice | **完了** | Claude | [plan](phase-03-local-effects-and-voice/plan.md) | [handover](phase-03-local-effects-and-voice/handover.md) | [diff](../diff-reports/phase-03-diff.md) |
| phase-04 | auto-direction | **完了** | Codex | [plan](phase-04-auto-direction/plan.md) | [handover](phase-04-auto-direction/handover.md) | 未作成 |
| phase-05 | topics-choices-and-progress | **完了** | Codex | [plan](phase-05-topics-choices-and-progress/plan.md) | [handover](phase-05-topics-choices-and-progress/handover.md) | 未作成 |
| phase-06 | play-assist | **完了** | Codex | [plan](phase-06-play-assist/plan.md) | [handover](phase-06-play-assist/handover.md) | 未作成 |
| phase-07 | scenario-pipeline | **完了** | Claude | [plan](phase-07-scenario-pipeline/plan.md) | [handover](phase-07-scenario-pipeline/handover.md) | [diff](../diff-reports/phase-07-diff.md) |
| phase-08 | web-hardening-and-sample | **完了** | Codex | [plan](phase-08-web-hardening-and-sample/plan.md) | [handover](phase-08-web-hardening-and-sample/handover.md) | [diff](../diff-reports/phase-08-diff.md) |

> **2026-09-03: ドキュメントを `docs/` へ一本化した。** それまで Obsidian と Claude Project に
> 写しがあり、**片方に phase-03、もう片方に phase-04〜06 の反映しか無い**状態で分岐していた。
> 経緯と運用ルールは [`docs/README.md`](../README.md)。
>
> **phase-04 / 05 / 06 の差分レポート（[D]）だけは未作成。** 実装と引継ぎ資料は揃っているので、
> 必要になったら後から書ける。phase-08 をブロックしない。

## 各フェーズの狙い（要約）

| フェーズ | ゴール |
|----------|--------|
| phase-01 | シナリオを表す Resource 群と、JSON→Resource のパーサ・バリデータ・条件式・演出スキーマが揃い、ヘッドレスで検証できる |
| phase-02 | 立ち絵付きテキストがテキスト送りで進む。ADV として最低限遊べる。UI は外観を持たない基底クラス＋参照実装 |
| phase-03 | 揺れ・フェード・立ち絵移動・SE/BGM が動き、PARALLEL / BLOCKING が正しく効く。ボイスが鳴る（未指定でも進む） |
| phase-04 | 非話者ダークと話者交代ホップが設定でオンオフできる |
| phase-05 | 選択肢と話題遷移、フラグ、**既読集合**を含む進行データの保存・復元ができる |
| phase-06 | オートモード・スキップ（既読連動）・バックログが動く |
| phase-07 | スプレッドシート → GAS → JSON → `.tres` の経路がエディタと CLI の両方から通る |
| phase-08 | unityroom 投稿チェックリストに適合し、サンプルプロジェクトで通しプレイできる |

**依存**: 01 → 02 → 03 → 04、02 → 05 → 06、**03 → 06**（バックログのボイスリプレイが `AdvVoicePlayer` に依存）、01 → 07、全 → 08。

## 現在地

- **完了フェーズ**: **phase-01 〜 phase-08**
- **次のフェーズ**: なし
- **リポジトリ**: `C:\Users\kzr12\Root\MyProjects\AdvKit\`（Godot 4.7 系 / Compatibility）
- **実装者**: phase-01〜03 と phase-07 は Claude、phase-04〜06 は Codex
- **仕様書**: [`docs/spec/adv-kit-spec.md`](../spec/adv-kit-spec.md)。**2026-09-03 に Obsidian 側の写しと統合済み**
- **ドキュメントの置き場所**: `docs/` のみ。写しを作らない（[README](../README.md)）

### テストの現況

**Godot 4.7-stable（Linux headless）と 4.7.2-stable（Windows 実機）の両方で実測。結果は同一。**
Linux 側は `.godot` を消してからの通し。

| テスト | 件数 | 結果 |
|--------|------|------|
| `test_scenario_parse.gd` | 157 | 全通過 |
| `test_playback.gd` | 32 | 全通過 |
| `test_effects.gd` | 93 | 全通過 |
| `test_auto_direction.gd` | 24 | 全通過 |
| `test_progress.gd` | 50 | 全通過 |
| `test_play_assist.gd` | 44 | 全通過 |
| `test_import.gd` | 113 | 全通過 |
| `test_sample_scene.gd` | 28 | 全通過 |

8 本とも終了コード 0（Windows の音声回帰は `--audio-driver Dummy`）。全 `.gd` の `--check-only` で警告 0 件。
終了時の `ObjectDB instances leaked` / `resources still in use` は既知（R-07）で無害。
**判定は必ず終了コードで行う。**

> Windows 実機で確認したのは 2026-09-03。`test_playback` / `test_effects` / `test_auto_direction` /
> `test_progress` / `test_play_assist` / `test_import` の 6 本を目視確認済み
> （`test_scenario_parse` は出力が流れて未確認。Linux では 157 件全通過）。
> WARNING は想定内のものだけ（`Voice` バス不在の `Master` フォールバック、実素材ゼロの音源・ボイス欠損、
> `speaker=nobody` の異常系）。`ObjectDB instances leaked` も既知（R-07）。

### テストの走らせ方

```powershell
cd C:\Users\kzr12\Root\MyProjects\AdvKit
$godot = "C:\Users\kzr12\Root\GodotEngine\godot.cmd"   # 中身は _console.exe のラッパー

& $godot --headless --import
& $godot --headless --script res://addons/adv_kit/tests/test_scenario_parse.gd; "parse    exit=$LASTEXITCODE"
& $godot --headless --script res://addons/adv_kit/tests/test_playback.gd;       "play     exit=$LASTEXITCODE"
& $godot --headless --audio-driver Dummy --script res://addons/adv_kit/tests/test_effects.gd; "effects  exit=$LASTEXITCODE"
& $godot --headless --script res://addons/adv_kit/tests/test_auto_direction.gd; "auto     exit=$LASTEXITCODE"
& $godot --headless --script res://addons/adv_kit/tests/test_progress.gd;       "progress exit=$LASTEXITCODE"
& $godot --headless --script res://addons/adv_kit/tests/test_play_assist.gd;    "assist   exit=$LASTEXITCODE"
& $godot --headless --script res://addons/adv_kit/tests/test_import.gd;         "import   exit=$LASTEXITCODE"
& $godot --headless --audio-driver Dummy --script res://addons/adv_kit/tests/test_sample_scene.gd; "sample   exit=$LASTEXITCODE"
```

### phase-08 の実測

サンプルの Web 出力は `build/phase08_web/Build.html` / `Build.pck` として生成できる。
初回 Web build ではタイトル操作後の立ち絵・本文・バックログ、最新版ではタイトル画面と
日本語フォント反映を確認した。
Windows の Godot エディタ Dock は、この環境では CUA のネイティブアプリ面が公開されず、
画面の目視確認は未実施。phase-07 の headless 構成テストは引き続き通過している。

> **`Godot_v4.x-stable_win64.exe`（無印）を直接呼ばないこと。** コンソールに接続しないため
> 出力が出ず、**終了コードも実行完了を待たずに 0 を返す**。`godot.cmd` がこのラッパーになっている。
> `--import` の前置は必須（`class_name` のグローバル解決）。エディタで開いている場合は閉じてから。

### 実 GAS での疎通（2026-09-03 確認済み）

スプレッドシート → GAS → JSON → `.tres` を**実環境で通した**。

- サンプルシート（3 キャラ / 5 話題 / 31 行）から **9 ファイル書き出し / 終了コード 0**
- WARNING は `missing_portrait_texture` 5 件のみ（立ち絵の実素材がまだ無いため。ERROR 0）
- **`content_hash` が `01c08038cf8d5d4d7f60532cb6c8afed` で、GAS をモック実行したときの値と完全一致**。
  GAS 側の実装が意図どおりであることの裏付け
- 2 回目の実行で `変更なし: content_hash ... が既存と一致` → **差分スキップが効く**
- 出力は `res://game/resources/adv/scenario/`（Book 1 + characters 3 + topics 5）

### シナリオの取り込み（phase-07）

```powershell
& $godot --headless --import
& $godot --headless --script res://addons/adv_kit/import/adv_import_cli.gd -- `
    --url=<GAS のウェブアプリ URL> --out=res://game/resources/adv/scenario/
& $godot --headless --import
```

終了コード **0=成功 / 1=ERROR あり / 2=引数が不正**。
エディタからは右上ドックの「ADV シナリオ」パネル。
**URL はリポジトリ・コミットメッセージ・チャットに書かないこと**（U-05）。

## 判断待ち

| # | 内容 | 判断のタイミング | 仕様書 |
|---|------|-----------------|--------|
| 1 | phase-04 / 05 / 06 の**差分レポート**を後から書くか（計画書と引継ぎ資料は揃っている） | 必要になったとき | - |
| 2 | `condition` に括弧を足すか。**phase-05 は括弧なしのまま実装された**（`AdvCondition` は括弧を受け付けない） | 必要になったとき | U-04 |

> **未決は U-04 だけになった。** U-07 / U-08 / U-09 / U-10 は 2026-09-03 に確定し、仕様書へ反映済み（下の決定ログ）。

## 決定ログ（フェーズをまたぐもの）

### 運用・環境

| 日付 | 決定 | 影響 |
|------|------|------|
| 2026-09-02 | パッケージは `res://addons/adv_kit/` のアドオンとして配布 | 全フェーズ |
| 2026-09-03 | 実装は phase-01〜03 が Claude、phase-04〜06 が Codex、phase-07 が Claude | 全フェーズ |
| 2026-09-03 | エンジンは **Godot 4.7 系**、レンダラーは **Compatibility** で確定。**4.8 以降には上げない**（unityroom の対応上限が 4.7）。`project.godot` の `config/features` は開いたエンジンが書き換えるので、git 差分に出たらバージョンを行き来した印 | 全フェーズ |
| 2026-09-03 | **git リポジトリは 1 本**（`AdvKit/`）。GitHub の private リポジトリ。配布は当面フォルダのコピー。`.uid` はコミットする。`.godot/` と `export_presets.cfg` は無視 | 全フェーズ |
| 2026-09-03 | **CI は終了コードで判定する**（stderr の有無で判定しない）。`AdvStep` の型自己参照による終了時リークは無害 | 全フェーズ |
| 2026-09-03 | **Windows では `_console.exe` を使う。** 無印 `.exe` はコンソールに接続せず、終了コードが実行完了を待たずに 0 を返す。`GodotEngine/godot.cmd` がラッパー | 全フェーズ |
| 2026-09-03 | **テスト専用アセット `tests/assets/test_tone.tres`**（0.3 秒 / 8kHz / 6.4KB の `AudioStreamWAV`）を置く。実素材ゼロでも音の再生経路を検証するため。`tests/` はエクスポート除外対象 | phase-03 以降 |

### データモデル・パイプライン

| 日付 | 決定 | 影響 |
|------|------|------|
| 2026-09-02 | シナリオ更新の入口はエディタプラグインと CLI の二本立て。**ランタイムから GAS API は叩かない**（CORS 制約） | phase-07 |
| 2026-09-02 | 選択肢と parallel 演出はシート上で独立した行として書き、パーサが畳み込む | phase-01 |
| 2026-09-02 | 既読管理のため安定ステップID `uid`（`topic_id:order`）を導入。`step_index` は永続化しない | phase-01, 05, 06 |
| 2026-09-03 | **R-01 解消**: `@abstract AdvStep` + `Array[AdvStep]` の `.tres` 往復で派生型が保たれる。設計変更は不要 | phase-02 以降 |
| 2026-09-03 | **R-07 解消**: `Array[AdvEffectStep]` でも `class_name` の循環は起きない（4.5 / 4.7）。それでも `Array[AdvStep]` を維持する（基底が派生を知る構造を避ける）。読み出し側が `as AdvEffectStep` でキャストする | phase-03 |
| 2026-09-03 | **R-02 解消**: `--headless --script` の前に `--import` を 1 回。`--import` では `EditorPlugin._enter_tree()` が走らないため、**CLI は `output_dir` の既定値フォールバックを持つ**（phase-07 で実装済み） | phase-07 |
| 2026-09-03 | `AdvOptionStep`（パースの中間表現）を仕様書 §4.3 に正式採用。`AdvPlayer` はこの型を見ない | phase-01, 05 |
| 2026-09-03 | 検証コード `invalid_json` を §4.9 に追加。**`invalid_condition` は `AdvScenarioValidator` が検出する**（`parse()` 単独では出ない） | 全フェーズ |
| **2026-09-03** | **U-07 確定: 章分割運用は行わない。`AdvScenarioBook.merge()` は実装しない。** JSON 1 本 → Book 1 本。`goto` の参照整合性は単一 Book 内で厳密に検証する | phase-07 |
| **2026-09-03** | **`AdvScenarioBook` に `schema_version` / `content_hash` を実装**（phase-01 からの持ち越しを解消）。`content_hash` は**両方が非空で一致したときだけ**書き出しをスキップする | phase-07 |
| **2026-09-03** | **インポータの出力は id 単位のファイルに分ける**: `scenario_book.tres` + `characters/<id>.tres` + `topics/<id>.tres`。「全消し再生成」ではなく差し替えにし、JSON から消えた id は**削除せず `stale_resource` の WARNING** | phase-07 |
| **2026-09-03** | **`.tres` の上書き生成には `Resource.take_over_path()` を使う**（`ResourceSaver.FLAG_CHANGE_PATH` では不足）。既存ファイルがリソースキャッシュに載っていると保存が弾かれるため。**参照される側を先に保存**して `resource_path` を付けると、Book 側が ExtResource 参照になる | phase-07 以降 |
| **2026-09-03** | **`missing_portrait_texture` は `portrait_set` を持たないキャラクターを対象外にする。** 立ち絵無しキャラは設計上の正常な形（仕様書 §1 の芯 4） | phase-07 |
| **2026-09-03** | **検証コードを 3 つ追加**: `fetch_failed`（ERROR）/ `write_failed`（ERROR）/ `stale_resource`（WARNING）。パイプラインの失敗も `AdvIssue` に寄せ、Dock と CLI の表示経路を 1 本に保つ | phase-07 |
| **2026-09-03** | **GAS の `content_hash` は `generated_at` を含めずに計算する。** 毎回変わる値を混ぜると差分スキップが永久に効かない | phase-07 |
| **2026-09-03** | **URL の秘匿**: Dock の入力値は `user://adv_kit_import.cfg`（`res://` にも `ProjectSettings` にも書かない）。CLI は `--url=` か環境変数 `ADV_KIT_SCENARIO_URL` | phase-07 |
| **2026-09-03** | **生の URL を `AdvImportResult` に入れない。** `import_from_url()` の入口で `redact_url()` を通し、`source_label` も issue の location もホスト名までに丸める。**表示側で消す設計は漏れる**（実 GAS で通したとき、CLI の結果行が `source_label` を印字して URL が標準出力とチャットに出た）。取得失敗時も丸めたまま、原因は HTTP ステータスでメッセージ側に載せる | phase-07 以降 |
| **2026-09-04** | **phase-08 の Web scenes export は、遅延ロードする素材をゲーム側シーンの `sample_assets` に明示する。** ランタイムのパス文字列ロード契約は変えず、PCK への依存登録だけを行う | phase-08 |
| **2026-09-04** | **headless 音声テストは再生開始のフレーム遅延を許容する。** `test_effects.gd` は BGM 開始を最大 8 フレーム待ってから状態を検証し、ドライバ起因の一時的な失敗を回帰と区別する | phase-08 |

### UI・進行制御

| 日付 | 決定 | 影響 |
|------|------|------|
| 2026-09-02 | UI は外観を持たない基底クラスとし、見た目は常にゲーム側が差し替える。Kit は `Theme` を持たない | phase-02, 05, 06 |
| 2026-09-03 | **R-08 解消**: ヘッドレスの `SceneTree` スクリプトでも `Tween` は完走する。`_initialize()` 内で `add_child()` した子の `_ready()` は次フレームなので、`onready` 参照の前に `await process_frame` が要る | phase-03 以降 |
| **2026-09-03** | **R-20（R-08 の続き）**: 同じ理由で、`_initialize()` 内で `add_child()` した `HTTPRequest` は `is_inside_tree() == false` のため `request()` が `ERR_UNCONFIGURED` を返す。**1 フレーム待つこと。** さらに**ホスト自身がツリー外だと `get_tree()` が null** を返すので `Engine.get_main_loop() as SceneTree` から取る | phase-07 以降 |
| 2026-09-03 | **R-09 解消**: `RichTextLabel.visible_ratio` + `VC_CHARS_AFTER_SHAPING` は日本語 + BBCode で意図どおり | phase-02 |
| 2026-09-03 | **入力を拾うノードは 1 つに寄せる。** `_unhandled_input` は木の逆順で配られるため、複数が同じアクションを拾うとノード順が暗黙の優先順位になる | phase-02 以降 |
| 2026-09-03 | **R-13 解消**: `@abstract` メソッドを `await` しても `REDUNDANT_AWAIT` は出ず、コルーチンなら正しく待つ | phase-03 |
| 2026-09-03 | **`AdvStage` は pose / expression / slot を「表示状態」として持つ**。`AdvPlayer` の同名 3 辞書は「シナリオが最後に指定した値」。**セーブ復元には `AdvStage` 側が正** | phase-03, 05 |
| **2026-09-03** | **U-10 確定: `get_progress()` に `portrait_states` を含める。** 保存するのは `AdvStage` の表示状態。phase-05 の実装がこの形になっており、仕様書 §9.1 / §5.3 へ反映済み | phase-05 |

### 演出（排他ターゲットと台帳）

| 日付 | 決定 | 影響 |
|------|------|------|
| 2026-09-03 | **同時に走る演出の衝突を仕様化**。演出ごとに**排他ターゲット**を宣言し、重なったら `conflicting_parallel_effects` の ERROR。判定基準は effect_id の重複ではなく**書き換える対象の重複**。ホストが BLOCKING 演出ならそれも同時に走る側に数える | phase-01, 03 |
| 2026-09-03 | **演出ハンドラは自分の排他ターゲットの実行中 `Tween` を `kill()` してから開始する**。「後から始まった方が勝つ」。実現は `AdvEffectContext` の台帳が一元的に行う | phase-03, 04 |
| 2026-09-03 | **拡張演出の排他ターゲットは `AdvEffectHandler.exclusive_targets(params)` の仮想メソッド**で宣言する | phase-03 |
| 2026-09-03 | **`AdvEffectHandler` は `effect_id` をフィールドに持つ**。1 クラスで複数 id を扱えるようにする | phase-03 |
| 2026-09-03 | **中断後始末は `kill()` する側（台帳）が呼ぶ**。自然完了では呼ばない。**中断された `hide_portrait` はノードを解放しない** | phase-03, 04 |
| 2026-09-03 | **同じプロパティの書き手は 1 つに決める。** 台帳は調停役であって所有者ではない（`adopt_tween()`） | phase-03, 04 |
| 2026-09-03 | **`ShakeRoot.position` の持ち主は `shake` 演出**。`AdvScene` はリサイズ時に size のみ同期する | phase-03 |
| 2026-09-03 | **`stop_bgm()` は BGM チャンネル 2 本すべてを対象にする**（R-17 の解） | phase-03 |
| 2026-09-03 | **U-09 確定（実装に合わせて確定）: `modulate` を成分で分ける。** ダークは **RGB のみ**（`AdvPortrait.set_modulate_rgb()`。排他ターゲット `portrait_modulate:{speaker}`）、フェードは **alpha のみ**（`portrait_alpha:{speaker}`）。ホップは `position` を直接書き、`move_portrait` と `portrait_position:{speaker}` を共有して「後勝ち」で決着する（＝**移動中に話者が変わると移動が打ち切られる**。許容する）。<br>**当初検討した合成プロパティ案（`tint` / `fade_alpha` / `slot_position` / `hop_offset` の 4 本）は採らない** — 成分で分ける今の形で足りており、プロパティが 4 本増えるコストと phase-03 のテスト改修に見合わない。取り合いが実害になったら再検討する | phase-04 |

### 音声

| 日付 | 決定 | 影響 |
|------|------|------|
| 2026-09-02 | オート・スキップ・バックログ・ボイスをすべて Kit が持つ | phase-03, 05, 06 |
| 2026-09-03 | **R-14 解消**: ヘッドレスでも `AudioStreamPlayer` の `play` / `playing` / 再生位置 / `finished` が機能する。ただし `Voice` バスは既定で存在せず、常に `Master` フォールバック経路が走る | phase-03, 06 |
| 2026-09-03 | **autoplay ガードは phase-03 で実装した**（仕様書 §10 は phase-08 としていた）。phase-08 は実 Web での検証のみ | phase-03, 08 |
| 2026-09-03 | **autoplay ガードの帰結**: topic の先頭ステップに畳み込まれた音は鳴らない（保留せず破棄する）。**シナリオの 1 行目に音を置かない**運用にするか、ゲーム側が `unlock_audio()` を先に呼ぶ | phase-03, 07 |
| 2026-09-03 | **音声ノード（`AdvAudioDirector` / `AdvVoicePlayer`）は `AdvPlayer` の子として実行時に生成する** | phase-03 |
| **2026-09-03** | **U-08 確定（B 案）: `stop_bgm` の `apply_final()` だけ即座に停止する。** `play_se` / `play_bgm` は何もしない。「スキップ中に音を鳴らさない」（§9.3）を破らずに、飛ばした停止が置き去りになる穴を塞ぐ。**phase-07 の作業中に実装済み**（`test_effects.gd` に 5 アサーション追加） | phase-06, 07 |
