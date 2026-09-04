# ADV Kit 仕様書（Godot 向け ADV 共通パッケージ）

> このドキュメントが source of truth。差分分析（[D]）の結果でここを更新し続ける。
> 設計方針は `godot-design-policy` に準拠する。
>
> **置き場所はここ（`docs/spec/adv-kit-spec.md`）だけ。** 2026-09-03 まで Obsidian と Claude Project に
> 2 つの写しがあり、**片方に phase-03、もう片方に phase-04〜06 の反映しか無い**状態で分岐していた。
> 同じ事故を繰り返さないため、写しを作らない（§0 の運用ルール参照 → `docs/README.md`）。

## 1. 概要

- **これは何か**: Godot 4 製ゲームで共通利用する ADV（アドベンチャー／会話パート）機能のライブラリ
- **配布形態**: `res://addons/adv_kit/` に自己完結するアドオン。**当面は各ゲームへフォルダをコピーする**
  - リポジトリは **1 本**（開発用プロジェクト `AdvKit/` の中にアドオンが入る形）。アドオン単体のリポジトリは
    `project.godot` を持てず、エディタで開けず `--headless` テストも走らないため分けない
  - submodule で取り込みたくなったら、`git subtree split -P addons/adv_kit` で**履歴付きのアドオン単体リポジトリを後から切り出す**。
    submodule はリポジトリ全体を 1 フォルダとしてマウントするため、リポジトリ直下が `plugin.cfg` である必要がある
- **対象プラットフォーム**: Web（unityroom 投稿を第一想定）。デスクトップでも動作すること
- **利用者**: 自分（Yuu）および同じ雛形から始まる将来のプロジェクト

### 設計上の芯

1. **シナリオはコードではなくデータ**。スプレッドシートを一次ソースとし、Godot 側は `.tres` として読むだけ。
2. **最小単位は「1回のテキスト送りで進む1ステップ」**。テキストも演出も同じステップ列に並ぶ。
3. **話題（topic）が呼び出し単位**。ゲーム側は `play_topic("prologue_01")` だけを知っていればよい。
4. **立ち絵が無くても成立する**。立ち絵は表現の追加であって、進行の前提ではない。
5. **JSON はビルド時にしか触らない**。ランタイム（特に Web）が読むのは `.tres` だけ（§10 参照）。
6. **見た目は Kit が持たない**。UI ノードは基底クラスと signal の契約だけを定め、外観はゲーム側が継承して差し替える（§5.4）。

---

## 2. アーキテクチャ方針

`godot-design-policy` に準拠する。確定事項:

| 項目 | 値 |
|------|-----|
| エンジン | Godot **4.5〜4.7**（unityroom 対応帯。`@abstract` が使える 4.5 以上を前提とする） |
| 言語 | GDScript のみ。静的型付け必須。C#(.NET) は使わない |
| レンダラー | **Compatibility** |
| スレッド | `Thread` / `WorkerThreadPool` を**使わない** |
| アニメーション | 組み込み `Tween` |
| データ定義 | custom `Resource`（`.tres`） |
| 入力 | InputMap アクション経由（`adv_advance` / `adv_skip` / `adv_auto` / `adv_backlog`。アドオンが未定義時に自動登録する。§4.6） |

### 条件付き方針の確定事項

- **unityroom 連携**: ADV Kit 自体はランキング／X ポストに関与しない。スコア送信はゲーム側の責務。Kit は `addons/adv_kit/` に閉じ、`addons/unityroom_sdk/` と共存する。
- **インタラクティブオーディオ**: なし。`AudioStreamPlayer` 直接制御のみ。
- **セーブ**: ADV Kit は「進行位置・フラグ・既読集合・立ち絵の表示状態」を `Dictionary` として **返す／受け取る** だけ。`user://` への書き込みはゲーム側の Autoload が担当する。
- **Autoload**: ADV Kit は Autoload を**1つも追加しない**。`AdvPlayer` はシーン内のノードとして存在する。
- **プレイ支援機能**: オートモード・スキップ（既読管理あり）・バックログ・ボイス再生を**すべて Kit が持つ**（§9）。
- **既定テーマ**: Kit は `Theme` を**持たない**。外観は常にゲーム側が差し替える（§5.4）。

### レイヤー分離（Godot 流の読み替え）

Unity 版の 4 層は持ち込まないが、**「Node に依存しないロジック」と「表示」の境界だけは厳格に引く**。

| 区分 | 実体 | 置き場所 | Node 参照 |
|------|------|----------|-----------|
| データ | `Resource` 派生 | `resources/` | 不可 |
| ロジック | `RefCounted` 派生（パーサ、バリデータ、進行状態） | `core/` | **不可** |
| 実行 | `Node` 派生（進行制御、演出ハンドラ） | `runtime/` | 可 |
| 表示 | `Control` / `.tscn` | `ui/` | 可 |
| ツール | `EditorPlugin` / CLI | `editor/`, `import/` | 可 |

`core/` は `Node` / `SceneTree` を一切参照しない。これによりシナリオのパース・検証・進行判定を `--headless` でテストできる。
**待機（`await`）を伴う処理は必ず `runtime/` 側に置く**。`core/` は「1回分の状態を進める同期メソッド」だけを提供し、待つかどうかは呼び出し元の Node が決める。

**`ui/` は `runtime/` を知らない。** `AdvStage` / `AdvPortrait` は演出ハンドラの存在を知らず、
演出側が `AdvEffectContext` 経由でこれらのメソッドを呼ぶ。唯一の例外は `AdvScene`（シーンの組み立て役）が
`AdvPlayer` を `@export` で保持することで、これは配線であって依存ではない。

**`runtime/` と `ui/` は `import/` `editor/` を知らない。** インポータはエクスポート除外対象（§10）なので、
ランタイムから参照した時点で製品ビルドが壊れる。

---

## 3. ディレクトリ構造

```text
res://
  addons/
    adv_kit/
      plugin.cfg
      adv_kit_plugin.gd            # EditorPlugin エントリ。設定 / InputMap / Dock の登録
      core/
        adv_scenario_parser.gd     # JSON(Dictionary) -> Resource 群
        adv_scenario_validator.gd  # 参照整合性チェック
        adv_condition.gd           # condition 文字列の構文解析・評価
        adv_effect_schema.gd       # 演出パラメータの型・既定値表（§7）と型変換
        adv_issue.gd               # 検証結果の1件（RefCounted）
        adv_parse_result.gd        # parse の戻り値（RefCounted）
        adv_progress_state.gd      # 進行位置・フラグ・既読集合（Node 非依存）
        adv_backlog.gd             # バックログのリングバッファ（Node 非依存）
        adv_backlog_entry.gd       # バックログ1件（RefCounted）
      resources/
        adv_character.gd
        adv_portrait_set.gd
        adv_step.gd                # @abstract 基底
        adv_line_step.gd
        adv_effect_step.gd
        adv_choice_step.gd
        adv_option_step.gd         # パースの中間表現
        adv_jump_step.gd
        adv_topic.gd
        adv_scenario_book.gd
        adv_kit_settings.gd
      runtime/
        adv_player.gd              # 進行制御
        adv_effect_context.gd      # 演出の実行文脈と排他ターゲットの Tween 台帳（§7）
        adv_audio_director.gd      # SE / BGM のチャンネル（§7）
        adv_voice_player.gd        # ボイス再生（単一チャンネル）
        effects/
          adv_effect_handler.gd    # @abstract
          adv_shake_effect.gd
          adv_fade_effect.gd
          adv_portrait_effect.gd   # 移動 / 表示 / 退場
          adv_audio_effect.gd
      ui/                          # 外観を持たない基底クラス（§5.4）
        adv_scene.tscn / .gd
        adv_message_window.gd
        adv_choice_menu.gd
        adv_backlog_view.gd
        adv_stage.tscn / .gd
        adv_portrait.tscn / .gd
      import/                      # エクスポート除外。ランタイムから参照しない
        adv_scenario_importer.gd   # 取得 + 検証 + 保存（共通ロジック）
        adv_import_result.gd       # インポート1回分の結果（AdvParseResult を継承）
        adv_import_cli.gd          # extends SceneTree。--headless 実行口
        gas/
          adv_scenario_export.gs   # GAS の doGet(e)（Godot は読まない）
          README.md                # シート構成とデプロイ手順
      editor/                      # エクスポート除外
        adv_import_dock.tscn / .gd # エディタパネル
      samples/
        sample_scenario.json
        ui/                        # 無装飾の参照実装。game/ は使わなくてよい
          plain_message_window.tscn / .gd
          plain_choice_menu.tscn / .gd
          plain_backlog_view.tscn / .gd
      tests/
        test_scenario_parse.gd     # extends SceneTree（phase-01）
        test_playback.gd           # phase-02
        test_effects.gd            # phase-03
        test_auto_direction.gd     # phase-04
        test_progress.gd           # phase-05
        test_play_assist.gd        # phase-06
        test_import.gd             # phase-07
        assets/
          test_tone.tres           # テスト専用の極小 AudioStreamWAV（下記）
      README.md
  game/                            # 各ゲーム固有。Kit は書き込まない
    resources/adv/scenario/*.tres  # インポータの出力先（既定）
    assets/adv/portraits/...
```

**原則**: ADV Kit は `addons/adv_kit/` の外へ**コードを置かない**。生成物（`.tres`）だけが `game/` に出る。
GAS スクリプトも Godot のコードではないが、アドオンを自己完結させるため `import/gas/` に置く。
出力先は `ProjectSettings` の `adv_kit/import/output_dir`（既定 `res://game/resources/adv/scenario/`）で変更できる。この設定はプラグイン有効化時に `_enter_tree()` で登録する。

> **`tests/assets/test_tone.tres`**: 0.3 秒 / 8kHz の `AudioStreamWAV` をコード生成して `.tres` 保存したもの（6.4KB）。
> 実素材が揃う前に「音が実際に鳴る経路」（SE の多重再生・BGM のクロスフェード・ボイス）を
> ヘッドレスで検証するために置く。テキストリソースなのでバイナリを git に持ち込まない。
> `tests/` はエクスポート除外対象（§10）なので製品には含まれない。

---

## 4. データモデル

### 4.1 AdvCharacter（キャラクターエンティティ）

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `id` | `StringName` | 話者ID。シナリオから参照される一意キー |
| `display_name` | `String` | 話者名。名前欄に出る |
| `name_color` | `Color` | 名前欄の色（既定は白） |
| `portrait_set` | `AdvPortraitSet` | 立ち絵定義。**null 可**（立ち絵無しキャラ） |

### 4.2 AdvPortraitSet（立ち絵差分）

差分は **表情 × ポーズ** の 2 軸。全組み合わせを用意する必要はない。

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `texture_paths` | `Dictionary` | キー `"<pose>/<expression>"`（`String`）→ テクスチャの**リソースパス文字列**（`String`） |
| `default_pose` | `StringName` | 未指定時に使うポーズ |
| `default_expression` | `StringName` | 未指定時に使う表情 |
| `pivot_offset_ratio` | `Vector2` | 立ち絵の基準点（既定 `(0.5, 1.0)` = 足元中央） |
| `scale` | `float` | 個別スケール補正 |

**`Texture2D` を直接持たない理由**: `@export var t: Texture2D` を持つと `.tres` のロード時に Godot が全テクスチャを自動で読み込む。ADV では未登場キャラの立ち絵まで一括ロードされ、Web で初期ロードが伸びる。パス文字列で保持し、`AdvStage` が必要になった時点で `load()` する。

**解決順**（`resolve(pose, expression) -> String`）:

1. `<pose>/<expression>`
2. `<pose>/<default_expression>`
3. `<default_pose>/<expression>`
4. `<default_pose>/<default_expression>`
5. いずれも無ければ**空文字を返す**（呼び出し側は立ち絵無しとして扱い、**進行は絶対に止めない**）

