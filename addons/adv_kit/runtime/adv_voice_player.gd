class_name AdvVoicePlayer
extends Node
## ボイスの単一チャンネル（仕様書 §9.4）。
##
## [b]同時に鳴るボイスは 1 つ。[/b] 次のステップへ進んだ時点で前のボイスを停止する。
## voice_path が空なら何も再生せず、そのまま進行する。[b]ボイスの有無で進行ロジックは分岐しない。[/b]
##
## AdvPlayer が自分の子として実行時に生成する。autoplay ガードは AdvPlayer と共有する。

signal voice_finished()

const FALLBACK_BUS := &"Master"

var _player: AudioStreamPlayer = null
var _audio_unlocked: bool = false
var _bus_warned: bool = false
var _current_path: String = ""


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "VoiceChannel"
	add_child(_player)
	_player.finished.connect(_on_player_finished)


## バスを設定する。存在しなければ Master にフォールバックし、警告は 1 回だけ出す。
func setup(p_bus_name: StringName) -> void:
	_ensure_player()
	var bus_name: StringName = p_bus_name
	if String(bus_name).is_empty() or AudioServer.get_bus_index(bus_name) < 0:
		if not _bus_warned:
			push_warning(
				"AdvVoicePlayer: オーディオバス \"%s\" が無いので %s を使います" % [
					bus_name, FALLBACK_BUS])
			_bus_warned = true
		bus_name = FALLBACK_BUS
	_player.bus = bus_name


func set_audio_unlocked(p_unlocked: bool) -> void:
	_audio_unlocked = p_unlocked


## ボイスを再生する。前のボイスは必ず止まる。
## 空パスは何もしない。解決できないパスは警告して[b]進行は続ける[/b]。
func play_voice(p_voice_path: String) -> void:
	stop()
	if p_voice_path.is_empty() or not _audio_unlocked:
		return
	if not ResourceLoader.exists(p_voice_path):
		push_warning("AdvVoicePlayer: ボイスが見つかりません: %s" % p_voice_path)
		return
	var stream: AudioStream = load(p_voice_path) as AudioStream
	if stream == null:
		push_warning("AdvVoicePlayer: AudioStream ではありません: %s" % p_voice_path)
		return
	_ensure_player()
	_current_path = p_voice_path
	_player.stream = stream
	_player.play()


func stop() -> void:
	_current_path = ""
	if _player != null and is_instance_valid(_player):
		_player.stop()


func is_playing() -> bool:
	return _player != null and is_instance_valid(_player) and _player.playing


func current_path() -> String:
	return _current_path


## 残り再生時間（秒）。鳴っていなければ 0。phase-06 のオートモードが使う。
func get_remaining_time() -> float:
	if not is_playing() or _player.stream == null:
		return 0.0
	return maxf(_player.stream.get_length() - _player.get_playback_position(), 0.0)


func _ensure_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	_player = AudioStreamPlayer.new()
	_player.name = "VoiceChannel"
	add_child(_player)
	_player.finished.connect(_on_player_finished)


func _on_player_finished() -> void:
	_current_path = ""
	voice_finished.emit()
