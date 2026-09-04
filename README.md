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
| 現在のフェーズ | **phase-08 完了** |

## このリポジトリの構成

```text
AdvKit/
  project.godot            # 開発・検証用のプロジェクト
  addons/adv_kit/          # ← 配布物。ゲーム側へはこのフォルダごと持っていく
  docs/                    # 仕様書・台帳・計画書・引継ぎ資料・差分レポート
  game/                    # サンプルゲーム側。Kit はここに書き込まない
                           #   resources/adv/scenario/*.tres ← インポータの出力
                           #   scenes/ / ui/ / assets/        ← phase-08 サンプル
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

# phase-01: 失敗が1件でもあれば終了コード 1
godot --headless --script res://addons/adv_kit/tests/test_scenario_parse.gd

# phase-02: 再生テスト
godot --headless --script res://addons/adv_kit/tests/test_playback.gd

# phase-03: 演出・ボイステスト
godot --headless --script res://addons/adv_kit/tests/test_effects.gd

# phase-04: 話者交代演出テスト
godot --headless --script res://addons/adv_kit/tests/test_auto_direction.gd

# phase-05: 選択肢・進行状態テスト
godot --headless --script res://addons/adv_kit/tests/test_progress.gd

# phase-06: オート・スキップ・バックログテスト
godot --headless --script res://addons/adv_kit/tests/test_play_assist.gd

# phase-07: シナリオインポータテスト
godot --headless --script res://addons/adv_kit/tests/test_import.gd

# phase-08: サンプルシーン smoke test
godot --headless --audio-driver Dummy --script res://addons/adv_kit/tests/test_sample_scene.gd
```

Windows の headless 実行では、音声ドライバを明示できるテストに
`--audio-driver Dummy` を付けてください。既定ドライバでは音声デバイスが無い環境で
`is_playing()` の確認だけが不安定になることがあります。

## サンプルを起動する

`project.godot` の main scene は `game/scenes/sample_main.tscn` です。エディタから実行するか、次で起動できます。

```bash
godot --path .
```

タイトル画面の `CLICK TO BEGIN` が最初のユーザー操作になり、音声を unlock してから
プロローグを開始します。本文送りはクリック / Space、オートは A、既読スキップは Ctrl、
バックログは B です。選択肢の後に別ルートへ進み、終了画面から再開できます。

## Web で確認する

ローカルの `export_presets.cfg`（gitignore 対象）を用意した環境では、次で `Build.pck` を含む
Web 出力を作れます。

```powershell
godot --headless --export-release Web build/phase08_web/Build.html
py -m http.server 8000 --bind 127.0.0.1 --directory build/phase08_web
```

ブラウザで `http://127.0.0.1:8000/Build.html` を開き、タイトル操作後に本文・選択肢・
バックログ・オート・スキップ・終了まで確認します。Web preset は Compatibility、
1280x720、`canvas_items` + `keep`、Thread 無しです。除外するのは次の 4 パターンだけです。

```text
res://addons/adv_kit/samples/*
res://addons/adv_kit/tests/*
res://addons/adv_kit/editor/*
res://addons/adv_kit/import/*
```

## シナリオの取り込み

スプレッドシート → GAS → JSON → `.tres` の経路です。詳細は
[アドオンの README](addons/adv_kit/README.md#シナリオパイプラインphase-07) と
[GAS の手順書](addons/adv_kit/import/gas/README.md) を参照してください。

```bash
godot --headless --import
godot --headless --script res://addons/adv_kit/import/adv_import_cli.gd -- \
    --url=<GAS のウェブアプリ URL> --out=res://game/resources/adv/scenario/
godot --headless --import
```

> **URL はリポジトリ・コミットメッセージ・チャットに書かないこと。**
> 認証は URL の秘匿のみです（仕様書 §6.2 / U-05）。
> CLI は環境変数 `ADV_KIT_SCENARIO_URL` からも読みます。

> **Windows で CLI から叩くときは `_console.exe` の方を使うこと。**
> `Godot_v4.7.x-stable_win64.exe` はコンソールに接続しないため、
> テストの出力が端末に出ず、終了コードも取れない。
> エディタを開くときは通常の `.exe`、CLI は `_console.exe` と使い分ける。

> 終了時に `ObjectDB instances leaked` / `resources still in use` が出ますが、
> `AdvStep` の型が自分自身を参照していることによる**エンジン終了時のみの既知の挙動**で、
> 終了コードには影響しません。**CI は必ず終了コードで判定してください**（stderr の有無で判定しない）。

## ドキュメント

**[`docs/`](docs/) が唯一の置き場所です。** 仕様書・フェーズ台帳・実装計画書・引継ぎ資料・差分レポートが
すべてここにあります。**仕様書（[`docs/spec/adv-kit-spec.md`](docs/spec/adv-kit-spec.md)）が source of truth。**

| 見たいもの | 場所 |
|---|---|
| いま何がどこまで終わっているか | [`docs/plans/INDEX.md`](docs/plans/INDEX.md) |
| 仕様 | [`docs/spec/adv-kit-spec.md`](docs/spec/adv-kit-spec.md) |
| フェーズごとの計画と引継ぎ | `docs/plans/phase-NN-<name>/` |
| 計画と実績の突き合わせ | `docs/diff-reports/` |
| 引継ぎ資料の書き方（Codex 向け） | [`docs/guidelines/codex-handover.md`](docs/guidelines/codex-handover.md) |

> **写しを作らないこと。** 2026-09-03 まで Obsidian と Claude Project に写しがあり、
> 片方にしか無い反映が生じて分岐しました。経緯は [`docs/README.md`](docs/README.md)。

## コミットの前に

`.uid` ファイル（Godot 4.4+ の安定リソース ID）は**コミットします**。
新しいスクリプトやシーンを足したら、`godot --headless --import` を1回走らせて
`.uid` を生成してから `git add` してください。
