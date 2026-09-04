# docs — ADV Kit の開発ドキュメント

**このフォルダが唯一の置き場所です。** Obsidian にも Claude Project にも写しを置きません。

## なぜ 1 か所に決めたか

2026-09-03 まで、仕様書と台帳が **Obsidian と Claude Project の 2 系統に分岐**していました。

- Obsidian 側 … phase-01 / 02 / 04 / 05 / 06 の記録あり。**仕様書に phase-03 の反映が無い**
- Claude Project 側 … phase-01 / 02 / 03 / 07 の記録あり。**phase-04〜06 の記録が無い**

片方だけを読むと必ず判断を誤ります（実際に「phase-04〜06 の記録が無い」と誤認しました）。
リポジトリなら **Codex も Claude も人間も同じものを読み書きでき、コードと同じコミットに乗る**ので、
ここへ一本化しました。

## 構成

```text
docs/
  README.md                       # このファイル
  spec/adv-kit-spec.md            # 仕様書。source of truth
  plans/
    INDEX.md                      # フェーズ台帳。現在地・判断待ち・決定ログ
    phase-NN-<name>/
      plan.md                     # 実装計画書（実装前に Claude が書く）
      handover.md                 # 引継ぎ資料（実装後に実装者が書く）
  diff-reports/
    phase-NN-diff.md              # 差分分析（計画と実績の突き合わせ）
  guidelines/
    codex-handover.md             # 引継ぎ資料のフォーマット。Codex はこれに従う
```

## 運用ルール

1. **仕様書が source of truth。** 実装が仕様から外れたら、差分レポートで必ず整合を取る
   （仕様書を直すか、実装を戻すかを決める）。放置しない。
2. **写しを作らない。** 「読みやすいから」で別の場所へコピーしない。
   参照が必要なら**リンクを置く**。
3. **フェーズ跨ぎの数値（テスト件数など）は `plans/INDEX.md` を単一の出所にする。**
   計画書に書いた数字は古くなる。
4. **フェーズの命名は `phase-NN-<kebab-name>`。** `NN` はゼロ埋め連番。
5. 実装者は Claude / Codex のどちらでもよい。**どちらがやったかを引継ぎ資料に必ず書く。**

## 実装ループ

```text
仕様書（source of truth）
   │
   ▼
[A] plan.md ──→ 実装 ──→ [C] handover.md
   ▲                          │
   │                          ▼
[E] 次フェーズ計画 ← 仕様書更新 ← [D] diff-reports/
```

- **[A]** 着手前に `plans/phase-NN-<name>/plan.md` を書く。タスクはID付き・受け入れ条件付きで分解する。
  「対象外（今回やらない）」を必ず書く。ここが空だと実装が越境する。
- **[C]** 実装後、`guidelines/codex-handover.md` のフォーマットで `handover.md` を書く。
  計画のタスクIDに対応づける。**構造を崩さない**（差分分析がこの構造に依存している）。
- **[D]** 計画と実績を突き合わせ、`diff-reports/phase-NN-diff.md` を書く。
  差分は必ず原因を分類する（仕様理解のズレ / 技術的制約 / スコープ変更 / 不具合 / 想定内の設計判断）。
- **[E]** 「反映要」とした項目を仕様書へ反映し、持ち越しを次フェーズのスコープに織り込む。
