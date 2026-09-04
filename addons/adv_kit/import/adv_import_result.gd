class_name AdvImportResult
extends AdvParseResult
## インポート1回分の結果（仕様書 §6.4）。
##
## AdvParseResult を継承しているので、[method AdvParseResult.is_ok] /
## [method AdvParseResult.errors] / [method AdvParseResult.warnings] /
## [method AdvParseResult.to_lines] がそのまま使える。
## ここで足すのは「書き出しの結果」だけ。
##
## [b]例外を投げない。[/b] 取得失敗も書き出し失敗も AdvIssue として積む。

## 取得元。ローカルパス、または[b]ホスト名まで丸めた URL[/b]。
##
## [b]生の URL を入れてはならない。[/b] この値は summary() と CLI のログ、
## エディタ Dock の表示に出る。URL の秘匿が唯一の認証手段なので
## （仕様書 §6.2 / U-05）、AdvScenarioImporter.redact_url() を通した値を入れる。
var source_label: String = ""

## 実際に書き出した .tres のパス。
var written_paths: PackedStringArray = PackedStringArray()

## JSON から消えたのに出力先に残っている .tres のパス。
## [b]削除しない。[/b] 参照切れによる事故を避けるため警告するだけ（仕様書 §6.4）。
var stale_paths: PackedStringArray = PackedStringArray()

## content_hash が既存 Book と一致したため書き出しを省いたか。
var skipped: bool = false


## 書き出したパスを1件足す。
## [b]外から written_paths.append() を呼ばないこと。[/b] PackedStringArray は値型で、
## プロパティ越しに得たものへ append しても書き戻らない。
func add_written(p_path: String) -> void:
	written_paths.append(p_path)


## 取り残された .tres を1件足す。理由は add_written と同じ。
func add_stale(p_path: String) -> void:
	stale_paths.append(p_path)


## Book が持つスキーマ版。Book が無ければ 0。
func schema_version() -> int:
	if book == null:
		return 0
	return book.schema_version


## Book が持つ content_hash。Book が無ければ空文字。
func content_hash() -> String:
	if book == null:
		return ""
	return book.content_hash


## 人が読む1行サマリ。CLI と Dock の両方が使う。
func summary() -> String:
	if not is_ok():
		return "失敗: ERROR %d 件 / WARNING %d 件（%s）" % [
			errors().size(), warnings().size(), source_label]
	if skipped:
		return "変更なし: content_hash \"%s\" が既存と一致（%s）" % [content_hash(), source_label]
	return "成功: %d ファイル書き出し / WARNING %d 件（%s）" % [
		written_paths.size(), warnings().size(), source_label]
