class_name AdvChoiceMenu
extends Control
## 外観を持たない選択肢 UI の契約（仕様書 §5.4）。
##
## Kit は Theme を提供しない。ゲーム側はこのクラスを継承したシーンを作り、
## present() / close() を実装して AdvPlayer へ差し込む。

signal option_chosen(index: int)


func present(_p_prompt: String, _p_options: Array[Dictionary]) -> void:
	push_error("AdvChoiceMenu.present() は派生クラスで実装してください")


func close() -> void:
	push_error("AdvChoiceMenu.close() は派生クラスで実装してください")
