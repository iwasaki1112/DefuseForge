class_name MapSelectionScreen
extends Control
## マップ選択画面
##
## Training画面から遷移し、マップを選択してゲームを開始する。
## MapRegistryから登録済みマップ一覧を取得して表示。

signal map_selected(preset_id: String)

const MAIN_MENU_SCENE := "res://scenes/screens/main_menu.tscn"
const GAME_SCENE := "res://scenes/screens/game.tscn"
var BACKGROUND_TEXTURE: Texture2D
var BACK_BUTTON_TEXTURE: Texture2D
var START_BUTTON_TEXTURE: Texture2D
var MAP_CARD_TEXTURE: Texture2D


func _init() -> void:
	BACKGROUND_TEXTURE = load("res://assets/ui/map_selection/background.png")
	BACK_BUTTON_TEXTURE = load("res://assets/ui/map_selection/back-button.png")
	START_BUTTON_TEXTURE = load("res://assets/ui/map_selection/start-button.png")
	MAP_CARD_TEXTURE = load("res://assets/ui/map_selection/map-card-1-button.png")

var _map_container: HBoxContainer
var _selected_map_id: String = ""
var _map_cards: Dictionary[String, TextureButton] = {}  # { map_id: TextureButton }
var _start_btn: TextureButton


func _ready() -> void:
	_setup_ui()
	_load_maps()


func _setup_ui() -> void:
	# 背景画像
	var bg := TextureRect.new()
	bg.texture = BACKGROUND_TEXTURE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)

	# マップ一覧（横スクロール、縦中央配置）
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	# 縦中央に配置
	scroll.anchor_left = 0.0
	scroll.anchor_right = 1.0
	scroll.anchor_top = 0.5
	scroll.anchor_bottom = 0.5
	scroll.offset_left = 0
	scroll.offset_right = 0
	scroll.offset_top = -180
	scroll.offset_bottom = 180

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	_map_container = HBoxContainer.new()
	_map_container.add_theme_constant_override("separation", 0)
	center.add_child(_map_container)

	# Backボタン（左下に配置）
	var back_btn := _create_texture_button(BACK_BUTTON_TEXTURE)
	back_btn.pressed.connect(_on_back_pressed)
	back_btn.custom_minimum_size = Vector2(300, 120)
	add_child(back_btn)
	back_btn.anchor_left = 0.0
	back_btn.anchor_right = 0.0
	back_btn.anchor_top = 1.0
	back_btn.anchor_bottom = 1.0
	back_btn.offset_left = 20
	back_btn.offset_right = 320
	back_btn.offset_top = -140
	back_btn.offset_bottom = -20

	# Startボタン（右下に配置）
	_start_btn = _create_texture_button(START_BUTTON_TEXTURE)
	_start_btn.pressed.connect(_on_start_pressed)
	_start_btn.custom_minimum_size = Vector2(300, 120)
	_start_btn.disabled = true
	add_child(_start_btn)
	_start_btn.anchor_left = 1.0
	_start_btn.anchor_right = 1.0
	_start_btn.anchor_top = 1.0
	_start_btn.anchor_bottom = 1.0
	_start_btn.offset_left = -320
	_start_btn.offset_right = -20
	_start_btn.offset_top = -140
	_start_btn.offset_bottom = -20


func _create_texture_button(texture: Texture2D) -> TextureButton:
	var btn := TextureButton.new()
	btn.texture_normal = texture
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	return btn


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


func _create_map_card(preset: MapPreset) -> TextureButton:
	var card := TextureButton.new()
	card.texture_normal = MAP_CARD_TEXTURE
	card.ignore_texture_size = true
	card.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT
	card.custom_minimum_size = Vector2(240, 320)
	card.pressed.connect(_on_map_card_pressed.bind(preset.id))
	card.set_meta("map_id", preset.id)
	return card


func _on_map_card_pressed(map_id: String) -> void:
	_select_map(map_id)


func _select_map(map_id: String) -> void:
	# 前の選択を解除
	if _selected_map_id and _map_cards.has(_selected_map_id):
		var prev_card := _map_cards[_selected_map_id]
		prev_card.modulate = Color.WHITE

	_selected_map_id = map_id

	# 新しい選択をハイライト
	if _map_cards.has(map_id):
		var card := _map_cards[map_id]
		card.modulate = Color(0.7, 0.9, 1.0, 1.0)

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
