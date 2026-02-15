@tool
extends EditorPlugin

var dock: Control = null

# ── Decal paint state ────────────────────────────────
var is_painting := false
var is_erasing := false
var last_paint_pos := Vector3.INF
var stroke_painted: Array[MeshInstance3D] = []
var stroke_erased: Array[MeshInstance3D] = []

# ── Shared decal resources ───────────────────────────
var decal_shader: Shader
var decal_mesh: PlaneMesh
var _material_cache: Dictionary = {}  # texture_path -> ShaderMaterial

const MIN_SPACING_RATIO := 0.3
const DECAL_PARENT_NAME := "DecalPatches"


func _enter_tree() -> void:
	dock = load("res://addons/map_decorator/map_decorator_dock.tscn").instantiate()
	dock.editor_plugin = self
	add_control_to_dock(DOCK_SLOT_LEFT_BL, dock)
	_setup_decal_resources()


func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null
	_material_cache.clear()


func _setup_decal_resources() -> void:
	decal_shader = load("res://shaders/grass_overlay.gdshader") as Shader
	decal_mesh = PlaneMesh.new()
	decal_mesh.size = Vector2(1, 1)
	decal_mesh.orientation = PlaneMesh.FACE_Y


# ── Handle check ─────────────────────────────────────

func _handles(object: Object) -> bool:
	# Always accept Node3D so _forward_3d_gui_input is called.
	# Mode checks happen inside _forward_3d_gui_input.
	return object is Node3D


# ── 3D Input ─────────────────────────────────────────

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not dock:
		return AFTER_GUI_INPUT_PASS

	if dock.has_selected_prop():
		return _handle_object_input(camera, event)

	if dock.is_decal_paint_active():
		return _handle_decal_input(camera, event)

	return AFTER_GUI_INPUT_PASS


# ── Object mode input ────────────────────────────────

func _handle_object_input(camera: Camera3D, event: InputEvent) -> int:
	if not (event is InputEventMouseButton):
		return AFTER_GUI_INPUT_PASS

	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return AFTER_GUI_INPUT_PASS

	var hit_pos = _raycast(camera, mb.position)
	if hit_pos == null:
		return AFTER_GUI_INPUT_PASS

	_place_prop_at(hit_pos)
	return AFTER_GUI_INPUT_STOP


func _place_prop_at(pos: Vector3) -> void:
	var prop_path: String = dock.get_selected_prop_path()
	if prop_path.is_empty():
		return

	var edited_scene := get_editor_interface().get_edited_scene_root()
	if not edited_scene:
		dock.set_prop_status("No scene open")
		return

	var prop_scene: PackedScene = load(prop_path) as PackedScene
	if not prop_scene:
		dock.set_prop_status("Load failed: " + prop_path)
		return

	var instance: Node = prop_scene.instantiate()
	var base_name: String = prop_path.get_file().get_basename()
	instance.name = dock._unique_name(edited_scene, base_name)

	edited_scene.add_child(instance, true)
	instance.owner = edited_scene

	if instance is Node3D:
		(instance as Node3D).global_position = pos

	# Undo/Redo
	var ur := get_undo_redo()
	ur.create_action("Place Prop: " + instance.name)
	ur.add_do_method(edited_scene, "add_child", instance)
	ur.add_do_method(instance, "set_owner", edited_scene)
	ur.add_undo_method(edited_scene, "remove_child", instance)
	ur.add_do_reference(instance)
	ur.commit_action(false)

	dock.set_prop_status("Placed: " + instance.name + " at " + str(pos.snapped(Vector3(0.1, 0.1, 0.1))))
	dock.deselect_prop()

	var sel := EditorInterface.get_selection()
	sel.clear()
	sel.add_node(instance)


# ── Decal mode input ─────────────────────────────────

func _handle_decal_input(camera: Camera3D, event: InputEvent) -> int:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				is_painting = true
				is_erasing = false
				stroke_painted.clear()
				last_paint_pos = Vector3.INF
				_paint_decal_at(camera, mb.position)
			else:
				is_painting = false
				_commit_paint_stroke()
			return AFTER_GUI_INPUT_STOP

		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				is_erasing = true
				is_painting = false
				stroke_erased.clear()
				_erase_decal_at(camera, mb.position)
			else:
				is_erasing = false
				_commit_erase_stroke()
			return AFTER_GUI_INPUT_STOP

	elif event is InputEventMouseMotion:
		if is_painting:
			_paint_decal_at(camera, (event as InputEventMouseMotion).position)
			return AFTER_GUI_INPUT_STOP
		elif is_erasing:
			_erase_decal_at(camera, (event as InputEventMouseMotion).position)
			return AFTER_GUI_INPUT_STOP

	return AFTER_GUI_INPUT_PASS


# ── Raycast (physics ray + Y=0 fallback) ────────────

