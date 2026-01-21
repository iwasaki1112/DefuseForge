@tool
class_name ContextMenuComponent
extends Control

## コンテキストメニューUIコンポーネント
## キャラクタータップ時にメニューを表示し、操作を選択させる
## モバイル（タッチ）とPC（マウス）両対応

signal item_selected(action_id: String, character: CharacterBody3D)
signal background_clicked(character: CharacterBody3D)  ## メニュー背景（ボタン以外）がクリックされた

const ContextMenuItemScript = preload("res://scripts/resources/context_menu_item.gd")

## 標準メニュー項目の定義
## 各テストシーンで同じ項目を使用するために一元管理
const DEFAULT_MENU_ITEMS: Array[Dictionary] = [
	{"id": "move", "name": "Move", "order": 0},
	{"id": "rotate", "name": "Rotate", "order": 1},
	{"id": "crouch", "name": "Crouch", "order": 2},
	{"id": "buy", "name": "Buy", "order": 3},
]

@export_group("外観設定")
@export var button_size: Vector2 = Vector2(120, 50)  ## ボタンサイズ（モバイル向け大きめ）
@export var font_size: int = 16  ## フォントサイズ
var _show_button_text: bool = true
@export var show_button_text: bool = true:  ## ボタンのテキスト表示
	get:
		return _show_button_text
	set(value):
		_show_button_text = value
		_queue_editor_refresh()

@export_group("ラジアル配置")
var _radial_radius: float = 120.0
var _radial_start_angle_degrees: float = -90.0
var _radial_padding: float = 8.0
var _use_background_texture_layout: bool = false
var _background_texture: Texture2D
var _background_scale: float = 1.0
var _background_radial_radius_ratio: float = 0.34

@export var radial_radius: float = 120.0:  ## 中心からボタン中心までの距離
	get:
		return _radial_radius
	set(value):
		_radial_radius = value
		_queue_editor_refresh()
@export var radial_start_angle_degrees: float = -90.0:  ## 最初のボタン角度（度）
	get:
		return _radial_start_angle_degrees
	set(value):
		_radial_start_angle_degrees = value
		_queue_editor_refresh()
@export var radial_padding: float = 8.0:  ## 画面端マージン
	get:
		return _radial_padding
	set(value):
		_radial_padding = value
		_queue_editor_refresh()
@export var use_background_texture_layout: bool = false:  ## 背景テクスチャ前提の配置を使用
	get:
		return _use_background_texture_layout
	set(value):
		_use_background_texture_layout = value
		_queue_editor_refresh()
@export var background_texture: Texture2D:  ## 背景テクスチャ（4分割固定向け）
	get:
		return _background_texture
	set(value):
		_background_texture = value
		_queue_editor_refresh()
@export var background_scale: float = 1.0:  ## 背景テクスチャのスケール
	get:
		return _background_scale
	set(value):
		_background_scale = value
		_queue_editor_refresh()
@export var background_radial_radius_ratio: float = 0.34:  ## 背景サイズからのラジアル半径比率
	get:
		return _background_radial_radius_ratio
	set(value):
		_background_radial_radius_ratio = value
		_queue_editor_refresh()

@export_group("セグメント画像")
var _use_segment_textures: bool = false
var _segment_move_texture: Texture2D
var _segment_rotation_texture: Texture2D
var _segment_buy_texture: Texture2D
var _segment_crouch_texture: Texture2D
var _segment_move_rotation_degrees: float = 0.0
var _segment_rotation_rotation_degrees: float = 90.0
var _segment_buy_rotation_degrees: float = 180.0
var _segment_crouch_rotation_degrees: float = 270.0
var _segment_scale: float = 1.0
var _segment_pivot_offset: Vector2 = Vector2(256, 256)

@export var use_segment_textures: bool = false:  ## セグメント画像を使う
	get:
		return _use_segment_textures
	set(value):
		_use_segment_textures = value
		_queue_editor_refresh()