存在チェックは `ResourceLoader.exists()` を使う。`FileAccess.file_exists()` は使わない（`.png` はインポート後 `.ctex` になり、エクスポート後の `.pck` では元パスが存在しないため）。**存在チェックはインポート時（エディタ／CLI）のみ行い、ランタイムでは行わない。**

> **`texture_paths` は `poses` × `expressions` の総当たりで組む**（§6.3 のパス規約に従う）。
> 全組み合わせを用意する必要が無い以上、**存在しないパスが表に入るのは正常**。
> したがって `missing_portrait_texture` 検査は**総当たり全部を対象にしない**。
> **シナリオ中で実際に参照された `(pose, expression)` の解決結果だけ**を検査対象とする。
> 総当たりを検査すると、正常なプロジェクトが警告まみれになる。
>
> **`portrait_set` が null のキャラクターも検査対象外**（phase-07 で確定）。
> 立ち絵を持たないキャラは設計上の正常な形（§1 の芯 4）であり、
> 検査すると地の文的な話者の全行に WARNING が出る。
>
> **重複排除は「入力の組み合わせ」ではなく「解決結果」で行う。**
> 解決順にフォールバックがあるため、別々の `(pose, expression)` が同じパスへ落ちる。
> 入力側で畳むと同じ警告が複数出る。

### 4.3 ステップ（シナリオ最小単位）

`AdvStep` を `@abstract` 基底とし、以下が派生する。**1ステップ = 1回のテキスト送りで消費される単位**。

`AdvStep` 共通フィールド:

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `order` | `int` | **スプレッドシートの `order` 列の値をそのまま保持する。** 書き手が振る値で、行を挿入しても既存行は変わらない |
| `uid` | `StringName` | **安定ステップID**。`"<topic_id>:<order>"`。パーサが生成する。既読管理とセーブの復元位置はこの ID を使う（§9.1） |
| `step_index` | `int` | 所属 topic の `steps` 配列における添字（畳み込み後）。`.tres` には保存してよいが、**セーブデータに書き出してはならない** |
| `parallel_effects` | `Array[AdvStep]` | このステップの開始と同時に走る演出（畳み込み結果）。**要素は必ず `AdvEffectStep`** だが、宣言型は `Array[AdvStep]` にする（下記）。スプレッドシートにも JSON にもこのフィールドは現れない。§4.8 参照 |

> **`step_index` をセーブデータに出さない理由**: 畳み込み後の添字なので、シナリオに `parallel` 演出を1行足しただけで全部ずれる。復元位置が別の台詞を指すことになる。`uid` は `order` 由来なので、行を挿入しても既存ステップの ID は変わらない。
> 混同しないこと: `.tres`（シナリオそのもの。再インポートで作り直される）に `step_index` が入るのは正常。禁止しているのは `get_progress()` の戻り値に含めることだけ。
> `order` の重複は検証エラー（`duplicate_step_order`）。同じ topic 内で `order` が重複すると `uid` が衝突するため。
>
> **`parallel_effects` を `Array[AdvEffectStep]` と書かない理由**: 基底が派生を型注釈に使うと `class_name` の解決が循環する懸念があったが、**Godot 4.5 / 4.7 で実測したところ循環エラーは起きない**（`Array[AdvEffectStep]` でも解決され、`.tres` 往復も通る）。それでも `Array[AdvStep]` を維持するのは、**基底クラスが自分の派生クラスを知る構造を避けるため**と、**型の自己参照がエンジン終了時のスクリプトリークを増やすため**（下記）。要素が `AdvEffectStep` であることは**パーサが保証し**（畳み込みで `dangling_parallel` 等を弾く）、読み出し側は `as AdvEffectStep` でキャストする。
>
> **既知の副作用**: `adv_step.gd` の型が自分自身を参照するため、エンジン終了時に
> `ObjectDB instances leaked` / `resources still in use` が出る。**終了コードには影響しない**。
> `--headless` の CI は**必ず終了コードで判定すること**（stderr の有無で判定しない）。

#### AdvLineStep（立ち絵情報に紐づいたテキスト）

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `speaker_id` | `StringName` | **`AdvCharacter.id` への参照**。`AdvScenarioBook.characters` の辞書キーと一致する。空文字なら地の文（名前欄非表示）。存在しない id は検証エラー `unknown_speaker` |
| `expression` | `StringName` | 空なら現在の表情を維持 |
| `pose` | `StringName` | 空なら現在のポーズを維持 |
| `slot` | `StringName` | 立ち絵の立ち位置。`left` / `center_left` / `center` / `center_right` / `right`。空なら現在位置維持、初出なら `center` |
| `text` | `String` | 本文。BBCode 可 |
| `voice_path` | `String` | ボイスのリソースパス。**空なら何も再生せず、そのまま進行する**（§9.4） |

> **命名規約**: `AdvCharacter` / `AdvTopic` への参照を保持するフィールドには `_id` サフィックスを付ける（`speaker_id`、`topic_id`）。一方、**スプレッドシートの列名と JSON のキーは `speaker` / `goto`** とし、サフィックスを付けない。Resource 側だけが「これは参照である」ことを型名で示す。この対応は `AdvScenarioParser` が吸収する。
> **例外**: steps シートの `topic_id` 列だけは行のグループ化キーなのでサフィックスを付ける（`topic` だと話題そのものと紛らわしいため）。

#### AdvEffectStep（演出）

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `effect_id` | `StringName` | §7 の表を参照 |
| `params` | `Dictionary` | 演出ごとのパラメータ。**キーと値の型は §7 の表が定義する**（`AdvEffectSchema`）。スプレッドシートでの書き方は §6.1 |
| `sync_mode` | `int` (enum `SyncMode {PARALLEL, BLOCKING}`) | 下記 |
| `auto_advance` | `bool` | `BLOCKING` のときのみ有効。`true` なら演出完了後に自動で次ステップへ進む。`false`（既定）なら演出完了後にテキスト送りを待つ |

**`sync_mode` の意味**（要件「直前のテキストと共に非同期再生されるか、テキスト送りまで自身を待ち受けるか」の確定）:

- `PARALLEL`: **直前のステップ**の開始と**同時に**再生を開始する。テキスト送り可能状態を妨げない。演出の完了は待たない。
- `BLOCKING`: この演出を**独立した1ステップ**として扱う。演出完了までテキスト送り入力を受け付けない。完了後の挙動は `auto_advance` による。

> `PARALLEL` 演出がどう `parallel_effects` に入るかは §4.8（畳み込み）を参照。

#### AdvChoiceStep（選択肢）

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `prompt` | `String` | 見出し（空可） |
| `options` | `Array[Dictionary]` | `{label: String, goto: StringName, flag: String, condition: String}`。**スプレッドシートでは1選択肢＝1行**で書き、パース時に畳み込む（§4.8） |

- `goto`: 遷移先 topic_id。空なら現在の topic を継続。
- `flag`: 選択時に立てるフラグ名（空可）。
- `condition`: 表示条件。§4.7 の文法。空なら常に表示。

#### AdvJumpStep（話題遷移）

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `goto` | `StringName` | 遷移先 topic_id。空なら topic 終了 |
| `condition` | `String` | §4.7 の文法。偽なら素通りして次のステップへ |

#### AdvOptionStep（選択肢1件・**パースの中間表現**）

JSON の `type` は5種あり、`option` もステップとして flat に並ぶ（§6.3）。
`AdvTopic.steps` を畳み込み前後で `Array[AdvStep]` に保つため、`option` 行も一度ステップとして読む。

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `label` | `String` | 選択肢の表示テキスト |
| `goto` | `StringName` | 遷移先 topic_id。空なら現在の topic を継続 |
| `flag` | `String` | 選択時に立てるフラグ名。空可 |
| `condition` | `String` | §4.7 の文法。空なら常に表示 |

**畳み込み（§4.8）後の `AdvTopic.steps` に `AdvOptionStep` が残ることはない。**
残る場合は畳み込み先が無かったということで、`dangling_option` の ERROR になっている。
`AdvPlayer` はこの型を見ない。選択肢は `AdvChoiceStep.options` から読む。

### 4.4 AdvTopic（話題）

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `id` | `StringName` | 一意キー |
| `title` | `String` | 管理用の表示名 |
| `steps` | `Array[AdvStep]` | ステップ列 |
| `tags` | `PackedStringArray` | 分類用。**`entry` タグを持つ topic は「ゲーム側から直接呼ばれるエントリポイント」**として扱い、到達性検証（`unreachable_topic`）の対象外にする |

### 4.5 AdvScenarioBook

`topics: Dictionary`（`StringName -> AdvTopic`）と `characters: Dictionary`（`StringName -> AdvCharacter`）を持つ集約 Resource。ゲーム側はこれ1つを `AdvPlayer` に渡す。
型付き辞書 `Dictionary[StringName, AdvTopic]` / `Dictionary[StringName, AdvCharacter]` で宣言する（エンジン帯 4.5+）。

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `topics` | `Dictionary[StringName, AdvTopic]` | topic_id → 話題 |
| `characters` | `Dictionary[StringName, AdvCharacter]` | character_id → 話者 |
| `schema_version` | `int` | JSON の `schema_version` をそのまま保持する。欠落時は 0 |
| `content_hash` | `String` | JSON の `content_hash` をそのまま保持する。インポータが「変更なし」を判定する材料（§6.4） |

`has_same_content(other) -> bool` は、**両方の `content_hash` が非空で一致したときだけ**真を返す。
片方でも空なら「分からない」＝書き出す、に倒す。

**Book は 1 つだけ扱う。** 章ごとにファイルを分ける運用（複数 Book のマージ）は
**2026-09-03 に「行わない」で確定した**（§13 U-07）。したがって `merge()` は**実装しない**。
`goto` の参照整合性は単一 Book 内で厳密に検証する。
分割運用が必要になったら、マージと「未解決 `goto` を警告に降格するモード」を追加するところから設計し直す。

### 4.6 AdvKitSettings

汎用演出と入力の設定。`.tres` としてプロジェクトに1つ置き、`AdvPlayer` に `@export` で注入する。

| フィールド | 既定 | 説明 |
|-----------|------|------|
| `dim_non_speakers` | `true` | 非話者の立ち絵を暗くする |
| `dim_color` | `Color(0.55,0.55,0.6)` | 暗転時に `modulate` の RGB へ入れる色 |
| `dim_duration` | `0.15` | 明暗の遷移時間。**暗黙の登場（§7）のフェード時間にも使う** |
| `hop_on_speaker_change` | `true` | 話者交代時に新話者を小さく跳ねさせる |
| `hop_height` | `18.0` | 跳ねる高さ(px) |
| `hop_duration` | `0.22` | 跳ねる時間 |
| `typing_speed` | `40.0` | 1秒あたりの表示文字数。0 で即時表示 |

**プレイ支援（§9）**

| フィールド | 既定 | 説明 |
|-----------|------|------|
| `auto_wait_time` | `1.5` | オートモードで、テキスト表示完了後に次へ進むまでの秒数 |
| `auto_wait_for_voice` | `true` | オートモードでボイス再生の終了を待つか。`true` なら `max(ボイス長, auto_wait_time)` |
| `skip_unread` | `false` | `false` = 既読ステップのみスキップ。`true` = 未読も強制スキップ |
| `skip_interval` | `0.02` | スキップ中に1ステップ進める間隔（秒） |
| `skip_stops_at_choice` | `true` | 選択肢に到達したらスキップを解除する |
| `backlog_max_entries` | `200` | バックログの保持上限。超えた分は古いものから捨てる |
| `backlog_voice_replay` | `true` | バックログからボイスを再生できるようにする |
| `voice_bus` | `&"Voice"` | ボイス用のオーディオバス名。存在しなければ `Master` にフォールバック |

