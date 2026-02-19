@tool
extends VBoxContainer

const PROPS_DIR := "res://scenes/props/"
const DECALS_DIR := "res://assets/decals/"

enum Mode { OBJECT, DECAL }

var editor_plugin: EditorPlugin = null
var _prop_paths: Array[String] = []
var _decal_paths: Array[String] = []

# Cached StyleBox for paint button active state
var _paint_on_style: StyleBoxFlat
var _indicator_style_idle: StyleBoxFlat
var _indicator_style_object: StyleBoxFlat
var _indicator_style_paint: StyleBoxFlat


func _ready() -> void:
	_create_styles()
	call_deferred("_scan_props")
	call_deferred("_scan_decals")
	call_deferred("_update_mode_indicator")


func _create_styles() -> void:
	# Paint button ON style (green)
	_paint_on_style = StyleBoxFlat.new()
	_paint_on_style.bg_color = Color(0.18, 0.52, 0.18)
	_paint_on_style.corner_radius_top_left = 4
	_paint_on_style.corner_radius_top_right = 4
	_paint_on_style.corner_radius_bottom_left = 4
	_paint_on_style.corner_radius_bottom_right = 4
	_paint_on_style.content_margin_left = 10
	_paint_on_style.content_margin_right = 10
	_paint_on_style.content_margin_top = 4
	_paint_on_style.content_margin_bottom = 4

	# Mode indicator styles
	_indicator_style_idle = StyleBoxFlat.new()
	_indicator_style_idle.bg_color = Color(0.2, 0.2, 0.2, 0.6)
	_indicator_style_idle.corner_radius_top_left = 3
	_indicator_style_idle.corner_radius_top_right = 3
	_indicator_style_idle.corner_radius_bottom_left = 3
	_indicator_style_idle.corner_radius_bottom_right = 3
	_indicator_style_idle.content_margin_left = 8
	_indicator_style_idle.content_margin_right = 8

	_indicator_style_object = StyleBoxFlat.new()
	_indicator_style_object.bg_color = Color(0.15, 0.30, 0.55, 0.7)
	_indicator_style_object.corner_radius_top_left = 3
	_indicator_style_object.corner_radius_top_right = 3
	_indicator_style_object.corner_radius_bottom_left = 3
	_indicator_style_object.corner_radius_bottom_right = 3
	_indicator_style_object.content_margin_left = 8
	_indicator_style_object.content_margin_right = 8

	_indicator_style_paint = StyleBoxFlat.new()
	_indicator_style_paint.bg_color = Color(0.18, 0.52, 0.18, 0.8)
	_indicator_style_paint.corner_radius_top_left = 3
	_indicator_style_paint.corner_radius_top_right = 3
	_indicator_style_paint.corner_radius_bottom_left = 3
	_indicator_style_paint.corner_radius_bottom_right = 3
	_indicator_style_paint.content_margin_left = 8
	_indicator_style_paint.content_margin_right = 8


# ── Mode indicator ────────────────────────────────────

func _update_mode_indicator() -> void:
	var panel: PanelContainer = $ModeIndicator
	var label: Label = $ModeIndicator/ModeLabel
	var tab := get_current_mode()

	if tab == Mode.OBJECT:
		label.text = "Select prop > click in 3D viewport"
		panel.add_theme_stylebox_override("panel", _indicator_style_object)
		label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	elif tab == Mode.DECAL:
		var paint_btn: Button = $DecalContainer/PaintControls/PaintButton
		if paint_btn.button_pressed:
			label.text = "PAINTING  |  L=paint  R=erase"
			panel.add_theme_stylebox_override("panel", _indicator_style_paint)
			label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
		else:
			label.text = "Select decal > press Paint"
			panel.add_theme_stylebox_override("panel", _indicator_style_idle)
			label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))


# ── Tab switching ─────────────────────────────────────

func _on_tab_changed(tab: int) -> void:
	$ObjectContainer.visible = (tab == Mode.OBJECT)
	$DecalContainer.visible = (tab == Mode.DECAL)
	# Turn off paint when switching to object tab
	if tab == Mode.OBJECT:
		var paint_btn: Button = $DecalContainer/PaintControls/PaintButton
		if paint_btn.button_pressed:
			paint_btn.button_pressed = false
	_update_mode_indicator()


func get_current_mode() -> int:
	return $TabBar.current_tab


# ── Object mode ──────────────────────────────────────

