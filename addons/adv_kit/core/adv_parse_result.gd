class_name AdvParseResult
extends RefCounted
## AdvScenarioParser.parse() の戻り値。

## パース結果。ERROR があっても「できたところまで」が入る（null にはしない）。
var book: AdvScenarioBook = null

## 検出された問題。
var issues: Array[AdvIssue] = []


## ERROR が 0 件なら true。
func is_ok() -> bool:
	for issue: AdvIssue in issues:
		if issue.is_error():
			return false
	return true


func errors() -> Array[AdvIssue]:
	var result: Array[AdvIssue] = []
	for issue: AdvIssue in issues:
		if issue.is_error():
			result.append(issue)
	return result


func warnings() -> Array[AdvIssue]:
	var result: Array[AdvIssue] = []
	for issue: AdvIssue in issues:
		if not issue.is_error():
			result.append(issue)
	return result


func add_issue(p_issue: AdvIssue) -> void:
	if p_issue != null:
		issues.append(p_issue)


func add_issues(p_issues: Array[AdvIssue]) -> void:
	for issue: AdvIssue in p_issues:
		add_issue(issue)


## 指定コードの issue が含まれるか。テストとログ用。
func has_code(p_code: StringName) -> bool:
	for issue: AdvIssue in issues:
		if issue.code == p_code:
			return true
	return false


## 全 issue の1行表現。
func to_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for issue: AdvIssue in issues:
		lines.append(issue.to_line())
	return lines
