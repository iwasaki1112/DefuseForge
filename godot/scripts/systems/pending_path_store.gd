class_name PendingPathStore
extends RefCounted
## 保留パスのデータ管理
## pending_pathsと_pending_paths_by_playerの全ライフサイクルを担当

## PathExecutionManagerへの参照
var _manager: Node = null

## 保留中のパス（キャラクターごと）
## { character_id: { "character": Node, "path": Array[Vector3], "vision_points_data": Array, "wait_points_data": Array,
##                   "path_mesh": Node3D, "vision_points": Array[MeshInstance3D], "wait_points": Array[MeshInstance3D] } }
var pending_paths: Dictionary = {}

## プレイヤーごとの保留パス（マルチプレイヤー用）
## { player_id: { character_id: PathConfirmMessage } }
var _pending_paths_by_player: Dictionary = {}


## セットアップ
func setup(manager: Node) -> void:
	_manager = manager


## 全ての保留パスをクリア
func clear_all_pending_paths() -> void:
	pending_paths.clear()


## 保留パス数を取得
func get_pending_path_count() -> int:
	return pending_paths.size()


## 指定キャラクターに保留パスがあるかチェック
func has_pending_path_for_character(character: Node) -> bool:
	if not character:
		return false
	return pending_paths.has(character.get_instance_id())


## 指定キャラクターの保留パスを編集用に取り出す
## パスデータを返し、pending_pathsから削除する（メッシュ・ポイントは削除しない）
## @return: パスデータのDictionary、存在しない場合は空のDictionary
func take_pending_path_for_editing(character: Node) -> Dictionary:
	if not character:
		return {}

	var char_id = character.get_instance_id()
	if not pending_paths.has(char_id):
		return {}

	var data = pending_paths[char_id]
	pending_paths.erase(char_id)
	return data


## 指定キャラクターの確定済みパスを取得（削除せずに参照のみ）
## @param character: 対象キャラクター
## @return: パスのVector3配列。見つからない場合は空配列
func get_pending_path_for_character(character: Node) -> Array:
	if not character:
		return []
	var char_id = character.get_instance_id()
	if not pending_paths.has(char_id):
		return []
	var data = pending_paths[char_id]
	return data.get("path", [])


## 特定キャラクターの保留パスをクリア（内部）
func clear_pending_path_for_character(char_id: int) -> void:
	if not pending_paths.has(char_id):
		return

	_free_pending_path_data(pending_paths[char_id])
	pending_paths.erase(char_id)


## 指定位置近くにある確定済みパスの先端を検索
## @param ground_pos: 地面上の位置（y=0）
## @param threshold: 検出閾値
## @return: {character: Node, path_data: Dictionary} を返す。見つからない場合は空のDictionary
func find_path_endpoint_at_position(ground_pos: Vector3, threshold: float = GameConstants.PATH_CLICK_THRESHOLD) -> Dictionary:
	var closest_distance: float = threshold
	var result: Dictionary = {}

	for char_id in pending_paths:
		var data: Dictionary = pending_paths[char_id]
		if not data.has("path") or not data.has("character"):
			continue

		var path: Array = data["path"]
		if path.size() < 2:
			continue

		var character: Node = data["character"]
		if not is_instance_valid(character):
			continue

		# 敵キャラクターのパスは対象外
		if PlayerState.is_enemy(character):
			continue

		# パスの先端（終点）を取得
		var endpoint: Vector3 = path[path.size() - 1]
		endpoint.y = 0.0
		var check_pos := ground_pos
		check_pos.y = 0.0

		var distance := endpoint.distance_to(check_pos)
		if distance < closest_distance:
			closest_distance = distance
			result = {
				"character": character,
				"char_id": char_id,
				"endpoint": endpoint,
				"distance": distance
			}

	return result