func _scan_props() -> void:
	var prop_list: ItemList = $ObjectContainer/PropList
	var status: Label = $ObjectContainer/PropStatusLabel
	_prop_paths.clear()
	prop_list.clear()

	var dir := DirAccess.open(PROPS_DIR)
	if not dir:
		status.text = "props/ not found"
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".glb") or file_name.ends_with(".tscn"):
			_prop_paths.append(PROPS_DIR + file_name)
			prop_list.add_item(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()

	status.text = str(_prop_paths.size()) + " props"


func _on_refresh_props() -> void:
	_scan_props()


func has_selected_prop() -> bool:
	if get_current_mode() != Mode.OBJECT:
		return false
	var prop_list: ItemList = $ObjectContainer/PropList
	return not prop_list.get_selected_items().is_empty()


func get_selected_prop_path() -> String:
	var prop_list: ItemList = $ObjectContainer/PropList
	var selected := prop_list.get_selected_items()
	if selected.is_empty():
		return ""
	return _prop_paths[selected[0]]


func set_prop_status(text: String) -> void:
	$ObjectContainer/PropStatusLabel.text = text


func deselect_prop() -> void:
	$ObjectContainer/PropList.deselect_all()


func _on_place_button_pressed() -> void:
	var prop_list: ItemList = $ObjectContainer/PropList
	var status: Label = $ObjectContainer/PropStatusLabel

	var selected := prop_list.get_selected_items()
	if selected.is_empty():
		status.text = "Select a prop"
		return

	var sel := EditorInterface.get_selection()
	var nodes := sel.get_selected_nodes()
	if nodes.is_empty():
		status.text = "Select a parent node"
		return

	var parent_node := nodes[0]
	var idx := selected[0]
	var prop_path := _prop_paths[idx]
	var prop_scene: PackedScene = load(prop_path) as PackedScene
	if not prop_scene:
		status.text = "Load failed: " + prop_path
		return

	var instance: Node = prop_scene.instantiate()
	var scene_owner: Node = parent_node.owner if parent_node.owner else parent_node
	instance.name = _unique_name(scene_owner, prop_path.get_file().get_basename())
	parent_node.add_child(instance, true)
	instance.owner = scene_owner

	status.text = "Placed: " + instance.name
	sel.clear()
	sel.add_node(instance)


func _on_prop_list_item_activated(_index: int) -> void:
	_on_place_button_pressed()


# ── Decal mode ───────────────────────────────────────

func _scan_decals() -> void:
	var decal_list: ItemList = $DecalContainer/DecalList
	var status: Label = $DecalContainer/DecalStatusLabel
	_decal_paths.clear()
	decal_list.clear()

	var dir := DirAccess.open(DECALS_DIR)
	if not dir:
		status.text = "decals/ not found"
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".png") or file_name.ends_with(".jpg"):
			_decal_paths.append(DECALS_DIR + file_name)
			decal_list.add_item(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()

	status.text = str(_decal_paths.size()) + " decals"


func _on_refresh_decals() -> void:
	_scan_decals()


func _on_paint_toggled(pressed: bool) -> void:
	var btn: Button = $DecalContainer/PaintControls/PaintButton
	if pressed:
		btn.text = "PAINT ON"
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_stylebox_override("normal", _paint_on_style)
		btn.add_theme_stylebox_override("hover", _paint_on_style)
		btn.add_theme_stylebox_override("pressed", _paint_on_style)
	else:
		btn.text = "Paint"
		btn.remove_theme_color_override("font_color")
		btn.remove_theme_stylebox_override("normal")
		btn.remove_theme_stylebox_override("hover")
		btn.remove_theme_stylebox_override("pressed")
	_update_mode_indicator()


func is_decal_paint_active() -> bool:
	if get_current_mode() != Mode.DECAL:
		return false
	var paint_btn: Button = $DecalContainer/PaintControls/PaintButton
	return paint_btn.button_pressed


func get_selected_decal_texture() -> Texture2D:
	var decal_list: ItemList = $DecalContainer/DecalList
	var selected := decal_list.get_selected_items()
	if selected.is_empty():
		return null
	var path := _decal_paths[selected[0]]
	return load(path) as Texture2D


func get_brush_size() -> float:
	return $DecalContainer/PaintControls/SizeSlider.value


func set_decal_status(text: String) -> void:
	$DecalContainer/DecalStatusLabel.text = text


func _on_size_changed(value: float) -> void:
	$DecalContainer/PaintControls/SizeValue.text = str(value)


# ── Random rotation ─────────────────────────────────

func _on_random_rotation_toggled(pressed: bool) -> void:
	if editor_plugin:
		editor_plugin.set_random_rotation_enabled(pressed)


func is_random_rotation_enabled() -> bool:
	return $RandomRotationCheck.button_pressed


# ── Utilities ────────────────────────────────────────

func _unique_name(scene_root: Node, base_name: String) -> String:
	if not scene_root.has_node(NodePath(base_name)):
		return base_name
	var i := 2
	while scene_root.has_node(NodePath(base_name + str(i))):
		i += 1
	return base_name + str(i)