**入力アクション**

| フィールド | 既定 | 既定バインド |
|-----------|------|-------------|
| `advance_action` | `&"adv_advance"` | マウス左 / Enter / Space |
| `skip_action` | `&"adv_skip"` | Ctrl（押しっぱなしでスキップ継続） |
| `auto_action` | `&"adv_auto"` | A |
| `backlog_action` | `&"adv_backlog"` | マウスホイール上 / B |

**InputMap の自動登録**: `adv_kit_plugin.gd` の `_enter_tree()` で、上記4アクションが `ProjectSettings` に未定義なら既定バインドを追加する。既に定義済みなら**触らない**。

### 4.7 condition の文法

フラグの真偽だけを扱う最小文法。**GDScript の `Expression` クラスは使わない**（Web での安全性と、スプレッドシート記述者にとっての可読性のため）。

```
expr    := or_expr
or_expr := and_expr ( "||" and_expr )*
and_expr:= term ( "&&" term )*
term    := "!"? identifier
identifier := [A-Za-z_][A-Za-z0-9_]*
```

- **`&&` が `||` より強く結合する**（`a && b || c` は `(a && b) || c`）。
- 括弧は**サポートしない**。必要になったら仕様書を改訂する（§13 U-04）。
- 未定義のフラグは `false` として評価する（構文検証の段階では「未定義フラグ」を検出しない。フラグは実行時に動的に生えるため、事前に集合を確定できない）。
- **空文字は文法の対象外**。構文検証を行わず、評価は常に `true`（＝条件指定なし）とする。

### 4.8 畳み込み（fold）

**スプレッドシートは「1行 = 1レコード」しか表現できない。** ネストした配列（`parallel_effects`、`options`）を1セルに JSON で押し込むのは書き手にとって事故のもとなので、**すべて独立した行として書き、パース時に直前のステップへ吸収する**。この処理を畳み込みと呼ぶ。

| 行の種類 | 畳み込み先 | 除去後 |
|----------|-----------|--------|
| `type=effect` かつ `sync=parallel` | 直前のステップの `parallel_effects` | `steps` から除去 |
| `type=option` | 直前の `AdvChoiceStep.options` | `steps` から除去 |

- **PARALLEL の畳み込み先は `AdvLineStep` に限らない。** 直前が `BLOCKING` の `AdvEffectStep` でも `AdvChoiceStep` でもよい（「揺らしながら選択肢を出す」が書けるようにするため）。したがって `parallel_effects` は `AdvStep` 基底が持つ。
- 複数の `parallel` 行を連続して書けば、すべて同じステップに畳み込まれる。順序は `order` 順を保つ。
- **同じステップに畳み込まれた演出は同時に走る。** 同じものを書き換える演出を並べると結果が定まらないため、
  §7 の**排他ターゲット**で衝突を検証する（`conflicting_parallel_effects`）。
  ホストのステップ自身が `BLOCKING` 演出の場合、**それも同時に走る側に数える**。
- **topic の先頭ステップが `parallel`** の場合のみ検証エラー（`dangling_parallel`）。畳み込み先が存在しないため。
- 直前が `AdvChoiceStep` でない `option` 行は検証エラー（`dangling_option`）。
- 畳み込み後、残った全ステップの `step_index` を 0 起点で振り直す。

**畳み込みは Godot 側（`AdvScenarioParser`）が行う。** GAS は行を JSON の `steps` 配列へ素直に並べるだけで、`sync` や `type: "option"` を解釈しない。JSON を flat に保つことで、手書き JSON でのテストが容易になる。

#### 記述例（steps シート）

| topic_id | order | type | speaker | text | effect_id | params | sync | label | goto |
|---|---|---|---|---|---|---|---|---|---|
| ch1 | 10 | line | yuu | 扉が開いた。 | | | | | |
| ch1 | 20 | effect | | | play_se | `stream=res://…/door.ogg` | parallel | | |
| ch1 | 30 | effect | | | shake | `strength=8; duration=0.4` | parallel | | |
| ch1 | 40 | choice | | | | | | | |
| ch1 | 50 | option | | | | | | 入る | ch2_in |
| ch1 | 60 | option | | | | | | 引き返す | ch2_back |

→ パース後は **2 ステップ**（`AdvLineStep` + `AdvChoiceStep`）。SE と揺れは line の `parallel_effects` に、2つの選択肢は choice の `options` に入る。

### 4.9 検証コード一覧

`AdvScenarioValidator` / `AdvScenarioParser` / `AdvScenarioImporter` が返す `AdvIssue.code` の全集合。**この表が正。実装計画書はここを参照する。**

`severity` の原則: **シナリオが再生できなくなるものが ERROR、意図的な記述かもしれないものが WARNING。**

| code | severity | 内容 |
|------|----------|------|
| `unknown_speaker` | ERROR | `speaker_id`、または `show_portrait` 等の `speaker` パラメータが `characters` に存在しない（空文字＝地の文は除く） |
| `unknown_topic` | ERROR | `goto` の遷移先 topic_id が存在しない |
| `duplicate_topic_id` | ERROR | topic_id の重複 |
| `duplicate_character_id` | ERROR | character_id の重複 |
| `duplicate_step_order` | ERROR | 同一 topic 内で `order` が重複（`uid` が衝突し既読管理が壊れる） |
| `missing_step_order` | ERROR | `order` の欠落、または整数として解釈できない |
| `unknown_step_type` | ERROR | `type` が5種のいずれでもない。当該ステップは捨てて残りのパースを続行する |
| `unknown_slot` | ERROR | `slot` が5種のいずれでもない（空文字＝維持は除く）。表示位置が決まらないため ERROR |
| `dangling_parallel` | ERROR | topic の先頭ステップが `PARALLEL` 演出で、畳み込み先が無い |
| `dangling_option` | ERROR | 直前が `AdvChoiceStep` でない `option` 行 |
| `empty_choice` | ERROR | 畳み込み後も `options` が 0 件の `AdvChoiceStep`。進行が詰まる |
| `invalid_condition` | ERROR | `condition` の構文エラー（§4.7） |
| `missing_effect_param` | ERROR | 必須パラメータの欠落（§7） |
| `invalid_effect_param` | ERROR | 値が宣言された型へ変換できない（`duration=abc` 等） |
| `unknown_effect_id` | WARNING | §7 の表にない `effect_id`。ゲーム側が `register_effect()` で足す拡張演出かもしれない |
| `unknown_effect_param` | WARNING | スキーマ外のパラメータキー。同上。**値は捨てず文字列のまま保持する** |
| `unreachable_topic` | WARNING | どの `goto` からも参照されず、`tags` に `entry` も含まない topic |
| `empty_topic` | WARNING | steps が 0 件の topic |
| `invalid_auto_advance` | WARNING | `sync_mode == PARALLEL` なのに `auto_advance == true`（意味を持たない指定） |
| `missing_portrait_texture` | WARNING | 立ち絵の解決結果が空、または解決先のリソースが存在しない。**インポート時のみ検査**（§4.2）。進行は止まらない |
| `conflicting_parallel_effects` | ERROR | 同時に走る演出どうしが同じ**排他ターゲット**を取り合っている（§7）。同じプロパティを 2 つの Tween が書くことになり結果が定まらない |
| `invalid_json` | ERROR | JSON そのものが壊れている。ファイルが読めない／ルートがオブジェクトでない／配列の要素がオブジェクトでない／`id` が空。**`name_color` が `#rrggbb` として解釈できない場合のみ WARNING**（白にフォールバックして進む） |
| `fetch_failed` | ERROR | GAS API の取得に失敗（HTTP エラー・タイムアウト・空レスポンス・リクエスト開始不能） |
| `write_failed` | ERROR | `.tres` の書き出しに失敗（出力先ディレクトリの作成失敗を含む）。**途中で止め、半端に書き出さない** |
| `stale_resource` | WARNING | JSON に対応する id が無い `.tres` が出力先に残っている。**削除せず警告のみ**（§6.4） |

**検出の担当**（実装が食い違ったら仕様書が正）:

| 担当 | code |
|------|------|
| `AdvScenarioParser`（読み取り） | `invalid_json`, `unknown_step_type`, `missing_step_order`, `duplicate_step_order`, `duplicate_topic_id`, `duplicate_character_id` |
| `AdvScenarioParser`（畳み込み） | `dangling_parallel`, `dangling_option` |
| `AdvEffectSchema`（パーサから呼ばれる） | `missing_effect_param`, `invalid_effect_param`, `unknown_effect_id`, `unknown_effect_param` |
| `AdvScenarioValidator` | `unknown_speaker`, `unknown_topic`, `unknown_slot`, `empty_choice`, `empty_topic`, `unreachable_topic`, `invalid_auto_advance`, `conflicting_parallel_effects`, **`invalid_condition`** |
| `AdvScenarioImporter`（phase-07） | `missing_portrait_texture`, `fetch_failed`, `write_failed`, `stale_resource`, `invalid_json` |

> **`invalid_condition` は `AdvScenarioValidator` が検出する**（`AdvCondition` は文法モジュールであって検出の起点ではない）。
> したがって **`parse()` だけでは条件式の構文エラーは出ない。必ず `validate()` を併せて呼ぶこと。**
> `AdvScenarioImporter` は両方を呼ぶので、インポート経路では全コードが出る。

> **`duplicate_step_order` の行は捨てる。** `uid` が衝突したまま Book に入れると既読管理が静かに壊れるため。
> `unknown_step_type` の行も同様に捨て、残りのパースは続行する。

---

## 5. シーン構成

```text
AdvScene (Control)                     ← 各ゲームがこの .tscn をインスタンス
├── ShakeRoot (Control)                ← 画面揺れの対象。full rect
│   ├── Background (TextureRect)
│   └── Stage (AdvStage: Control)
│       └── (実行時に AdvPortrait を slot 分だけ生成)
├── FadeLayer (ColorRect)              ← ShakeRoot の後 = 手前。揺れない
├── MessageWindow (AdvMessageWindow 派生)       ← FadeLayer の後 = 最前面
├── ChoiceMenu (AdvChoiceMenu 派生)
├── BacklogView (AdvBacklogView 派生)  ← 既定は非表示。開いている間は進行を止める
└── AdvPlayer (Node)                   ← 進行制御。@export で上記を参照
    ├── AdvAudioDirector (Node)        ← 実行時に生成。SE / BGM
    └── AdvVoicePlayer (Node)          ← 実行時に生成。ボイス
```

**音声ノードは `AdvPlayer` が自分の子として実行時に生成する。** `AdvScene.tscn` に置かないのは、
ゲーム側が独自のシーン構成を組んだときにも音が鳴るようにするため。
これは「他ノードの子構成を組み替えない」（§5.4）に抵触しない。

### 5.1 前後関係と揺れの対象（確定事項）

- **フェードがダイアログを隠さない**要件は、`FadeLayer` を `MessageWindow` より**前の兄弟**に置くことだけで満たす。`CanvasLayer` は使わない（同一 Control ツリー内の兄弟順で足りるため。追加の理由はない）。
- **画面揺れの対象は `ShakeRoot`（背景＋立ち絵）のみ**。`FadeLayer` と `MessageWindow` は揺れない。
  - **ノードの実行時 reparent は行わない。** 「メッセージウィンドウも揺らす」オプションは、それを実現するには前後関係を壊すか reparent が必要になり、上のフェード要件と両立しないため**仕様として持たない**。必要になったら `AdvScene` 側で別の揺れ対象を用意する。
