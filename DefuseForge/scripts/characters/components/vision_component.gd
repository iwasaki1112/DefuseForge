class_name VisionComponent
extends Node

## 視界管理コンポーネント（シャドウキャスト方式）
## 壁セグメントの端点を利用した安定した可視性計算

signal vision_updated(visible_points: PackedVector3Array)
signal wall_hit_updated(hit_points: PackedVector3Array)

## 視界パラメータ
@export var fov_degrees: float = 90.0           # 視野角（度）
@export var view_distance: float = 15.0         # 視界距離
@export var edge_ray_count: int = 30            # FOV境界のレイ数（補助）
@export var update_interval: float = 0.033      # 更新間隔（秒）
@export var eye_height: float = 1.5             # 目の高さ

## 壁検出用コリジョンマスク
@export_flags_3d_physics var wall_collision_mask: int = 2  # Layer 2 = 壁

## 内部変数
var _character: CharacterBody3D
var _update_timer: float = 0.0
var _visible_polygon: PackedVector3Array = []
var _wall_hit_points: PackedVector3Array = []


func _ready() -> void:
	_character = get_parent() as CharacterBody3D
	if _character == null:
		push_error("[VisionComponent] Parent must be CharacterBody3D")
		return


## 更新処理（CharacterBaseから呼ばれる）
func update(delta: float) -> void:
	_update_timer -= delta
	if _update_timer <= 0:
		_update_timer = update_interval
		_calculate_shadow_cast_vision()


## シャドウキャスト方式で視界を計算
func _calculate_shadow_cast_vision() -> void:
	if _character == null:
		return

	var space_state = _character.get_world_3d().direct_space_state
	var origin = _character.global_position + Vector3(0, eye_height, 0)

	# 視線方向を決定（視線ポイント優先、なければキャラクターの向き）
	var look_direction: Vector3 = _get_effective_look_direction()

	# 視線方向から角度を計算（Godotでは-Zが前方なので符号反転）
	var char_rotation = atan2(look_direction.x, -look_direction.z)
	var half_fov = deg_to_rad(fov_degrees / 2.0)

	# FOVの境界角度
	var fov_min_angle = char_rotation - half_fov
	var fov_max_angle = char_rotation + half_fov

	# 壁のコーナーポイントを収集
	var wall_corners = _collect_wall_corners(origin)

	# レイを発射する角度のリストを作成
	var ray_angles: Array[float] = []

	# 1. FOVの境界と内部に均等にレイを配置
	for i in range(edge_ray_count + 1):
		var t = float(i) / float(edge_ray_count)
		var angle = fov_min_angle + t * (fov_max_angle - fov_min_angle)
		ray_angles.append(angle)

	# 2. 壁コーナーへのレイ（コーナーの少し左右にも）
	for corner in wall_corners:
		var to_corner = Vector2(corner.x - origin.x, corner.z - origin.z)
		var corner_angle = atan2(to_corner.x, -to_corner.y)  # -Zが前方

		# FOV内のコーナーのみ
		var relative_angle = _wrap_angle(corner_angle - char_rotation)
		if abs(relative_angle) <= half_fov + 0.01:
			# コーナーとその少し左右
			ray_angles.append(corner_angle - 0.001)
			ray_angles.append(corner_angle)
			ray_angles.append(corner_angle + 0.001)

	# キャラクターの向きを基準に相対角度でソート（±PI境界問題を回避）
	var angle_data: Array[Dictionary] = []
	for angle in ray_angles:
		var relative = _wrap_angle(angle - char_rotation)
		angle_data.append({"absolute": angle, "relative": relative})

	# 相対角度でソート
	angle_data.sort_custom(func(a, b): return a.relative < b.relative)

	# 重複を除去
	var unique_angles: Array[float] = []
	for data in angle_data:
		var angle = data.absolute
		if unique_angles.is_empty():
			unique_angles.append(angle)
		else:
			# 相対角度で比較して重複チェック
			var last_relative = _wrap_angle(unique_angles[-1] - char_rotation)
			var current_relative = data.relative
			if abs(current_relative - last_relative) > 0.0001:
				unique_angles.append(angle)

	# 各角度にレイを発射
	_visible_polygon.clear()
	_wall_hit_points.clear()

	# 原点を最初に追加
	_visible_polygon.append(origin)

	for angle in unique_angles:
		# FOV範囲内かチェック
		var relative = _wrap_angle(angle - char_rotation)
		if abs(relative) > half_fov:
			continue

		var direction = Vector3(sin(angle), 0, -cos(angle))  # キャラクターの前方(-Z)に合わせる
		var end_point = origin + direction * view_distance

		var query = PhysicsRayQueryParameters3D.create(origin, end_point, wall_collision_mask)
		query.exclude = [_character.get_rid()]
		var result = space_state.intersect_ray(query)

		if result:
			_visible_polygon.append(result.position)
			_wall_hit_points.append(result.position)
		else:
			_visible_polygon.append(end_point)

	vision_updated.emit(_visible_polygon)
	wall_hit_updated.emit(_wall_hit_points)


