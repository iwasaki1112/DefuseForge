class_name MapSelectionScreen
extends Control
## マップ選択画面
##
## Training画面から遷移し、マップを選択してゲームを開始する。
## MapRegistryから登録済みマップ一覧を取得して表示。

signal map_selected(preset_id: String)

const MAIN_MENU_SCENE := "res://scenes/screens/main_menu.tscn"
const GAME_SCENE := "res://scenes/screens/game.tscn"
const ScreenLayoutScript := preload("res://scripts/ui/screen_layout.gd")

var _map_container: GridContainer
var _selected_map_id: String = ""
var _map_cards: Dictionary[String, PanelContainer] = {}  # { map_id: PanelContainer }
var _start_btn: Button


func _ready() -> void:
	_setup_ui()
	_load_maps()


func _setup_ui() -> void:
	# 背景色
	ScreenLayoutScript.add_solid_background(self)

	# メインコンテナ
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 40)
	main_vbox.add_theme_constant_override("separation", 20)
	add_child(main_vbox)

	# ヘッダー
	var header := _create_header()
	main_vbox.add_child(header)

	# マップ一覧（スクロール可能）
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	_map_container = GridContainer.new()
	_map_container.columns = 2
	_map_container.add_theme_constant_override("h_separation", 20)
	_map_container.add_theme_constant_override("v_separation", 20)
	_map_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_map_container)

	# フッター（開始ボタン）
	var footer := _create_footer()
	main_vbox.add_child(footer)


func _create_header() -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)

	# 戻るボタン
	var back_btn := Button.new()
	back_btn.text = "< Back"
	back_btn.custom_minimum_size = Vector2(100, 50)
	back_btn.add_theme_font_size_override("font_size", 20)
	back_btn.pressed.connect(_on_back_pressed)
	hbox.add_child(back_btn)

	# タイトル
	var title := Label.new()
	title.text = "Select Map"
	title.add_theme_font_size_override("font_size", 36)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(title)

	# スペーサー（左右対称用）
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(spacer)

	return hbox


func _create_footer() -> Control:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)

	_start_btn = Button.new()
	_start_btn.name = "StartButton"
	_start_btn.text = "Start Game"
	_start_btn.custom_minimum_size = Vector2(250, 60)
	_start_btn.add_theme_font_size_override("font_size", 28)
	_start_btn.disabled = true
	_start_btn.pressed.connect(_on_start_pressed)
	hbox.add_child(_start_btn)

	return hbox


func _load_maps() -> void:
	var presets := MapRegistry.get_all()

	if presets.is_empty():
		var no_maps_label := Label.new()
		no_maps_label.text = "No maps available"
		no_maps_label.add_theme_font_size_override("font_size", 24)
		no_maps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_map_container.add_child(no_maps_label)
		return

	for preset in presets:
		var card := _create_map_card(preset)
		_map_container.add_child(card)
		_map_cards[preset.id] = card


func _create_map_card(preset: MapPreset) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(300, 200)

	# スタイルボックス
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25, 1.0)
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	card.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# サムネイル（あれば）
	var thumbnail_rect := TextureRect.new()
	thumbnail_rect.custom_minimum_size = Vector2(270, 100)
	thumbnail_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	thumbnail_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	if preset.thumbnail:
		thumbnail_rect.texture = preset.thumbnail
	else:
		# プレースホルダー
		var placeholder := ColorRect.new()
		placeholder.color = Color(0.15, 0.15, 0.2, 1.0)
		placeholder.custom_minimum_size = Vector2(270, 100)

		var placeholder_label := Label.new()
		placeholder_label.text = "No Preview"
		placeholder_label.add_theme_font_size_override("font_size", 16)
		placeholder_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		placeholder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		placeholder.add_child(placeholder_label)

		vbox.add_child(placeholder)
		thumbnail_rect.queue_free()
		thumbnail_rect = null

	if thumbnail_rect:
		vbox.add_child(thumbnail_rect)

	# マップ名
	var name_label := Label.new()
	name_label.text = preset.display_name if preset.display_name else preset.id
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	# 説明
	if preset.description:
		var desc_label := Label.new()
		desc_label.text = preset.description
		desc_label.add_theme_font_size_override("font_size", 14)
		desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(desc_label)

	# クリック検出用ボタン（透明）
	var click_btn := Button.new()
	click_btn.flat = true
	click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	click_btn.pressed.connect(_on_map_card_pressed.bind(preset.id))
	card.add_child(click_btn)

	# メタデータとしてIDを保持
	card.set_meta("map_id", preset.id)

	return card


func _on_map_card_pressed(map_id: String) -> void:
	_select_map(map_id)


func _select_map(map_id: String) -> void:
	# 前の選択を解除
	if _selected_map_id and _map_cards.has(_selected_map_id):
		var prev_card := _map_cards[_selected_map_id] as PanelContainer
		var prev_style := prev_card.get_theme_stylebox("panel") as StyleBoxFlat
		prev_style.border_color = Color(0.3, 0.3, 0.35, 1.0)

	_selected_map_id = map_id

	# 新しい選択をハイライト
	if _map_cards.has(map_id):
		var card := _map_cards[map_id] as PanelContainer
		var style := card.get_theme_stylebox("panel") as StyleBoxFlat
		style.border_color = Color(0.3, 0.7, 1.0, 1.0)

	# 開始ボタンを有効化
	if _start_btn:
		_start_btn.disabled = false

	map_selected.emit(map_id)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_start_pressed() -> void:
	if _selected_map_id.is_empty():
		return

	# 選択したマップIDを保持してゲームシーンに遷移
	_start_game_with_map(_selected_map_id)


func _start_game_with_map(map_id: String) -> void:
	# マップIDをグローバルに保持（SettingsManagerを使用）
	SettingsManager.set_selected_map(map_id)
	get_tree().change_scene_to_file(GAME_SCENE)
