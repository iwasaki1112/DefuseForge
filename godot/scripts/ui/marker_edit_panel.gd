extends VBoxContainer
class_name MarkerEditPanel
## マルチキャラクター対応マーカー編集パネル
## キャラクター選択＋Vision/Runマーカー設定UI

## キャラクター選択時のシグナル
signal character_selected(character: Node)
## Vision追加要求シグナル
signal vision_add_requested(character: Node)
## Vision Undo要求シグナル
signal vision_undo_requested(character: Node)
## Run追加要求シグナル
signal run_add_requested(character: Node)
## Run Undo要求シグナル
signal run_undo_requested(character: Node)
## 確定要求シグナル
signal confirm_requested()
## キャンセル要求シグナル
signal cancel_requested()

## キャラクター選択部分
var _character_label: Label = null
var _character_container: HBoxContainer = null
var _character_buttons: Dictionary = {}  # { char_id: Button }

## 視線ポイント部分
var _vision_label: Label = null
var _vision_hbox: HBoxContainer = null
var _add_vision_button: Button = null
var _undo_vision_button: Button = null

## Runマーカー部分
var _run_label: Label = null
var _run_hbox: HBoxContainer = null
var _add_run_button: Button = null
var _undo_run_button: Button = null

## 確定/キャンセル
var _confirm_button: Button = null
var _cancel_button: Button = null

## 対象キャラクター
var _characters: Array[Node] = []
var _active_character: Node = null

## PathDrawerへの参照
var _path_drawer: Node = null


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# パネルスタイル
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(220, 0)

	# キャラクター選択ラベル
	_character_label = Label.new()
	_character_label.text = "Select character for markers:"
	add_child(_character_label)

	# キャラクターボタンコンテナ
	_character_container = HBoxContainer.new()
	_character_container.add_theme_constant_override("separation", 4)
	add_child(_character_container)

	# セパレータ1
	var sep1 = HSeparator.new()
	add_child(sep1)

	# 視線ポイントラベル
	_vision_label = Label.new()
	_vision_label.text = "Vision Points: 0"
	add_child(_vision_label)

	# 視線ポイントボタン
	_vision_hbox = HBoxContainer.new()
	_vision_hbox.add_theme_constant_override("separation", 4)
	add_child(_vision_hbox)

	_add_vision_button = Button.new()
	_add_vision_button.text = "Add Vision"
	_add_vision_button.pressed.connect(_on_add_vision_pressed)
	_vision_hbox.add_child(_add_vision_button)

	_undo_vision_button = Button.new()
	_undo_vision_button.text = "Undo"
	_undo_vision_button.pressed.connect(_on_undo_vision_pressed)
	_vision_hbox.add_child(_undo_vision_button)

	# セパレータ2
	var sep2 = HSeparator.new()
	add_child(sep2)

	# Runマーカーラベル
	_run_label = Label.new()
	_run_label.text = "Run Segments: 0"
	add_child(_run_label)

	# Runマーカーボタン
	_run_hbox = HBoxContainer.new()
	_run_hbox.add_theme_constant_override("separation", 4)
	add_child(_run_hbox)

	_add_run_button = Button.new()
	_add_run_button.text = "Add Run"
	_add_run_button.pressed.connect(_on_add_run_pressed)
	_run_hbox.add_child(_add_run_button)

	_undo_run_button = Button.new()
	_undo_run_button.text = "Undo"
	_undo_run_button.pressed.connect(_on_undo_run_pressed)
	_run_hbox.add_child(_undo_run_button)

	# セパレータ3
	var sep3 = HSeparator.new()
	add_child(sep3)

	# 確定ボタン
	_confirm_button = Button.new()
	_confirm_button.text = "Confirm Path"
	_confirm_button.pressed.connect(_on_confirm_pressed)
	add_child(_confirm_button)

	# キャンセルボタン
	_cancel_button = Button.new()
	_cancel_button.text = "Cancel"
	_cancel_button.pressed.connect(_on_cancel_pressed)
	add_child(_cancel_button)


## パネルをセットアップ
## @param characters: 対象キャラクター配列
## @param path_drawer: PathDrawerへの参照
func setup(characters: Array[Node], path_drawer: Node) -> void:
	_characters = characters
	_path_drawer = path_drawer
	_rebuild_character_buttons()

	# 最初のキャラクターをアクティブに
	if _characters.size() > 0:
		set_active_character(_characters[0])


## キャラクターボタンを再構築
func _rebuild_character_buttons() -> void:
	# 既存のボタンをクリア
	for btn in _character_buttons.values():
		btn.queue_free()
	_character_buttons.clear()

	# 単一キャラクターの場合はキャラクター選択UIを非表示
	_character_label.visible = _characters.size() > 1
	_character_container.visible = _characters.size() > 1

	# キャラクターごとにボタンを作成
	for character in _characters:
		var char_id = character.get_instance_id()
		var label = CharacterColorManager.get_character_label(character)
		var color = CharacterColorManager.get_character_color(character)

		var btn = Button.new()
		btn.text = label
		btn.custom_minimum_size = Vector2(40, 40)
		btn.add_theme_font_size_override("font_size", 18)
		btn.pressed.connect(_on_character_button_pressed.bind(character))

		# スタイルを適用
		_apply_button_style(btn, color, false)

		_character_container.add_child(btn)
		_character_buttons[char_id] = btn


