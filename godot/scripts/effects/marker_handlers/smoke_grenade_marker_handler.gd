class_name SmokeGrenadeMarkerHandler
extends MarkerHandlerBase

## スモークグレネードマーカーハンドラ
## パス上からのスモーク投擲位置・目標・バウンスを管理するマーカーの入力・管理を担当


const SmokeGrenadeMarkerScript = preload("res://scripts/effects/smoke_grenade_marker.gd")


## スモークグレネードマーカーデータ配列
var _smoke_grenade_markers: Array[Dictionary] = []

## スモークグレネードマーカーメッシュ配列
var _smoke_grenade_meshes: Array[MeshInstance3D] = []

## 投擲位置（アンカー）
var _pending_anchor: Vector3 = Vector3.ZERO

## 投擲位置の比率
var _pending_ratio: float = 0.0

## アンカー設定済みフラグ
var _has_anchor: bool = false

## バウンスポイント
var _bounce_point: Vector3 = Vector3.ZERO

## バウンス法線
var _bounce_normal: Vector3 = Vector3.ZERO

## バウンス設定済みフラグ
var _has_bounce: bool = false

## 軌道プレビューメッシュ
var _trajectory_mesh: MeshInstance3D = null


## 入力処理
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			return _process_click(mouse_event.position)

	elif event is InputEventMouseMotion:
		_update_trajectory_preview(event.position)

	return false


## クリック処理
func _process_click(screen_pos: Vector2) -> bool:
	if not _has_anchor:
		var ground_pos = _get_ground_position(screen_pos)
		if ground_pos == null:
			return false

		var result = _find_closest_point_on_path(ground_pos)
		if result.distance > _get_path_click_threshold():
			return false

		_pending_anchor = result.point
		_pending_ratio = result.ratio
		_has_anchor = true
		_setup_trajectory_mesh()
		return true

	elif not _has_bounce:
		var target_result = _raycast_wall_or_floor(screen_pos)
		if target_result.is_empty():
			return false

		var hit_pos: Vector3 = target_result.position
		var hit_normal: Vector3 = target_result.normal

		var is_wall = abs(hit_normal.y) < 0.5

		if is_wall:
			hit_pos.y = 1.0
			_bounce_point = hit_pos
			_bounce_normal = hit_normal
			_has_bounce = true
		else:
			_finish_smoke_grenade_marker(hit_pos, Vector3.ZERO, Vector3.ZERO)
		return true

	else:
		var ground_pos = _get_ground_position(screen_pos)
		if ground_pos == null:
			return false

		_finish_smoke_grenade_marker(ground_pos, _bounce_point, _bounce_normal)
		return true


## スモークグレネードマーカー完成
func _finish_smoke_grenade_marker(target_pos: Vector3, bounce_point: Vector3, bounce_normal: Vector3) -> void:
	var has_bounce = bounce_point.length_squared() > 0.001
	var new_marker = {
		"path_ratio": _pending_ratio,
		"anchor": _pending_anchor,
		"target_pos": target_pos,
		"bounce_point": bounce_point if has_bounce else Vector3.ZERO,
		"bounce_normal": bounce_normal if has_bounce else Vector3.ZERO
	}

	_smoke_grenade_markers.append(new_marker)

	var marker = _create_smoke_grenade_marker_node(_pending_anchor, target_pos, bounce_point)
	_smoke_grenade_meshes.append(marker)

	marker_added.emit(new_marker)
	_notify_timeline_changed()

	_reset_pending_state()


## スモークグレネードマーカーノード作成
func _create_smoke_grenade_marker_node(anchor: Vector3, target: Vector3, bounce: Vector3) -> MeshInstance3D:
	var marker = MeshInstance3D.new()
	marker.set_script(SmokeGrenadeMarkerScript)
	_add_child_to_drawer(marker)
	marker.set_position_and_target(anchor, target, bounce)
	return marker


## 軌道プレビューメッシュセットアップ
func _setup_trajectory_mesh() -> void:
	if _trajectory_mesh:
		return

	_trajectory_mesh = MeshInstance3D.new()
	_trajectory_mesh.name = "SmokeGrenadeTrajectoryPreview"
	_add_child_to_drawer(_trajectory_mesh)

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.7, 0.7, 0.7, 0.6)  # 灰色
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trajectory_mesh.material_override = mat


## 軌道プレビュー更新
func _update_trajectory_preview(screen_pos: Vector2) -> void:
	if not _has_anchor or not _trajectory_mesh:
		return

	var target_pos = _get_ground_position(screen_pos)
	if target_pos == null:
		var wall_result = _raycast_wall_or_floor(screen_pos)
		if wall_result.is_empty():
			return
		target_pos = wall_result.position

	var im = ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	var start_pos = _pending_anchor + Vector3(0, 0.05, 0)

	if _has_bounce:
		im.surface_add_vertex(start_pos)
		im.surface_add_vertex(_bounce_point)
		im.surface_add_vertex(_bounce_point)
		im.surface_add_vertex(target_pos)
	else:
		im.surface_add_vertex(start_pos)
		im.surface_add_vertex(target_pos)

	im.surface_end()
	_trajectory_mesh.mesh = im


## 軌道プレビュー削除
func _cleanup_trajectory_mesh() -> void:
	if _trajectory_mesh:
		_trajectory_mesh.queue_free()
		_trajectory_mesh = null


## 保留状態リセット
func _reset_pending_state() -> void:
	_has_anchor = false
	_pending_anchor = Vector3.ZERO
	_pending_ratio = 0.0
	_has_bounce = false
	_bounce_point = Vector3.ZERO
	_bounce_normal = Vector3.ZERO
	_cleanup_trajectory_mesh()


func has_markers() -> bool:
	return _smoke_grenade_markers.size() > 0


func get_marker_count() -> int:
	return _smoke_grenade_markers.size()


func get_markers() -> Array[Dictionary]:
	return _smoke_grenade_markers


func take_markers() -> Array[MeshInstance3D]:
	var markers = _smoke_grenade_meshes.duplicate()
	_smoke_grenade_meshes.clear()
	return markers


func undo_last() -> Dictionary:
	if _smoke_grenade_markers.size() == 0:
		return {}

	var removed_data = _smoke_grenade_markers.pop_back()
	if _smoke_grenade_meshes.size() > 0:
		var mesh = _smoke_grenade_meshes.pop_back()
		if is_instance_valid(mesh):
			mesh.queue_free()

	return removed_data


func clear_all() -> void:
	_smoke_grenade_markers.clear()
	for mesh in _smoke_grenade_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_smoke_grenade_meshes.clear()
	_reset_pending_state()


func reset_state() -> void:
	_reset_pending_state()
