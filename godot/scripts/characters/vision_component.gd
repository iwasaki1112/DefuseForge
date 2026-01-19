class_name VisionComponent
extends Node3D

## Vision Component for Fog of War System (Shadow Cast Method)
## Uses wall corner points for stable visibility calculation

signal vision_updated(visible_points: PackedVector3Array)

# ============================================
# Quality Presets (FogOfWarSystem.Qualityと連動)
# ============================================
enum Quality { LOW, MEDIUM, HIGH }
const QUALITY_PRESETS := {
	Quality.LOW: { "ray_count": 45, "update_interval": 0.05, "corner_rays": 1 },     # モバイル
	Quality.MEDIUM: { "ray_count": 90, "update_interval": 0.033, "corner_rays": 3 }, # バランス
	Quality.HIGH: { "ray_count": 180, "update_interval": 0.033, "corner_rays": 5 },  # PC
}

# ============================================
# Export Settings
# ============================================
@export_group("Vision Settings")
@export var fov_degrees: float = 90.0  ## Field of view in degrees
@export var view_distance: float = 15.0  ## Vision distance in meters
@export var edge_ray_count: int = 90  ## Number of rays for FOV edges
@export var update_interval: float = 0.033  ## Update interval in seconds
@export var eye_height: float = 1.5  ## Eye height from ground
@export var corner_extra_rays: int = 3  ## Extra rays per corner

@export_group("Collision Settings")
@export_flags_3d_physics var wall_collision_mask: int = 2  ## Collision mask for walls

# ============================================
# State
# ============================================
var _enabled: bool = true
var _visible_polygon: PackedVector3Array = PackedVector3Array()
var _time_since_update: float = 0.0

# スナップ用（ピクピク防止）
var _last_snapped_position: Vector3 = Vector3.ZERO
var _last_snapped_angle: float = 0.0
var _has_valid_vision: bool = false  # 初回計算フラグ

# テンポラルスムージング用（歩行揺れ防止）
var _smoothed_eye_position: Vector3 = Vector3.ZERO
var _smoothed_angle: float = 0.0
var _smoothed_initialized: bool = false

const ANGLE_SNAP_DEGREES: float = 0.5  # 角度を0.5度単位でスナップ（より滑らか）
const EYE_POSITION_SMOOTHING: float = 0.3  # 視点位置の平滑化係数（小さいほど滑らか）
const ANGLE_SMOOTHING: float = 0.3  # 角度の平滑化係数（小さいほど滑らか）

# 壁コーナーキャッシュ（パフォーマンス最適化）
# 壁は静的なので初回構築後は再構築しない（invalidate_wall_cache()で手動更新可能）
static var _wall_corners_cache: Array[Vector3] = []
static var _wall_corners_dirty: bool = true

# 静止時最適化
var _stationary_frames: int = 0
const STATIONARY_UPDATE_INTERVAL: float = 0.1  # 静止時は100ms間隔
const STATIONARY_THRESHOLD: int = 3  # この回数連続で変化なしなら静止とみなす

# ============================================
# References
# ============================================
var _character: Node3D = null
var _character_rid: RID  # RIDキャッシュ（毎フレーム取得を回避）

# ============================================
# Lifecycle
# ============================================

func _ready() -> void:
	_character = get_parent()
	# RIDをキャッシュ（毎レイキャストで取得を回避）
	if _character is CollisionObject3D:
		_character_rid = _character.get_rid()


func _physics_process(delta: float) -> void:
	if not _enabled:
		return

	# 静止時は更新間隔を長くする
	var current_interval := update_interval if _stationary_frames < STATIONARY_THRESHOLD else STATIONARY_UPDATE_INTERVAL

	_time_since_update += delta
	if _time_since_update >= current_interval:
		_time_since_update = 0.0
		_calculate_shadow_cast_vision()


# ============================================
# Public API
# ============================================

