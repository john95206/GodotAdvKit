class_name AdvChoiceStep
extends AdvStep
## 選択肢（仕様書 §4.3）。
##
## スプレッドシートでは 1 選択肢 = 1 行（type=option）で書き、
## パース時に直前の AdvChoiceStep へ畳み込む（仕様書 §4.8）。

## options 辞書のキー。
const KEY_LABEL := "label"
const KEY_GOTO := "goto"
const KEY_FLAG := "flag"
const KEY_CONDITION := "condition"

## 見出し。空可。
@export var prompt: String = ""

## 選択肢。各要素は
## {label: String, goto: StringName, flag: String, condition: String}。
## [b]仕様上ここだけは Variant を許容する。[/b]
@export var options: Array[Dictionary] = []


## 選択肢を1件追加する（畳み込み時にパーサが呼ぶ）。
func add_option(p_label: String, p_goto: StringName, p_flag: String, p_condition: String) -> void:
	options.append({
		KEY_LABEL: p_label,
		KEY_GOTO: p_goto,
		KEY_FLAG: p_flag,
		KEY_CONDITION: p_condition,
	})


func get_class_label() -> String:
	return "choice"


func describe() -> String:
	return "choice(order=%d, options=%d)" % [order, options.size()]
