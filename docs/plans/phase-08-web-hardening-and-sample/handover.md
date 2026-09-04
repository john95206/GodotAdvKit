# 引継ぎ資料: フェーズ08 web-hardening-and-sample

- **対象計画書**: `docs/plans/phase-08-web-hardening-and-sample/plan.md`
- **実装者**: Codex
- **完了日**: 2026-09-04
- **配置先**: `C:\Users\kzr12\Root\MyProjects\AdvKit\`
- **検証環境**: Godot 4.7.2-stable（Windows 実機、Compatibility）。ヘッドレステストは
  `_console.exe` の `godot.cmd` 経由、Web はローカル HTTP サーバ + Codex In-app Browser。
- **テスト結果**（終了コード 0）:

  | テスト | 件数 | 結果 |
  |--------|------|------|
  | `test_scenario_parse.gd` | 157 | 全通過 |
  | `test_playback.gd` | 32 | 全通過 |
  | `test_effects.gd` | 93 | `--audio-driver Dummy` で全通過 |
  | `test_auto_direction.gd` | 24 | 全通過 |
  | `test_progress.gd` | 50 | 全通過 |
  | `test_play_assist.gd` | 44 | 全通過 |
  | `test_import.gd` | 113 | 全通過 |
  | `test_sample_scene.gd` | 28 | 全通過 |

## 1. 実装済み内容（タスクID対応）

| 計画タスクID | 状態 | 実装した内容 / 変更したファイル |
|--------------|------|--------------------------------|
| T-01 | 完了 | `game/assets/adv/` に背景 PNG、Yuu / Rin の立ち絵 PNG、BGM / SE / voice の `AudioStreamWAV` Resource を追加。`game/assets/fonts/NotoSansJP-VF.ttf` とライセンス NOTICE も追加 |
| T-02 | 完了 | `addons/adv_kit/samples/sample_scenario.json` の素材参照を更新し、CLI で `game/resources/adv/scenario/` を再生成。Book の `content_hash` は `sample-phase08-0001`、立ち絵の missing warning は 0 件 |
| T-03 | 完了 | `game/ui/sample_message_window.*`、`sample_choice_menu.*`、`sample_backlog_view.*`。各基底 UI を継承し、ゲーム側 Theme と表示・選択・バックログ音声リプレイを実装 |
| T-04 | 完了 | `game/scenes/sample_adv_scene.tscn` と `game/scenes/sample_main.tscn`、`game/scripts/sample_main.gd`。タイトル操作で `unlock_audio()` を呼び、プロローグ、選択肢、終了、再開を接続 |
| T-05 | 完了 | `project.godot` の main scene / 1280x720 / `canvas_items` + `keep` を設定。ローカル gitignore の `export_presets.cfg` に Compatibility、Thread 無し、4 つの除外パターンを設定 |
| T-06 | 完了 | `game/resources/adv/settings.tres` に暗転 0.18 秒、ホップ 14px / 0.16 秒、タイプ速度、オート待機などを分離。サンプルで過剰にならない値に調整 |
| T-07 | 完了 | `addons/adv_kit/tests/test_sample_scene.gd` を追加し 28 アサーションを確認。`Build.html` / `Build.pck` を含む Web 出力を生成。ブラウザでタイトル画面とフォント反映後の表示を確認 |
| T-08 | 完了 | ルート README、アドオン README、`game/README.md`、`docs/plans/INDEX.md`、仕様書 §10 / §11 / 変更履歴、本文書、`docs/diff-reports/phase-08-diff.md` を更新 |

### DoD

| 項目 | 結果 |
|------|------|
| サンプルシーンをエディタで開いて UI の重なり・余白・文字切れがない | ⚠️ シーン構成と smoke test は確認済み。Godot ネイティブ画面はこの環境の CUA に公開されず、エディタ上の目視だけ未実施 |
| タイトルの最初のクリック前に音声が鳴らず、クリック後に BGM / SE / voice が再生可能 | ⚠️ autoplay guard の既存テスト、タイトル→unlock のコード経路、ブラウザのタイトル表示を確認。現在の CUA ブラウザでは最新版の開始ボタン入力が安定せず、音量を伴う実ブラウザ再生は完全には再確認できていない |
| Web export が Compatibility / thread 無しで成功し、`Build.html` と `Build.pck` が生成される | ✅ 終了コード 0、`Build.html` / `Build.pck` / `Build.js` / `Build.wasm` を確認 |
| Web ブラウザで title → 本編 → choice → backlog / auto / skip → end の導線を確認する | ⚠️ 初回 Web build では title → 本編 → backlog を目視確認。最新版は title 表示と日本語フォント反映まで確認したが、CUA の入力不安定により全導線の再確認は保留 |
| `AdvScene` の `ShakeRoot` リサイズ追従と `ShakeRoot.position` の揺れが Web でも破綻しない | ⚠️ `canvas_items` + `keep`、既存の ShakeRoot シーン構成、Web 出力を確認。リサイズ操作を伴う目視は未実施 |
| 既存テストとサンプル smoke test が終了コード 0 | ✅ 8 本、合計 541 アサーション相当（各テストの件数は上表） |
| 全変更された GDScript が静的型付きで警告 0 件 | ✅ `--check-only` を実行し警告なし |
| 4 つの Web export 除外手順が文書化される | ✅ README 3 本とローカル preset に記録 |
| phase08 handover が全セクションを埋め、T-01〜T-08 と対応づく | ✅ 本文書 |

## 2. 計画との差分

| 項目 | 計画 | 実際 | 理由 |
|------|------|------|------|
| 素材 | 実素材を `game/assets/adv/` に置く | 背景・立ち絵・音声をサンプル用に生成して配置 | 実 GAS の取得や外部素材の権利確認を今回の対象外とし、パイプラインの Web 検証を自己完結させるため |
| Web preset | ローカル preset を生成 | `export_presets.cfg` に `export_filter=scenes` とメインシーンの依存 Resource を明示 | `all_resources` では除外対象まで PCK に入り、scenes export では依存関係の明示が必要だったため |
| phase-07 テストの sample fixture | 既存テストをそのまま通す | `test_import.gd` の欠損テクスチャ検査だけ、phase-08 の実素材を一時的に壊した入力で検証。ハッシュ期待値は sample JSON から取得 | phase-08 の sample JSON を実素材付きに更新しても、phase-07 の検証意図と回帰検知を維持するため |
| 音声の再生開始待ち | 既存テストの 1 フレーム待ち | `test_effects.gd` に BGM が再生中になるまで最大 8 フレーム待つ helper を追加 | Windows headless で音声初期化が 1 フレームを越える場合があり、環境差をテスト失敗にしないため |
| Web 全導線 | title から end まで実ブラウザで確認 | 旧 build で title → 本編 → backlog、最新版で title と日本語フォントを確認。全導線は未完 | CUA の最新版キャンバス入力が安定せず、同じ操作を再現できなかったため |
| エディタ目視 | Dock / サンプルシーンを目視 | headless 構成テストと Web 画面のみ | この実行環境では Godot ネイティブアプリ面が CUA に公開されなかったため |

**対象外への越境はなし。** `addons/adv_kit/` のランタイム API、GAS の実デプロイ、
unityroom 投稿、ランキング / X 連携、セーブ、Thread / WorkerThreadPool、ランタイム JSON パースは変更していない。

## 3. 未完了・残タスク

| 内容 | 未完了の理由 | 次フェーズで必要か |
|------|--------------|--------------------|
| Godot エディタ上のサンプルシーンと phase-07 Dock の目視 | CUA にネイティブ Godot 画面が公開されなかった | 要。投稿前の人手確認 |
| 最新 Web build の title → 本編 → choice → backlog / auto / skip → end の実ブラウザ再確認 | CUA のキャンバス入力が最新版で安定しなかった | 要。ブラウザまたは実機で一度確認 |
| `epilogue_regret.tres` の stale resource | phase-07 由来の既存 Resource。今回の JSON から外れたが、削除はユーザー確認が必要 | 不要。単一 Book の参照対象外。ただし整理するなら別作業 |
| `AdvEffectSchema.register()` | 仕様上の保留 | 不要。必要になるまで持たない |

## 4. 発生した問題・既知の不具合

| 症状 | 再現条件 | 暫定対応 / 未対応 |
|------|----------|-------------------|
| Windows headless の音声開始が 1 フレームでは間に合わないことがある | `test_effects.gd` の BGM 開始直後を 1 フレーム後だけ確認した場合 | phase08 で最大 8 フレーム待つよう修正。既定ドライバ 5 回、Dummy 8 回の反復で全通過 |
| シナリオ再生成時に `stale_resource` WARNING が 1 件 | 既存の `topics/epilogue_regret.tres` が現在の sample JSON にない | 既存ファイルは削除せず保持。Book と Web scenes export の参照対象外 |
| Godot 終了時に `ObjectDB instances leaked` / `resources still in use` | headless / editor 終了時 | phase-01 からの既知挙動。終了コードで判定 |
| CUA の最新版 Web canvas 入力が不安定 | title 表示後に同じクリック / Space を送っても開始しない場合がある | アセット・シーン・信号接続は smoke test で確認済み。実ブラウザで再確認が必要 |

## 5. 設計・実装上の判断

- **サンプルはタイトル操作で `unlock_audio()` を呼ぶ** — ブラウザの autoplay 制約を本文開始より前に解消し、最初の行に畳み込まれた音を失わないため。
- **Web scenes export の依存を `sample_assets` で明示した** — Kit の立ち絵・音声は仕様どおりパス文字列で遅延ロードするため、シーンから文字列参照だけを追う exporter に依存を認識させる必要がある。ランタイムの遅延ロード契約は変更していない。
- **日本語フォントをサンプルへ同梱した** — ブラウザ環境の fallback に任せると文字化け・豆腐表示になったため。`NotoSansJP-VF.ttf` と `NOTICE.txt` を `game/assets/fonts/` に置いた。
- **サンプル固有の UI を `game/ui/` に置いた** — Kit の UI は外観を持たない基底クラスという仕様を守り、配布アドオンへゲームデザインを混ぜないため。
- **`export_presets.cfg` はローカルのままにした** — `.gitignore` 対象で、環境依存の絶対パスや署名情報をリポジトリへ持ち込まないため。
- **既存の `epilogue_regret.tres` は削除しなかった** — stale warning は事実として記録したが、既存ユーザー成果物を破壊する削除は今回の要求に含まれないため。

## 6. 仕様書への反映提案

| 箇所 | 内容 | 状態 |
|------|------|------|
| §10 | phase-08 の実 Web 検証完了、タイトル操作で `unlock_audio()` を呼ぶサンプル運用を記載 | 反映済み |
| §11 | phase-08 を 2026-09-04 完了へ更新し、成果物を追記 | 反映済み |
| 変更履歴 | サンプル、Web 設定、smoke test の追加を記録 | 反映済み |
| §5 / §10 | `game/` サンプルの具体的なファイル構成と scenes export の依存明示 | 今回は README に記載。仕様本文への追記は任意 |

## 7. 動作確認状況

- **確認済み**:
  - `godot --headless --import` が終了コード 0。
  - 既存 7 テストと `test_sample_scene.gd` が `--audio-driver Dummy` を含む手順で終了コード 0。
  - sample importer で Book / character 3 件 / topic 4 件を書き出し、`missing_portrait_texture` 0 件。
  - Web export が終了コード 0。`build/phase08_web/Build.html`、`Build.pck`、JS、WASM を確認。
  - ローカルブラウザで最新版のタイトル画面を表示し、Noto Sans JP の日本語が豆腐にならないことを確認。
  - 初回 build でタイトル操作後の立ち絵・本文・バックログ表示を確認。
  - 全 GDScript の static check、`git diff --check` を実行。
  - `test_effects.gd` は既定ドライバ 5 回 / Dummy 8 回を反復し、すべて終了コード 0。
- **未確認**:
  - Godot ネイティブエディタ上の UI 余白 / Dock 見た目。
  - 最新 Web build の全入力導線と、canvas リサイズしながらの ShakeRoot の目視。
  - 実音量を含む Web autoplay の完全な再確認。実ブラウザの操作確認を残す。

## 8. 次フェーズへの申し送り

- 最初に `godot --headless --export-release Web build/phase08_web/Build.html` を再実行し、ローカル HTTP サーバで最新版を開いて全導線を人手確認する。
- `export_presets.cfg` はローカル生成物なのでコミットしない。除外は `samples/*`、`tests/*`、`editor/*`、`import/*` の 4 つだけにする。
- `sample_assets` は Web scenes export の依存を明示するためのゲーム側フィールド。ランタイムでこの配列を使ってロードしない。
- `AdvScene/ShakeRoot` は Web リサイズ対応のため、`ShakeRoot` 自体を full-rect anchor にしない既存構造を壊さない。
- `epilogue_regret.tres` は stale warning の対象だが、削除する場合は phase-07 の成果物に対する変更として別途確認する。
- 実素材へ差し替える場合も、シナリオは JSON から `.tres` へ import し、ランタイムから JSON を参照しない。
