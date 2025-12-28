extends Node3D

## 地形コリジョン生成システム
## メッシュの高さを分析してBoxShape3Dを配置

func _ready() -> void:
	_generate_collision()


func _generate_collision() -> void:
	var mesh_instance: MeshInstance3D = $GrassMesh
	var collision_body: StaticBody3D = $TerrainCollision

	if mesh_instance == null or mesh_instance.mesh == null:
		push_error("[TerrainCollisionGenerator] GrassMeshが見つかりません")
		return

	if collision_body == null:
		push_error("[TerrainCollisionGenerator] TerrainCollisionが見つかりません")
		return

	var mesh: Mesh = mesh_instance.mesh

	# メッシュの頂点を収集
	var min_pos := Vector3(INF, INF, INF)
	var max_pos := Vector3(-INF, -INF, -INF)
	var total_y := 0.0
	var vertex_count := 0

	# 中心付近の頂点のY座標を収集（より正確な地面高さのため）
	var center_y_values: Array[float] = []
	var center_radius := 10.0  # 中心から10ユニット以内

	for surface_idx in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_idx)
		if arrays.size() == 0:
			continue

		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]

		for vertex in vertices:
			var world_pos: Vector3 = mesh_instance.transform * vertex
			min_pos.x = min(min_pos.x, world_pos.x)
			min_pos.y = min(min_pos.y, world_pos.y)
			min_pos.z = min(min_pos.z, world_pos.z)
			max_pos.x = max(max_pos.x, world_pos.x)
			max_pos.y = max(max_pos.y, world_pos.y)
			max_pos.z = max(max_pos.z, world_pos.z)
			total_y += world_pos.y
			vertex_count += 1

			# 中心付近の頂点を記録
			var dist_from_center := sqrt(world_pos.x * world_pos.x + world_pos.z * world_pos.z)
			if dist_from_center < center_radius:
				center_y_values.append(world_pos.y)

	if vertex_count == 0:
		push_error("[TerrainCollisionGenerator] メッシュから頂点を取得できませんでした")
		return

	# 地面は最低点（草の根元）
	var ground_y: float = min_pos.y
	print("[TerrainCollisionGenerator] メッシュ分析: 頂点数=", vertex_count)
	print("[TerrainCollisionGenerator] Y範囲: min=", min_pos.y, " max=", max_pos.y)
	print("[TerrainCollisionGenerator] 地面Y=", ground_y, " (最低点を使用)")

	# BoxShape3Dを配置
	var box := BoxShape3D.new()
	var size_x := max_pos.x - min_pos.x
	var size_z := max_pos.z - min_pos.z
	box.size = Vector3(size_x, 1.0, size_z)

	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = box
	collision_shape.position = Vector3(
		(min_pos.x + max_pos.x) / 2.0,
		ground_y - 0.5,  # 上面がground_yになるように
		(min_pos.z + max_pos.z) / 2.0
	)
	collision_body.add_child(collision_shape)

	print("[TerrainCollisionGenerator] コリジョン生成完了: 上面Y=", ground_y, " サイズ=", box.size)
