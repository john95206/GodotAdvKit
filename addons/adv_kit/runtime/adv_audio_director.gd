class_name AdvAudioDirector
extends Node
## SE と BGM のチャンネル（仕様書 §7 / §10）。
##
## [b]AdvPlayer が自分の子として実行時に生成する。[/b] AdvScene.tscn に置かないのは、
## ゲーム側が独自のシーン構成を組んでも音が鳴るようにするため。
##
## [b]autoplay ガード[/b]（仕様書 §10）: 初回のユーザー操作までは一切鳴らさず、保留もしない。
## Web のブラウザポリシーで最初の音が握り潰されると、以後のチャンネル状態が
## 実際の再生とずれるため、「後でまとめて鳴らす」ことはしない。

## BGM は 2 本を交互に使ってクロスフェードする。
const BGM_CHANNEL_COUNT: int = 2
const SILENT_DB: float = -60.0

var _bgm_players: Array[AudioStreamPlayer] = []
var _active_bgm: int = 0
var _bgm_tween: Tween = null
var _current_bgm_path: String = ""
var _audio_unlocked: bool = false

## テスト・デバッグ用の記録。
## [b]実素材が 1 つも無い状態でも「何を再生しようとしたか」を検証できるようにする[/b]
## （R-18）。request は autoplay ガードを通過した回数、play は実際に鳴らした回数。
var _se_request_count: int = 0
var _se_play_count: int = 0
var _last_se_path: String = ""
var _requested_bgm_path: String = ""


func _ready() -> void:
	for index: int in BGM_CHANNEL_COUNT:
		var player := AudioStreamPlayer.new()
		player.name = "Bgm%d" % index
		player.volume_db = SILENT_DB
		add_child(player)
		_bgm_players.append(player)


## autoplay ガードの開閉。false の間は一切鳴らさない。
func set_audio_unlocked(p_unlocked: bool) -> void:
	_audio_unlocked = p_unlocked


func is_audio_unlocked() -> bool:
	return _audio_unlocked


## ワンショット SE。多重再生可（仕様書 §7）。再生し終わったノードは自分で解放される。
func play_se(p_stream_path: String, p_volume_db: float) -> void:
	if not _audio_unlocked:
		return
	if p_stream_path.is_empty():
		return
	_se_request_count += 1
	_last_se_path = p_stream_path
	var stream: AudioStream = _load_stream(p_stream_path, "play_se")
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = p_volume_db
	add_child(player)
	player.finished.connect(player.queue_free, CONNECT_ONE_SHOT)
	player.play()
	_se_play_count += 1


## BGM。単一チャンネル扱いで、切り替え時はクロスフェードする（仕様書 §7）。
func play_bgm(p_stream_path: String, p_fade_in_time: float, p_loop: bool) -> void:
	if not _audio_unlocked:
		return
	if p_stream_path.is_empty():
		return
	_requested_bgm_path = p_stream_path
	var stream: AudioStream = _load_stream(p_stream_path, "play_bgm")
	if stream == null:
		return
	if p_stream_path == _current_bgm_path and _current_player().playing:
		return

	_set_stream_loop(stream, p_loop)
	var previous: AudioStreamPlayer = _current_player()
	_active_bgm = (_active_bgm + 1) % BGM_CHANNEL_COUNT
	var next: AudioStreamPlayer = _current_player()
	_current_bgm_path = p_stream_path

	next.stream = stream
	next.volume_db = SILENT_DB if p_fade_in_time > 0.0 else 0.0
	next.play()

	_kill_bgm_tween()
	if p_fade_in_time <= 0.0:
		_silence(previous)
		return
	_bgm_tween = create_tween()
	_bgm_tween.set_parallel(true)
	_bgm_tween.tween_property(next, "volume_db", 0.0, p_fade_in_time)
	if previous.playing:
		_bgm_tween.tween_property(previous, "volume_db", SILENT_DB, p_fade_in_time)
		_bgm_tween.chain().tween_callback(_silence.bind(previous))


## BGM を止める。fade_out_time が 0 以下なら即座に止める。
func stop_bgm(p_fade_out_time: float) -> void:
	_kill_bgm_tween()
	_current_bgm_path = ""
	if p_fade_out_time <= 0.0:
		for player: AudioStreamPlayer in _bgm_players:
			_silence(player)
		return
	# クロスフェードの途中でも全チャンネルを対象にする（片方だけ残さない）。
	_bgm_tween = create_tween()
	_bgm_tween.set_parallel(true)
	for player: AudioStreamPlayer in _bgm_players:
		if player.playing:
			_bgm_tween.tween_property(player, "volume_db", SILENT_DB, p_fade_out_time)
	_bgm_tween.chain().tween_callback(_silence_all)


## SE も BGM もすべて止める。AdvPlayer.stop() が呼ぶ。
func stop_all() -> void:
	_kill_bgm_tween()
	_current_bgm_path = ""
	_silence_all()
	for child: Node in get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		if player != null and not _bgm_players.has(player):
			player.stop()
			player.queue_free()


func is_bgm_playing() -> bool:
	for player: AudioStreamPlayer in _bgm_players:
		if player.playing:
			return true
	return false


func current_bgm_path() -> String:
	return _current_bgm_path


## autoplay ガードを通過した SE の要求回数（音源の有無に関わらず数える）。
func se_request_count() -> int:
	return _se_request_count


## 実際に AudioStreamPlayer で鳴らした SE の回数。
func se_play_count() -> int:
	return _se_play_count


## 最後に要求された BGM のパス（音源が無くても記録される）。
func requested_bgm_path() -> String:
	return _requested_bgm_path


func last_se_path() -> String:
	return _last_se_path


func _current_player() -> AudioStreamPlayer:
	if _bgm_players.is_empty():
		return null
	return _bgm_players[_active_bgm]


func _silence(p_player: AudioStreamPlayer) -> void:
	if p_player == null or not is_instance_valid(p_player):
		return
	p_player.stop()
	p_player.volume_db = SILENT_DB


func _silence_all() -> void:
	for player: AudioStreamPlayer in _bgm_players:
		_silence(player)


func _kill_bgm_tween() -> void:
	if _bgm_tween != null and is_instance_valid(_bgm_tween):
		_bgm_tween.kill()
	_bgm_tween = null


## 存在しない音源で進行を止めない（仕様書 §9.4 と同じ方針）。
## ランタイムで load() する前に必ず ResourceLoader.exists() で確認する。
static func _load_stream(p_path: String, p_context: String) -> AudioStream:
	if p_path.is_empty():
		return null
	if not ResourceLoader.exists(p_path):
		push_warning("AdvAudioDirector: %s: 音源が見つかりません: %s" % [p_context, p_path])
		return null
	var stream: AudioStream = load(p_path) as AudioStream
	if stream == null:
		push_warning("AdvAudioDirector: %s: AudioStream ではありません: %s" % [p_context, p_path])
	return stream


## ループ指定はストリームの型ごとにプロパティ名が違う。
static func _set_stream_loop(p_stream: AudioStream, p_loop: bool) -> void:
	var wav: AudioStreamWAV = p_stream as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if p_loop else AudioStreamWAV.LOOP_DISABLED
		return
	if "loop" in p_stream:
		p_stream.set(&"loop", p_loop)
