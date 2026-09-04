# 実装計画書: フェーズ08 web-hardening-and-sample

- **作成日**: 2026-09-04
- **実装者**: Codex
- **対象リポジトリ**: `C:\Users\kzr12\Root\MyProjects\AdvKit\`（Godot 4.7 系 / Compatibility）

## 1. フェーズ概要

- **ゴール**: `AdvScene` / `AdvPlayer` を実素材で動かすサンプルを用意し、Web 書き出しで
  autoplay ガード、画面リサイズ、演出、選択肢、バックログが破綻しないことを確認する。
- **仕様書の該当箇所**: §5（シーン構成・UI 差し替え契約）、§8（汎用演出）、§9（プレイ支援）、
  §10（Web / unityroom 制約）、§11（phase-08）。
- **前提フェーズ**: phase-01〜07 完了。phase-07 の未完了項目（実素材・Web・Dock 目視）を引き取る。

## 2. スコープ

**対象**

- `game/` 配下のサンプルシーン、ゲーム側 UI、設定 Resource、立ち絵・音声素材。
- サンプルシナリオを実素材で再生できるようにするための `sample_scenario.json` の更新と `.tres` 再生成。
- `project.godot` の main scene / viewport / stretch 設定。
- Web export 用のローカル preset（`export_presets.cfg` は gitignore 対象）と、再現可能な手順の README。
- サンプルシーンを対象にしたヘッドレス smoke test。
- 目視確認で決めた演出パラメータ（暗転、ホップ、揺れ、フェード、オート待機）。
- phase-07 引継ぎに記載された Windows 既定オーディオドライバ差の検証手順の文書化。

**対象外（今回やらない）**

- `addons/adv_kit/` のランタイム API 変更。既存契約の範囲でゲーム側から差し替える。
- GAS の実デプロイや認証 URL の取得。phase-07 の CLI / Dock の契約を利用するだけ。
- unityroom へのアップロード、ランキング SDK、X ポスト。
- 実際の投稿後環境でしか確認できないランキング疎通。
- `export_presets.cfg` のコミット。絶対パスを含みうるため、ローカル生成・README 手順化に留める。
- `Thread` / `WorkerThreadPool` の導入、JSON のランタイム読み込み、セーブ機能の追加。

## 3. タスク分解

| ID | タスク | 受け入れ条件 | 依存 |
|----|--------|--------------|------|
| T-01 | サンプル素材 | `game/assets/adv/` に背景・立ち絵・音声を置き、サンプル Book が全参照を解決できる | - |
| T-02 | サンプルシナリオ / Resource | 実素材パスを使う JSON から `.tres` を生成し、missing texture 警告 0 件で読み戻せる | T-01 |
| T-03 | ゲーム側 UI | `AdvMessageWindow` / `AdvChoiceMenu` / `AdvBacklogView` の差し替えシーンが契約どおり動く | - |
| T-04 | サンプルメインシーン | タイトル操作で音声を unlock して再生を開始し、選択肢・終了・再開を操作できる | T-02,T-03 |
| T-05 | Web 設定 | main scene、1280x720、`canvas_items` + `keep`、Compatibility を維持し、Web preset は thread 無し | T-04 |
| T-06 | 演出調整 | 立ち絵の暗転 / 話者ホップ / 揺れ / フェードがサンプルで過剰にならず、設定 Resource に分離される | T-04 |
| T-07 | 検証 | 既存 7 テスト（effects は Dummy audio driver）と sample smoke test が終了コード 0。Web export が `Build.pck` を出力する | T-05,T-06 |
| T-08 | 文書・台帳 | README に起動方法、Web 検証、export 除外、既知の音声ドライバ差を追記し、phase08 handover を作成する | T-07 |

## 4. 完了定義（DoD）

- [ ] サンプルシーンをエディタで開いて UI の重なり・余白・文字切れがない。※ Godot ネイティブ画面の目視は未実施
- [ ] タイトルの最初のクリック前に音声が鳴らず、クリック後に BGM / SE / voice が再生可能。※ 実ブラウザの最新版全導線は未確認
- [x] Web export が Compatibility / thread 無しで成功し、`Build.html` と `Build.pck` が生成される。
- [ ] Web ブラウザで title → 本編 → choice → backlog / auto / skip → end の導線を確認する。※ CUA の最新版入力が不安定
- [ ] `AdvScene` の `ShakeRoot` リサイズ追従と `ShakeRoot.position` の揺れが Web でも破綻しない。※ リサイズ操作の目視は未実施
- [x] 既存テストとサンプル smoke test が終了コード 0。
- [x] 全変更された GDScript が静的型付きで警告 0 件。
- [x] `addons/adv_kit/samples` / `tests` / `editor` / `import` を Web export から除外する手順が文書化される。
- [x] phase08 handover が `codex-handover.md` の全セクションを埋め、T-01〜T-08 と対応づく。

## 5. リスク・確認事項

| ID | 内容 | 対応 |
|----|------|------|
| R-24 | Windows の既定オーディオドライバでは headless の再生状態が不安定 | 回帰テストは `--audio-driver Dummy` で実行し、Web は実ブラウザで確認する |
| R-25 | ignored な `export_presets.cfg` が環境ごとに無い | ローカル preset を生成して export し、README に再作成手順を残す |
| R-26 | Web の canvas リサイズで `ShakeRoot` がずれる | `1280x720` / `canvas_items` / `keep` と実ブラウザ確認で検証する |
