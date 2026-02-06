class_name PathPointMeshManager
extends RefCounted
## Vision/Wait/Grenadeポイントメッシュの作成・管理
## 確定済みパスと移動中パスの両方のポイントメッシュを担当

## ポイントタイプのエイリアス
const PointType = ActionPointData.Type

## パスメッシュを追加する親ノード
var _mesh_parent: Node3D = null

## 移動中パスのポイントメッシュ（統合管理）
## { character_id -> { point_type -> Array[MeshInstance3D] } }
var _moving_path_points: Dictionary = {}


## セットアップ
func setup(mesh_parent: Node3D) -> void:
	_mesh_parent = mesh_parent


## 移動中パスにポイントメッシュを追加（内部ヘルパー）
func add_moving_path_point(char_id: int, point_type: int, mesh: MeshInstance3D) -> void:
	if not mesh:
		return
	if not _moving_path_points.has(char_id):
		_moving_path_points[char_id] = {}
	if not _moving_path_points[char_id].has(point_type):
		_moving_path_points[char_id][point_type] = []
	_moving_path_points[char_id][point_type].append(mesh)


## 移動中パスのポイントを取得（内部ヘルパー）
func get_moving_path_points(char_id: int, point_type: int) -> Array:
	if not _moving_path_points.has(char_id):
		return []
	if not _moving_path_points[char_id].has(point_type):
		return []
	return _moving_path_points[char_id][point_type]


## 移動中パスのポイントメッシュを解放（統合版）
## @param char_id: キャラクターID
## @param point_type: ポイントタイプ（-1で全タイプ）
func free_moving_path_points(char_id: int, point_type: int = -1) -> void:
	if not _moving_path_points.has(char_id):
		return

	var char_points: Dictionary = _moving_path_points[char_id]

	if point_type < 0:
		# 全タイプを解放
		for type_key in char_points.keys():
			PointFactory.free_point_meshes(char_points[type_key])
		_moving_path_points.erase(char_id)
	else:
		# 特定タイプのみ解放
		if char_points.has(point_type):
			PointFactory.free_point_meshes(char_points[point_type])
			char_points.erase(point_type)
		# 全タイプが空になったらエントリを削除
		if char_points.is_empty():
			_moving_path_points.erase(char_id)


## 調整済み視線ポイントから新しいVisionPointを生成（PointFactory使用）
func create_vision_points(
	path: Array[Vector3],
	adjusted_vision_points: Array[Dictionary],
	character: Node,
	calculate_position_on_path: Callable
) -> Array[MeshInstance3D]:
	var points: Array[MeshInstance3D] = []
	var char_color = CharacterColorManager.get_character_color(character)

	for vp in adjusted_vision_points:
		var ratio: float = vp.path_ratio

		# anchorが保存されている場合はそれを使用、なければpath_ratioから計算
		var anchor: Vector3
		if vp.has("anchor") and vp.anchor != Vector3.ZERO:
			anchor = vp.anchor
		else:
			anchor = calculate_position_on_path.call(path, ratio)

		# PointFactoryでVisionPointを作成
		var target_point = vp.get("target_point", null)
		var direction: Vector3 = vp.get("direction", Vector3.FORWARD)
		var point = PointFactory.create_vision_point(anchor, target_point, direction, char_color, _mesh_parent)
		points.append(point)

		# マーカー参照をpoint_dataに直接保持（距離マッチング不要化）
		vp["marker"] = point

	return points


## 調整済みWaitポイントから新しいWaitPointを生成（PointFactory使用）
func create_wait_points(
	_path: Array[Vector3],
	adjusted_wait_points: Array[Dictionary],
	character: Node
) -> Array[MeshInstance3D]:
	var points: Array[MeshInstance3D] = []
	var char_color = CharacterColorManager.get_character_color(character)

	for wp in adjusted_wait_points:
		var point = PointFactory.create_wait_point_from_dict(wp, char_color, _mesh_parent)
		points.append(point)

		# マーカー参照をpoint_dataに直接保持（距離マッチング不要化）
		wp["marker"] = point

	return points


## 単一のWaitPointメッシュを作成（PointFactory使用）
func create_single_wait_point(anchor: Vector3, duration: float, character: Node) -> MeshInstance3D:
	if not _mesh_parent:
		return null
	var char_color = CharacterColorManager.get_character_color(character)
	return PointFactory.create_wait_point(anchor, duration, char_color, _mesh_parent)


