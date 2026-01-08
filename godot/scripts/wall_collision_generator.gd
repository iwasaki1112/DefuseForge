extends Node3D

## 壁メッシュからコリジョンを自動生成するスクリプト
## collision_layer = 6 (bit 1 + bit 2) で生成
## - bit 1: 入力レイキャスト用
## - bit 2: GridManager障害物検出用

signal collisions_generated(count: int)

var mesh_count: int = 0

func _ready() -> void:
	# 少し待ってからコリジョン生成（シーン読み込み完了後）
	call_deferred("_generate_collisions")


func _generate_collisions() -> void:
	print("[WallCollision] コリジョン生成開始...")
	mesh_count = 0
	_process_node_recursive(self)
	print("[WallCollision] コリジョン生成完了: ", mesh_count, " メッシュ")
	collisions_generated.emit(mesh_count)


func _process_node_recursive(node: Node) -> void:
	# MeshInstance3Dの場合、コリジョンを生成
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			# 壁メッシュのみ対象（"Wall"を含む名前）
			var name_lower := mesh_instance.name.to_lower()
			if not name_lower.contains("wall"):
				# 壁以外はスキップ
				for child in node.get_children():
					_process_node_recursive(child)
				return

			# 既にコリジョンがある場合はスキップ
			var has_collision := false
			for child in mesh_instance.get_children():
				if child is StaticBody3D:
					has_collision = true
					break

			if not has_collision:
				var global_pos = mesh_instance.global_position
				print("[WallCollision] メッシュ発見: ", mesh_instance.name, " at ", global_pos)
				_create_collision_for_mesh(mesh_instance)
				mesh_count += 1

	# 子ノードを再帰的に処理
	for child in node.get_children():
		_process_node_recursive(child)


func _create_collision_for_mesh(mesh_instance: MeshInstance3D) -> void:
	# StaticBody3Dを作成
	var static_body := StaticBody3D.new()
	static_body.name = mesh_instance.name + "_col"
	# collision_layer = 6 (bit 1 + bit 2)
	# - bit 1 (layer 2): 入力レイキャスト
	# - bit 2 (layer 3): GridManager障害物検出
	static_body.collision_layer = 6
	static_body.collision_mask = 0

	# メッシュからコリジョンシェイプを生成
	var shape: Shape3D = mesh_instance.mesh.create_convex_shape(true, true)
	if shape == null:
		# フォールバック: トライメッシュシェイプ
		shape = mesh_instance.mesh.create_trimesh_shape()

	if shape == null:
		print("[WallCollision] シェイプ作成失敗: ", mesh_instance.name)
		return

	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape

	# StaticBodyに追加
	static_body.add_child(collision_shape)

	# メッシュの子として追加
	mesh_instance.add_child(static_body)
	print("[WallCollision] コリジョン追加: ", mesh_instance.name, " (layer=6)")
