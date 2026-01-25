extends Control
class_name RoundHUD
## ラウンドHUD
##
## タイマー、生存者数、ラウンド結果を表示するUI。

# ============================================
# Constants
# ============================================

const TIMER_WARNING_THRESHOLD := 10.0  # 残り時間警告閾値（秒）
const TIMER_WARNING_COLOR := Color(1.0, 0.3, 0.3)  # 警告時の色（赤）
const TIMER_NORMAL_COLOR := Color.WHITE  # 通常時の色

const CT_COLOR := Color(0.4, 0.6, 1.0)  # CTの色（青）
const T_COLOR := Color(1.0, 0.6, 0.3)  # Tの色（オレンジ）

# ============================================
# UI Elements
# ============================================

var _top_bar: HBoxContainer = null
var _ct_label: Label = null
var _timer_label: Label = null
var _t_label: Label = null
var _result_overlay: ColorRect = null
var _result_label: Label = null

# ============================================
# Lifecycle
# ============================================

func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	# 画面全体に広がるように設定
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 上部バー
	_top_bar = HBoxContainer.new()
	_top_bar.name = "TopBar"
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.offset_top = 10
	_top_bar.offset_bottom = 60
	_top_bar.offset_left = 20
	_top_bar.offset_right = -20
	_top_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_top_bar.add_theme_constant_override("separation", 30)
	add_child(_top_bar)

	# CT生存者数ラベル
	_ct_label = Label.new()
	_ct_label.name = "CTLabel"
	_ct_label.text = "CT: 0"
	_ct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ct_label.add_theme_font_size_override("font_size", 28)
	_ct_label.add_theme_color_override("font_color", CT_COLOR)
	_ct_label.custom_minimum_size = Vector2(80, 0)
	_top_bar.add_child(_ct_label)

	# タイマーラベル
	_timer_label = Label.new()
	_timer_label.name = "TimerLabel"
	_timer_label.text = "1:30"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 36)
	_timer_label.add_theme_color_override("font_color", TIMER_NORMAL_COLOR)
	_timer_label.custom_minimum_size = Vector2(100, 0)
	_top_bar.add_child(_timer_label)

	# T生存者数ラベル
	_t_label = Label.new()
	_t_label.name = "TLabel"
	_t_label.text = "T: 0"
	_t_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_t_label.add_theme_font_size_override("font_size", 28)
	_t_label.add_theme_color_override("font_color", T_COLOR)
	_t_label.custom_minimum_size = Vector2(80, 0)
	_top_bar.add_child(_t_label)

	# 結果オーバーレイ（非表示で初期化）
	_result_overlay = ColorRect.new()
	_result_overlay.name = "ResultOverlay"
	_result_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_overlay.color = Color(0, 0, 0, 0.7)
	_result_overlay.visible = false
	_result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_result_overlay)

	# 結果ラベル
	_result_label = Label.new()
	_result_label.name = "ResultLabel"
	_result_label.text = ""
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_label.set_anchors_preset(Control.PRESET_CENTER)
	_result_label.add_theme_font_size_override("font_size", 48)
	_result_overlay.add_child(_result_label)

# ============================================
# Public Methods
# ============================================

## タイマーを更新
func update_timer(remaining: float) -> void:
	var total_seconds := int(remaining)
	@warning_ignore("integer_division")
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	_timer_label.text = "%d:%02d" % [minutes, seconds]

	# 警告色の切り替え
	if remaining <= TIMER_WARNING_THRESHOLD:
		_timer_label.add_theme_color_override("font_color", TIMER_WARNING_COLOR)
	else:
		_timer_label.add_theme_color_override("font_color", TIMER_NORMAL_COLOR)


## 生存者数を更新
func update_survivor_counts(ct: int, t: int) -> void:
	_ct_label.text = "CT: %d" % ct
	_t_label.text = "T: %d" % t


## 結果を表示
## winner: GameCharacter.Team, _reason: RoundManager.EndReason
func show_result(winner: int, _reason: int) -> void:
	var result_text: String
	var result_color: Color

	match winner:
		GameCharacter.Team.COUNTER_TERRORIST:
			result_text = "COUNTER-TERRORIST WINS"
			result_color = CT_COLOR
		GameCharacter.Team.TERRORIST:
			result_text = "TERRORIST WINS"
			result_color = T_COLOR
		_:
			result_text = "DRAW"
			result_color = Color.WHITE

	_result_label.text = result_text
	_result_label.add_theme_color_override("font_color", result_color)
	_result_overlay.visible = true

	# フェードインアニメーション
	_result_overlay.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_result_overlay, "modulate:a", 1.0, 0.3)


## 結果を非表示
func hide_result() -> void:
	_result_overlay.visible = false
