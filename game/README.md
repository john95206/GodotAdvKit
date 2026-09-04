# AdvKit サンプルゲーム

`game/` は ADV Kit のゲーム側実装を確認するためのサンプルです。アドオン本体の
`AdvMessageWindow` / `AdvChoiceMenu` / `AdvBacklogView` を継承した UI、実素材、
インポート済みの `.tres`、Web 書き出しを一つの小さなシーンにまとめています。

## 起動

プロジェクトルートで次を実行するか、Godot エディタからプロジェクトを実行します。

```powershell
godot --path .
```

main scene は `scenes/sample_main.tscn` です。タイトル画面の `CLICK TO BEGIN` が
音声 unlock を兼ねた最初のユーザー操作になります。

| 操作 | 動作 |
|---|---|
| クリック / Space | 本文送り・タイプライタ完了 |
| A | オートモード切り替え |
| Ctrl | 既読スキップ |
| B | バックログ開閉 |

## Web 確認

`export_presets.cfg` は環境依存のため gitignore 対象です。ローカル preset を用意した後、
次で書き出せます。

```powershell
godot --headless --export-release Web build/phase08_web/Build.html
py -m http.server 8000 --bind 127.0.0.1 --directory build/phase08_web
```

`http://127.0.0.1:8000/Build.html` を開き、タイトル操作後に本文、選択肢、バックログ、
オート、スキップ、終了画面を確認します。Web preset は Compatibility、1280x720、
`canvas_items` + `keep`、Thread 無しで、`addons/adv_kit/` のうち除外するのは
`samples/*`、`tests/*`、`editor/*`、`import/*` の 4 パターンだけです。

## シナリオと素材

- `resources/adv/scenario/`: phase-07 の importer が生成した Book / character / topic Resource
- `resources/adv/settings.tres`: サンプル用の暗転・ホップ・タイプ速度・オート待機設定
- `assets/adv/`: 背景、立ち絵、BGM、SE、ボイス
- `ui/`: ゲーム側の UI 差し替え実装

シナリオ JSON を更新した場合は、インポータを再実行して Resource を更新します。
ランタイムは JSON を読みません。