## ボタンスタイルを適用
func _apply_button_style(btn: Button, color: Color, is_active: bool) -> void:
	var style_normal = StyleBoxFlat.new()
	var style_hover = StyleBoxFlat.new()
	var style_pressed = StyleBoxFlat.new()

	if is_active:
		# アクティブ：明るい色、太い枠線
		style_normal.bg_color = color
		style_normal.border_width_bottom = 3
		style_normal.border_width_top = 3
		style_normal.border_width_left = 3
		style_normal.border_width_right = 3
		style_normal.border_color = Color.WHITE
	else:
		# 非アクティブ：暗い色
		style_normal.bg_color = Color(color.r * 0.4, color.g * 0.4, color.b * 0.4, 0.8)
		style_normal.border_width_bottom = 1
		style_normal.border_width_top = 1
		style_normal.border_width_left = 1
		style_normal.border_width_right = 1
		style_normal.border_color = color

	style_normal.corner_radius_top_left = 4
	style_normal.corner_radius_top_right = 4
	style_normal.corner_radius_bottom_left = 4
	style_normal.corner_radius_bottom_right = 4

	# ホバースタイル
	style_hover.bg_color = Color(color.r * 0.8, color.g * 0.8, color.b * 0.8, 1.0)
	style_hover.corner_radius_top_left = 4
	style_hover.corner_radius_top_right = 4
	style_hover.corner_radius_bottom_left = 4
	style_hover.corner_radius_bottom_right = 4

	# プレススタイル
	style_pressed.bg_color = color
	style_pressed.corner_radius_top_left = 4
	style_pressed.corner_radius_top_right = 4
	style_pressed.corner_radius_bottom_left = 4
	style_pressed.corner_radius_bottom_right = 4

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	# テキスト色
	btn.add_theme_color_override("font_color", Color.WHITE if is_active else Color(0.8, 0.8, 0.8))


## アクティブキャラクターを設定
func set_active_character(character: Node) -> void:
	_active_character = character

	# PathDrawerのアクティブキャラクターを更新
	if _path_drawer and _path_drawer.has_method("set_active_edit_character"):
		_path_drawer.set_active_edit_character(character)

	# ボタンのハイライトを更新
	_update_button_highlights()

	# ラベルを更新
	_update_labels()

	character_selected.emit(character)


## ボタンのハイライト状態を更新
func _update_button_highlights() -> void:
	for character in _characters:
		var char_id = character.get_instance_id()
		if not _character_buttons.has(char_id):
			continue

		var btn = _character_buttons[char_id]
		var color = CharacterColorManager.get_character_color(character)
		var is_active = (character == _active_character)
		_apply_button_style(btn, color, is_active)


## ラベルを更新
func _update_labels() -> void:
	if not _active_character:
		return

	var char_label = CharacterColorManager.get_character_label(_active_character)

	# 視線ポイント数
	var vision_count = 0
	if _path_drawer and _path_drawer.has_method("get_vision_point_count_for_character"):
		vision_count = _path_drawer.get_vision_point_count_for_character(_active_character)
	_vision_label.text = "Vision Points (%s): %d" % [char_label, vision_count]

	# Run区間数
	var run_count = 0
	if _path_drawer and _path_drawer.has_method("get_run_segment_count_for_character"):
		run_count = _path_drawer.get_run_segment_count_for_character(_active_character)
	var incomplete = ""
	if _path_drawer and _path_drawer.has_method("has_incomplete_run_start"):
		if _path_drawer.has_incomplete_run_start():
			incomplete = " (setting...)"
	_run_label.text = "Run Segments (%s): %d%s" % [char_label, run_count, incomplete]


## 視線ポイントが追加された時に呼ぶ
func on_vision_point_added() -> void:
	_update_labels()


## Run区間が追加された時に呼ぶ
func on_run_segment_added() -> void:
	_update_labels()


## キャラクターボタン押下時
func _on_character_button_pressed(character: Node) -> void:
	set_active_character(character)


## Add Vision押下時
func _on_add_vision_pressed() -> void:
	if _active_character:
		vision_add_requested.emit(_active_character)


## Undo Vision押下時
func _on_undo_vision_pressed() -> void:
	if _active_character:
		vision_undo_requested.emit(_active_character)
		_update_labels()


## Add Run押下時
func _on_add_run_pressed() -> void:
	if _active_character:
		run_add_requested.emit(_active_character)


## Undo Run押下時
func _on_undo_run_pressed() -> void:
	if _active_character:
		run_undo_requested.emit(_active_character)
		_update_labels()


## Confirm押下時
func _on_confirm_pressed() -> void:
	confirm_requested.emit()


## Cancel押下時
func _on_cancel_pressed() -> void:
	cancel_requested.emit()


## アクティブキャラクターを取得
func get_active_character() -> Node:
	return _active_character


## パネルをクリア
func clear() -> void:
	_characters.clear()
	_active_character = null
	for btn in _character_buttons.values():
		btn.queue_free()
	_character_buttons.clear()
	_vision_label.text = "Vision Points: 0"
	_run_label.text = "Run Segments: 0"
