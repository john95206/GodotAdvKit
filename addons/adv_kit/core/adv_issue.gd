class_name AdvIssue
extends RefCounted
## 検証結果の1件（仕様書 §4.9）。
##
## [b]パーサもバリデータも例外を投げない。[/b] 問題は必ずこの型で返す。

enum Severity {
	## シナリオが再生できなくなるもの。
	ERROR,
	## 意図的な記述かもしれないもの。
	WARNING,
}

## 重大度。
var severity: Severity = Severity.ERROR

## 検証コード。仕様書 §4.9 の表が全集合。
var code: StringName = &""

## 発生箇所。"topics/prologue_01/steps[3]" 形式。
var location: String = ""

## 人が読むメッセージ。
var message: String = ""


static func error(p_code: StringName, p_location: String, p_message: String) -> AdvIssue:
	var issue := AdvIssue.new()
	issue.severity = Severity.ERROR
	issue.code = p_code
	issue.location = p_location
	issue.message = p_message
	return issue


static func warning(p_code: StringName, p_location: String, p_message: String) -> AdvIssue:
	var issue := AdvIssue.new()
	issue.severity = Severity.WARNING
	issue.code = p_code
	issue.location = p_location
	issue.message = p_message
	return issue


func is_error() -> bool:
	return severity == Severity.ERROR


## ログ出力用の1行表現。
func to_line() -> String:
	var tag: String = "ERROR" if is_error() else "WARN "
	return "[%s] %s @ %s — %s" % [tag, code, location, message]