## Get the visible polygon (used by FogOfWarSystem)
func get_visible_polygon() -> PackedVector3Array:
	return _visible_polygon


## Force immediate vision update
func force_update() -> void:
	_calculate_shadow_cast_vision()


## Set quality preset (call before _ready or use apply_quality)
func set_quality(q: Quality) -> void:
	var preset: Dictionary = QUALITY_PRESETS[q]
	edge_ray_count = preset["ray_count"]
	update_interval = preset["update_interval"]
	corner_extra_rays = preset["corner_rays"]


## Set field of view
func set_fov(degrees: float) -> void:
	fov_degrees = clamp(degrees, 1.0, 360.0)


## Set view distance
func set_view_distance(distance: float) -> void:
	view_distance = max(1.0, distance)


## 壁コーナーキャッシュを無効化（壁が動的に変更された場合に呼び出す）
static func invalidate_wall_cache() -> void:
	_wall_corners_dirty = true


## Disable vision (for death, etc.)
func disable() -> void:
	_enabled = false
	_visible_polygon = PackedVector3Array()
	_has_valid_vision = false
	_smoothed_initialized = false
	vision_updated.emit(_visible_polygon)


## Enable vision
func enable() -> void:
	_enabled = true
	_calculate_shadow_cast_vision()


## Check if vision is enabled
func is_enabled() -> bool:
	return _enabled


## Check if a world position is within FOV (lightweight check with single raycast)
## Used for enemy visibility detection without full polygon calculation
func is_position_in_view(world_pos: Vector3) -> bool:
	if not _character:
		return false

	var origin := _get_eye_position()
	var to_target := world_pos - origin
	var distance := to_target.length()

	# Distance check
	if distance > view_distance:
		return false

	# FOV check (XZ plane)
	var look_dir := _get_look_direction()
	var to_target_xz := Vector3(to_target.x, 0, to_target.z).normalized()
	var look_dir_xz := Vector3(look_dir.x, 0, look_dir.z).normalized()

	if to_target_xz.length_squared() < 0.001 or look_dir_xz.length_squared() < 0.001:
		return true  # Target is directly above/below or look direction is vertical

	var angle := rad_to_deg(look_dir_xz.angle_to(to_target_xz))
	if angle > fov_degrees / 2.0:
		return false

	# Wall occlusion check (single raycast)
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return false

	var query := PhysicsRayQueryParameters3D.create(origin, world_pos, wall_collision_mask)
	if _character_rid.is_valid():
		query.exclude = [_character_rid]

	var result := space_state.intersect_ray(query)

	return result.is_empty()


# ============================================
# Shadow Cast Vision Calculation
# ============================================

