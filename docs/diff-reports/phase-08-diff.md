# 差分レポート: フェーズ08 web-hardening-and-sample

- **対象計画書**: `docs/plans/phase-08-web-hardening-and-sample/plan.md`
- **対象引継ぎ資料**: `docs/plans/phase-08-web-hardening-and-sample/handover.md`
- **分析日**: 2026-09-04

## 1. サマリ

- **計画タスク**: 全 8 件中 **完了 8 / 部分 0 / 未着手 0**
- **DoD の留保**: 実装・自動検証は完了。Godot ネイティブ画面と最新版 Web の全入力導線は、実行環境の CUA 制約で目視留保
- **総合判定**: **実装完了、投稿前に短い人手確認が必要**。ランタイム API や仕様の越境はない。

## 2. 逸脱の詳細（原因分類つき）

| # | 差分 | 分類 | 影響範囲 | 仕様書へ反映 |
|---|------|------|----------|--------------|
| 1 | 実素材ではなく、サンプル用に生成した PNG / WAV を同梱した | 想定内の判断 | `game/assets/` のみ | README / handover に反映 |
| 2 | Web preset の `export_filter` を `scenes` とし、シーンから遅延ロード素材への依存を `sample_assets` で明示した | 技術的制約 | Web PCK の内容 | README / handover に反映 |
| 3 | 日本語フォントをサンプルへ同梱した | ブラウザ差異 | `game/assets/fonts/` と Web PCK | NOTICE / README に反映 |
| 4 | `test_import.gd` の欠損テクスチャ fixture を、実素材付き sample JSON と両立する形に更新した | 回帰修正 | phase-07 のテストだけ | handover に反映 |
| 5 | `test_effects.gd` の音声開始確認に最大 8 フレーム待ちを追加した | 回帰修正 | headless 音声テスト | handover に反映 |
| 6 | 最新版 Web の全導線と Godot エディタ目視が未完 | 環境制約 | 投稿前確認 | handover に未完了として記載 |

**対象外への越境はない。** `addons/adv_kit/` のランタイム API、GAS、unityroom 投稿、
ランキング / X、セーブ、Thread、ランタイム JSON パースには手を出していない。

## 3. 受け入れ条件の確認

| タスク | 判定 | 根拠 |
|--------|------|------|
| T-01 | ✅ | 背景 1、立ち絵 8、音声 Resource 3 を配置。Book の参照を解決 |
| T-02 | ✅ | sample JSON → `.tres` 書き出し。missing warning 0 件 |
| T-03 | ✅ | 3 つのゲーム側 UI 差し替えシーンと smoke test |
| T-04 | ✅ | タイトル、unlock、topic 開始、終了 / 再開の signal wiring |
| T-05 | ✅ | project 設定、Web preset、Build.pck |
| T-06 | ✅ | `settings.tres` に値を分離し、ShakeRoot 構成を維持 |
| T-07 | ✅ | 8 テスト（sample smoke test は 28 件）、Web export 終了コード 0 |
| T-08 | ✅ | README 3 本、台帳、仕様書、handover、diff を更新 |

## 4. 残課題

1. 実機の Godot エディタで `sample_main.tscn` の余白・文字切れ・Dock の見た目を確認する。
2. 最新 Web build で title → 本編 → choice → backlog / auto / skip → end を確認する。
3. `epilogue_regret.tres` を削除するかどうかは別途判断する（今回削除していない）。