- **`ShakeRoot` はアンカーを設定しない（`Layout Mode = Position`）中間ノード**とし、その子（`Background` / `Stage`）を full-rect にする。full-rect アンカーの `Control` の `position` を書くと `offset_*` が書き換わるだけで、親のリサイズやアンカープリセット再適用で戻ってしまうため。Web は canvas リサイズが実際に起きるので、この構成は必須。
- アンカー無しの中間ノードは親のリサイズを自分では受け取らないため、**`AdvScene` が `resized` を購読して `ShakeRoot.size` だけを同期する**。
- **`ShakeRoot.position` の持ち主は `shake` 演出であり、他の誰も書いてはならない。**
  リサイズ処理で `position` をゼロに戻すと、揺れの最中に打ち消される。
  揺れは `ShakeRoot.position` に単純なオフセットを与え、演出終了時に必ず `Vector2.ZERO` へ戻す。`pivot_offset` は使わない（回転ではなく平行移動のため）。

### 5.2 タイプライタ表示

**Kit 側（`AdvPlayer`）の責務**: `Tween` で 0→1 の比率を刻み、`AdvMessageWindow.set_typing_progress(ratio)` に渡すだけ。本文ノードが何であるかは知らない。

- 所要時間は `duration = 表示文字数 / typing_speed`（`typing_speed` が 0 なら Tween を使わず即座に `complete_typing()`）。
- 文字数は BBCode タグを除いた**表示文字数**で数える（`RichTextLabel.get_total_character_count()` 相当。Kit 側では `text` から BBCode を除去して数える）。

**参照実装（`samples/ui/`）での推奨**: `RichTextLabel.visible_ratio` に受け取った比率をそのまま代入する。BBCode 併用時の日本語表示が意図とずれないよう、`visible_characters_behavior` に **`TextServer.VC_CHARS_AFTER_SHAPING`** を設定しておく。ゲーム側が別の見せ方（1文字ずつ `Label` を生やす等）をしても Kit は関知しない。この組み合わせは phase-02 で実測し、日本語 + BBCode で意図どおりに動くことを確認済み。

### 5.3 AdvPlayer の公開 API

```gdscript
# 基本
func setup(book: AdvScenarioBook, settings: AdvKitSettings) -> void
func play_topic(topic_id: StringName) -> void
func advance() -> void                      # テキスト送り
func skip_typing() -> void                  # タイプライタ即時完了
func stop() -> void
func is_busy() -> bool                      # BLOCKING 演出の完了待ち中は真
func register_effect(effect_id: StringName, handler: AdvEffectHandler) -> void

# 音声（§10）
func unlock_audio() -> void                 # autoplay ガードの解除
func is_audio_unlocked() -> bool
func get_audio_director() -> AdvAudioDirector
func get_voice_player() -> AdvVoicePlayer

# フラグ
func set_flag(flag_name: String, value: bool) -> void
func has_flag(flag_name: String) -> bool

# プレイ支援（§9）
func set_auto_mode(enabled: bool) -> void
func is_auto_mode() -> bool
func start_skip() -> void
func stop_skip() -> void
func is_skipping() -> bool
func get_backlog() -> Array[AdvBacklogEntry]
func open_backlog() -> void      # 進行を止め、AdvBacklogView.present() を呼ぶ
func close_backlog() -> void     # 進行を再開する
func is_backlog_open() -> bool
func replay_voice(entry: AdvBacklogEntry) -> void
func is_step_read(uid: StringName) -> bool

# セーブ（すべて JSON 化可能な素の型）
func get_progress() -> Dictionary   # {topic_id, step_uid, flags, read_steps, portrait_states}
func restore_progress(data: Dictionary) -> void

# signal（過去形の事実）
signal topic_started(topic_id: StringName)
signal topic_finished(topic_id: StringName)
signal step_shown(topic_id: StringName, step_uid: StringName)
signal line_completed(topic_id: StringName, step_uid: StringName)
signal choice_presented(options: Array)
signal choice_selected(index: int, option: Dictionary)
signal flag_changed(flag_name: String, value: bool)
signal backlog_appended(entry: AdvBacklogEntry)
signal auto_mode_changed(enabled: bool)
signal skip_started()
signal skip_stopped(reason: StringName)     # "user" / "choice" / "unread" / "finished"
signal scenario_finished()
```

- **signal の引数は `step_index` ではなく `step_uid`**。受け手（バックログ、既読管理、ゲーム側のフック）が永続化しても壊れないようにするため。
- **`BLOCKING` 演出の実行中は `advance()` を受け付けない**（`is_busy()` が真）。

### 5.4 UI の差し替え契約

**Kit は `Theme` を持たない。外観は常にゲーム側が用意する。**

`AdvMessageWindow` / `AdvChoiceMenu` / `AdvBacklogView` は、**外観を持たない基底クラス**として `class_name` を提供する。ゲーム側はこれを継承した `.tscn` を作り、`AdvPlayer` の `@export` へ差し込む。Kit 側は `samples/` に最小の参照実装（無装飾）を置くだけで、`game/` はそれを使わなくてよい。

`AdvMessageWindow` の契約:

```gdscript
class_name AdvMessageWindow extends Control
# 派生クラスが実装するもの
func show_line(speaker_name: String, name_color: Color, text: String) -> void
func set_typing_progress(ratio: float) -> void
func complete_typing() -> void
func clear() -> void
# 派生クラスが出すもの
signal advance_requested()
signal skip_typing_requested()
```

`AdvChoiceMenu` の契約:

```gdscript
class_name AdvChoiceMenu extends Control
func present(prompt: String, options: Array[Dictionary]) -> void  # 表示可能なものだけ渡される
func close() -> void
signal option_chosen(index: int)
```

`AdvBacklogView` の契約:

```gdscript
class_name AdvBacklogView extends Control
func present(entries: Array[AdvBacklogEntry]) -> void
func close() -> void
signal closed()
signal voice_replay_requested(entry: AdvBacklogEntry)
```

- `AdvPlayer` は**基底型でのみ**参照する。派生クラスの独自メソッドを呼ばない。
- **条件式で `false` になった選択肢は `present()` に渡さない。** UI 側に条件判定をさせない。

- **引数名に `name` を使わない**（`Node.name` を隠蔽して `SHADOWED_VARIABLE_BASE_CLASS` 警告になるため）。`flag_name` を使う。
- `topic_finished` で `goto` が無い場合は `scenario_finished` を出し、ゲーム側が次の状態へ遷移する。**ADV Kit はシーン遷移を行わない。**
- **Call down, signal up**: `AdvPlayer` は同一 `.tscn` 内の UI ノードを `@export` で受け取り、そのメソッドを呼ぶ。UI 側は `advance_requested` などの signal で `AdvPlayer` に通知する。UI が `get_parent()` を辿ることは禁止。`AdvPlayer` が**他ノードの子構成を組み替えることも禁止**（自分の子として音声ノードを足すのは対象外）。
- **入力を拾うノードは 1 つに寄せる。** `_unhandled_input` は木の逆順で配られるため、複数のノードが同じアクションを拾うとノード順が暗黙の優先順位になり、シーンを組み替えた瞬間に壊れる。

---

## 6. シナリオパイプライン

```text
スプレッドシート ──GAS(doGet)──> JSON ──> AdvScenarioImporter ──> .tres ──> ランタイムは load() のみ
                                            ├── エディタ Dock（手動）
                                            └── CLI（--headless、自動化）
```

**この経路はすべてデスクトップ（エディタ／CLI）で完結する。ランタイムから GAS API を叩くことはしない。**
理由: GAS ウェブアプリは `script.googleusercontent.com` へ 302 リダイレクトし CORS ヘッダを制御できないため、ブラウザ上の Godot からの `HTTPRequest` は成立しない。この制約は仕様として固定する。

### 6.1 スプレッドシート構成

3 シート構成。列名はヘッダ行（1行目）で判定する（列順に依存しない）。

**`characters` シート**

| id | display_name | name_color | portrait_dir | poses | expressions | default_pose | default_expression |
|----|--------------|-----------|--------------|-------|-------------|--------------|--------------------|

**`topics` シート**

| id | title | tags |
|----|-------|------|

**`steps` シート**（1行 = 1レコード。`topic_id` でグループ化し、`order` で整列）

| 列名 | 使う `type` | 内容 |
|------|------------|------|
| `topic_id` | 全 | 所属する話題。`topics` シートの `id` を参照 |
| `order` | 全 | 並び順の整数。**連番にせず 10, 20, 30… と空けておく**（後から行を挿入できる）。この値は安定ステップID `uid` の一部になるため、**既存行の `order` は変更しない**（変更すると既読データが壊れる。§9.1） |
| `type` | 全 | `line` / `effect` / `choice` / `jump` / `option` |
| `speaker` | line | `characters` シートの `id` を参照。空なら地の文 |
| `expression` | line | 表情。空なら維持 |
| `pose` | line | ポーズ。空なら維持 |
| `slot` | line | 立ち位置。空なら維持 |
| `text` | line | 本文 |
| `voice` | line | ボイスのリソースパス |
| `effect_id` | effect | §7 の表の演出ID |
| `params` | effect | `key=value` のセミコロン区切り（下記） |
| `sync` | effect | `parallel` / `blocking`。空なら `blocking` |
| `auto_advance` | effect | `TRUE` / `FALSE`。空なら `FALSE` |
| `prompt` | choice | 選択肢の見出し |
| `label` | option | 選択肢の表示テキスト |
| `flag` | option | 選択時に立てるフラグ名 |
| `goto` | jump / option | 遷移先 topic_id |
| `condition` | jump / option | §4.7 の条件式 |

- **空セルは「未指定」**。`""` と `null` を区別しない。GAS は空セルのキーごと JSON から落とす。
- 使わない `type` の列は空のままでよい。GAS は `type` を見て必要な列だけ拾う。
- `poses` / `expressions` / `tags` は**カンマ区切り**で書き、GAS が配列にする。
- **`id` は英数字とアンダースコアで書く。** インポータは `id` をそのまま `.tres` のファイル名にするため（§6.4）、
  使えない文字は `_` に丸められ、丸めた結果の衝突は検出されない。

#### `params` の記法

**1セルに JSON を書かない。** `key=value` をセミコロンで区切る:

```
strength=8; duration=0.4
stream=res://game/assets/adv/se/door.ogg
to_slot=left; duration=0.6; ease=out
```

- 前後の空白は無視する。値に `;` や `=` を含めたい場合は**その演出を使わない**（現状の演出パラメータに該当ケースはない。必要になったら仕様を改訂する）。
- **値の型は `effect_id` ごとのスキーマ（§7 の表）が決める。** `strength=8` は `float`、`loop=true` は `bool`、`stream=res://…` は `String` としてパースされる。書き手が型を気にする必要はない。
- **型変換とスキーマ照合は GAS ではなく Godot 側（`AdvEffectSchema`）が行う。** JSON 上の `params` は「値がすべて文字列の辞書」で構わない。GAS は `key=value` を分解するだけ。
- スキーマに無いキーは警告（`unknown_effect_param`）にして**捨てずに保持する**。ゲーム側が `register_effect()` で追加した演出のパラメータかもしれないため。拡張演出のハンドラは、必要なら自分で型変換する（`AdvEffectHandler` の静的ヘルパを使える）。

### 6.2 GAS API

- `doGet(e)` が全シートを読み、正規化した JSON を返す。実体は `addons/adv_kit/import/gas/adv_scenario_export.gs`。
- レスポンスに `content_hash` を含め、インポータ側で「変更なし」をスキップできるようにする。
  **`content_hash` は `generated_at` を含めずに計算する**。毎回変わる値を混ぜると差分スキップが永久に効かない。
