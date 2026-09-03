# AdvKit

Godot 4.7 向けの **ADV（ノベルゲーム）共通パッケージ**と、その開発用プロジェクト。

本体は [`addons/adv_kit/`](addons/adv_kit/) にあります。使い方はそちらの
[README](addons/adv_kit/README.md) を参照してください。

| | |
|---|---|
| エンジン | Godot **4.7-stable**（.NET 版ではない） |
| 上限 | **4.8 以降には上げない。** unityroom の対応上限が 4.7（2026-06-23 時点）。超えると投稿できない |

> `project.godot` の `config/features` は**プロジェクトを開いたエンジンが書き換えます**。
> 4.5 で開くと `"4.5"` に、4.7 で開くと `"4.7"` に戻ります（片道ではありません）。
> git の差分に出たら、それはバージョンを行き来した印です。
| レンダラー | **Compatibility**（Web / unityroom 前提） |
| 言語 | GDScript（静的型付け必須） |
| 現在のフェーズ | **phase-01 完了 / phase-02 未着手** |

## このリポジトリの構成

```text
AdvKit/
  project.godot            # 開発・検証用のプロジェクト
  addons/adv_kit/          # ← 配布物。ゲーム側へはこのフォルダごと持っていく
  game/                    # 各ゲーム固有。Kit はここに書き込まない（現在は空）
```

**ADV Kit は `addons/adv_kit/` の外へコードを置きません。** ルートの `project.godot` は
アドオンを開発・テストするための入れ物で、配布物には含めません。

## 他のゲームへの取り込み方

`addons/adv_kit/` フォルダをゲームのプロジェクトへコピーし、
プロジェクト設定 → プラグイン から有効化します。

> **submodule で取り込みたくなったら**: submodule はリポジトリ全体を 1 フォルダとして
> マウントするため、リポジトリ直下が `plugin.cfg` である必要があります。
> そのときは履歴付きで切り出せます。
>
> ```bash
> git subtree split -P addons/adv_kit -b adv-kit-only
> ```
>
> 逆（分けたものを1つに戻す）より簡単なので、**必要になるまで分けません**。

## テスト

```bash
# class_name のグローバル解決のため、先にインポートを1回走らせる
godot --headless --import

# 失敗が1件でもあれば終了コード 1
godot --headless --script res://addons/adv_kit/tests/test_scenario_parse.gd
```

> **Windows で CLI から叩くときは `_console.exe` の方を使うこと。**
> `Godot_v4.7.x-stable_win64.exe` はコンソールに接続しないため、
> テストの出力が端末に出ず、終了コードも取れない。
> エディタを開くときは通常の `.exe`、CLI は `_console.exe` と使い分ける。

> 終了時に `ObjectDB instances leaked` / `resources still in use` が出ますが、
> `AdvStep` の型が自分自身を参照していることによる**エンジン終了時のみの既知の挙動**で、
> 終了コードには影響しません。**CI は必ず終了コードで判定してください**（stderr の有無で判定しない）。

## ドキュメント

仕様書・実装計画書・引継ぎ資料・差分レポートは Obsidian 側の
`プロジェクト/Godot 向けライブラリ制作/` にあります。**仕様書が source of truth** です。

## コミットの前に

`.uid` ファイル（Godot 4.4+ の安定リソース ID）は**コミットします**。
新しいスクリプトやシーンを足したら、`godot --headless --import` を1回走らせて
`.uid` を生成してから `git add` してください。
