class_name PathMeshManager
extends RefCounted
## パスライン（線）メッシュの作成・更新・削除を管理
## ポイントメッシュは PathPointMeshManager が担当

## パスメッシュを追加する親ノード
var _mesh_parent: Node3D = null


## セットアップ
func setup(mesh_parent: Node3D) -> void:
	_mesh_parent = mesh_parent


## パスメッシュを作成（キャラクター色対応、プール使用）
func create_path_mesh(path: Array[Vector3], character: Node = null) -> MeshInstance3D:
	# キャラクター色を適用（ない場合はデフォルト水色）
	var line_color: Color
	if character:
		var char_color = CharacterColorManager.get_character_color(character)
		line_color = Color(char_color.r, char_color.g, char_color.b, 0.8)
	else:
		line_color = Color(0.3, 0.8, 1.0, 0.8)

	# プールからメッシュを取得
	var mesh = PathLineMeshPool.acquire(_mesh_parent, line_color, GameConstants.PATH_LINE_WIDTH)

	# パスを描画
	var packed_path = PackedVector3Array()
	for point in path:
		packed_path.append(point)
	mesh.update_from_points(packed_path)

	return mesh


## パス進行状況更新時のメッシュ更新
## 通過したパス部分を削除してメッシュを更新
## @param path_index: 現在のパスインデックス
## @param pending_paths: pending_pathsのDictionary（参照）
## @param char_id: キャラクターID
func update_path_progress(path_index: int, pending_paths: Dictionary, char_id: int) -> void:
	if not pending_paths.has(char_id):
		return

	var path_data = pending_paths[char_id]
	var full_path = path_data.get("path", [])

	if full_path.size() < 2:
		return

	var path_mesh = path_data.get("path_mesh")
	if not path_mesh or not is_instance_valid(path_mesh):
		return

	if path_index >= full_path.size() - 1:
		# 最後のポイントに到達 - メッシュをクリア
		path_mesh.clear()
		return

	# 通過した距離を計算（アニメーション連続性用）
	var passed_distance: float = 0.0
	for i in range(1, path_index + 1):
		if i < full_path.size():
			passed_distance += full_path[i - 1].distance_to(full_path[i])

	# path_index以降のポイントで新しいパスを作成
	var remaining_path = PackedVector3Array()
	for i in range(path_index, full_path.size()):
		remaining_path.append(full_path[i])

	# パスメッシュを更新
	if remaining_path.size() >= 2:
		# 通過距離をオフセットとして設定（ドットアニメーション連続性用）
		if path_mesh.has_method("set_path_offset"):
			path_mesh.set_path_offset(passed_distance)
		path_mesh.update_from_points(remaining_path)
	else:
		path_mesh.clear()


## 延長パスに切り替わった時の処理
## 古いパスメッシュをクリアし、延長パスメッシュを新しいメインパスとして設定
func on_extension_path_activated(char_id: int, pending_paths: Dictionary, extension_path_meshes: Dictionary, active_path_meshes: Dictionary) -> void:
	# 古いパスメッシュをクリア
	if pending_paths.has(char_id):
		var path_data = pending_paths[char_id]
		var old_mesh = path_data.get("path_mesh")
		if old_mesh and is_instance_valid(old_mesh):
			old_mesh.clear()

	# アクティブパスメッシュ（過去の延長パス）もクリア
	if active_path_meshes.has(char_id):
		for mesh in active_path_meshes[char_id]:
			if is_instance_valid(mesh):
				mesh.clear()
		active_path_meshes[char_id].clear()

	# 延長パスメッシュを新しいメインパスメッシュとして設定
	if extension_path_meshes.has(char_id):
		var mesh = extension_path_meshes[char_id]
		if is_instance_valid(mesh) and pending_paths.has(char_id):
			pending_paths[char_id]["path_mesh"] = mesh
		extension_path_meshes.erase(char_id)


## 延長パスのメッシュを解放（プールに返却）
func free_extension_mesh(char_id: int, extension_path_meshes: Dictionary) -> void:
	if extension_path_meshes.has(char_id):
		var mesh = extension_path_meshes[char_id]
		if is_instance_valid(mesh):
			PathLineMeshPool.release(mesh)
		extension_path_meshes.erase(char_id)


## アクティブパスメッシュを解放（プールに返却、複数回延長した場合の全セグメント）
func free_active_meshes(char_id: int, active_path_meshes: Dictionary) -> void:
	if active_path_meshes.has(char_id):
		var meshes: Array = active_path_meshes[char_id]
		for mesh in meshes:
			if is_instance_valid(mesh):
				PathLineMeshPool.release(mesh)
		active_path_meshes.erase(char_id)