- `topics` シートに存在しない `topic_id` を持つ steps 行は捨て、レスポンスの `warnings` 配列に理由を入れる。
- ウェブアプリとしてデプロイ。アクセス権は「全員（匿名を含む）」。
- **認証は URL の秘匿のみ**（U-05 確定）。トークンや署名は付けない。**リポジトリ・チャット・コミットメッセージに書かない。**
  - **エディタ Dock の入力値は `user://adv_kit_import.cfg`** に保存する（`res://` にも `ProjectSettings` にも書かない）。
  - **CLI は `--url=`、または環境変数 `ADV_KIT_SCENARIO_URL`** から読む。
  - **生の URL を `AdvImportResult` に入れない。** `AdvScenarioImporter.import_from_url()` が
    入口で `redact_url()` を通し、`source_label` も issue の location も**ホスト名までに丸める**
    （`script.google.com (以降は伏せています)`）。結果は CLI の標準出力にも Dock にも出るため、
    表示側で消すのでは漏れる。**取得に失敗したときも丸めた表記のまま**で、
    原因は HTTP ステータスなどメッセージ側に載せる
  - この判断が成り立つ前提: シナリオは最終的に公開ゲームへ焼き込まれる内容なので、URL が漏れても被害は「未公開シナリオの先読み」に留まる。**書き込み系の `doPost` を足さないこと**が条件。足すならこの決定を見直す。
- **CORS 制約により、この API はブラウザ上の Godot から呼べない**（§6 冒頭）。呼び出し元はエディタ Dock と CLI に限る。

### 6.3 JSON スキーマ（API レスポンス）

```json
{
  "schema_version": 1,
  "generated_at": "2026-09-02T12:00:00+09:00",
  "content_hash": "…",
  "characters": [
    {
      "id": "yuu",
      "display_name": "ユウ",
      "name_color": "#ffd27f",
      "portrait_dir": "res://game/assets/adv/portraits/yuu",
      "poses": ["stand", "arms_crossed"],
      "expressions": ["normal", "smile", "angry"],
      "default_pose": "stand",
      "default_expression": "normal"
    }
  ],
  "topics": [
    {
      "id": "prologue_01",
      "title": "プロローグ",
      "tags": ["chapter1", "entry"],
      "steps": [
        { "order": 10, "type": "line", "speaker": "yuu", "expression": "smile", "slot": "center", "text": "やあ。", "voice": "res://game/assets/adv/voice/yuu_0001.ogg" },
        { "order": 20, "type": "effect", "effect_id": "play_se", "params": { "stream": "res://game/assets/adv/se/door.ogg" }, "sync": "parallel" },
        { "order": 30, "type": "effect", "effect_id": "shake", "params": { "strength": "8", "duration": "0.4" }, "sync": "blocking", "auto_advance": true },
        { "order": 40, "type": "choice", "prompt": "どうする？" },
        { "order": 50, "type": "option", "label": "行く", "goto": "route_a", "flag": "chose_go" },
        { "order": 60, "type": "option", "label": "行かない", "goto": "route_b", "condition": "!chose_go" },
        { "order": 70, "type": "jump", "goto": "prologue_02" }
      ]
    }
  ]
}
```

**立ち絵のパス規約**: `<portrait_dir>/<pose>_<expression>.png`。存在しない組み合わせは解決順（§4.2）でフォールバックする。テクスチャの実体は JSON に含めず、Godot 側でパス解決する。

**JSON における `steps` は flat**。`option` は独立要素として並び、`params` の値はすべて文字列でよい。畳み込みと型変換は Godot 側が行う（§4.8）。

> **1 行目に音を置かない。** autoplay ガード（§10）により、topic の先頭ステップに畳み込まれた
> `play_se` / `play_bgm` は、初回のユーザー操作より前なので破棄される。

### 6.4 インポータの2つの入口

共通ロジック `AdvScenarioImporter`（`RefCounted`）が全処理を持ち、2つの薄い入口がそれを呼ぶ。

1. **エディタ Dock** — `EditorPlugin` が右上ドック（`DOCK_SLOT_RIGHT_UL`）にパネルを追加。URL 入力 / 出力先 / 取得 / ローカル JSON 選択 / 検証結果表示。
2. **CLI** — `extends SceneTree` の MainLoop スクリプト。

```bash
godot --headless --import        # 先に1回（class_name のグローバル解決）
godot --headless --script res://addons/adv_kit/import/adv_import_cli.gd -- \
    --url=<URL> --out=res://game/resources/adv/scenario/
godot --headless --import        # 書き出した .tres を取り込む
```

| オプション | 意味 |
|-----------|------|
| `--url=<URL>` | GAS から取得する。環境変数 `ADV_KIT_SCENARIO_URL` でも渡せる |
| `--file=<path>` | ローカル JSON から取り込む（オフライン検証用） |
| `--out=<res://dir/>` | 出力先。省略時は `ProjectSettings` → 既定値の順 |
| `--book-name=<name>` | Book のファイル名。既定 `scenario_book.tres` |
| `--force` | `content_hash` が一致していても書き出す |
| `--no-write` | 検証だけ行う（ドライラン） |
| `--no-texture-check` | 立ち絵の存在検査を省く |
| `-h`, `--help` | 使い方を表示する |

**終了コード: 0=成功 / 1=ERROR あり / 2=引数が不正。** CI はこれで判定する。

**CLI は URL を一切表示しない。** 取得元は「GAS ウェブアプリ（URL は伏せます）」とだけ出し、
結果行の取得元も丸めた表記になる（§6.2）。

- **CLI で `.tres` を書き出した直後は `.godot/` のインポートキャッシュが古い。** CI や自動化では書き出し後に `godot --headless --import` を1回走らせること。CLI 自身は import を行わない（責務を分けるため）。
- **CLI は `output_dir` の既定値フォールバックを必ず持つ。** `--import` では `EditorPlugin._enter_tree()` が走らず、`ProjectSettings` にキーが無い状態で CLI が動くことがあるため（R-02）。

#### 出力レイアウト

```text
<out>/scenario_book.tres     # AdvScenarioBook。characters / topics を ExtResource で参照
<out>/characters/<id>.tres   # AdvCharacter
<out>/topics/<id>.tres       # AdvTopic（steps は SubResource として内包）
```

**id 単位のファイルに分ける。** 書き出しは「全消し再生成」ではなく**差し替え**で、
既存 `.tres` と同一 `id` のものを上書きし、**JSON に存在しなくなったものは削除せず `stale_resource` の WARNING を出すだけ**にする（参照切れによる事故を避けるため。手動で消す）。

- 出力先ディレクトリは `characters/` `topics/` ごと再帰生成する。作成に失敗したら `write_failed` で**そこで止める**（半端に書き出さない）。
- **`.tres` のパス確定には `Resource.take_over_path()` を使う**（`ResourceSaver.FLAG_CHANGE_PATH` では不足）。
  既存ファイルがリソースキャッシュに載っている 2 回目以降で、「同じパスを持つリソースが 2 つある」となって保存が弾かれるため。
- **`characters` / `topics` を先に保存してから Book を保存する。** 参照される側に `resource_path` が付いていないと、
  Book に SubResource として全部が埋め込まれる。
- `stale_resource` の検査対象は `characters/` と `topics/` のみ。出力先の直下は見ない。

#### 処理の順序

1. JSON をパース（`JSON.new().parse()`。`JSON.parse_string` は失敗時にエンジンのエラーログを吐くので使わない）
2. `AdvScenarioParser.parse()`
3. `AdvScenarioValidator.validate()`（**`parse()` だけでは `invalid_condition` が出ない**）
4. `AdvScenarioImporter.check_portrait_textures()`（§4.2）
5. **ERROR が 1 件でもあれば書き出さずに終わる**
6. `content_hash` が既存 Book と一致し `--force` でなければ、書き出しを省く
7. 書き出し → stale 検出

> **Windows で CI を組む場合**: `Godot_v4.x-stable_win64.exe`（無印）は**コンソールに接続しない**ため、
> 出力が出ず、**終了コードも実行完了を待たずに 0 を返す**。必ず `_console.exe` を使うこと。

---

## 7. 演出（局所）

この表が `AdvEffectSchema`（`core/adv_effect_schema.gd`）の定義そのものになる。**パラメータ名・型・既定値をコードとこの表で一致させること。**

| effect_id | params（名前: 型 = 既定値） | 実装メモ |
|-----------|------------------------------|----------|
| `shake` | `strength: float = 8.0`, `duration: float = 0.4`, `frequency: float = 24.0` | `ShakeRoot.position` を **`Tween.tween_method()` + 自前のサイン波減衰**で振動させる（`tween_property` では周波数を表現できない）。終了時に必ず `Vector2.ZERO` へ戻す |
| `fade_out` | `duration: float = 0.5`, `color: Color = Color.BLACK` | `FadeLayer` の色を `color` に設定し、alpha を 0→1 |
| `fade_in` | `duration: float = 0.5`, `color: Color`（**省略可・実行時解決**） | `color` 省略時は現在の `FadeLayer` の色を維持。alpha を 1→0 |
| `show_portrait` | `speaker: String`（必須）, `slot: String = "center"`, `duration: float = 0.2` | 立ち絵の登場。alpha 0→1 |
| `hide_portrait` | `speaker: String`（必須）, `duration: float = 0.2` | 立ち絵の退場。完了後にノードを解放 |
| `move_portrait` | `speaker: String`（必須）, `to_slot: String`（必須）, `duration: float = 0.4`, `ease: String = "out"` | `AdvPortrait.position` を Tween |
| `play_se` | `stream: String`（必須）, `volume_db: float = 0.0` | ワンショット。多重再生可 |
| `play_bgm` | `stream: String`（必須）, `fade_in_time: float = 0.0`, `loop: bool = true` | 単一チャンネル。切り替え時はクロスフェード |
| `stop_bgm` | `fade_out_time: float = 0.0` | BGM チャンネル 2 本すべてを対象にする |

- 型は `float` / `bool` / `String` / `Color`（`#rrggbb` 文字列から変換）の4種のみ。
- パラメータの必須性は3種類ある。`AdvEffectSchema` はこの3値を持つ。
  - **必須**（`required`）: 欠落は検証エラー `missing_effect_param`
  - **既定値あり**（`default`）: 欠落時は表の既定値を補う
  - **省略可・実行時解決**（`runtime`）: 欠落時は値を入れず、演出ハンドラが実行時に決める（`fade_in` の `color` のみ）。検証は通す
- `speaker` パラメータは `AdvCharacter.id` への参照であり、`unknown_speaker` の検証対象に含める。
- **音源が存在しない場合は `push_warning` して何もしない。進行は絶対に止めない**（立ち絵と同じ方針。§4.2）。
  ランタイムで `load()` する前に必ず `ResourceLoader.exists()` で確認する。

### 排他ターゲット（同時に走る演出の衝突）

**同じステップで同時に走る演出が、同じものを書き換えようとすると結果が定まらない。**
2 つの `Tween` が同じプロパティを書き、片方が終了時に初期値へ戻すと、
もう片方の途中経過が巻き戻る。

同時に走る組み合わせは 2 つある（§4.8）:

- ひとつのステップの `parallel_effects` に入った演出どうし
- **ホストのステップ自身が `BLOCKING` 演出の場合、それと `parallel_effects` の演出**

そこで各演出は**排他ターゲット**を宣言する。`{speaker}` は `params.speaker` で置換する。

| effect_id | 排他ターゲット |
|-----------|---------------|
| `shake` | `shake_root_position` |
| `fade_out` / `fade_in` | `fade_layer_alpha` |
| `show_portrait` | `portrait_alpha:{speaker}` |
| `hide_portrait` | `portrait_alpha:{speaker}` と `portrait_position:{speaker}`（**ノードの解放を伴うため、そのキャラの全ターゲットを占有する**） |
| `move_portrait` | `portrait_position:{speaker}` |
| `play_bgm` / `stop_bgm` | `bgm_channel` |
| `play_se` | **なし**（ワンショットで多重再生可） |

