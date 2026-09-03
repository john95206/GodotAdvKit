class_name AdvBacklog
extends RefCounted
## 上限付きバックログ。進行保存とは独立した一時データ（仕様書 §9.5）。

var _max_entries: int = 200
var _entries: Array[AdvBacklogEntry] = []


func set_max_entries(p_max_entries: int) -> void:
    _max_entries = maxi(p_max_entries, 0)
    _trim_to_limit()


func get_max_entries() -> int:
    return _max_entries


func append(p_entry: AdvBacklogEntry) -> void:
    if p_entry == null or _max_entries <= 0:
        return
    _entries.append(p_entry)
    _trim_to_limit()


## append() と同じ操作名を明示した別名。ゲーム側の記述を読みやすくする。
func add_entry(p_entry: AdvBacklogEntry) -> void:
    append(p_entry)


func get_entries() -> Array[AdvBacklogEntry]:
    var result: Array[AdvBacklogEntry] = []
    result.append_array(_entries)
    return result


func size() -> int:
    return _entries.size()


func is_empty() -> bool:
    return _entries.is_empty()


func clear() -> void:
    _entries.clear()


func _trim_to_limit() -> void:
    while _entries.size() > _max_entries:
        _entries.pop_front()
