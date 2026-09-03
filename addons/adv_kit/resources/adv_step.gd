@abstract
class_name AdvStep
extends Resource
## 全ステップの抽象基底（仕様書 §4.3）。
##
## [b]1 ステップ = 1 回のテキスト送りで消費される単位。[/b]

## スプレッドシートの order 列の値をそのまま保持する。
## 書き手が振る値で、行を挿入しても既存行は変わらない。
@export var order: int = 0

## 安定ステップID。"<topic_id>:<order>" 形式で、パーサが生成する。
## 既読管理とセーブの復元位置はこの ID を使う（仕様書 §9.1）。
@export var uid: StringName = &""

## 所属 topic の steps 配列における添字（畳み込み後）。
## [b].tres には保存してよいが、セーブデータに書き出してはならない。[/b]
## 畳み込み後の添字なので、parallel 演出を1行足しただけで全部ずれる。
@export var step_index: int = -1

## このステップの開始と同時に走る演出（畳み込み結果。仕様書 §4.8）。
## [b]要素は必ず AdvEffectStep[/b] だが、宣言型は Array[AdvStep] にする。
## 基底 AdvStep が派生 AdvEffectStep を型注釈に使うと class_name の
## グローバル解決が循環しうるため（仕様書 §4.3 / R-07）。
## 要素が AdvEffectStep であることは AdvScenarioParser が保証する。
@export var parallel_effects: Array[AdvStep] = []


## ログ・エラーメッセージ用の1行表現。派生クラスが上書きする。
func describe() -> String:
	return "%s(order=%d)" % [get_class_label(), order]


## 派生クラスの短い識別名。JSON の type と対応する。
func get_class_label() -> String:
	return "step"
