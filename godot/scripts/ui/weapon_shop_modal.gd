class_name WeaponShopModal
extends Control

## 武器購入モーダルUIコンポーネント
## 武器一覧を表示し、選択・購入を行う

signal weapon_purchased(weapon: WeaponPreset, character: CharacterBody3D)
signal closed()

const MODAL_SIZE := Vector2(400, 500)
const BUTTON_SIZE := Vector2(360, 60)
const OVERLAY_COLOR := Color(0, 0, 0, 0.5)
const AFFORDABLE_COLOR := Color(0.2, 0.6, 0.2)  ## 購入可能時の色
const SELECTED_COLOR := Color(0.3, 0.5, 0.7)  ## 選択時の色

@export_group("外観設定")
@export var animation_duration: float = 0.15  ## 表示/非表示アニメーション時間

var _overlay: ColorRect
var _panel: PanelContainer
var _title_label: Label
var _money_label: Label
var _scroll: ScrollContainer
var _weapon_list: VBoxContainer
var _close_button: Button
var _buy_button: Button

var _weapon_buttons: Array[Button] = []
var _current_character: CharacterBody3D = null
var _selected_weapon: WeaponPreset = null
var _is_open: bool = false
var _tween: Tween


func _ready() -> void:
	_build_ui()
	hide()
	PlayerState.money_changed.connect(_on_money_changed)


func _build_ui() -> void:
	# フルスクリーンアンカー
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 半透明オーバーレイ
	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = OVERLAY_COLOR
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# 中央配置用コンテナ
	var center_container = CenterContainer.new()
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center_container)

	# 中央パネル
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = MODAL_SIZE
	center_container.add_child(_panel)

	# メインコンテナ
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(main_vbox)

	# マージンコンテナ
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(margin)

	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(content_vbox)

	# ヘッダー（タイトル + 所持金）
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	content_vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "BUY WEAPONS"
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_money_label = Label.new()
	_money_label.text = "$0"
	_money_label.add_theme_font_size_override("font_size", 18)
	_money_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
	header.add_child(_money_label)

	# セパレーター
	var separator = HSeparator.new()
	content_vbox.add_child(separator)

	# スクロールコンテナ
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_vbox.add_child(_scroll)

	_weapon_list = VBoxContainer.new()
	_weapon_list.add_theme_constant_override("separation", 8)
	_weapon_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_weapon_list)

	# 下部ボタン
	var button_container = HBoxContainer.new()
	button_container.add_theme_constant_override("separation", 10)
	button_container.alignment = BoxContainer.ALIGNMENT_END
	content_vbox.add_child(button_container)

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.custom_minimum_size = Vector2(100, 44)
	_close_button.pressed.connect(_on_close_pressed)
	button_container.add_child(_close_button)

	_buy_button = Button.new()
	_buy_button.text = "Buy"
	_buy_button.custom_minimum_size = Vector2(100, 44)
	_buy_button.disabled = true
	_buy_button.pressed.connect(_on_buy_pressed)
	button_container.add_child(_buy_button)


## モーダルを開く
func open(character: CharacterBody3D) -> void:
	if _is_open:
		return

	_current_character = character
	_selected_weapon = null
	_is_open = true

	_update_money_display()
	_populate_weapon_list()
	_update_buy_button()

	# アニメーション
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


## モーダルを閉じる
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


## モーダルが開いているか
func is_open() -> bool:
	return _is_open


## 武器リストを構築
func _populate_weapon_list() -> void:
	# 既存ボタンをクリア
	for button in _weapon_buttons:
		button.queue_free()
	_weapon_buttons.clear()

	# WeaponRegistryから武器一覧取得
	var weapons := WeaponRegistry.get_all()
	var current_money := PlayerState.get_money()

	for weapon in weapons:
		var preset := weapon as WeaponPreset
		if not preset:
			continue

		var button := Button.new()
		button.custom_minimum_size = BUTTON_SIZE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 16)

		# ボタンテキスト: 名前 + 価格
		var price_text := "$%d" % preset.price
		button.text = "%s - %s" % [preset.display_name, price_text]

		# 購入可否で色分け
		var can_buy := current_money >= preset.price
		if not can_buy:
			button.disabled = true
			button.modulate = Color(0.5, 0.5, 0.5)
		else:
			button.modulate = Color.WHITE

		# クリックイベント
		var captured_weapon := preset
		button.pressed.connect(func(): _on_weapon_selected(captured_weapon, button))

		_weapon_list.add_child(button)
		_weapon_buttons.append(button)


## 武器選択時
func _on_weapon_selected(weapon: WeaponPreset, button: Button) -> void:
	_selected_weapon = weapon

	# 全ボタンの選択状態をリセット
	var current_money := PlayerState.get_money()
	for btn in _weapon_buttons:
		# 購入可否を再計算
		var can_buy := true
		for w in WeaponRegistry.get_all():
			var preset := w as WeaponPreset
			if preset and btn.text.begins_with(preset.display_name):
				can_buy = current_money >= preset.price
				break

		if btn.disabled:
			btn.modulate = Color(0.5, 0.5, 0.5)
		elif btn == button:
			btn.modulate = SELECTED_COLOR
		else:
			btn.modulate = Color.WHITE

	# 選択ボタンをハイライト
	button.modulate = SELECTED_COLOR

	_update_buy_button()


## Buyボタンの状態を更新
func _update_buy_button() -> void:
	if not _selected_weapon:
		_buy_button.disabled = true
		_buy_button.text = "Buy"
		return

	var can_afford := PlayerState.can_afford(_selected_weapon.price)
	_buy_button.disabled = not can_afford
	_buy_button.text = "Buy ($%d)" % _selected_weapon.price


## 所持金表示を更新
func _update_money_display() -> void:
	_money_label.text = "$%d" % PlayerState.get_money()


## 所持金変更時のコールバック
func _on_money_changed(_new_amount: int) -> void:
	if _is_open:
		_update_money_display()
		_populate_weapon_list()
		_update_buy_button()


## Closeボタン押下
func _on_close_pressed() -> void:
	close()


## Buyボタン押下
func _on_buy_pressed() -> void:
	if not _selected_weapon or not _current_character:
		return

	# 購入処理
	if PlayerState.spend_money(_selected_weapon.price):
		# 武器装備
		_current_character.equip_weapon(_selected_weapon)
		print("[WeaponShopModal] Purchased: %s for $%d" % [_selected_weapon.display_name, _selected_weapon.price])

		# シグナル発火
		var purchased_weapon := _selected_weapon
		var character := _current_character
		close()
		weapon_purchased.emit(purchased_weapon, character)


## 閉じるアニメーション完了時
func _on_close_animation_finished() -> void:
	hide()
	_current_character = null
	_selected_weapon = null
	closed.emit()


## オーバーレイクリック検出
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		var pressed := false
		if event is InputEventMouseButton:
			pressed = event.pressed
		elif event is InputEventScreenTouch:
			pressed = event.pressed

		if pressed and _is_open:
			# パネル外クリックで閉じる
			var local_pos := _panel.get_local_mouse_position()
			var panel_rect := Rect2(Vector2.ZERO, _panel.size)
			if not panel_rect.has_point(local_pos):
				close()
				get_viewport().set_input_as_handled()
