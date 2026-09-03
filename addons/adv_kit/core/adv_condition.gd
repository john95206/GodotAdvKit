class_name AdvCondition
extends RefCounted
## condition 文字列の構文解析と評価（仕様書 §4.7）。
##
## [codeblock]
## expr       := or_expr
## or_expr    := and_expr ( "||" and_expr )*
## and_expr   := term ( "&&" term )*
## term       := "!"? identifier
## identifier := [A-Za-z_][A-Za-z0-9_]*
## [/codeblock]
##
## [b]GDScript の Expression クラスは使わない。[/b]
## Web での安全性と、スプレッドシート記述者にとっての可読性のため。
##
## [br]・[code]&&[/code] が [code]||[/code] より強く結合する（[code]a && b || c[/code] は [code](a && b) || c[/code]）
## [br]・括弧はサポートしない（仕様書 §13 U-04）
## [br]・未定義フラグは false。[b]構文検証の段階では未定義フラグを検出しない[/b]
## [br]・空文字は文法の対象外。検証せず、評価は常に true（＝条件指定なし）

const ISSUE_CODE := &"invalid_condition"


## 構文検証のみを行う。問題があれば invalid_condition の ERROR を1件返す。
## 空文字は issue なしで通す。
static func validate(p_expr: String, p_location: String) -> Array[AdvIssue]:
	var issues: Array[AdvIssue] = []
	if is_always_true(p_expr):
		return issues
	var parser := _Parser.new()
	parser.setup(p_expr, {})
	parser.parse()
	if not parser.error.is_empty():
		issues.append(AdvIssue.error(
			ISSUE_CODE,
			p_location,
			"条件式 \"%s\" の構文エラー: %s" % [p_expr, parser.error]
		))
	return issues


## 評価する。未定義フラグは false 扱い。
## 構文エラー時は false を返し push_warning する。
static func evaluate(p_expr: String, p_flags: Dictionary) -> bool:
	if is_always_true(p_expr):
		return true
	var parser := _Parser.new()
	parser.setup(p_expr, p_flags)
	var value: bool = parser.parse()
	if not parser.error.is_empty():
		push_warning("AdvCondition: 条件式 \"%s\" の構文エラー: %s" % [p_expr, parser.error])
		return false
	return value


## 条件指定なし（空文字・空白のみ）かどうか。
static func is_always_true(p_expr: String) -> bool:
	return p_expr.strip_edges().is_empty()


## 構文が正しいかどうかだけを返す簡易版。
static func is_valid(p_expr: String) -> bool:
	return validate(p_expr, "").is_empty()


## トークナイズと再帰下降パースを1回で行う。
## 構文木は作らず、評価しながら降りる（構文検証時は空の flags で評価だけ捨てる）。
class _Parser extends RefCounted:
	enum Token { NONE, IDENT, NOT, AND, OR }

	var _kinds := PackedInt32Array()
	var _texts := PackedStringArray()
	var _pos: int = 0
	var _flags: Dictionary = {}

	## 空でなければ構文エラー。最初の1件だけを保持する。
	var error: String = ""

	func setup(p_expr: String, p_flags: Dictionary) -> void:
		_flags = p_flags
		_tokenize(p_expr)

	func parse() -> bool:
		if not error.is_empty():
			return false
		var value: bool = _parse_or()
		if error.is_empty() and _pos < _kinds.size():
			_fail("余分なトークン '%s' があります" % _texts[_pos])
		return value

	func _parse_or() -> bool:
		var value: bool = _parse_and()
		while error.is_empty() and _peek() == Token.OR:
			_pos += 1
			var rhs: bool = _parse_and()
			value = value or rhs
		return value

	func _parse_and() -> bool:
		var value: bool = _parse_term()
		while error.is_empty() and _peek() == Token.AND:
			_pos += 1
			var rhs: bool = _parse_term()
			value = value and rhs
		return value

	func _parse_term() -> bool:
		if not error.is_empty():
			return false
		var negate: bool = false
		if _peek() == Token.NOT:
			negate = true
			_pos += 1
		if _peek() != Token.IDENT:
			if _pos >= _kinds.size():
				_fail("式が途中で終わっています。フラグ名が必要です")
			else:
				_fail("'%s' の位置にはフラグ名が必要です" % _texts[_pos])
			return false
		var flag_name: String = _texts[_pos]
		_pos += 1
		var value: bool = bool(_flags.get(flag_name, false))
		return (not value) if negate else value

	## 現在位置のトークン種別（Token の値）。終端なら Token.NONE。
	func _peek() -> int:
		if _pos >= _kinds.size():
			return int(Token.NONE)
		return _kinds[_pos]

	func _fail(p_message: String) -> void:
		if error.is_empty():
			error = p_message

	func _tokenize(p_expr: String) -> void:
		var i: int = 0
		var n: int = p_expr.length()
		while i < n:
			var c: String = p_expr[i]
			if c == " " or c == "\t" or c == "\n" or c == "\r":
				i += 1
				continue
			if c == "&":
				if i + 1 < n and p_expr[i + 1] == "&":
					_push(Token.AND, "&&")
					i += 2
					continue
				_fail("'&' は単独では使えません。'&&' と書いてください")
				return
			if c == "|":
				if i + 1 < n and p_expr[i + 1] == "|":
					_push(Token.OR, "||")
					i += 2
					continue
				_fail("'|' は単独では使えません。'||' と書いてください")
				return
			if c == "!":
				_push(Token.NOT, "!")
				i += 1
				continue
			if _is_ident_start(c):
				var start: int = i
				i += 1
				while i < n and _is_ident_char(p_expr[i]):
					i += 1
				_push(Token.IDENT, p_expr.substr(start, i - start))
				continue
			_fail("使用できない文字 '%s' があります（使えるのは英数字・_ と ! && || のみ）" % c)
			return

	func _push(p_kind: Token, p_text: String) -> void:
		_kinds.append(int(p_kind))
		_texts.append(p_text)

	static func _is_ident_start(c: String) -> bool:
		return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"

	static func _is_ident_char(c: String) -> bool:
		return _is_ident_start(c) or (c >= "0" and c <= "9")
