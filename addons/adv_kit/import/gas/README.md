# GAS（スプレッドシート → シナリオ JSON）

`adv_scenario_export.gs` を Google スプレッドシートに紐づけた Apps Script へ貼り、
ウェブアプリとしてデプロイすると、仕様書 §6.3 の JSON を返す API になります。

その JSON を Godot 側（エディタ Dock / CLI）が `.tres` に変換します。
**ランタイムからこの URL を叩くことはありません**（CORS 制約。仕様書 §6 冒頭）。

## 1. シートを作る

シートは 3 つ。**1 行目がヘッダ行**で、列の順番は問いません（列名で引きます）。

### `characters`

| id | display_name | name_color | portrait_dir | poses | expressions | default_pose | default_expression |
|----|--------------|-----------|--------------|-------|-------------|--------------|--------------------|
| yuu | ユウ | `#ffd27f` | `res://game/assets/adv/portraits/yuu` | `stand, arms_crossed` | `normal, smile, worried` | stand | normal |

- `poses` / `expressions` は**カンマ区切り**。総当たりで `<portrait_dir>/<pose>_<expression>.png` を組みます
- **全組み合わせを用意する必要はありません**。欠けている組み合わせは解決順（仕様書 §4.2）でフォールバックします
- 立ち絵を持たないキャラは `portrait_dir` 以降を空にします

### `topics`

| id | title | tags |
|----|-------|------|
| prologue_01 | プロローグ | `chapter1, entry` |

- `tags` はカンマ区切り。**`entry` を含む topic** はゲーム側から直接呼ばれる想定として、
  到達性検証（`unreachable_topic`）の対象外になります

### `steps`

| topic_id | order | type | speaker | expression | pose | slot | text | voice | effect_id | params | sync | auto_advance | prompt | label | flag | goto | condition |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|

- `order` は **10, 20, 30… と空けておく**。後から行を挿入できます
- **既存行の `order` を変えないこと。** `order` は安定ステップID `uid` の一部で、変えると既読データが壊れます
- `type` は `line` / `effect` / `choice` / `jump` / `option`
- 使わない列は空のままで構いません。GAS が `type` を見て必要な列だけ拾います
- `params` は **1 セルに JSON を書かない**。`key=value` をセミコロン区切りで書きます

  ```text
  strength=8; duration=0.4
  stream=res://game/assets/adv/se/door.ogg
  to_slot=left; duration=0.6; ease=out
  ```

- `parallel` 演出と `option` は**独立した行**として書きます。直前のステップへ畳み込むのは Godot 側です（仕様書 §4.8）
- **topic の 1 行目に音を置かないこと。** autoplay ガード（仕様書 §10）で破棄されます

## 2. デプロイする

1. スプレッドシートで **拡張機能 → Apps Script**
2. `adv_scenario_export.gs` の中身を貼る
3. `previewScenarioJson` を一度実行して、実行ログに JSON が出ることを確認する（権限承認もここで済みます）
4. **デプロイ → 新しいデプロイ → 種類「ウェブアプリ」**
   - 次のユーザーとして実行: **自分**
   - アクセスできるユーザー: **全員**
5. 発行された `https://script.google.com/macros/s/.../exec` を控える

## 3. URL の扱い

**認証は URL の秘匿のみ**です（仕様書 §6.2 / U-05）。トークンや署名は付けません。

- **リポジトリ・コミットメッセージ・チャットに URL を書かないこと**
- エディタ Dock に入力した URL は `user://adv_kit_import.cfg` に保存されます（`res://` ではありません）
- CLI では `--url=` か、環境変数 `ADV_KIT_SCENARIO_URL` で渡します

この判断が成り立つ前提は、**書き込み系の `doPost` を足さないこと**です。
足すならこの決定をやり直してください。

## 4. GAS がやらないこと

| やらないこと | 誰がやるか |
|---|---|
| 畳み込み（`parallel` 演出 / `option` 行を直前のステップへ吸収） | `AdvScenarioParser`（仕様書 §4.8） |
| `params` の型変換 | `AdvEffectSchema`（仕様書 §7） |
| 参照整合性の検証（`unknown_speaker` / `unknown_topic` など） | `AdvScenarioValidator`（仕様書 §4.9） |
| 立ち絵の存在確認 | `AdvScenarioImporter`（仕様書 §4.2） |

JSON を flat に保つことで、**手書き JSON でのテストが容易**になります。
`--file=` でローカル JSON を食わせれば、GAS 無しで経路全体を検証できます。

## 5. `content_hash`

`generated_at` を**含めずに** MD5 を取っています。
中身が変わっていないのに毎回ハッシュが変わると、インポータの差分スキップ（仕様書 §6.4）が効かないためです。
