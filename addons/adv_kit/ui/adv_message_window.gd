class_name AdvMessageWindow
extends Control
## 外観を持たないメッセージ窓の契約（仕様書 §5.4）。
##
## Kit は Theme を提供しない。ゲーム側はこのクラスを継承したシーンを作り、
## show_line() などを実装して AdvPlayer へ差し込む。

signal advance_requested()
signal skip_typing_requested()


func show_line(p_speaker_name: String, p_name_color: Color, p_text: String) -> void:
	push_error("AdvMessageWindow.show_line() は派生クラスで実装してください")


func set_typing_progress(p_ratio: float) -> void:
	push_error("AdvMessageWindow.set_typing_progress() は派生クラスで実装してください")


func complete_typing() -> void:
	push_error("AdvMessageWindow.complete_typing() は派生クラスで実装してください")


func clear() -> void:
	push_error("AdvMessageWindow.clear() は派生クラスで実装してください")