汎用演出（§8）が使う `portrait_modulate:{speaker}` は、シナリオデータに現れないため
この表には無いが、**同じ台帳の名前空間を共有する**。

- 同時に走る演出の排他ターゲットが重なったら `conflicting_parallel_effects` の **ERROR**（§4.9）。
- したがって **`play_se` は何本並べてもよく、`show_portrait` と `move_portrait` は同じキャラでも同時に書ける**（alpha と位置で対象が違う）。
  一方、`shake` を 2 本、`fade_out` と `fade_in`、同じキャラの `show` と `hide` は弾かれる。
- **未知の `effect_id` は排他ターゲットを持たない**（空集合）。ゲーム側が `register_effect()` で足す拡張演出は、
  `AdvEffectHandler.exclusive_targets()` を override して自分で宣言する。宣言しなければ衝突検査の対象外。

### ランタイム規約

静的検証をすり抜けるケース（拡張演出、`auto_advance` の連鎖などステップをまたいだ重なり）に備え、
**排他ターゲットごとに実行中の `Tween` を 1 本だけ持つ台帳**（`AdvEffectContext`）を置く。

1. **演出ハンドラは `Tween` を必ず `AdvEffectContext.acquire_tween(targets)` 経由で作る。**
   台帳は同じターゲットで走っている `Tween` を `kill()` してから新しいものを渡す。
   これにより「**後から始まった方が勝つ**」という決まった挙動になる。何もしないと未定義になる。
2. **`Tween.kill()` は `finished` を出さない。** 「終わったら元に戻す」を `tween_callback` に置くと、
   中断されたときだけ適用されない。そこで**中断時の後始末は `kill()` する側（＝台帳）が呼ぶ**。
   `acquire_tween(targets, on_interrupt)` の第 2 引数で登録し、**他者に `kill()` されたときだけ**呼ぶ
   （自然完了では呼ばない）。例: `shake` は `ShakeRoot.position` を原点へ戻す。
3. **中断された演出は「諦める」。** 中断された `hide_portrait` は**ノードを解放しない**。
   解放すると、勝ったはずの `show_portrait` が解放済みノードを触ることになる。
4. **同じプロパティの書き手は 1 つに決める。** 台帳は調停役であって所有者ではない。
   `AdvPortrait.modulate.a` の `Tween` を作るのは `AdvPortrait` だけ（暗黙の登場も `show_portrait` も
   これを使い、台帳へは `adopt_tween()` で載せる）。`ShakeRoot.position` を書くのは `shake` だけ。
   **`modulate` の RGB を書くのは非話者ダークだけ**（§8）。

**暗黙の登場**: `AdvLineStep` の話者が Stage に未登場なら、`show_portrait` を明示しなくても `AdvStage` が自動で登場させる（alpha 0→1、`dim_duration` と同じ時間）。`show_portrait` は「テキストより前に出したい」場合のための明示手段。

**拡張規約**: 演出は `AdvEffectHandler` を継承したクラスを `AdvPlayer.register_effect()` に登録することでゲーム側が追加できる。Kit のコアに手を入れさせない。組み込みと同じ id を登録すれば差し替えになる。

`AdvEffectHandler` の契約:

```gdscript
@abstract
class_name AdvEffectHandler extends RefCounted

## register_effect() が代入する。1 クラスで複数の effect_id を扱えるようにするため。
var effect_id: StringName = &""

# 通常再生。完了まで await できる
@abstract func play(ctx: AdvEffectContext, params: Dictionary) -> void
# スキップ時。再生せず「完了後の状態」だけを即座に適用する（§9.3）
@abstract func apply_final(ctx: AdvEffectContext, params: Dictionary) -> void

## この演出が占有する排他ターゲット。既定は上の表を引く。
## 拡張演出はこれを override して自分のターゲットを宣言する。
func exclusive_targets(params: Dictionary) -> PackedStringArray
```

- **`effect_id` をフィールドにする**ことで、`play()` のシグネチャを変えずに 1 クラスで複数の id を扱える
  （`fade_out` / `fade_in` は同じクラス、`show` / `hide` / `move` も同じクラス）。
  同じクラスを 2 つの id に登録するときは**別インスタンス**にする。
- **排他ターゲットの宣言は仮想メソッドで行う。** `register_effect()` の引数では渡さない
  （`{speaker}` のような params 依存を登録時の固定文字列では表現できないため）。
- `play()` は `await handler.play(...)` の形で呼ばれる。`@abstract` メソッドを `await` しても
  `REDUNDANT_AWAIT` にはならず、同期実装なら即座に返る（Godot 4.7 で実測）。
- `apply_final()` は必須。スキップ中に `play()` を呼ばず `apply_final()` を呼ぶことで、フェードの到達色や立ち絵の最終位置だけが反映される。
- **音声系の `apply_final()`**（U-08 の B 案。2026-09-03 確定）:
  - `play_se` / `play_bgm` … **何もしない**（スキップ中に音を鳴らさないため）
  - **`stop_bgm` … `fade_out_time` を無視して即座に止める。**
    「完了後の状態」＝無音なので、これを適用するのが §9.3 の主旨に合う。
    何もしないと、スキップで停止を飛ばした BGM が鳴り続ける。

`AdvEffectContext`（`runtime/adv_effect_context.gd`）が演出ハンドラへ渡すもの:
`host`（Tween の生成元 = `AdvPlayer`）、`stage`、`shake_root`、`fade_layer`、`book`、`settings`、
`audio`（`AdvAudioDirector`）、`voice`（`AdvVoicePlayer`）、および上記の台帳 API
（`acquire_tween` / `adopt_tween` / `kill_targets` / `kill_all`）。
**`RefCounted` であり、ノードを所有しない。**

---

## 8. 演出（汎用 / 自動）

`AdvKitSettings` でオンオフする。**シナリオデータには一切現れない**。

- **非話者ダーク**: `AdvLineStep` の `speaker_id` が変わったとき、`Stage` 上の全 `AdvPortrait` の
  **`modulate` の RGB だけ**を Tween する。話者は白、それ以外は `dim_color`。
  地の文（speaker 空）のときは全員ダークにせず、**直前の話者の明暗状態を維持**する。
- **話者交代ホップ**: 話者が**変わったときのみ**、新話者の `AdvPortrait.position` を上方向に
  `hop_height` 跳ねさせて戻す。同じ話者の連続発話では跳ねない。
  §7 の「暗黙の登場」で新規生成された立ち絵も、登場と同時に跳ねる。

両方とも `Tween` で行い、進行はブロックしない。

### U-09 の確定（2026-09-03。**実装に合わせて確定**）

§7 の局所演出と同じものを書き換えるため、書き手の分離を次のように決めた。

| 書き手 | 書く対象 | 排他ターゲット |
|--------|----------|---------------|
| 非話者ダーク（§8） | **`modulate` の RGB のみ**。alpha は触らない | `portrait_modulate:{speaker}` |
| フェード（暗黙の登場 / `show_portrait` / `hide_portrait`） | **`modulate.a` のみ** | `portrait_alpha:{speaker}` |
| 話者交代ホップ（§8）と `move_portrait` | `position` | `portrait_position:{speaker}` |

- **`modulate` は「RGB＝ダーク」「A＝フェード」で成分ごとに分ける。**
  ダーク側は `AdvPortrait.set_modulate_rgb()`（alpha を保ったまま RGB だけ差し替える）を通す。
  これで「同じプロパティの書き手は 1 つ」（§7 ランタイム規約 4）を、成分の単位で満たす。
- **ホップと `move_portrait` は `portrait_position:{speaker}` を共有する。**
  取り合ったら台帳の「後から始まった方が勝つ」で決着する。
  つまり**移動中に話者が変わると移動が打ち切られる**。これは許容する。
- `hop_duration` / `hop_height` が 0 以下のときは Tween を作らず、
  台帳の当該ターゲットを `kill_targets()` してから静止位置を直接代入する。

> **採らなかった案**: `AdvPortrait` に `tint` / `fade_alpha` / `slot_position` / `hop_offset` の
> 中間プロパティを持たせて合成する案（当初 U-09 の B 案として検討）。
> ホップと移動の取り合いまで消せるが、プロパティが 4 本増え、
> phase-03 の立ち絵系テスト（`modulate.a` を直接見ているもの）の書き換えを伴う。
> **成分で分ける今の形で足りている**ため採用しない。取り合いが実害になったら再検討する。

---

## 9. プレイ支援機能

オートモード・スキップ・バックログ・ボイスはすべて Kit の責務。UI の外観はゲーム側（§5.4）。

### 9.1 既読管理

- 既読の単位は**ステップ**。`AdvLineStep` が最後まで表示された時点で、その `uid` を既読集合に加える。
  - 「最後まで表示」= タイプライタ完了。途中で送った場合も、その時点で全文が表示されるので既読とする。
- 既読集合の**内部表現は `Dictionary`**（キー `uid: StringName`、値 `true`）で重複を排除し、`get_progress()` の出力時のみ `PackedStringArray` に変換する。`restore_progress()` は `PackedStringArray` を受けて `Dictionary` に戻す。**内部で `String` と `StringName` を混在させない**（キーの同一性が揺れるため、境界での変換点をこの2箇所に限定する）。
- 既読集合は `get_progress()` に含まれ、**セーブデータをまたいで持ち回る**のがこの機能の前提。ゲーム側は「進行データ」と「既読データ」を別々に保存してよい（`restore_progress()` は `read_steps` が欠けていても動く）。
- `uid` は `"<topic_id>:<order>"`（§4.3）。シナリオに行を挿入しても既存の既読が壊れない。
  - **`order` を振り直すと既読も壊れる**。運用上、既存行の `order` は変更しない。
- 既読集合はシナリオが増えるほど単調増加する。上限を設けず、Web の `user://` 容量が問題になったら圧縮を検討する（現時点では対応しない）。

**立ち絵の復元（U-10 確定・2026-09-03）**: `uid` だけでは絵が戻らないため、
`get_progress()` に **`portrait_states`** を含める。
**保存すべきは `AdvStage` が持つ「表示状態」**（`AdvPlayer` の同名フィールドは
「シナリオが最後に指定した値」であって、実際の表示とは別物）。

```gdscript
get_progress() -> {topic_id, step_uid, flags, read_steps, portrait_states}
```

**`portrait_states` は任意項目**。`restore_progress()` は欠けていても動く（立ち絵が戻らないだけ）。
復元位置は **`step_uid` を優先**し、`step_index` は永続化しない（§4.3）。

### 9.2 オートモード

- `set_auto_mode(true)` で有効。`auto_action` のトグルでも切り替わる。
- 挙動: テキスト表示完了 → 待機 → 自動で `advance()`。待機時間は `auto_wait_time`。`auto_wait_for_voice` が真でボイスがある場合は `max(ボイス残時間, auto_wait_time)`（`AdvVoicePlayer.get_remaining_time()`）。
- **解除条件**: ユーザーが `advance_action` を押した / 選択肢が出た / バックログを開いた / `scenario_finished`。
- `BLOCKING` 演出の完了待ちはオートモードでも短縮しない。演出の見せ場を潰さないため。

### 9.3 スキップ

- `skip_action` を**押している間**継続する（トグルではない）。`skip_interval` ごとに1ステップ進める。
- `skip_unread == false`（既定）のとき、**未読ステップに到達したらスキップを解除**する（`skip_stopped("unread")`）。`true` なら未読でも進む。
- `skip_stops_at_choice == true`（既定）のとき、選択肢に到達したら解除する（`skip_stopped("choice")`）。
- スキップ中は**タイプライタと `PARALLEL` 演出を再生しない**。`BLOCKING` 演出は**再生せず即座に完了扱い**にする（見た目より速度を優先する。フェードの状態など「完了後の状態」だけは `apply_final()` で適用する）。
- **スキップ中もボイスと SE・BGM は鳴らさない。ただし `stop_bgm` だけは即座に効く**（U-08 の B 案。§7）。
  「鳴らさない」を破らずに、飛ばした停止が置き去りになる穴を塞ぐ。