func _raycast(camera: Camera3D, screen_pos: Vector2):
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)

	# Physics raycast
	var space := camera.get_world_3d().direct_space_state
	var to := origin + dir * 1000.0
	var query := PhysicsRayQueryParameters3D.create(origin, to)
	var result := space.intersect_ray(query)
	if result.size() > 0:
		return result.position

	# Fallback: Y=0 plane intersection
	if absf(dir.y) > 0.001:
		var t := -origin.y / dir.y
		if t > 0.0:
			return origin + dir * t

	return null


# ── Decal parent node ────────────────────────────────

func _get_decal_parent() -> Node3D:
	var root := get_editor_interface().get_edited_scene_root()
	if not root:
		return null
	var parent := root.get_node_or_null(DECAL_PARENT_NAME) as Node3D
	if not parent:
		parent = Node3D.new()
		parent.name = DECAL_PARENT_NAME
		root.add_child(parent)
		parent.owner = root
	return parent


# ── Decal material (cached per texture) ─────────────

func _get_decal_material(texture: Texture2D) -> ShaderMaterial:
	if not decal_shader or not texture:
		return null

	var key := texture.resource_path
	if _material_cache.has(key):
		return _material_cache[key]

	var mat := ShaderMaterial.new()
	mat.shader = decal_shader
	mat.set_shader_parameter("grass_texture", texture)
	mat.render_priority = 1
	_material_cache[key] = mat
	return mat


# ── Decal paint ──────────────────────────────────────

func _paint_decal_at(camera: Camera3D, screen_pos: Vector2) -> void:
	var hit = _raycast(camera, screen_pos)
	if hit == null:
		return
	var pos: Vector3 = hit

	var brush_size: float = dock.get_brush_size()
	var min_dist: float = brush_size * MIN_SPACING_RATIO
	if last_paint_pos != Vector3.INF and pos.distance_to(last_paint_pos) < min_dist:
		return

	var texture: Texture2D = dock.get_selected_decal_texture()
	var mat := _get_decal_material(texture)
	if not mat:
		dock.set_decal_status("Select a decal texture")
		return

	var parent := _get_decal_parent()
	if not parent:
		return

	var s: float = brush_size * randf_range(0.85, 1.15)
	var angle := randf() * TAU
	var ca := cos(angle)
	var sa := sin(angle)

	var mi := MeshInstance3D.new()
	mi.mesh = decal_mesh
	mi.material_override = mat
	mi.transform = Transform3D(
		Vector3(s * ca, 0.0, s * sa),
		Vector3(0.0, 1.0, 0.0),
		Vector3(-s * sa, 0.0, s * ca),
		Vector3(pos.x, 0.01, pos.z)
	)

	parent.add_child(mi)
	mi.owner = get_editor_interface().get_edited_scene_root()
	mi.name = "Decal_%d" % parent.get_child_count()

	stroke_painted.append(mi)
	last_paint_pos = pos


func _commit_paint_stroke() -> void:
	if stroke_painted.is_empty():
		return

	var ur := get_undo_redo()
	var root := get_editor_interface().get_edited_scene_root()
	var parent := _get_decal_parent()
	if not parent or not root:
		stroke_painted.clear()
		return

	ur.create_action("Paint Decals (%d patches)" % stroke_painted.size())
	for node in stroke_painted:
		ur.add_do_method(parent, "add_child", node)
		ur.add_do_method(node, "set_owner", root)
		ur.add_undo_method(parent, "remove_child", node)
		ur.add_do_reference(node)
	ur.commit_action(false)

	stroke_painted.clear()


# ── Decal erase ──────────────────────────────────────

func _erase_decal_at(camera: Camera3D, screen_pos: Vector2) -> void:
	var hit = _raycast(camera, screen_pos)
	if hit == null:
		return
	var pos: Vector3 = hit

	var parent := _get_decal_parent()
	if not parent:
		return

	var erase_radius: float = dock.get_brush_size() * 0.5

	for child in parent.get_children():
		var mi := child as MeshInstance3D
		if mi and not stroke_erased.has(mi):
			var cp: Vector3 = mi.transform.origin
			if Vector2(cp.x, cp.z).distance_to(Vector2(pos.x, pos.z)) < erase_radius:
				stroke_erased.append(mi)
				parent.remove_child(mi)


func _commit_erase_stroke() -> void:
	if stroke_erased.is_empty():
		return

	var ur := get_undo_redo()
	var root := get_editor_interface().get_edited_scene_root()
	var parent := _get_decal_parent()
	if not parent or not root:
		stroke_erased.clear()
		return

	ur.create_action("Erase Decals (%d patches)" % stroke_erased.size())
	for node in stroke_erased:
		ur.add_do_method(parent, "remove_child", node)
		ur.add_undo_method(parent, "add_child", node)
		ur.add_undo_method(node, "set_owner", root)
		ur.add_undo_reference(node)
	ur.commit_action(false)

	stroke_erased.clear()
