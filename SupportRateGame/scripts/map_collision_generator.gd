extends Node3D

## マップのメッシュからコリジョンを自動生成するスクリプト

var mesh_count: int = 0

func _ready() -> void:
	# 少し待ってからコリジョン生成（シーン読み込み完了後）
	call_deferred("_generate_collisions")


func _generate_collisions() -> void:
	print("[MapCollision] コリジョン生成開始...")
	print("[MapCollision] 子ノード数: ", get_child_count())
	mesh_count = 0
	_process_node_recursive(self)
	print("[MapCollision] コリジョン生成完了: ", mesh_count, " メッシュ")


func _process_node_recursive(node: Node) -> void:
	# デバッグ: ノード情報を出力
	if node != self:
		print("[MapCollision] ノード: ", node.name, " タイプ: ", node.get_class())

	# MeshInstance3Dの場合、コリジョンを生成
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			print("[MapCollision] メッシュ発見: ", mesh_instance.name)
			_create_collision_for_mesh(mesh_instance)
			mesh_count += 1

	# 子ノードを再帰的に処理
	for child in node.get_children():
		_process_node_recursive(child)


func _create_collision_for_mesh(mesh_instance: MeshInstance3D) -> void:
	# StaticBody3Dを作成
	var static_body := StaticBody3D.new()
	static_body.name = mesh_instance.name + "_col"
	static_body.collision_layer = 2  # 地形レイヤー
	static_body.collision_mask = 0

	# メッシュからトライメッシュコリジョンシェイプを生成
	var shape := mesh_instance.mesh.create_trimesh_shape()
	if shape == null:
		print("[MapCollision] シェイプ作成失敗: ", mesh_instance.name)
		return

	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape

	# StaticBodyに追加
	static_body.add_child(collision_shape)

	# メッシュの親に追加し、同じトランスフォームを適用
	mesh_instance.add_child(static_body)
	print("[MapCollision] コリジョン追加: ", mesh_instance.name)
