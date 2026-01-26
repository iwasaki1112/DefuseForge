class_name PathRaycastHelper
extends RefCounted

## レイキャストユーティリティクラス
## 壁検出、ドア検出、床・壁へのレイキャストなどの機能を提供


## 2点間に壁があるかチェック（ドアは除外）
## @param space_state: PhysicsDirectSpaceState3D
## @param from: 開始位置
## @param to: 終了位置
## @param wall_collision_mask: 壁検出用のコリジョンマスク
## @param ground_plane_height: 地面の高さ
## @return: { "hit": bool, "position": Vector3 (ヒット位置、hitがtrueの場合) }
static func check_wall_between(
	space_state: PhysicsDirectSpaceState3D,
	from: Vector3,
	to: Vector3,
	wall_collision_mask: int,
	ground_plane_height: float = 0.0
) -> Dictionary:
	if not space_state:
		return { "hit": false }

	# 地面ギリギリを避けるため、少し高さを上げてレイキャスト
	var check_from = from + Vector3(0, 0.5, 0)
	var check_to = to + Vector3(0, 0.5, 0)

	var query = PhysicsRayQueryParameters3D.create(check_from, check_to, wall_collision_mask)

	# 最大10回までレイキャストを試行（ドアを除外しながら）
	var excluded_rids: Array[RID] = []
	for _i in range(10):
		query.exclude = excluded_rids
		var result = space_state.intersect_ray(query)

		if not result:
			return { "hit": false }

		var collider = result.collider

		# ドアグループに属するオブジェクトは無視（パスはドアを貫通できる）
		if _is_door_object(collider):
			# このコライダーを除外リストに追加して再試行
			if collider is CollisionObject3D:
				excluded_rids.append(collider.get_rid())
			continue

		# 壁にヒット - 位置を地面高さに補正
		var hit_pos = result.position
		hit_pos.y = ground_plane_height
		return { "hit": true, "position": hit_pos }

	return { "hit": false }


## 壁または床へのレイキャスト
## @param camera: カメラ
## @param space_state: PhysicsDirectSpaceState3D
## @param screen_pos: スクリーン座標
## @return: レイキャスト結果（空の場合はヒットなし）
static func raycast_wall_or_floor(
	camera: Camera3D,
	space_state: PhysicsDirectSpaceState3D,
	screen_pos: Vector2
) -> Dictionary:
	if not camera or not space_state:
		return {}

	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)
	var ray_end = ray_origin + ray_dir * 100.0

	# 壁と床の両方を検出（レイヤー1とレイヤー2）
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 3)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	return space_state.intersect_ray(query)


## ドアをレイキャストで検出
## @param camera: カメラ
## @param space_state: PhysicsDirectSpaceState3D
## @param screen_pos: スクリーン座標
## @return: 検出されたドアノード（なければnull）
static func raycast_door(
	camera: Camera3D,
	space_state: PhysicsDirectSpaceState3D,
	screen_pos: Vector2
) -> Node3D:
	if not camera or not space_state:
		return null

	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)
	var ray_end = ray_origin + ray_dir * 100.0

	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return null

	# doorsグループを探す
	var collider = result.collider
	var node = collider
	while node:
		if node.is_in_group("doors"):
			return node as Node3D
		node = node.get_parent()
	return null


## 地面平面との交点を取得
## @param camera: カメラ
## @param ground_plane: 地面平面
## @param screen_pos: スクリーン座標
## @return: 地面上の位置（交点がなければnull）
static func get_ground_position(camera: Camera3D, ground_plane: Plane, screen_pos: Vector2) -> Variant:
	if not camera:
		return null

	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_direction = camera.project_ray_normal(screen_pos)

	var intersection = ground_plane.intersects_ray(ray_origin, ray_direction)
	if intersection:
		return intersection as Vector3
	return null


## オブジェクトがドアかどうかをチェック
static func _is_door_object(obj: Object) -> bool:
	if not obj:
		return false
	var node = obj as Node
	if not node:
		return false

	# ノードまたはその親がdoorsグループに属しているかチェック
	while node:
		if node.is_in_group("doors"):
			return true
		node = node.get_parent()
	return false


## レイキャスト結果が壁かどうかを判定
## @param normal: レイキャストヒットの法線
## @return: 壁の場合true
static func is_wall_hit(normal: Vector3) -> bool:
	return abs(normal.y) < 0.5