@export var segment_move_texture: Texture2D:
	get:
		return _segment_move_texture
	set(value):
		_segment_move_texture = value
		_queue_editor_refresh()
@export var segment_rotation_texture: Texture2D:
	get:
		return _segment_rotation_texture
	set(value):
		_segment_rotation_texture = value
		_queue_editor_refresh()
@export var segment_buy_texture: Texture2D:
	get:
		return _segment_buy_texture
	set(value):
		_segment_buy_texture = value
		_queue_editor_refresh()
@export var segment_crouch_texture: Texture2D:
	get:
		return _segment_crouch_texture
	set(value):
		_segment_crouch_texture = value
		_queue_editor_refresh()
@export var segment_move_rotation_degrees: float = 0.0:
	get:
		return _segment_move_rotation_degrees
	set(value):
		_segment_move_rotation_degrees = value
		_queue_editor_refresh()
@export var segment_rotation_rotation_degrees: float = 90.0:
	get:
		return _segment_rotation_rotation_degrees
	set(value):
		_segment_rotation_rotation_degrees = value
		_queue_editor_refresh()
@export var segment_buy_rotation_degrees: float = 180.0:
	get:
		return _segment_buy_rotation_degrees
	set(value):
		_segment_buy_rotation_degrees = value
		_queue_editor_refresh()
@export var segment_crouch_rotation_degrees: float = 270.0:
	get:
		return _segment_crouch_rotation_degrees
	set(value):
		_segment_crouch_rotation_degrees = value
		_queue_editor_refresh()
@export var segment_scale: float = 1.0:  ## セグメントのスケール
	get:
		return _segment_scale
	set(value):
		_segment_scale = value
		_queue_editor_refresh()
@export var segment_pivot_offset: Vector2 = Vector2(256, 256):  ## セグメント回転中心
	get:
		return _segment_pivot_offset
	set(value):
		_segment_pivot_offset = value
		_queue_editor_refresh()

@export_group("アニメーション")
@export var animation_duration: float = 0.15  ## 表示/非表示アニメーション時間
@export var item_animation_duration: float = 0.18  ## 各ボタンの表示アニメーション時間
@export var item_stagger_delay: float = 0.06  ## ボタン表示の遅延間隔
@export var item_scale_start: float = 0.6  ## 表示開始時スケール
@export var item_scale_peak: float = 1.06  ## ふわっと膨らむピーク
@export var item_scale_end: float = 1.0  ## 最終スケール

var _menu_root: Control
var _background: TextureRect
var _items: Array = []  # Array of ContextMenuItem resources
var _buttons: Array[BaseButton] = []
var _current_character: CharacterBody3D = null
var _is_open: bool = false
var _tween: Tween
var _item_tween: Tween


func _ready() -> void:
	_build_ui()
	if Engine.is_editor_hint():
		setup_default_items()
		_rebuild_buttons()
		show()
	else:
		hide()


func _queue_editor_refresh() -> void:
	if not Engine.is_editor_hint():
		return
	if not is_inside_tree():
		return
	call_deferred("_rebuild_buttons")


func _build_ui() -> void:
	# ルートをCanvasLayer配下に配置するため、アンカーを設定
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	# メニューのルートコンテナ
	_menu_root = Control.new()
	_menu_root.mouse_filter = Control.MOUSE_FILTER_PASS  # 親に入力を伝播
	add_child(_menu_root)

	_background = TextureRect.new()
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_menu_root.add_child(_background)