func _calculate_shadow_cast_vision() -> void:
	if not _character:
		return

	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return

	# スムージング済みの位置と角度を取得
	var origin := _get_eye_position()
	var char_rotation := _get_look_angle()

	# 角度のみスナップ（位置はスムージングで対応）
	var snapped_rotation := _snap_angle(char_rotation)

	# 角度が変わっていなければスキップ（位置は常に更新）
	if _has_valid_vision:
		var angle_changed: bool = absf(snapped_rotation - _last_snapped_angle) > 0.001
		var pos_changed: bool = origin.distance_to(_last_snapped_position) >= 0.05
		if not angle_changed and not pos_changed:
			_stationary_frames += 1  # 静止カウント増加
			return
		else:
			_stationary_frames = 0  # 動いたのでリセット

	_last_snapped_position = origin
	_last_snapped_angle = snapped_rotation
	char_rotation = snapped_rotation

	var half_fov := deg_to_rad(fov_degrees / 2.0)

	# FOV boundary angles
	var fov_min_angle := char_rotation - half_fov
	var fov_max_angle := char_rotation + half_fov

	# Collect wall corners
	var wall_corners := _collect_wall_corners(origin)

	# Build list of ray angles
	var ray_angles: Array[float] = []

	# 1. Evenly distributed rays across FOV
	for i in range(edge_ray_count + 1):
		var t := float(i) / float(edge_ray_count)
		var angle := fov_min_angle + t * (fov_max_angle - fov_min_angle)
		ray_angles.append(angle)

	# 2. Rays toward wall corners (with multiple offsets for precise shadow edges)
	const CORNER_OFFSET_DEGREES: float = 0.8  # コーナー周辺のオフセット角度
	var corner_offset_rad := deg_to_rad(CORNER_OFFSET_DEGREES)

	for corner in wall_corners:
		var to_corner := Vector2(corner.x - origin.x, corner.z - origin.z)
		var corner_angle := atan2(to_corner.x, -to_corner.y)  # -Z is forward

		# Only corners within FOV
		var relative_angle := _wrap_angle(corner_angle - char_rotation)
		if abs(relative_angle) <= half_fov + 0.02:
			# コーナーの両側に複数のレイを追加（影のエッジを精密に）
			if corner_extra_rays > 0:
				for i in range(-corner_extra_rays, corner_extra_rays + 1):
					var offset := corner_offset_rad * float(i) / float(corner_extra_rays)
					ray_angles.append(corner_angle + offset)
			else:
				ray_angles.append(corner_angle)

	# Sort angles
	ray_angles.sort()

	# Remove duplicates
	var unique_angles: Array[float] = []
	for angle in ray_angles:
		if unique_angles.is_empty() or abs(angle - unique_angles[-1]) > 0.0001:
			unique_angles.append(angle)

	# Cast rays at each angle
	_visible_polygon.clear()

	# First point is the origin
	_visible_polygon.append(origin)

	for angle in unique_angles:
		# Check if within FOV range
		var relative := _wrap_angle(angle - char_rotation)
		if abs(relative) > half_fov:
			continue

		var direction := Vector3(sin(angle), 0, -cos(angle))
		var end_point := origin + direction * view_distance

		var query := PhysicsRayQueryParameters3D.create(origin, end_point, wall_collision_mask)
		if _character_rid.is_valid():
			query.exclude = [_character_rid]

		var result := space_state.intersect_ray(query)

		if result:
			_visible_polygon.append(result.position)
		else:
			_visible_polygon.append(end_point)

	# スナップ済み位置/角度が変化した場合のみここに到達するのでシグナル発火
	_has_valid_vision = true
	vision_updated.emit(_visible_polygon)


## Collect wall corner points from scene (with caching)
func _collect_wall_corners(origin: Vector3) -> Array[Vector3]:
	# キャッシュが古い場合は再構築
	if _wall_corners_dirty:
		_rebuild_wall_corners_cache()
		_wall_corners_dirty = false

	# キャッシュから視界範囲内のコーナーだけを返す
	var corners: Array[Vector3] = []
	var max_dist := view_distance * 1.5

	for corner in _wall_corners_cache:
		var dist := Vector2(corner.x - origin.x, corner.z - origin.z).length()
		if dist <= max_dist:
			corners.append(corner)

	return corners


## 壁コーナーキャッシュを再構築（全コーナーを収集）
func _rebuild_wall_corners_cache() -> void:
	_wall_corners_cache.clear()

	# Search for walls in "walls" group
	var walls := get_tree().get_nodes_in_group("walls")
	for wall in walls:
		var wall_corners := _get_node_corners(wall)
		_wall_corners_cache.append_array(wall_corners)

	# Also check CSGBox3D nodes with collision layer 2
	_collect_csg_corners_to_cache(get_tree().root)


## Recursively collect corners from CSGBox3D nodes (for cache building)
func _collect_csg_corners_to_cache(node: Node) -> void:
	if node is CSGBox3D:
		var csg: CSGBox3D = node
		if csg.use_collision and (csg.collision_layer & wall_collision_mask) != 0:
			var box_corners := _get_csg_box_corners(csg)
			_wall_corners_cache.append_array(box_corners)

	for child in node.get_children():
		_collect_csg_corners_to_cache(child)


