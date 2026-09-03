class_name AdvJumpStep
extends AdvStep
## 話題遷移（仕様書 §4.3）。

## 遷移先 topic_id。空なら topic 終了。
@export var goto: StringName = &""

## 遷移条件（仕様書 §4.7）。偽なら素通りして次のステップへ。
@export var condition: String = ""


func get_class_label() -> String:
	return "jump"


func describe() -> String:
	return "jump(order=%d, goto=%s)" % [order, goto]