## メニューを開く
## is_multi_select: 複数キャラクター選択時はtrue（MOVEのみ表示）
func open(screen_position: Vector2, character: CharacterBody3D, is_multi_select: bool = false) -> void:
	if _is_open:
		# 既に開いている場合は即座にリセット（アニメーションなし、シグナルなし）
		if _tween:
			_tween.kill()
		_menu_root.hide()
		_is_open = false
		# menu_closedは発火しない（新しいメニューを開くため）

	_current_character = character
	_is_open = true

	# 選択数に応じてメニュー項目を設定
	if is_multi_select:
		setup_multi_select_items()
	else:
		setup_default_items()

	# キャラクター状態に応じてラベルを更新
	_update_dynamic_labels(character)

	# ボタンを再構築
	_rebuild_buttons()

	# 位置を計算（画面端クリッピング対策）
	_apply_menu_position(screen_position)

	# アニメーション
	show()
	_menu_root.show()  # リセット時にhide()されているため
	_menu_root.modulate.a = 0.0
	_menu_root.scale = Vector2(0.9, 0.9)

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_menu_root, "modulate:a", 1.0, animation_duration)
	_tween.tween_property(_menu_root, "scale", Vector2.ONE, animation_duration).set_ease(Tween.EASE_OUT)
	_play_item_open_animation()


## メニューを閉じる
func close() -> void:
	if not _is_open:
		return

	_is_open = false
	_current_character = null

	# アニメーション
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_menu_root, "modulate:a", 0.0, animation_duration)
	_tween.tween_property(_menu_root, "scale", Vector2(0.9, 0.9), animation_duration).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(hide)


## メニュー項目を追加
func add_item(item: Resource) -> void:
	_items.append(item)
	_items.sort_custom(func(a, b): return a.order < b.order)


## メニュー項目を削除
func remove_item(action_id: String) -> void:
	for i in range(_items.size() - 1, -1, -1):
		if _items[i].action_id == action_id:
			_items.remove_at(i)
			break


## メニュー項目の有効/無効を設定
func set_item_enabled(action_id: String, enabled: bool) -> void:
	for item in _items:
		if item.action_id == action_id:
			item.enabled = enabled
			break


## メニュー項目の表示名を設定
func set_item_display_name(action_id: String, display_name: String) -> void:
	for item in _items:
		if item.action_id == action_id:
			item.display_name = display_name
			break


## 全メニュー項目をクリア
func clear_items() -> void:
	_items.clear()


## 標準メニュー項目をセットアップ
## どこから呼び出しても同じ項目が追加される
func setup_default_items() -> void:
	clear_items()
	for item_data in DEFAULT_MENU_ITEMS:
		var item = ContextMenuItemScript.create(item_data["id"], item_data["name"], item_data["order"])
		add_item(item)


## 複数選択時用のメニュー項目をセットアップ（MOVEのみ）
func setup_multi_select_items() -> void:
	clear_items()
	var item = ContextMenuItemScript.create("move", "Move", 0)
	add_item(item)


## メニューが開いているか
func is_open() -> bool:
	return _is_open


## 現在のキャラクターを取得
func get_current_character() -> CharacterBody3D:
	return _current_character


## パネルの矩形を取得（画面座標）
func get_panel_rect() -> Rect2:
	if _menu_root:
		return Rect2(_menu_root.global_position, _menu_root.size)
	return Rect2()


## メニュー位置を更新（カメラ移動時など）
func update_screen_position(screen_position: Vector2) -> void:
	if not _is_open:
		return
	if not _menu_root or _menu_root.size == Vector2.ZERO:
		return
	_apply_menu_position(screen_position)


