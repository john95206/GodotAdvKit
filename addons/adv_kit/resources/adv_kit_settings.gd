class_name AdvKitSettings
extends Resource
## 汎用演出・プレイ支援・入力の設定（仕様書 §4.6）。
##
## .tres としてプロジェクトに1つ置き、AdvPlayer に @export で注入する。
## [b]phase-01 ではこの Resource を読む側がまだ存在しない。[/b]
## 定義と既定値だけを確定させる。

@export_group("汎用演出", "dim_")
## 非話者の立ち絵を暗くする。
@export var dim_non_speakers: bool = true
## 暗転時の modulate。
@export var dim_color: Color = Color(0.55, 0.55, 0.6)
## 明暗の遷移時間（秒）。
@export var dim_duration: float = 0.15

@export_group("汎用演出（ホップ）", "hop_")
## 話者交代時に新話者を小さく跳ねさせる。
@export var hop_on_speaker_change: bool = true
## 跳ねる高さ（px）。
@export var hop_height: float = 18.0
## 跳ねる時間（秒）。
@export var hop_duration: float = 0.22

@export_group("表示")
## 1秒あたりの表示文字数。0 で即時表示。
@export var typing_speed: float = 40.0

@export_group("オートモード", "auto_")
## テキスト表示完了後に次へ進むまでの秒数。
@export var auto_wait_time: float = 1.5
## ボイス再生の終了を待つか。true なら max(ボイス長, auto_wait_time)。
@export var auto_wait_for_voice: bool = true

@export_group("スキップ", "skip_")
## false = 既読ステップのみスキップ。true = 未読も強制スキップ。
@export var skip_unread: bool = false
## スキップ中に1ステップ進める間隔（秒）。
@export var skip_interval: float = 0.02
## 選択肢に到達したらスキップを解除する。
@export var skip_stops_at_choice: bool = true

@export_group("バックログ", "backlog_")
## バックログの保持上限。超えた分は古いものから捨てる。
@export var backlog_max_entries: int = 200
## バックログからボイスを再生できるようにする。
@export var backlog_voice_replay: bool = true

@export_group("ボイス", "voice_")
## ボイス用のオーディオバス名。存在しなければ Master にフォールバックする。
@export var voice_bus: StringName = &"Voice"

@export_group("入力アクション")
## テキスト送り。既定バインド: マウス左 / Enter / Space。
@export var advance_action: StringName = &"adv_advance"
## スキップ。既定バインド: Ctrl（押しっぱなしで継続）。
@export var skip_action: StringName = &"adv_skip"
## オートモード切り替え。既定バインド: A。
@export var auto_action: StringName = &"adv_auto"
## バックログ表示。既定バインド: マウスホイール上 / B。
@export var backlog_action: StringName = &"adv_backlog"
