class_name CharacterTimelineRow
extends HBoxContainer
## キャラクタータイムライン行
## キャラクターラベル（A, B, C...）+ TimelineBarの組み合わせ

const TimelineBarScript = preload("res://scripts/ui/timeline_bar.gd")

## ラベルの幅
const LABEL_WIDTH: float = 30.0
const LABEL_FONT_SIZE: int = 18
const ROW_HEIGHT: float = 28.0
const SPACING: float = 8.0

## 内部参照
var _label: Label = null
var _timeline_bar: TimelineBar = null
var _character: Node = null
var _character_color: Color = Color.CYAN


func _init() -> void:
	custom_minimum_size = Vector2(0, ROW_HEIGHT)
	add_theme_constant_override("separation", int(SPACING))
	# マウスイベントを通過させる
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


## UIを構築
func _build_ui() -> void:
	# キャラクターラベル
	_label = Label.new()
	_label.text = "A"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.custom_minimum_size = Vector2(LABEL_WIDTH, ROW_HEIGHT)
	_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	# タイムラインバー
	_timeline_bar = TimelineBar.new()
	_timeline_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_timeline_bar)


## セットアップ
## @param character: キャラクターノード
## @param label_text: ラベルテキスト（A, B, C...）
## @param color: キャラクター色
func setup(character: Node, label_text: String, color: Color) -> void:
	_character = character
	_character_color = color

	if _label:
		_label.text = label_text
		_label.add_theme_color_override("font_color", color)

	if _timeline_bar:
		_timeline_bar.set_timeline_data(null, color)


## タイムラインデータを設定
func set_timeline_data(data: TimelineCalculator.TimelineData) -> void:
	if _timeline_bar:
		_timeline_bar.set_timeline_data(data, _character_color)


## タイムラインをクリア
func clear() -> void:
	if _timeline_bar:
		_timeline_bar.clear()


## キャラクターを取得
func get_character() -> Node:
	return _character


## キャラクター色を取得
func get_character_color() -> Color:
	return _character_color


## 合計時間を取得
func get_total_duration() -> float:
	return _timeline_bar.get_total_duration() if _timeline_bar else 0.0


## 最大時間を設定（相対スケーリング用）
func set_max_duration(max_duration: float) -> void:
	if _timeline_bar:
		_timeline_bar.set_max_duration(max_duration)


## パス比率から時間を取得
func get_time_at_ratio(ratio: float) -> float:
	return _timeline_bar.get_time_at_ratio(ratio) if _timeline_bar else 0.0