## 壁のコーナーポイントを収集
func _collect_wall_corners(origin: Vector3) -> Array[Vector3]:
	var corners: Array[Vector3] = []

	# シーン内の壁（Layer 2）を検索
	var walls = get_tree().get_nodes_in_group("walls")

	for wall in walls:
		if wall is StaticBody3D:
			# 壁のコリジョンシェイプからコーナーを取得
			for child in wall.get_children():
				if child is CollisionShape3D:
					var shape = child.shape
					if shape is BoxShape3D:
						var box_corners = _get_box_corners(wall.global_transform, child.transform, shape)
						for corner in box_corners:
							var dist = Vector2(corner.x - origin.x, corner.z - origin.z).length()
							if dist <= view_distance * 1.5:  # 視界距離内のみ
								corners.append(corner)

	return corners


## BoxShapeのコーナー座標を取得
func _get_box_corners(wall_transform: Transform3D, shape_transform: Transform3D, shape: BoxShape3D) -> Array[Vector3]:
	var corners: Array[Vector3] = []
	var half_size = shape.size / 2.0

	# ローカル座標でのコーナー（XZ平面の4隅）
	var local_corners = [
		Vector3(-half_size.x, 0, -half_size.z),
		Vector3(half_size.x, 0, -half_size.z),
		Vector3(half_size.x, 0, half_size.z),
		Vector3(-half_size.x, 0, half_size.z),
	]

	# グローバル座標に変換
	var combined_transform = wall_transform * shape_transform
	for local_corner in local_corners:
		corners.append(combined_transform * local_corner)

	return corners


## 角度を-PI〜PIにラップ
func _wrap_angle(angle: float) -> float:
	while angle > PI:
		angle -= TAU
	while angle < -PI:
		angle += TAU
	return angle


## 視線方向を取得（AnimationComponentの回転を反映）
func _get_effective_look_direction() -> Vector3:
	# AnimationComponentの現在の回転角度を取得
	var animation = _character.get("animation") if _character else null

	# キャラクターの基本向き（body forward）
	var forward = _character.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()

	if animation and animation.has_method("get_current_aim_rotation"):
		var aim_rotation: Vector2 = animation.get_current_aim_rotation()
		var yaw = aim_rotation.x  # ラジアン

		# 基本向きに上半身回転を適用
		# forwardはbasis.z（後ろ方向）なので、回転を適用
		var rotated = forward.rotated(Vector3.UP, yaw)
		return rotated

	return forward


## 視界ポリゴンを取得
func get_visible_polygon() -> PackedVector3Array:
	return _visible_polygon


## 壁ヒットポイントを取得
func get_wall_hit_points() -> PackedVector3Array:
	return _wall_hit_points


## 視野角を変更
func set_fov(degrees: float) -> void:
	fov_degrees = degrees


## 視界距離を変更
func set_view_distance(distance: float) -> void:
	view_distance = distance


## 即座に視界を更新
func force_update() -> void:
	_calculate_shadow_cast_vision()


## 視界を無効化（死亡時など）
func disable() -> void:
	set_process(false)
	_visible_polygon.clear()
	_wall_hit_points.clear()
	vision_updated.emit(_visible_polygon)
	wall_hit_updated.emit(_wall_hit_points)


## 視界を有効化
func enable() -> void:
	set_process(true)
	force_update()
