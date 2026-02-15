@tool
extends EditorPlugin

var dock: Control = null


func _enter_tree() -> void:
	dock = load("res://addons/prop_placer/prop_placer_dock.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_LEFT_BL, dock)


func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null


func _handles(object) -> bool:
	# PropListで選択中はビューポートクリックを受け取る
	if dock and dock.has_selected_prop():
		return true
	return false


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not dock:
		return AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if dock.has_selected_prop():
				var from = camera.project_ray_origin(event.position)
				var dir = camera.project_ray_normal(event.position)
				var hit_pos = _raycast(from, dir, camera)
				if hit_pos != null:
					dock.place_at_position(hit_pos)
					return AFTER_GUI_INPUT_STOP

	return AFTER_GUI_INPUT_PASS


func _raycast(from: Vector3, dir: Vector3, camera: Camera3D):
	var space = camera.get_world_3d().direct_space_state
	var to = from + dir * 1000.0
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space.intersect_ray(query)
	if result.size() > 0:
		return result.position

	# 物理ヒットなし → Y=0平面との交差を計算
	if abs(dir.y) > 0.001:
		var t = -from.y / dir.y
		if t > 0:
			return from + dir * t

	return null