- 既読の記録は通常どおり行う。
- **解除理由**（`skip_stopped` の引数）: `"user"`（キーを離した）/ `"unread"`（未読に到達）/ `"choice"`（選択肢に到達）/ `"finished"`（シナリオ終端）。

### 9.4 ボイス

- `AdvLineStep.voice_path` が空なら**何も再生せず、そのまま進行する**。ボイスの有無で進行ロジックは分岐しない。
- 再生先は専用の `AudioStreamPlayer`（`AdvVoicePlayer`）。バスは `voice_bus`（既定 `Voice`）で、そのバスが存在しなければ `Master` にフォールバックし `push_warning` する（ゲーム側にバス設定を強制しない）。**警告は 1 回だけ出す**（毎行出すとログが埋まる）。
- **同時に鳴るボイスは1つ**。次のステップへ進んだ時点で前のボイスを停止する。
- `voice_path` が解決できない場合（ファイルなし）は `push_warning` して**進行は続ける**。立ち絵と同じく、欠損で止めない。
- Web の autoplay ポリシー対応は §10 と同じ。初回のユーザー操作までは再生しない。

### 9.5 バックログ

- 記録対象は `AdvLineStep` のみ（演出・選択肢・ジャンプは記録しない）。
- `AdvBacklogEntry`（`RefCounted`）: `uid`, `speaker_name`, `name_color`, `text`, `voice_path`。
- 上限 `backlog_max_entries`（既定 200）。超えたら古いものから捨てる。**Web のメモリを守るため上限は必須。**
- 開閉は `AdvPlayer.open_backlog()` / `close_backlog()` が唯一の入口。`backlog_action` の入力を `AdvPlayer` が拾って `open_backlog()` を呼ぶほか、ゲーム側が画面上のボタンから直接呼んでもよい。**開いているかどうかの状態は `AdvPlayer` が持つ**（UI 側は持たない）。
- バックログを開いている間は進行を止める（`advance()` を受け付けない）。`AdvBacklogView.closed` を受けて `close_backlog()` し、再開する。
- `backlog_voice_replay` が真なら、エントリのボイスを再生できる。再生は通常のボイス再生と同じチャンネルを使う。
- **バックログは進行データではない**ため `get_progress()` に含めない。話題をまたいで保持し、`stop()` でクリアする。

---

## 10. Web / unityroom 制約への対応

- **ランタイムで JSON をパースしない。** Web 実行時に読むのは `.tres` のみ（`load()` / `ResourceLoader`）。JSON → Resource の変換はエディタと CLI でしか動かない。これにより「重い JSON パースを `Thread` 無しでどう分割するか」という問題自体が発生しない。
- `Thread` / `WorkerThreadPool` を使わない。ランタイムで待機が必要なのは Tween と音声だけで、いずれもフレーム跨ぎで完結する。
- **立ち絵テクスチャは遅延ロード**（§4.2）。`AdvStage` が必要になった時点で `load()` する。音源も同じく再生の直前に `load()` する。
- **autoplay ガード（phase-03 で実装済み）**: 音は最初のユーザー操作より前に鳴らさない。
  `AdvPlayer` は「初回の `advance()` / `skip_typing()` が呼ばれるまで **BGM・SE・ボイスのすべて**を再生しない」ガードを持つ。**保留した音は破棄する**（後からまとめて鳴らさない）。
  - ブラウザに最初の音を握り潰されると、以後のチャンネル状態が実際の再生とずれるため、保留はしない。
  - ゲーム側がタイトル画面のクリックなど、より早いユーザー操作で解除したい場合は
    **`AdvPlayer.unlock_audio()`** を呼ぶ。
  - 帰結として、**topic の先頭ステップに畳み込まれた音は鳴らない**（§6.3 の注記）。
  - **phase-08 で実 Web ビルドによる検証を完了した。** サンプルのタイトル操作で `unlock_audio()` を
    先に呼び、ブラウザの autoplay 制約下でも本文・ボイス・BGM・SE の経路を確認する。
- セーブは Kit の責務外（§2）。`get_progress()` の戻り値は JSON 化可能な素の型のみで構成すること。
- **エクスポート除外パターン**: `addons/adv_kit/` を一括除外しない。除外してよいのは以下のみ。
  - `res://addons/adv_kit/samples/*`
  - `res://addons/adv_kit/tests/*`（`tests/assets/` を含む）
  - `res://addons/adv_kit/editor/*`
  - `res://addons/adv_kit/import/*`（`gas/` を含む。ランタイムから参照されないため）

  `export_presets.cfg` は `.gitignore` 対象なので、**プロジェクトごとに手で設定する**。

---

## 11. フェーズ計画

| フェーズ | 目的 | 主な成果物 |
|----------|------|------------|
| phase-01 | 土台とデータモデル | **完了（2026-09-03）**。`addons/adv_kit/` 骨格、`resources/` 全 Resource、`core/` パーサ・バリデータ・条件式・演出スキーマ、サンプル JSON、ヘッドレステスト（157 件） |
| phase-02 | 基本再生 | **完了（2026-09-03）**。`AdvPlayer`、`AdvMessageWindow` 基底と参照実装、`AdvStage`、`AdvPortrait`（32 件） |
| phase-03 | 局所演出とボイス | **完了（2026-09-03）**。`AdvEffectHandler` 群、`AdvEffectContext`（排他ターゲットの台帳）、`PARALLEL` / `BLOCKING` の進行制御、`register_effect`、`AdvAudioDirector`、`AdvVoicePlayer`、autoplay ガード（93 件） |
| phase-04 | 汎用演出 | **完了（2026-09-03。実装者は Codex）**。非話者ダーク（`portrait_modulate:`）、話者交代ホップ（24 件） |
| phase-05 | 話題・選択肢・進行データ | **完了（2026-09-03。実装者は Codex）**。`AdvChoiceMenu`、`goto`、条件式の評価、`AdvProgressState`、既読集合、`get_progress` / `restore_progress`（50 件） |
| phase-06 | プレイ支援 | **完了（2026-09-03。実装者は Codex）**。オートモード、スキップ（既読連動）、バックログ、ボイスのリプレイ（44 件） |
| phase-07 | シナリオパイプライン | **完了（2026-09-03）**。GAS スクリプト、`AdvScenarioImporter`、`AdvImportResult`、エディタ Dock、CLI（100 件） |
| phase-08 | Web 堅牢化とサンプル | **完了（2026-09-04。実装者は Codex）**。Compatibility / Thread 無しの Web 書き出し、サンプルプロジェクト、実素材、ゲーム側 UI、README、ヘッドレス smoke test |

**依存**: 01 → 02 → 03 → 04、02 → 05 → 06、**03 → 06**（バックログのボイスリプレイが `AdvVoicePlayer` に依存）、01 → 07、全 → 08。

> **phase-04 / 05 / 06 は実装計画書・引継ぎ資料・差分レポートが残っていない。**
> 仕様書への反映は、phase-07 の作業中にコードを読んで行った（U-09 / U-10 / U-04）。

---

## 12. 用語集

| 用語 | 定義 |
|------|------|
| ステップ (step) | 1回のテキスト送りで消費されるシナリオの最小単位 |
| 話題 (topic) | ステップ列のまとまり。呼び出しと遷移の単位 |
| エントリ topic | `tags` に `entry` を持つ topic。ゲーム側から直接 `play_topic()` される |
| スロット (slot) | 立ち絵の立ち位置。5段階の論理位置で、実座標は `AdvStage` が解決する |
| ブック (book) | 話題とキャラクターを束ねた集約 Resource |
| 畳み込み (fold) | シート上で独立した行として書かれた `parallel` 演出／`option` を、直前のステップへ吸収して `steps` から除去する処理（§4.8） |
| uid（安定ステップID） | `"<topic_id>:<order>"`。既読管理とセーブ復元に使う。行を挿入しても変わらない（§4.3） |
| 既読 | `AdvLineStep` が最後まで表示されたこと。ステップ単位で `uid` の集合として保持する（§9.1） |
| 排他ターゲット | 演出が占有する「書き換える対象」の名前（§7）。重なりを検証で弾き、ランタイムでは台帳が調停する |
| 台帳 | `AdvEffectContext` が持つ「排他ターゲット → 実行中の Tween」の対応表（§7 ランタイム規約） |
| stale リソース | JSON に対応する id が無いのに出力先へ残っている `.tres`（§6.4）。削除せず警告する |

---

## 13. 未決事項

| ID | 内容 | 確定期限 |
|----|------|----------|
| U-04 | 条件式に括弧・数値変数が必要か。**文法自体は §4.7 で phase-01 に確定させた**。**phase-05 では「括弧を追加しない」と判断済み**（既存の `!` / `&&` / `\|\|` / 識別子だけの文法と `&&` 優先順位を維持し、拡張は別フェーズで仕様・移行・エラー表示をまとめて判断する）。残っているのは拡張の要否のみ。**優先順**: ①括弧（`(a \|\| b) && c` が書けず、フラグが3つを超えると展開で破綻する）②数値比較（カウンタ型フラグ）③到達済み述語 `visited(topic_id)`。`!` の多重適用・`xor`・真偽リテラルは不要 | 必要になったとき |

### 確定済み（2026-09-02）

| ID | 決定 | 反映先 |
|----|------|--------|
| U-01 | オートモード・スキップとも**要**。既読管理を伴う | §9.1〜9.3、`uid` の導入（§4.3）、phase-06 |
| U-02 | バックログ**要** | §9.5、phase-06 |
| U-03 | ボイス再生**要**。`voice_path` 未指定でもボイスなしで動く | §9.4、phase-03 |
| U-05 | GAS API の認証は**URL 秘匿のみ**。トークンは付けない | §6.2 |
| U-06 | メッセージウィンドウの外観は**常にゲーム側で差し替える**。Kit は `Theme` を持たない | §5.4、参照実装は `samples/ui/` |

### 確定済み（2026-09-03）

| ID | 決定 | 反映先 |
|----|------|--------|
| U-07 | **章分割運用は行わない。`AdvScenarioBook.merge()` は実装しない。** JSON 1 本 → Book 1 本。`goto` の参照整合性は単一 Book 内で厳密に検証する | §4.5、phase-07 |
| U-08 | **B 案。`stop_bgm` の `apply_final()` だけ即座に停止する。** `play_se` / `play_bgm` は何もしない。「スキップ中に音を鳴らさない」（§9.3）を破らずに、飛ばした停止が置き去りになる穴を塞ぐ | §7、§9.3、phase-06 |
| U-09 | **`modulate` を成分で分ける。** ダークは RGB のみ（`portrait_modulate:{speaker}`）、フェードは alpha のみ（`portrait_alpha:{speaker}`）。ホップは `position` を直接書き、`move_portrait` と `portrait_position:{speaker}` を共有して「後勝ち」で決着する。**合成プロパティ案（当初の B 案）は採らない** | §8、phase-04 |
| U-10 | **`get_progress()` に `portrait_states` を含める。** 保存するのは `AdvStage` が持つ「表示状態」 | §9.1、phase-05 |

### 実測で解消した技術的リスク