## 単一のVisionPointメッシュを作成（PointFactory使用）
func create_single_vision_point(anchor: Vector3, target_point: Vector3, character: Node) -> MeshInstance3D:
	if not _mesh_parent:
		return null
	var char_color = CharacterColorManager.get_character_color(character)
	return PointFactory.create_vision_point(anchor, target_point, Vector3.ZERO, char_color, _mesh_parent)


## ポイント到達時の統合コールバック
func on_point_reached(point_type: int, _index: int, point_data: Dictionary, character: Node, pending_paths: Dictionary) -> void:
	if not character:
		return

	# マーカー参照が直接保持されている場合はそれを使用（確実なマッチング）
	if point_data.has("marker"):
		var marker = point_data.marker
		if is_instance_valid(marker) and marker.visible:
			marker.visible = false
		return

	# フォールバック: 移動中パスの動的ポイント（マーカー参照なし）
	var char_id = character.get_instance_id()
	var anchor: Vector3 = point_data.get("anchor", Vector3.ZERO)

	# 移動中パスのポイントを取得
	var moving_points: Array = get_moving_path_points(char_id, point_type)

	# ポイントタイプに応じたpending_pathsのキー名
	var point_key: String = "vision_points" if point_type == PointType.VISION else "wait_points"

	# フォールバック: 位置ベースマッチング（移動中パスなど）
	if anchor != Vector3.ZERO:
		hide_point_at_position(char_id, anchor, point_key, pending_paths, moving_points)


## 指定位置のポイントを非表示にする（位置ベースマッチング）
## @param char_id: キャラクターID
## @param anchor: ポイントのアンカー位置
## @param point_key: pending_paths内のポイント配列のキー名
## @param pending_paths: pending_pathsのDictionary（参照）
## @param moving_points: 移動中パスのポイント配列（オプション）
## @param threshold: マッチング距離閾値（デフォルト0.2で正確なマッチング）
func hide_point_at_position(char_id: int, anchor: Vector3, point_key: String, pending_paths: Dictionary, moving_points: Array = [], threshold: float = 0.2) -> void:
	var anchor_flat = Vector3(anchor.x, 0.0, anchor.z)

	# 移動中パスの動的ポイントを優先チェック
	for i in range(moving_points.size()):
		var point = moving_points[i]
		if is_instance_valid(point) and point.visible:
			var point_pos = point.global_position
			point_pos.y = 0.0
			var dist = point_pos.distance_to(anchor_flat)
			if dist < threshold:
				point.visible = false
				return

	# 確認済みパスのポイントを非表示
	if pending_paths.has(char_id):
		var path_data = pending_paths[char_id]
		var points = path_data.get(point_key, [])
		for i in range(points.size()):
			var point = points[i]
			if is_instance_valid(point) and point.visible:
				var point_pos = point.global_position
				point_pos.y = 0.0
				var dist = point_pos.distance_to(anchor_flat)
				if dist < threshold:
					point.visible = false
					return


## 指定タイプのポイント比率を一括調整
func adjust_point_ratios_for_type(
	point_data: Array[Dictionary],
	point_type: int,
	connect_length: float,
	base_length: float,
	adjust_vision_ratios: Callable,
	adjust_wait_ratios: Callable
) -> Array[Dictionary]:
	match point_type:
		PointType.VISION:
			return adjust_vision_ratios.call(point_data, connect_length, base_length)
		PointType.WAIT:
			return adjust_wait_ratios.call(point_data, connect_length, base_length)
		_:
			return point_data.duplicate()


## 指定タイプのポイントを一括生成
func create_points_for_type(
	path: Array[Vector3],
	point_data: Array[Dictionary],
	point_type: int,
	character: Node,
	calculate_position_on_path: Callable
) -> Array[MeshInstance3D]:
	match point_type:
		PointType.VISION:
			return create_vision_points(path, point_data, character, calculate_position_on_path)
		PointType.WAIT:
			return create_wait_points(path, point_data, character)
		_:
			return []


## PathDrawerから統一APIでポイントデータを取得
func get_all_points_from_drawer(path_drawer: Node, is_multi_mode: bool) -> Dictionary:
	var result: Dictionary = {}

	for type_value in PointType.values():
		if is_multi_mode:
			result[type_value] = {
				"data": path_drawer.get_all_points_by_type(type_value),
				"meshes": path_drawer.take_all_points_by_type(type_value)
			}
		else:
			result[type_value] = {
				"data": path_drawer.get_points_by_type(type_value).duplicate(),
				"meshes": path_drawer.take_points_by_type(type_value)
			}

	return result


## ポイントメッシュを一括削除（PointFactory委譲）
func free_point_meshes(meshes: Array) -> void:
	PointFactory.free_point_meshes(meshes)
