class_name AdvBacklogEntry
extends RefCounted
## バックログに表示する 1 行分の値（仕様書 §9.5）。

var uid: StringName
var speaker_name: String
var name_color: Color
var text: String
var voice_path: String


func _init(
    p_uid: StringName = &"",
    p_speaker_name: String = "",
    p_name_color: Color = Color.WHITE,
    p_text: String = "",
    p_voice_path: String = ""
) -> void:
    uid = p_uid
    speaker_name = p_speaker_name
    name_color = p_name_color
    text = p_text
    voice_path = p_voice_path
