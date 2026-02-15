@tool
extends VBoxContainer

const PROPS_DIR = "res://scenes/props/"

var editor_plugin = null
var _prop_paths = []


func _ready():
	call_deferred("_scan_props")


func _scan_props():
	var prop_list = get_node_or_null("PropList")
	var status_label = get_node_or_null("StatusLabel")
	if not prop_list or not status_label:
		return

	_prop_paths.clear()
	prop_list.clear()

	var dir = DirAccess.open(PROPS_DIR)
	if not dir:
		status_label.text = "props/ not found"
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".glb") or file_name.ends_with(".tscn"):
			_prop_paths.append(PROPS_DIR + file_name)
			prop_list.add_item(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()

	status_label.text = str(_prop_paths.size()) + " props"


func _on_refresh_button_pressed():
	_scan_props()


func has_selected_prop():
	var prop_list = get_node_or_null("PropList")
	if not prop_list:
		return false
	return not prop_list.get_selected_items().is_empty()


func place_at_position(pos):
	var prop_list = get_node_or_null("PropList")
	var status_label = get_node_or_null("StatusLabel")
	if not prop_list or not status_label:
		return

	var selected = prop_list.get_selected_items()
	if selected.is_empty():
		return

	var edited_scene = EditorInterface.get_edited_scene_root()
	if not edited_scene:
		status_label.text = "No scene open"
		return

	var idx = selected[0]
	var prop_path = _prop_paths[idx]
	var prop_scene = load(prop_path)
	if not prop_scene:
		status_label.text = "Load failed: " + prop_path
		return

	var instance = prop_scene.instantiate()
	var base_name = prop_path.get_file().get_basename()
	instance.name = _unique_name(edited_scene, base_name)

	edited_scene.add_child(instance, true)
	instance.owner = edited_scene

	if instance is Node3D:
		instance.global_position = pos

	status_label.text = "Placed: " + instance.name + " at " + str(pos.snapped(Vector3(0.1, 0.1, 0.1)))

	# 配置後に選択を解除（連続配置を防止）
	prop_list.deselect_all()

	var sel = EditorInterface.get_selection()
	sel.clear()
	sel.add_node(instance)


func _on_place_button_pressed():
	var prop_list = get_node_or_null("PropList")
	var status_label = get_node_or_null("StatusLabel")
	if not prop_list or not status_label:
		return

	var selected = prop_list.get_selected_items()
	if selected.is_empty():
		status_label.text = "Select a prop"
		return

	var sel = EditorInterface.get_selection()
	var nodes = sel.get_selected_nodes()
	if nodes.is_empty():
		status_label.text = "Select a parent node"
		return

	var parent_node = nodes[0]
	var idx = selected[0]
	var prop_path = _prop_paths[idx]
	var prop_scene = load(prop_path)
	if not prop_scene:
		status_label.text = "Load failed: " + prop_path
		return

	var instance = prop_scene.instantiate()
	var scene_owner = parent_node.owner if parent_node.owner else parent_node
	instance.name = _unique_name(scene_owner, prop_path.get_file().get_basename())
	parent_node.add_child(instance, true)
	instance.owner = scene_owner

	status_label.text = "Placed: " + instance.name

	sel.clear()
	sel.add_node(instance)


func _on_prop_list_item_activated(_index):
	_on_place_button_pressed()


func _unique_name(scene_root, base_name):
	if not scene_root.has_node(NodePath(base_name)):
		return base_name
	var i = 2
	while scene_root.has_node(NodePath(base_name + str(i))):
		i += 1
	return base_name + str(i)