| ID | 決定 | 反映先 |
|----|------|--------|
| R-01 | **解消。** `@abstract AdvStep` + `Array[AdvStep]` の `.tres` 往復で派生型・ネストした `parallel_effects`・`options` 内の `StringName`・型付き辞書のキー型がすべて保たれる。設計変更は**不要** | §4.3 |
| R-02 | **解消。** `--headless --script` の前に `--import` を1回走らせれば足りる。ただし `--import` では `EditorPlugin._enter_tree()` が走らないため、`adv_kit/import/output_dir` は登録されない。**CLI 側に既定値フォールバックを持たせた** | §6.4、phase-07 |
| R-07 | **解消。** Godot 4.5 / 4.7 で `class_name` の循環は起きない。それでも `Array[AdvStep]` を維持する（理由は §4.3）。型の自己参照はエンジン終了時のスクリプトリークを生むが終了コードに影響しない。**CI は終了コードで判定する** | §4.3 |
| R-08 | **解消。** ヘッドレスの `SceneTree` スクリプトでも `Tween` は完走する。`_initialize()` 内で `add_child()` した子の `_ready()` は次フレームなので、`onready` 参照の前に `await process_frame` が要る | phase-03 以降のテスト全部 |
| R-09 | **解消。** `RichTextLabel.visible_ratio` + `VC_CHARS_AFTER_SHAPING` は日本語 + BBCode で意図どおり | §5.2 |
| R-13 | **解消。** `@abstract` メソッドを `await` しても `REDUNDANT_AWAIT` は出ず、コルーチンなら正しく待つ | §7 |
| R-14 | **解消。** ヘッドレスでも `AudioStreamPlayer` の `play` / `playing` / 再生位置 / `finished` が機能する（Linux・Windows とも同一）。ただし `Voice` バスは既定で存在せず、常に `Master` フォールバック経路が走る | §9.4 |
| R-15〜R-18 | **解消。** 台帳・中断後始末・BGM の全チャンネル停止・テスト用アセットで対処（phase-03 引継ぎ資料 §5） | §7 |
| **R-19** | **解消。** `.tres` の上書き生成には **`Resource.take_over_path()`** を使う。`ResourceSaver.FLAG_CHANGE_PATH` だけだと、既存ファイルがリソースキャッシュに載っている 2 回目以降で保存が弾かれる。**参照される側を先に保存**して `resource_path` を付けると、集約側が ExtResource 参照になる | §6.4、phase-07 |
| **R-20** | **解消（R-08 の続き）。** ヘッドレスの `SceneTree` でも `HTTPRequest` は動く。ただし `_initialize()` 内で `add_child()` した `HTTPRequest` は `is_inside_tree() == false` で `request()` が `ERR_UNCONFIGURED` を返すため、**1 フレーム待つ**。さらに**ホスト自身がツリー外だと `get_tree()` が null** を返すので `Engine.get_main_loop() as SceneTree` から取る | §6.4、phase-07 |
| **R-21** | **解消。** `ResourceLoader.exists()` は `--script` 実行でも機能する。`.png` はインポート後 `.ctex` になるため `FileAccess.file_exists()` は使えない | §4.2、phase-07 |
| **R-22** | **解消。** `@tool` の Dock はエディタ外でも `instantiate()` + `add_child()` できる（`EditorInterface` / `EditorFileDialog` を触っていないため）。`Engine.is_editor_hint()` のガードは不要 | phase-07 |
| **R-23** | **解消。** 出力先は `DirAccess.make_dir_recursive_absolute()` で `characters/` `topics/` ごと生成する。失敗したら `write_failed` で止める | §6.4、phase-07 |
| - | エンジンは **Godot 4.7 系**、レンダラーは **Compatibility** で確定。**4.8 以降には上げない**（unityroom の対応上限が 4.7） | 全フェーズ |
| - | 実装担当は phase-01〜03 と phase-07 が **Claude**、phase-04〜06 が **Codex** | 運用 |

---

## 14. 変更履歴

| 日付 | フェーズ | 変更内容 | 理由 |
|------|----------|----------|------|
| 2026-09-04 | phase-08 | `game/` に実素材付きサンプル、ゲーム側 UI 差し替え、設定 Resource、Web 用 main scene / export 手順、sample smoke test を追加。Compatibility / 1280x720 / `canvas_items` + `keep` / Thread 無しで Web 書き出しを確認 | unityroom 投稿前に、Kit のランタイム契約を実素材とブラウザで通し確認できる最小サンプルを用意するため |
| 2026-09-03 | phase-07 | **URL 漏れの修正を反映**: §6.2 に「生の URL を `AdvImportResult` に入れない。`import_from_url()` が入口で `redact_url()` を通す」を明記し、「取得失敗時だけ issue に URL が入る」という以前の記述を撤回。§6.4 に「CLI は URL を一切表示しない」を追記 | 実 GAS で通したところ、CLI の結果行が `source_label` をそのまま印字して**URL を標準出力へ漏らしていた**。「取得元は伏せる」と表示しながら最後の 1 行で出しており、U-05（秘匿が唯一の認証）を破っていた。表示側で消す設計では漏れると分かったので、**結果オブジェクトに生の URL を持たせない**形に変えた |
| 2026-09-03 | phase-07 | **phase-07 の実装・実測を受けて改訂**（あわせて記録の無かった phase-04 / 05 / 06 の実装をコードから読み取って反映）: **§3** に `import/adv_import_result.gd` / `import/gas/` / `editor/` / phase-04〜07 のテストを追加／**§4.2** に「`portrait_set` が null のキャラは `missing_portrait_texture` の対象外」「重複排除は解決結果で行う」を追記／**§4.5** に `has_same_content()` と **U-07 の確定**（`merge()` 不要）を明記／**§4.9** に `fetch_failed` / `write_failed` / `stale_resource` を追加し、担当表に `AdvScenarioImporter` の行を追加／**§6.1** に `id` の文字種の運用を追記／**§6.2** に URL の保存先（`user://adv_kit_import.cfg` / 環境変数）と `content_hash` の計算方法を明記／**§6.4** を全面改訂（出力レイアウト・CLI のオプションと終了コード・`take_over_path`・処理順序）／**§7** に音声系 `apply_final()` の確定（**U-08 = B 案**）と `portrait_modulate:` の存在を明記／**§8** を **U-09 の確定（実装に合わせて成分分離を採用）**で書き換え／**§9.1** に **U-10 の確定**（`portrait_states`）／**§9.3** にスキップ中の `stop_bgm` の扱い／**§10** にエクスポート除外の運用注記／**§11** を phase-04〜07 完了に更新／**§13** を「未決 = U-04 のみ」に整理し、U-07〜U-10 を確定済みへ、R-19〜R-23 を追加 | phase-07 で仕様書に穴（インポータの出力レイアウト・パイプライン失敗時のコード・CLI の契約が未定義）が判明したため。あわせて、記録なしで実装された phase-04〜06 の実態と仕様書の食い違い（特に U-09）を解消した |
| 2026-09-04 | phase-05 | `AdvChoiceMenu` と無装飾の参照 UI を追加し、`AdvPlayer` に条件付き選択肢、flag、`goto`、topic 遷移、UID ベースの既読・進行保存／復元を実装。立ち絵状態は任意の `portrait_states` として保存する。**U-04 は「phase-05 では括弧を追加しない」で確定** | 選択分岐を含む ADV の再生と、シナリオ変更に耐える進行復元を成立させるため |
| 2026-09-04 | phase-06 | `AdvBacklog` / `AdvBacklogEntry` / `AdvBacklogView` を追加し、`AdvPlayer` にオート、既読連動スキップ、バックログ開閉・ボイスリプレイを実装 | 既読データを利用したプレイ支援機能を、UI 差し替え可能な契約で成立させるため |
| 2026-09-03 | phase-03 | phase-03 の実装・実測を受けて改訂: §3 に `runtime/adv_effect_context.gd` と `runtime/adv_audio_director.gd`、`tests/assets/test_tone.tres` を追加／§7 の拡張規約に `AdvEffectHandler.effect_id` と `exclusive_targets()` 仮想メソッドを明記／§7 に「ランタイム規約」を新設し、台帳・中断後始末は `kill()` 側が呼ぶ・中断された退場は諦める・同じプロパティの書き手は 1 つに決める、の 4 点を定めた／§7 と §9.3 に音声系 `apply_final()` の穴を明記し U-08 として起票／§10 の autoplay ガードを phase-08 → phase-03 実装済みに更新／§5 のシーン構成に実行時生成の音声ノードを追記／§5.1 に「`ShakeRoot.position` の持ち主は `shake`」を明記／§8 に汎用演出と局所演出の衝突を注記し U-09 として起票／§9.1 に立ち絵の復元（U-10）を注記／§2 に `ui/` → `runtime/` の非依存を明記／§6.4 に Windows の `_console.exe` の注意を追記／§11 のフェーズ表を更新 | phase-03 で仕様書に穴（`AdvEffectContext` の置き場所が無い・中断時の後始末が未定義・音声 `apply_final()` の帰結が詰められていない）が判明したため |
| 2026-09-03 | phase-01 | **同時に走る演出の衝突を仕様化**: §7 に**排他ターゲット**の表を追加し、§4.9 に `conflicting_parallel_effects`（ERROR）を追加。§4.8 に「ホストが BLOCKING 演出ならそれも同時に走る側に数える」を明記 | `parallel_effects` に同じ対象を書き換える演出が複数入ると、2 つの Tween が同じプロパティを取り合って結果が定まらない。データの段階で弾けるのに、仕様にも検証にも無かった |
| 2026-09-03 | phase-01 | phase-01 の実装・実測を受けて改訂: **`AdvOptionStep`（パースの中間表現）を §4.3 に追加**／**検証コード `invalid_json` を §4.9 に追加**し、あわせて §4.9 に担当表を明記／`AdvScenarioBook` に `schema_version` と `content_hash` を追加／`missing_portrait_texture` の検査対象を「シナリオ中で実際に参照された組み合わせのみ」に限定（§4.2）／`parallel_effects` の型に関する注記を実測結果で更新（R-07）／未決事項に R-01・R-02・R-07 の解消と U-04 の優先順位を追記 | phase-01 の実装で、仕様書に穴（`option` に対応する型が無い・JSON 破損時のコードが無い）と、前提の誤り（`class_name` の循環は起きない）が判明したため |
| 2026-09-02 | - | 初版作成。要件資料から展開 | - |
| 2026-09-02 | - | 検証を受けて追補: 検証コード一覧を §4.9 として仕様書側に集約／`parallel_effects` の宣言型を `Array[AdvStep]` に／`AdvEffectHandler` に `apply_final()` を追加／`AdvEffectSchema` のパラメータ必須性を required/default/runtime の3値に／バックログ開閉 API を `AdvPlayer` に追加／`ShakeRoot` をアンカー無しの中間ノードに／§5.2 を「Kit は比率を渡すだけ」に書き分け／autoplay ガードを全音声に拡大／既読集合の内部表現を `Dictionary` に固定 | 検証で見つかった実装不能・責務越境・source of truth の二重化を解消 |
| 2026-09-02 | - | シート表現の問い合わせを受けて改訂: `speaker_id` が `AdvCharacter.id` への参照であることと `_id` 命名規約を明記／`parallel_effects` を `AdvStep` 基底へ移し畳み込み先を任意ステップに緩和／選択肢を `type=option` の行分解に変更／`params` を `key=value;` 記法に変更し `AdvEffectSchema` として型と既定値を §7 に定義／§4.8「畳み込み」と steps シートの列定義を新設 | ネストした配列を1セルの JSON で表現させる設計が、スプレッドシート記述者にとって事故のもとだったため |
| 2026-09-02 | - | 検証を受けて改訂: フェードと揺れの前後関係を確定（reparent 廃止）／ランタイム JSON パースを禁止し CORS 制約を明記／立ち絵を `Texture2D` からパス文字列へ／`auto_advance`・`show_portrait`・`hide_portrait`・`skip_action` を追加／condition 文法を §4.7 として独立／`entry` タグによる到達性判定／`step_index` の定義／エクスポート除外パターン／`name` 引数の禁止 | 自己矛盾と Godot 4 の実挙動との食い違いを解消 |