## 指定位置が確定済みパス上にあるかを検索（先端は除外）
## @param ground_pos: 地面上の位置（y=0）
## @param threshold: 検出閾値
## @return: {character: Node, char_id: int, path_ratio: float, point: Vector3, distance: float} を返す。見つからない場合は空のDictionary
func find_path_point_at_position(ground_pos: Vector3, threshold: float = GameConstants.PATH_CLICK_THRESHOLD) -> Dictionary:
	var closest_distance: float = threshold
	var result: Dictionary = {}

	for char_id in pending_paths:
		var data: Dictionary = pending_paths[char_id]
		if not data.has("path") or not data.has("character"):
			continue

		var path: Array = data["path"]
		if path.size() < 2:
			continue

		var character: Node = data["character"]
		if not is_instance_valid(character):
			continue

		# 敵キャラクターのパスは対象外
		if PlayerState.is_enemy(character):
			continue

		# PackedVector3Arrayに変換してPathCalculatorを使用
		var path_packed := PackedVector3Array()
		for p in path:
			path_packed.append(p)

		var check_pos := ground_pos
		check_pos.y = 0.0

		var path_result := PathCalculator.find_closest_point_on_path(path_packed, check_pos)
		if path_result.is_empty():
			continue

		var distance: float = path_result.distance
		if distance < closest_distance:
			# 先端（終点）付近は除外（パス延長用に狭い範囲のみ除外）
			var endpoint: Vector3 = path[path.size() - 1]
			endpoint.y = 0.0
			const ENDPOINT_EXCLUSION_THRESHOLD := 0.15  # パス延長用の除外範囲
			if path_result.point.distance_to(endpoint) < ENDPOINT_EXCLUSION_THRESHOLD:
				continue

			closest_distance = distance
			result = {
				"character": character,
				"char_id": char_id,
				"path_ratio": path_result.ratio,
				"point": path_result.point,
				"distance": distance
			}

	return result


## 全ての確定済みパスへの距離を取得（他パスとの比較用）
## @param ground_pos: 地面上の位置（y=0）
## @return: { char_id: distance } の辞書
func get_all_pending_path_distances(ground_pos: Vector3) -> Dictionary:
	var distances: Dictionary = {}
	var check_pos := ground_pos
	check_pos.y = 0.0

	for char_id in pending_paths:
		var data: Dictionary = pending_paths[char_id]
		if not data.has("path") or not data.has("character"):
			continue

		var path: Array = data["path"]
		if path.size() < 2:
			continue

		var character: Node = data["character"]
		if not is_instance_valid(character):
			continue

		# 敵キャラクターのパスは対象外
		if PlayerState.is_enemy(character):
			continue

		# PackedVector3Arrayに変換してPathCalculatorを使用
		var path_packed := PackedVector3Array()
		for p in path:
			path_packed.append(p)

		var path_result := PathCalculator.find_closest_point_on_path(path_packed, check_pos)
		if not path_result.is_empty():
			distances[char_id] = path_result.distance

	return distances


## pending_pathsへの登録
func register_pending_path(
	char_id: int,
	character: Node,
	full_path: Array[Vector3],
	adjusted_points: Dictionary,
	point_nodes: Dictionary,
	path_mesh: MeshInstance3D,
	player_id: int = -1
) -> void:
	var pending_data := {
		"character": character,
		"path": full_path,
		"vision_points_data": adjusted_points.get("vision", []),
		"wait_points_data": adjusted_points.get("wait", []),
		"path_mesh": path_mesh,
		"vision_points": point_nodes.get("vision", []),
		"wait_points": point_nodes.get("wait", [])
	}

	if player_id >= 0:
		pending_data["player_id"] = player_id

	pending_paths[char_id] = pending_data


## pending_pathsのデータからメッシュとポイントを解放（プールに返却）
func _free_pending_path_data(data: Dictionary) -> void:
	if data.has("path_mesh") and is_instance_valid(data["path_mesh"]):
		PathLineMeshPool.release(data["path_mesh"])

	# ポイントメッシュを解放（プールに返却）
	var mesh_keys = ["vision_points", "wait_points"]
	for key in mesh_keys:
		if data.has(key):
			PointFactory.free_point_meshes(data[key])


# ============================================
# Multiplayer API
# ============================================

## プレイヤーの保留パスを取得
func get_pending_paths_for_player(player_id: int) -> Dictionary:
	return _pending_paths_by_player.get(player_id, {}).duplicate()


## 全プレイヤーの保留パスを取得
func get_all_pending_paths_by_player() -> Dictionary:
	return _pending_paths_by_player.duplicate()


## プレイヤーの保留パスをクリア
func clear_pending_paths_for_player(player_id: int) -> void:
	if not _pending_paths_by_player.has(player_id):
		return

	var player_paths: Dictionary = _pending_paths_by_player[player_id]
	for char_id in player_paths.keys():
		clear_pending_path_for_character(char_id)

	_pending_paths_by_player.erase(player_id)


## プレイヤーごとのパス管理に追加
func add_pending_path_for_player(player_id: int, char_id: int, path_msg) -> void:
	if not _pending_paths_by_player.has(player_id):
		_pending_paths_by_player[player_id] = {}
	_pending_paths_by_player[player_id][char_id] = path_msg
