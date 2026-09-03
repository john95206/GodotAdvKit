class_name AdvOptionStep
extends AdvStep
## 選択肢1件を表す[b]パースの中間表現[/b]。
##
## JSON の type="option" は 1 行 = 1 レコードで並んでいる（仕様書 §6.3）。
## パーサは一度これを AdvStep として読み、畳み込み（仕様書 §4.8）で
## 直前の AdvChoiceStep.options へ移してから steps から除去する。
## [b]畳み込み後の AdvTopic.steps に AdvOptionStep が残ることはない。[/b]
## 残っていればそれは dangling_option（畳み込み先が無い）としてエラーになっている。
##
## [i]註: 仕様書 §4 の表にはこのクラスが無い。JSON の 5 種の type を
## 素直に 1:1 で Resource へ写すために phase-01 で追加した中間型で、
## 畳み込み前後で AdvTopic.steps の型を Array[AdvStep] に保つためのもの。[/i]

## 選択肢の表示テキスト。
@export var label: String = ""

## 遷移先 topic_id。空なら現在の topic を継続。
@export var goto: StringName = &""

## 選択時に立てるフラグ名。空可。
@export var flag: String = ""

## 表示条件（仕様書 §4.7）。空なら常に表示。
@export var condition: String = ""


func get_class_label() -> String:
	return "option"


func describe() -> String:
	return "option(order=%d, label=\"%s\")" % [order, label]