## Get corners from CSGBox3D
func _get_csg_box_corners(csg: CSGBox3D) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var half_size := csg.size / 2.0

	# Local XZ plane corners
	var local_corners := [
		Vector3(-half_size.x, 0, -half_size.z),
		Vector3(half_size.x, 0, -half_size.z),
		Vector3(half_size.x, 0, half_size.z),
		Vector3(-half_size.x, 0, half_size.z),
	]

	# Convert to global coordinates
	for local_corner in local_corners:
		result.append(csg.global_transform * local_corner)

	return result


## Get corners from StaticBody3D with BoxShape3D
func _get_node_corners(wall: Node) -> Array[Vector3]:
	var corners: Array[Vector3] = []

	if wall is StaticBody3D:
		var static_body: StaticBody3D = wall
		for child in static_body.get_children():
			if child is CollisionShape3D:
				var col_shape: CollisionShape3D = child
				var shape = col_shape.shape
				if shape is BoxShape3D:
					var box_shape: BoxShape3D = shape
					var half_size: Vector3 = box_shape.size / 2.0
					var local_corners: Array[Vector3] = [
						Vector3(-half_size.x, 0, -half_size.z),
						Vector3(half_size.x, 0, -half_size.z),
						Vector3(half_size.x, 0, half_size.z),
						Vector3(-half_size.x, 0, half_size.z),
					]
					var combined_transform: Transform3D = static_body.global_transform * col_shape.transform
					for local_corner in local_corners:
						corners.append(combined_transform * local_corner)

	return corners


## 角度をスナップ（度単位）
func _snap_angle(angle_rad: float) -> float:
	var angle_deg := rad_to_deg(angle_rad)
	var snapped_deg := snappedf(angle_deg, ANGLE_SNAP_DEGREES)
	return deg_to_rad(snapped_deg)


## Wrap angle to -PI to PI range
func _wrap_angle(angle: float) -> float:
	while angle > PI:
		angle -= TAU
	while angle < -PI:
		angle += TAU
	return angle


func _get_eye_position() -> Vector3:
	if not _character:
		return global_position

	# 現在の目の位置を計算
	var target_pos := _character.global_position
	target_pos.y += eye_height

	# テンポラルスムージング（全軸に適用してカクカクを防止）
	if not _smoothed_initialized:
		_smoothed_eye_position = target_pos
	else:
		_smoothed_eye_position = _smoothed_eye_position.lerp(target_pos, EYE_POSITION_SMOOTHING)

	return _smoothed_eye_position


func _get_look_angle() -> float:
	var direction := _get_look_direction()
	var target_angle := atan2(direction.x, -direction.z)

	# 角度のテンポラルスムージング（体の揺れを吸収）
	if not _smoothed_initialized:
		_smoothed_angle = target_angle
		_smoothed_initialized = true
	else:
		# 角度の差分を -PI ~ PI に正規化してから補間
		var angle_diff := _wrap_angle(target_angle - _smoothed_angle)
		_smoothed_angle = _wrap_angle(_smoothed_angle + angle_diff * ANGLE_SMOOTHING)

	return _smoothed_angle


func _get_look_direction() -> Vector3:
	if not _character:
		return Vector3.FORWARD

	# アニメーションコントローラーからエイム方向を取得
	if _character.has_method("get_anim_controller"):
		var anim_ctrl = _character.get_anim_controller()
		if anim_ctrl and anim_ctrl.has_method("get_look_direction"):
			var dir = anim_ctrl.get_look_direction()
			dir.y = 0
			if dir.length_squared() > 0.001:
				return dir.normalized()

	# フォールバック: キャラクターの前方向
	var forward := _character.global_transform.basis.z
	forward.y = 0

	if forward.length_squared() < 0.001:
		return Vector3.FORWARD

	return forward.normalized()