## ボタンを再構築
func _rebuild_buttons() -> void:
	# 既存ボタンをクリア（即座に削除してサイズを正しく計算）
	for button in _buttons:
		_menu_root.remove_child(button)
		button.queue_free()
	_buttons.clear()

	# メニューサイズを再計算
	var button_extent = Vector2(button_size.x * 0.5, button_size.y * 0.5)
	if use_segment_textures and _has_any_segment_texture():
		var base_size = _get_segment_base_size()
		_menu_root.custom_minimum_size = Vector2(base_size, base_size) * segment_scale
		_menu_root.size = _menu_root.custom_minimum_size
	elif use_background_texture_layout and background_texture:
		var texture_size = background_texture.get_size() * background_scale
		_menu_root.custom_minimum_size = texture_size
		_menu_root.size = texture_size
	else:
		var menu_half_size = Vector2(radial_radius, radial_radius) + button_extent
		_menu_root.custom_minimum_size = menu_half_size * 2.0
		_menu_root.size = _menu_root.custom_minimum_size

	_background.texture = background_texture
	_background.visible = (background_texture != null) and not use_segment_textures

	# 新規ボタンを作成
	for item in _items:
		var button: BaseButton = null
		var segment_texture = _get_segment_texture(item.action_id)
		if use_segment_textures and segment_texture:
			var texture_button = TextureButton.new()
			texture_button.texture_normal = segment_texture
			texture_button.texture_pressed = segment_texture
			texture_button.texture_hover = segment_texture
			texture_button.texture_disabled = segment_texture
			texture_button.ignore_texture_size = true
			texture_button.stretch_mode = TextureButton.STRETCH_SCALE
			var scaled_size = segment_texture.get_size() * segment_scale
			texture_button.custom_minimum_size = scaled_size
			texture_button.size = scaled_size
			texture_button.disabled = not item.enabled
			texture_button.tooltip_text = item.display_name
			texture_button.texture_click_mask = _get_click_mask(segment_texture)
			button = texture_button
		else:
			var text_button = Button.new()
			text_button.text = item.display_name if show_button_text else ""
			text_button.tooltip_text = item.display_name
			text_button.custom_minimum_size = button_size
			text_button.size = button_size
			text_button.disabled = not item.enabled
			text_button.flat = true
			text_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			text_button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
			text_button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
			text_button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
			text_button.add_theme_font_size_override("font_size", font_size)
			text_button.pivot_offset = button_size * 0.5

			# アイコンがあれば設定
			if item.icon:
				text_button.icon = item.icon
			button = text_button

		button.set_anchors_preset(Control.PRESET_TOP_LEFT)

		# クリックイベント
		var action_id = item.action_id
		button.set_meta("action_id", action_id)
		button.pressed.connect(func(): _on_button_pressed(action_id))

		_menu_root.add_child(button)
		_buttons.append(button)

	if use_segment_textures and _has_any_segment_texture():
		_update_segment_layout()
	else:
		_update_radial_layout()

	# サイズを確定
	_menu_root.reset_size()


## ボタン押下時
func _on_button_pressed(action_id: String) -> void:
	var character = _current_character
	close()
	item_selected.emit(action_id, character)


## メニュー外クリック検出
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		var pressed = false
		if event is InputEventMouseButton:
			pressed = event.pressed
		elif event is InputEventScreenTouch:
			pressed = event.pressed

		if pressed and _is_open:
			var local_pos = _menu_root.get_local_mouse_position()
			var panel_rect = Rect2(Vector2.ZERO, _menu_root.size)
			if not panel_rect.has_point(local_pos):
				# パネル外をクリックした場合は閉じて選択解除
				var character = _current_character
				close()
				background_clicked.emit(character)
				get_viewport().set_input_as_handled()
			elif not _is_point_over_any_button(local_pos):
				# パネル内だがボタン以外（中央の穴など）をクリックした場合
				var character = _current_character
				close()
				background_clicked.emit(character)
				get_viewport().set_input_as_handled()


## クリック位置がボタン上かどうかを判定
func _is_point_over_any_button(local_pos: Vector2) -> bool:
	for button in _buttons:
		if not is_instance_valid(button):
			continue
		var button_rect = Rect2(button.position, button.size)
		if button_rect.has_point(local_pos):
			return true
	return false


## キャラクター状態に応じて動的ラベルを更新
func _update_dynamic_labels(character: CharacterBody3D) -> void:
	if character and character.has_method("is_crouching"):
		var is_crouching = character.is_crouching()
		set_item_display_name("crouch", "Stand" if is_crouching else "Crouch")


