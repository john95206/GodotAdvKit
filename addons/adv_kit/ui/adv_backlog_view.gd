class_name AdvBacklogView
extends Control
## 外観を持たないバックログ UI の契約（仕様書 §5.4 / §9.5）。
##
## Kit は Theme を提供しない。ゲーム側はこのクラスを継承したシーンを作り、
## present() / close() と必要な signal を実装して AdvPlayer へ差し込む。

signal closed()
signal voice_replay_requested(entry: AdvBacklogEntry)


func present(_p_entries: Array[AdvBacklogEntry]) -> void:
    push_error("AdvBacklogView.present() は派生クラスで実装してください")


func close() -> void:
    push_error("AdvBacklogView.close() は派生クラスで実装してください")
