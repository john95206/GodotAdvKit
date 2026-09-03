class_name AdvEffectContext
extends RefCounted
## 演出ハンドラに渡す実行文脈（仕様書 §7）。
##
## ノードを所有しない。[member host] の [method Node.create_tween] に委譲するだけの
## [b]RefCounted[/b] であり、シーン構成を知らないハンドラでも演出を書けるようにする。
##
## 中核は[b]排他ターゲットごとの Tween 台帳[/b]。仕様書 §7 のランタイム規約
## 「演出ハンドラは自分の排他ターゲットに対する実行中の Tween を kill() してから開始する」を、
## ハンドラ個別ではなくこのクラスが一元的に実現する。結果として、静的検証をすり抜けた
## 重なり（ステップをまたぐ演出、拡張演出）でも「後から始まった方が勝つ」になる。

## Tween の生成元。実体は AdvPlayer。
var host: Node = null

## 立ち絵ステージ。
var stage: AdvStage = null

## 画面揺れの対象（仕様書 §5.1）。position の持ち主は shake 演出。
var shake_root: Control = null

## フェード用の最前面レイヤ。
var fade_layer: ColorRect = null

## 再生中のシナリオ。speaker パラメータの解決に使う。
var book: AdvScenarioBook = null

## 再生設定。
var settings: AdvKitSettings = null

## SE / BGM のチャンネル。
var audio: AdvAudioDirector = null

## ボイスの単一チャンネル。
var voice: AdvVoicePlayer = null

## 排他ターゲット文字列 -> 実行中の Tween。
var _tweens: Dictionary[String, Tween] = {}

## Tween -> 中断時に呼ぶ後始末。kill() では Tween の finished が出ないため、
## 「途中で止められたときに最終状態へ寄せる」責務をここに持たせる。
var _finalizers: Dictionary = {}


## 排他ターゲットを占有して新しい Tween を作る。
## 同じターゲットで走っている Tween は kill() してから作る。
## [param p_on_interrupt] は、この Tween が[b]他者に kill() されたとき[/b]に呼ばれる。
## 自然完了したときは呼ばれない。
func acquire_tween(
	p_targets: PackedStringArray, p_on_interrupt: Callable = Callable()
) -> Tween:
	kill_targets(p_targets)
	if host == null or not host.is_inside_tree():
		return null
	var tween: Tween = host.create_tween()
	_register(p_targets, tween, p_on_interrupt)
	return tween


## 既に作られた Tween（AdvStage / AdvPortrait が作ったもの）を台帳へ載せる。
## 立ち絵の alpha は AdvPortrait が唯一の持ち主なので、演出側で作り直さずこちらを使う。
func adopt_tween(
	p_targets: PackedStringArray, p_tween: Tween, p_on_interrupt: Callable = Callable()
) -> Tween:
	kill_targets(p_targets)
	if p_tween == null or not is_instance_valid(p_tween):
		return null
	_register(p_targets, p_tween, p_on_interrupt)
	return p_tween


## 指定ターゲットで走っている Tween を止める。中断後始末を呼んでから kill() する。
func kill_targets(p_targets: PackedStringArray) -> void:
	for target: String in p_targets:
		if not _tweens.has(target):
			continue
		_kill_tween(_tweens[target])


## 台帳の全 Tween を止める。AdvPlayer.stop() が呼ぶ。
func kill_all() -> void:
	for tween: Tween in _tweens.values().duplicate():
		_kill_tween(tween)
	_tweens.clear()
	_finalizers.clear()


## いま占有されている排他ターゲットの一覧（テスト・デバッグ用）。
func active_targets() -> PackedStringArray:
	var result := PackedStringArray()
	for target: String in _tweens.keys():
		result.append(target)
	result.sort()
	return result


## speaker パラメータから AdvCharacter を引く。未知なら null。
func get_character(p_id: StringName) -> AdvCharacter:
	if book == null:
		return null
	return book.get_character(p_id)


## ステージ上の立ち絵を引く。居なければ null。
func get_portrait(p_id: StringName) -> AdvPortrait:
	if stage == null:
		return null
	return stage.get_portrait(p_id)


func _register(
	p_targets: PackedStringArray, p_tween: Tween, p_on_interrupt: Callable
) -> void:
	if p_on_interrupt.is_valid():
		_finalizers[p_tween] = p_on_interrupt
	if p_targets.is_empty():
		# 排他ターゲットを持たない演出（play_se）。台帳には載せない。
		p_tween.finished.connect(_on_tween_finished.bind(p_tween), CONNECT_ONE_SHOT)
		return
	for target: String in p_targets:
		_tweens[target] = p_tween
	p_tween.finished.connect(_on_tween_finished.bind(p_tween), CONNECT_ONE_SHOT)


## 自然完了。最終状態はハンドラ自身が Tween の最後に置いているので後始末は呼ばない。
func _on_tween_finished(p_tween: Tween) -> void:
	_forget(p_tween, false)


func _kill_tween(p_tween: Tween) -> void:
	_forget(p_tween, true)
	if p_tween != null and is_instance_valid(p_tween):
		p_tween.kill()


## 台帳と後始末表から Tween を外す。中断のときだけ後始末を呼ぶ。
func _forget(p_tween: Tween, p_call_finalizer: bool) -> void:
	for target: String in _tweens.keys().duplicate():
		if _tweens[target] == p_tween:
			_tweens.erase(target)
	if not _finalizers.has(p_tween):
		return
	var finalizer: Callable = _finalizers[p_tween]
	_finalizers.erase(p_tween)
	if p_call_finalizer and finalizer.is_valid():
		finalizer.call()
