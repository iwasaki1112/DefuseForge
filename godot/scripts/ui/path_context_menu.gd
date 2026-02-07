class_name PathContextMenu
extends Control
## パス上タップ時のコンテキストメニュー
##
## パス上をタップした際にA/B/Cのボタンを表示し、選択を受け付ける。
## 将来的にWait Point等の機能に拡張可能。

signal menu_item_selected(item_id: String, path_data: Dictionary)
signal menu_closed()

const MENU_WIDTH := 150
const BUTTON_HEIGHT := 50
const OVERLAY_COLOR := Color(0, 0, 0, 0.3)
const BUTTON_MARGIN := 8

@export_group("外観設定")
@export var animation_duration: float = 0.15  ## 表示/非表示アニメーション時間

var _overlay: ColorRect
var _panel: PanelContainer
var _button_container: VBoxContainer
var _current_path_data: Dictionary = {}
var _is_open: bool = false
var _tween: Tween


func _ready() -> void:
	_build_ui()
	hide()


func _build_ui() -> void:
	# フルスクリーンアンカー
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 半透明オーバーレイ
	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = OVERLAY_COLOR
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.gui_input.connect(_on_overlay_input)
	add_child(_overlay)

	# メニューパネル
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	add_child(_panel)

	# マージンコンテナ
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", BUTTON_MARGIN)
	margin.add_theme_constant_override("margin_top", BUTTON_MARGIN)
	margin.add_theme_constant_override("margin_right", BUTTON_MARGIN)
	margin.add_theme_constant_override("margin_bottom", BUTTON_MARGIN)
	_panel.add_child(margin)

	# ボタンコンテナ
	_button_container = VBoxContainer.new()
	_button_container.add_theme_constant_override("separation", 4)
	margin.add_child(_button_container)

	# WaitPointボタンを作成
	_create_menu_button("WaitPoint", "wait_point")


## メニューボタンを作成
func _create_menu_button(text: String, item_id: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(MENU_WIDTH - BUTTON_MARGIN * 2, BUTTON_HEIGHT)
	button.pressed.connect(_on_button_pressed.bind(item_id))
	_button_container.add_child(button)
	return button


## 指定位置にメニューを表示
## @param screen_pos: 表示位置（スクリーン座標）
## @param path_data: パス情報（キャラクター、パス比率等）
func show_at_position(screen_pos: Vector2, path_data: Dictionary) -> void:
	if _is_open:
		return

	_current_path_data = path_data
	_is_open = true

	# パネルサイズを取得（ボタン数に応じて自動調整）
	await get_tree().process_frame  # レイアウト計算を待つ
	var panel_size := _panel.size

	# 画面端を考慮して位置を調整
	var viewport_size := get_viewport_rect().size
	var pos := screen_pos

	# 右端からはみ出す場合は左にずらす
	if pos.x + panel_size.x > viewport_size.x:
		pos.x = viewport_size.x - panel_size.x - 10

	# 下端からはみ出す場合は上にずらす
	if pos.y + panel_size.y > viewport_size.y:
		pos.y = viewport_size.y - panel_size.y - 10

	# 左端・上端の制限
	pos.x = max(10, pos.x)
	pos.y = max(10, pos.y)

	_panel.position = pos

	# アニメーション表示
	show()
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.9, 0.9)
	_overlay.modulate.a = 0.0

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 1.0, animation_duration)
	_tween.tween_property(_panel, "scale", Vector2.ONE, animation_duration).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_overlay, "modulate:a", 1.0, animation_duration)


## メニューを閉じる
func close() -> void:
	if not _is_open:
		return

	_is_open = false

	# アニメーション
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 0.0, animation_duration)
	_tween.tween_property(_panel, "scale", Vector2(0.9, 0.9), animation_duration).set_ease(Tween.EASE_IN)
	_tween.tween_property(_overlay, "modulate:a", 0.0, animation_duration)
	_tween.chain().tween_callback(_on_close_animation_finished)


## メニューが開いているか
func is_open() -> bool:
	return _is_open


## ボタン押下時
func _on_button_pressed(item_id: String) -> void:
	var path_data := _current_path_data
	close()
	menu_item_selected.emit(item_id, path_data)


## 閉じるアニメーション完了時
func _on_close_animation_finished() -> void:
	hide()
	_current_path_data = {}
	menu_closed.emit()


## オーバーレイクリック検出（パネル外クリックで閉じる）
func _on_overlay_input(event: InputEvent) -> void:
	if not _is_open:
		return

	var is_press := false
	if event is InputEventMouseButton:
		is_press = event.pressed
	elif event is InputEventScreenTouch:
		is_press = event.pressed

	if is_press:
		close()
		get_viewport().set_input_as_handled()
