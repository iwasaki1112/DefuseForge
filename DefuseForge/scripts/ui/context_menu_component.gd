class_name ContextMenuComponent
extends Control

## コンテキストメニューUIコンポーネント
## キャラクタータップ時にメニューを表示し、操作を選択させる
## モバイル（タッチ）とPC（マウス）両対応

signal item_selected(action_id: String, character: CharacterBody3D)

const ContextMenuItemScript = preload("res://scripts/resources/context_menu_item.gd")

## 標準メニュー項目の定義
## 各テストシーンで同じ項目を使用するために一元管理
const DEFAULT_MENU_ITEMS: Array[Dictionary] = [
	{"id": "move", "name": "Move", "order": 0},
	{"id": "rotate", "name": "Rotate", "order": 1},
	{"id": "crouch", "name": "Crouch", "order": 2},
]

@export_group("外観設定")
@export var button_size: Vector2 = Vector2(120, 50)  ## ボタンサイズ（モバイル向け大きめ）
@export var button_margin: float = 4.0  ## ボタン間のマージン
@export var panel_padding: float = 8.0  ## パネル内側のパディング
@export var font_size: int = 16  ## フォントサイズ

@export_group("アニメーション")
@export var animation_duration: float = 0.15  ## 表示/非表示アニメーション時間

var _panel: PanelContainer
var _vbox: VBoxContainer
var _items: Array = []  # Array of ContextMenuItem resources
var _buttons: Array[Button] = []
var _current_character: CharacterBody3D = null
var _is_open: bool = false
var _tween: Tween


func _ready() -> void:
	_build_ui()
	hide()


func _build_ui() -> void:
	# ルートをCanvasLayer配下に配置するため、アンカーを設定
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	# パネルコンテナ
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	# マージンコンテナ
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(panel_padding))
	margin.add_theme_constant_override("margin_top", int(panel_padding))
	margin.add_theme_constant_override("margin_right", int(panel_padding))
	margin.add_theme_constant_override("margin_bottom", int(panel_padding))
	_panel.add_child(margin)

	# 縦並びコンテナ
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", int(button_margin))
	margin.add_child(_vbox)


## メニューを開く
## is_multi_select: 複数キャラクター選択時はtrue（MOVEのみ表示）
func open(screen_position: Vector2, character: CharacterBody3D, is_multi_select: bool = false) -> void:
	if _is_open:
		# 既に開いている場合は即座にリセット（アニメーションなし、シグナルなし）
		if _tween:
			_tween.kill()
		_panel.hide()
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
	await get_tree().process_frame  # サイズ計算を待つ
	var menu_size = _panel.size
	var viewport_size = get_viewport().get_visible_rect().size

	var pos = screen_position
	# 右端クリッピング
	if pos.x + menu_size.x > viewport_size.x:
		pos.x = viewport_size.x - menu_size.x - 10
	# 下端クリッピング
	if pos.y + menu_size.y > viewport_size.y:
		pos.y = viewport_size.y - menu_size.y - 10
	# 左端・上端
	pos.x = max(10, pos.x)
	pos.y = max(10, pos.y)

	_panel.position = pos

	# アニメーション
	show()
	_panel.show()  # パネルも表示（リセット時にhide()されているため）
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.9, 0.9)

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 1.0, animation_duration)
	_tween.tween_property(_panel, "scale", Vector2.ONE, animation_duration).set_ease(Tween.EASE_OUT)


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
	_tween.tween_property(_panel, "modulate:a", 0.0, animation_duration)
	_tween.tween_property(_panel, "scale", Vector2(0.9, 0.9), animation_duration).set_ease(Tween.EASE_IN)
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
	if _panel:
		return Rect2(_panel.global_position, _panel.size)
	return Rect2()


## ボタンを再構築
func _rebuild_buttons() -> void:
	# 既存ボタンをクリア（即座に削除してサイズを正しく計算）
	for button in _buttons:
		_vbox.remove_child(button)
		button.queue_free()
	_buttons.clear()

	# VBoxContainerのサイズをリセット
	_vbox.reset_size()

	# 新規ボタンを作成
	for item in _items:
		var button = Button.new()
		button.text = item.display_name
		button.custom_minimum_size = button_size
		button.disabled = not item.enabled
		button.add_theme_font_size_override("font_size", font_size)

		# アイコンがあれば設定
		if item.icon:
			button.icon = item.icon

		# クリックイベント
		var action_id = item.action_id
		button.pressed.connect(func(): _on_button_pressed(action_id))

		_vbox.add_child(button)
		_buttons.append(button)

	# パネルサイズをリセット
	_panel.reset_size()


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
			# パネル外をクリックした場合は閉じる
			var local_pos = _panel.get_local_mouse_position()
			var panel_rect = Rect2(Vector2.ZERO, _panel.size)
			if not panel_rect.has_point(local_pos):
				close()
				get_viewport().set_input_as_handled()


## キャラクター状態に応じて動的ラベルを更新
func _update_dynamic_labels(character: CharacterBody3D) -> void:
	if character and character.has_method("is_crouching"):
		var is_crouching = character.is_crouching()
		set_item_display_name("crouch", "Stand" if is_crouching else "Crouch")