func _update_radial_layout() -> void:
	if _buttons.is_empty():
		return

	var center = _menu_root.size * 0.5
	var count = _buttons.size()
	var angle_step = TAU / max(1, count)
	var start_angle = deg_to_rad(radial_start_angle_degrees)
	var layout_radius = radial_radius
	if use_background_texture_layout and background_texture:
		layout_radius = min(_menu_root.size.x, _menu_root.size.y) * background_radial_radius_ratio

	for i in range(count):
		var angle = start_angle + angle_step * i
		var offset = Vector2(cos(angle), sin(angle)) * layout_radius
		var pos = center + offset - (button_size * 0.5)
		_buttons[i].position = pos


func _update_segment_layout() -> void:
	if _buttons.is_empty():
		return

	var center = _menu_root.size * 0.5
	var base_pivot = segment_pivot_offset * segment_scale

	for button in _buttons:
		var action_id = button.get_meta("action_id") if button.has_meta("action_id") else ""

		button.pivot_offset = base_pivot
		button.position = center - base_pivot
		button.rotation_degrees = _get_segment_rotation_degrees(action_id)


func _get_segment_texture(action_id: String) -> Texture2D:
	match action_id:
		"move":
			return segment_move_texture
		"rotate", "rotation":
			return segment_rotation_texture
		"buy":
			return segment_buy_texture
		"crouch":
			return segment_crouch_texture
	return null


func _get_segment_rotation_degrees(action_id: String) -> float:
	match action_id:
		"move":
			return segment_move_rotation_degrees
		"rotate", "rotation":
			return segment_rotation_rotation_degrees
		"buy":
			return segment_buy_rotation_degrees
		"crouch":
			return segment_crouch_rotation_degrees
	return 0.0


func _has_any_segment_texture() -> bool:
	return segment_move_texture or segment_rotation_texture or segment_buy_texture or segment_crouch_texture


func _get_segment_base_size() -> float:
	var max_size := 0.0
	for texture in [segment_move_texture, segment_rotation_texture, segment_buy_texture, segment_crouch_texture]:
		if texture:
			max_size = max(max_size, texture.get_size().x)
	return max_size if max_size > 0.0 else _menu_root.size.x


func _get_click_mask(texture: Texture2D) -> BitMap:
	var image := texture.get_image()
	var bitmap := BitMap.new()
	if image:
		bitmap.create_from_image_alpha(image)
	return bitmap


func _apply_menu_position(screen_position: Vector2) -> void:
	var menu_size = _menu_root.size
	var viewport_size = get_viewport().get_visible_rect().size

	var pos = screen_position - (menu_size * 0.5)
	# 画面端クリッピング
	pos.x = clamp(pos.x, radial_padding, viewport_size.x - menu_size.x - radial_padding)
	pos.y = clamp(pos.y, radial_padding, viewport_size.y - menu_size.y - radial_padding)

	_menu_root.position = pos
	_menu_root.pivot_offset = _menu_root.size * 0.5


func _play_item_open_animation() -> void:
	if _item_tween:
		_item_tween.kill()
	_item_tween = create_tween()
	_item_tween.set_parallel(true)
	for i in range(_buttons.size()):
		var button = _buttons[i]
		button.modulate.a = 0.0
		button.scale = Vector2.ONE * item_scale_start
		var delay = item_stagger_delay * i
		_item_tween.tween_property(button, "modulate:a", 1.0, item_animation_duration).set_delay(delay)
		_item_tween.tween_property(button, "scale", Vector2.ONE * item_scale_peak, item_animation_duration * 0.7).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_item_tween.tween_property(button, "scale", Vector2.ONE * item_scale_end, item_animation_duration * 0.3).set_delay(delay + item_animation_duration * 0.7).set_ease(Tween.EASE_OUT)
