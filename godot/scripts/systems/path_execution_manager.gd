extends Node
class_name PathExecutionManager
## パス実行管理
## パス確定・実行・pending_paths管理を担当

const PathLineMeshScript = preload("res://scripts/effects/path_line_mesh.gd")
const PathFollowingCtrl = preload("res://scripts/characters/path_following_controller.gd")
const VisionMarkerScript = preload("res://scripts/effects/vision_marker.gd")
const RunMarkerScript = preload("res://scripts/effects/run_marker.gd")
const ClearMarkerScript = preload("res://scripts/effects/clear_marker.gd")
const GrenadeMarkerScript = preload("res://scripts/effects/grenade_marker.gd")
const SmokeGrenadeMarkerScript = preload("res://scripts/effects/smoke_grenade_marker.gd")
const DoorMarkerScript = preload("res://scripts/effects/door_marker.gd")
const WaitMarkerScript = preload("res://scripts/effects/wait_marker.gd")
const ActionMarkerDataScript = preload("res://scripts/effects/action_marker_data.gd")

## パス確定時のシグナル
signal path_confirmed(character_count: int)
## 全パス実行開始時のシグナル
signal paths_execution_started(count: int)
## 全パス完了時のシグナル
signal all_paths_completed()
## パスクリア時のシグナル
signal paths_cleared()
## 個別キャラクターのパス完了シグナル
signal character_path_completed(character: Node)
## グレネードマーカー到達時のシグナル
signal grenade_marker_reached(character: Node, marker_data: Dictionary)
## スモークグレネードマーカー到達時のシグナル
signal smoke_grenade_marker_reached(character: Node, marker_data: Dictionary)
## ドアマーカー到達時のシグナル
signal door_marker_reached(character: Node, door: Node3D)
## Visionマーカー到達時のシグナル（移動中パスマーカー非表示用）
signal vision_point_reached(character: Node, path_ratio: float)
## 延長マーカーの比率がスケールされた時のシグナル
signal extension_markers_scaled(character: Node, scale: float)

## 保留中のパス（キャラクターごと）
## { character_id: { "character": Node, "path": Array[Vector3], "vision_points": Array, "run_segments": Array, "clear_points": Array,
##                   "grenade_markers_data": Array, "smoke_grenade_markers_data": Array, "door_markers_data": Array, "wait_markers_data": Array,
##                   "path_mesh": Node3D, "vision_markers": Array, "run_markers": Array, "clear_markers": Array,
##                   "grenade_markers": Array, "smoke_grenade_markers": Array, "door_markers": Array, "wait_markers": Array } }
var pending_paths: Dictionary = {}

## プレイヤーごとの保留パス（マルチプレイヤー用）
## { player_id: { character_id: PathConfirmMessage } }
var _pending_paths_by_player: Dictionary = {}

## パス追従コントローラー { character_id -> PathFollowingController }
var _path_controllers: Dictionary = {}

## 延長パスのメッシュ { character_id -> MeshInstance3D }
var _extension_path_meshes: Dictionary = {}

## アクティブパスメッシュ（延長後に切り替わったパス） { character_id -> Array[MeshInstance3D] }
## 複数回延長した場合に全てのセグメントを保持
var _active_path_meshes: Dictionary = {}

## パスメッシュを追加する親ノード
var _mesh_parent: Node3D = null

## 実行順序カウンター（衝突回避の優先度決定用）
var _execution_order_counter: int = 0


## セットアップ
func setup(mesh_parent: Node3D) -> void:
	_mesh_parent = mesh_parent


## パスを確定して保存
func confirm_path(
	target_characters: Array[Node],
	path_drawer: Node,
	_primary_character: Node
) -> bool:
	if not path_drawer.has_pending_path():
		return false

	if target_characters.is_empty():
		return false

	# シングルキャラクターのみサポート
	var character = target_characters[0]
	var char_id = character.get_instance_id()
	var char_pos = character.global_position

	var display_path := _copy_vector3_array(path_drawer.get_drawn_path())
	var base_path := _copy_vector3_array(path_drawer.get_smoothed_path())
	var marker_data := _get_marker_data_from_drawer(path_drawer)

	# 元のマーカーメッシュを削除
	_free_drawer_marker_meshes(path_drawer)

	# 既存のパスがあれば削除
	_clear_pending_path_for_character(char_id)

	# 接続線を含むパスを作成
	var connected := _build_connected_paths(char_pos, base_path, display_path)
	var full_path: Array[Vector3] = connected.full_path
	var full_display_path: Array[Vector3] = connected.full_display_path
	var connect_length: float = connected.connect_length
	var base_length: float = connected.base_length

	# マーカーの比率を再計算
	var adjusted_markers := _adjust_marker_data_for_connection(marker_data, connect_length, base_length)

	# anchorが保存されているVisionマーカーの比率を、実際のパス上の位置から再計算
	adjusted_markers["vision"] = _recalculate_vision_ratios_from_anchors(full_path, adjusted_markers.get("vision", []))

	# パスメッシュを作成（表示用の生パスを使用）
	var path_mesh = _create_path_mesh(full_display_path, character)

	# マーカーを新規生成
	var marker_nodes := _create_marker_nodes_for_path(full_path, adjusted_markers, character)

	_register_pending_path(char_id, character, full_path, adjusted_markers, marker_nodes, path_mesh)

	path_confirmed.emit(1)
	return true


## 全キャラクターのパスを同時実行
func execute_all_paths(run: bool) -> int:
	if pending_paths.is_empty():
		return 0

	# 優先度カウンターをリセット
	_execution_order_counter = 0

	var executed_count = 0
	for char_id in pending_paths:
		var data = pending_paths[char_id]
		# 既に実行済み（characterキーなし）のエントリはスキップ
		if not data.has("character"):
			continue
		var character = data["character"] as CharacterBody3D

		var path := _copy_vector3_array(data.get("path", []))
		var vision_points := _copy_dict_array(data.get("vision_points", []))
		var run_segments := _copy_dict_array(data.get("run_segments", []))
		var clear_points := _copy_dict_array(data.get("clear_points", []))
		var grenade_markers_data := _copy_dict_array(data.get("grenade_markers_data", []))
		var smoke_grenade_markers_data := _copy_dict_array(data.get("smoke_grenade_markers_data", []))
		var door_markers_data := _copy_dict_array(data.get("door_markers_data", []))
		var wait_markers_data := _copy_dict_array(data.get("wait_markers_data", []))

		if not is_instance_valid(character):
			continue

		# コントローラーを取得または作成
		var controller = _get_or_create_path_controller(character)
		controller.setup(character)

		# 衝突回避用の優先度を設定（先に実行されるほど低い値=高優先）
		controller.set_movement_priority(_execution_order_counter)
		_execution_order_counter += 1

		if controller.start_path(path, vision_points, run_segments, run, clear_points, grenade_markers_data, door_markers_data, wait_markers_data, smoke_grenade_markers_data):
			executed_count += 1

	# マーカーデータのみクリア（パスとメッシュは残す）
	for char_id in pending_paths:
		var data = pending_paths[char_id]
		# パスは進行状況表示のために残す
		data.erase("vision_points")
		data.erase("run_segments")
		data.erase("clear_points")
		data.erase("grenade_markers_data")
		data.erase("smoke_grenade_markers_data")
		data.erase("door_markers_data")
		data.erase("wait_markers_data")
		data.erase("character")

	paths_execution_started.emit(executed_count)
	return executed_count


## 全ての保留パスをクリア
func clear_all_pending_paths() -> void:
	_clear_all_path_meshes()
	pending_paths.clear()
	paths_cleared.emit()


## 保留パス数を取得
func get_pending_path_count() -> int:
	return pending_paths.size()


## 指定キャラクターに保留パスがあるかチェック
func has_pending_path_for_character(character: Node) -> bool:
	if not character:
		return false
	return pending_paths.has(character.get_instance_id())


## 指定キャラクターの保留パスを編集用に取り出す
## パスデータを返し、pending_pathsから削除する（メッシュ・マーカーは削除しない）
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


## 指定位置近くにある確定済みパスの先端を検索
## @param ground_pos: 地面上の位置（y=0）
## @param threshold: 検出閾値
## @return: {character: Node, path_data: Dictionary} を返す。見つからない場合は空のDictionary
func find_path_endpoint_at_position(ground_pos: Vector3, threshold: float = 0.5) -> Dictionary:
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
func find_path_point_at_position(ground_pos: Vector3, threshold: float = 0.5) -> Dictionary:
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
			# 先端（終点）付近は除外
			var endpoint: Vector3 = path[path.size() - 1]
			endpoint.y = 0.0
			if path_result.point.distance_to(endpoint) < threshold:
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


## パス追従中のコントローラーがあるかチェック
func is_any_path_following_active() -> bool:
	for controller in _path_controllers.values():
		if controller.is_following_path():
			return true
	return false


## 移動中パス上の点を検索（先端は除外）
## @param ground_pos: 地面上の位置（y=0）
## @param threshold: 検出閾値
## @return: {character: Node, char_id: int, path_ratio: float, point: Vector3, distance: float} を返す。見つからない場合は空のDictionary
func find_moving_path_point_at_position(ground_pos: Vector3, threshold: float = 0.5) -> Dictionary:
	var closest_distance: float = threshold
	var result: Dictionary = {}

	for char_id in _path_controllers:
		var controller = _path_controllers[char_id]

		if not controller.is_following_path():
			continue

		# キャラクターを取得
		var character: Node = null
		if "_character" in controller:
			character = controller._character
		if not is_instance_valid(character):
			continue

		# 敵キャラクターのパスは対象外
		if PlayerState.is_enemy(character):
			continue

		# 残りパスと延長パスを結合して取得
		var full_path: PackedVector3Array = controller.get_full_remaining_path()
		if full_path.size() < 2:
			continue

		var check_pos := ground_pos
		check_pos.y = 0.0

		var path_result := PathCalculator.find_closest_point_on_path(full_path, check_pos)
		if path_result.is_empty():
			continue

		var distance: float = path_result.distance
		if distance < closest_distance:
			# 先端（終点）付近は除外
			var endpoint: Vector3 = full_path[full_path.size() - 1]
			endpoint.y = 0.0
			if path_result.point.distance_to(endpoint) < threshold:
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


## 移動中パスにVisionマーカーを追加
## @param character: 対象キャラクター
## @param path_ratio: パス上の比率
## @param anchor: アンカー位置
## @param target_point: 視線方向の目標点
## @return: 成功した場合true
func add_vision_marker_to_moving_path(character: Node, path_ratio: float, anchor: Vector3, target_point: Vector3) -> bool:
	if not is_instance_valid(character):
		return false

	var char_id = character.get_instance_id()
	if not _path_controllers.has(char_id):
		return false

	var controller = _path_controllers[char_id]
	if not controller.is_following_path():
		return false

	controller.add_vision_point_to_extension(path_ratio, anchor, target_point)
	return true


## ========================================
## 移動中パス延長機能
## ========================================

## 移動中パスの終点を検索
## @param ground_pos: 地面上の位置（y=0）
## @param threshold: 検出閾値
## @return: {character: Node, endpoint: Vector3, distance: float, is_extending_extension: bool} を返す。見つからない場合は空のDictionary
func find_moving_path_endpoint_at_position(ground_pos: Vector3, threshold: float = 0.5) -> Dictionary:
	var closest_distance: float = threshold
	var result: Dictionary = {}

	for char_id in _path_controllers:
		var controller = _path_controllers[char_id]

		if not controller.is_following_path():
			continue

		# キャラクターを取得
		var character: Node = null
		if "_character" in controller:
			character = controller._character
		if not is_instance_valid(character):
			continue

		# 敵キャラクターのパスは対象外
		if PlayerState.is_enemy(character):
			continue

		# 延長パスがある場合はその終点を使用、なければ元のパス終点を使用
		var endpoint: Vector3 = Vector3.ZERO
		var is_extending_extension: bool = false
		if controller.has_extension_path():
			endpoint = controller.get_extension_path_endpoint()
			is_extending_extension = true
		else:
			endpoint = controller.get_path_endpoint()

		if endpoint == Vector3.ZERO:
			continue

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
				"distance": distance,
				"is_extending_extension": is_extending_extension
			}

	return result


## 移動中キャラクターの残りパスデータを取得
## @param character: 対象キャラクター
## @param get_extension: 延長パスのデータを取得するかどうか（延長の延長用）
## @return: 残りパスデータのDictionary
func get_remaining_path_for_character(character: Node, get_extension: bool = false) -> Dictionary:
	if not character:
		return {}

	var char_id = character.get_instance_id()
	if not _path_controllers.has(char_id):
		return {}

	var controller = _path_controllers[char_id]
	if not controller.is_following_path():
		return {}

	# 延長パスのデータを取得する場合
	if get_extension and controller.has_extension_path():
		return controller.get_extension_path_data()

	return controller.get_remaining_path_data()


## 移動中キャラクターに延長パスを設定
## @param character: 対象キャラクター
## @param extension_path: 延長パス
## @param markers: マーカーデータ
## @param append_to_existing: 既存の延長パスに追加するか（延長の延長用）
## @return: 設定成功したらtrue
func set_extension_path_for_character(character: Node, extension_path: Array[Vector3], markers: Dictionary, append_to_existing: bool = false) -> bool:
	if not character:
		return false

	var char_id = character.get_instance_id()
	if not _path_controllers.has(char_id):
		return false

	var controller = _path_controllers[char_id]
	if not controller.is_following_path():
		return false

	# 既存の延長パスに追加する場合、現在のメッシュをアクティブメッシュに移動
	if append_to_existing and controller.has_extension_path():
		if _extension_path_meshes.has(char_id):
			var old_mesh = _extension_path_meshes[char_id]
			if is_instance_valid(old_mesh):
				if not _active_path_meshes.has(char_id):
					_active_path_meshes[char_id] = []
				_active_path_meshes[char_id].append(old_mesh)
			_extension_path_meshes.erase(char_id)

	controller.set_extension_path(extension_path, markers, append_to_existing)

	# 新しい延長パスのメッシュを作成
	var mesh = _create_path_mesh(extension_path, character)
	if mesh:
		_extension_path_meshes[char_id] = mesh

	return true


## 延長パスのメッシュを解放
func _free_extension_mesh(char_id: int) -> void:
	if _extension_path_meshes.has(char_id):
		var mesh = _extension_path_meshes[char_id]
		if is_instance_valid(mesh):
			mesh.queue_free()
		_extension_path_meshes.erase(char_id)


## アクティブパスメッシュを解放（複数回延長した場合の全セグメント）
func _free_active_path_meshes(char_id: int) -> void:
	if _active_path_meshes.has(char_id):
		var meshes: Array = _active_path_meshes[char_id]
		for mesh in meshes:
			if is_instance_valid(mesh):
				mesh.queue_free()
		_active_path_meshes.erase(char_id)


## 移動中キャラクターの延長パスをキャンセル
## @param character: 対象キャラクター
func cancel_extension_for_character(character: Node) -> void:
	if not character:
		return

	var char_id = character.get_instance_id()
	if not _path_controllers.has(char_id):
		return

	var controller = _path_controllers[char_id]
	controller.cancel_extension()

	# 延長パスのメッシュも削除
	_free_extension_mesh(char_id)


## 指定キャラクターがパス追従中かチェック
func is_character_following_path(character: Node) -> bool:
	if not character:
		return false
	var char_id = character.get_instance_id()
	if _path_controllers.has(char_id):
		return _path_controllers[char_id].is_following_path()
	return false


## 指定キャラクターの進行率を取得 (0.0 ~ 1.0)
func get_character_progress(character: Node) -> float:
	if not character:
		return 0.0
	var char_id = character.get_instance_id()
	if _path_controllers.has(char_id):
		var controller = _path_controllers[char_id]
		if controller.has_method("get_current_progress"):
			return controller.get_current_progress()
	return 0.0


## 指定キャラクターの待機状態を取得
func get_character_waiting_state(character: Node) -> Dictionary:
	if not character:
		return { "is_waiting": false, "type": "", "remaining": 0.0 }
	var char_id = character.get_instance_id()
	if _path_controllers.has(char_id):
		var controller = _path_controllers[char_id]
		if controller.has_method("get_waiting_state"):
			return controller.get_waiting_state()
	return { "is_waiting": false, "type": "", "remaining": 0.0 }


## 全てのアクティブキャラクターの進行状況を取得
## @return: { character_id: { progress: float, waiting_state: Dictionary } }
func get_all_progress() -> Dictionary:
	var result: Dictionary = {}
	for char_id in _path_controllers:
		var controller = _path_controllers[char_id]
		if controller.is_following_path():
			var progress = 0.0
			var waiting_state = { "is_waiting": false, "type": "", "remaining": 0.0 }
			if controller.has_method("get_current_progress"):
				progress = controller.get_current_progress()
			if controller.has_method("get_waiting_state"):
				waiting_state = controller.get_waiting_state()
			result[char_id] = {
				"progress": progress,
				"waiting_state": waiting_state
			}
	return result


## 全てのパス追従をキャンセル
func cancel_all_path_following() -> void:
	for controller in _path_controllers.values():
		if controller.is_following_path():
			controller.cancel()


## 指定キャラクターのパス追従をキャンセル
func cancel_path_following(character: Node, clear_pending: bool = true) -> void:
	if not character:
		return
	var char_id = character.get_instance_id()
	if _path_controllers.has(char_id):
		var controller = _path_controllers[char_id]
		if controller.is_following_path():
			controller.cancel()
	if clear_pending:
		_clear_pending_path_for_character(char_id)
		# 延長パスとアクティブパスのメッシュも削除
		_free_extension_mesh(char_id)
		_free_active_path_meshes(char_id)


## 全パス追従コントローラーを処理（毎フレーム呼ぶ）
func process_controllers(delta: float) -> void:
	for controller in _path_controllers.values():
		if controller.is_following_path():
			controller.process(delta)


## パス追従完了時のコールバック（外部から呼ばれる）
func on_path_following_completed(_character: Node) -> void:
	# 全てのコントローラーが完了したかチェック
	var any_active = false
	for controller in _path_controllers.values():
		if controller.is_following_path():
			any_active = true
			break
	if not any_active:
		# 全員完了したのでパスメッシュを削除
		_clear_all_path_meshes()
		pending_paths.clear()
		all_paths_completed.emit()


## キャラクター用のPathFollowingControllerを取得または作成
func _get_or_create_path_controller(character: Node) -> Node:
	var char_id = character.get_instance_id()
	if _path_controllers.has(char_id):
		var existing = _path_controllers[char_id]
		# Ensure combat awareness is connected
		if character.combat_awareness and existing.has_method("set_combat_awareness"):
			existing.set_combat_awareness(character.combat_awareness)
		return existing

	var controller = Node.new()
	controller.set_script(PathFollowingCtrl)
	controller.name = "PathFollowingController_%d" % char_id
	_mesh_parent.add_child(controller)
	controller.path_completed.connect(_on_path_completed.bind(character))
	controller.path_cancelled.connect(_on_path_cancelled.bind(character))
	controller.grenade_marker_reached.connect(_on_grenade_marker_reached.bind(character))
	controller.smoke_grenade_marker_reached.connect(_on_smoke_grenade_marker_reached.bind(character))
	controller.door_marker_reached.connect(_on_door_marker_reached.bind(character))
	controller.extension_path_activated.connect(_on_extension_path_activated.bind(character))
	controller.path_progress_updated.connect(_on_path_progress_updated.bind(character))
	controller.vision_point_reached.connect(_on_vision_point_reached.bind(character))
	controller.extension_markers_scaled.connect(_on_extension_markers_scaled.bind(character))

	# Connect combat awareness for automatic enemy aiming during movement
	if character.combat_awareness:
		controller.set_combat_awareness(character.combat_awareness)

	_path_controllers[char_id] = controller
	return controller


func _on_path_completed(character: Node) -> void:
	# 到着したキャラクターのパスメッシュを即座に削除
	if character:
		var char_id = character.get_instance_id()
		if pending_paths.has(char_id):
			_free_pending_path_data(pending_paths[char_id])
			pending_paths.erase(char_id)
		# 延長パスのメッシュも削除
		_free_extension_mesh(char_id)
		# アクティブパスメッシュも削除（複数回延長した場合の全セグメント）
		_free_active_path_meshes(char_id)

	character_path_completed.emit(character)
	on_path_following_completed(character)


func _on_path_cancelled(_character: Node) -> void:
	pass


## パス進行状況更新時のコールバック
## 通過したパス部分を削除してメッシュを更新
func _on_path_progress_updated(path_index: int, character: Node) -> void:
	if not character:
		return

	var char_id = character.get_instance_id()

	# 通常のパスメッシュを更新
	if pending_paths.has(char_id):
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

		# path_index以降のポイントで新しいパスを作成
		var remaining_path = PackedVector3Array()
		for i in range(path_index, full_path.size()):
			remaining_path.append(full_path[i])

		# パスメッシュを更新
		if remaining_path.size() >= 2:
			path_mesh.update_from_points(remaining_path)
		else:
			path_mesh.clear()


## 延長パスに切り替わった時のコールバック
## 古いパスメッシュをクリアし、延長パスメッシュを新しいメインパスとして設定
func _on_extension_path_activated(character: Node) -> void:
	if not character:
		return

	var char_id = character.get_instance_id()

	# 古いパスメッシュをクリア
	if pending_paths.has(char_id):
		var path_data = pending_paths[char_id]
		var old_mesh = path_data.get("path_mesh")
		if old_mesh and is_instance_valid(old_mesh):
			old_mesh.clear()

	# アクティブパスメッシュ（過去の延長パス）もクリア
	if _active_path_meshes.has(char_id):
		for mesh in _active_path_meshes[char_id]:
			if is_instance_valid(mesh):
				mesh.clear()
		_active_path_meshes[char_id].clear()

	# 延長パスメッシュを新しいメインパスメッシュとして設定
	if _extension_path_meshes.has(char_id):
		var mesh = _extension_path_meshes[char_id]
		if is_instance_valid(mesh) and pending_paths.has(char_id):
			pending_paths[char_id]["path_mesh"] = mesh
		_extension_path_meshes.erase(char_id)

	# コントローラから新しいパスデータを取得して保存
	if _path_controllers.has(char_id) and pending_paths.has(char_id):
		var controller = _path_controllers[char_id]
		var new_path = controller.get_current_path()
		pending_paths[char_id]["path"] = new_path


func _on_grenade_marker_reached(_index: int, marker_data: Dictionary, character: Node) -> void:
	grenade_marker_reached.emit(character, marker_data)


func _on_smoke_grenade_marker_reached(_index: int, marker_data: Dictionary, character: Node) -> void:
	smoke_grenade_marker_reached.emit(character, marker_data)


func _on_door_marker_reached(_index: int, door: Node3D, character: Node) -> void:
	door_marker_reached.emit(character, door)


## Visionマーカー到達時のコールバック
## 通過したVisionマーカーを非表示にする
func _on_vision_point_reached(index: int, _direction: Vector3, character: Node) -> void:
	if not character:
		return

	var char_id = character.get_instance_id()

	# path_ratioを取得してシグナルを発行（移動中パスマーカー非表示用）
	var path_ratio: float = 0.0
	if _path_controllers.has(char_id):
		var controller = _path_controllers[char_id]
		var vision_points = controller.get_vision_points()
		if index >= 0 and index < vision_points.size():
			path_ratio = vision_points[index].get("path_ratio", 0.0)
	vision_point_reached.emit(character, path_ratio)

	# 確認済みパスのマーカーを非表示
	if not pending_paths.has(char_id):
		return

	var path_data = pending_paths[char_id]
	var vision_markers = path_data.get("vision_markers", [])

	if index >= 0 and index < vision_markers.size():
		var marker = vision_markers[index]
		if is_instance_valid(marker):
			marker.visible = false


## 延長マーカーの比率がスケールされた時のコールバック
func _on_extension_markers_scaled(scale: float, character: Node) -> void:
	extension_markers_scaled.emit(character, scale)


## 直接パスを実行（UI経由せず、パスメッシュなし）
## ドアキックなどの自動移動に使用
## @param character: 移動するキャラクター
## @param target_pos: 目標位置
## @param run: 走るかどうか
## @return: 成功したらtrue
func execute_direct_path(character: CharacterBody3D, target_pos: Vector3, run: bool = false) -> bool:
	if not is_instance_valid(character):
		return false

	# パスを作成（現在位置から目標位置）
	var char_pos := character.global_position
	char_pos.y = 0.0
	var target := target_pos
	target.y = 0.0

	# 既に目標に近い場合はスキップ
	if char_pos.distance_to(target) < 0.3:
		# 即座に完了シグナルを発火
		character_path_completed.emit(character)
		return true

	var path: Array[Vector3] = [char_pos, target]

	# コントローラーを取得または作成
	var controller = _get_or_create_path_controller(character)
	controller.setup(character)

	# 衝突回避用の優先度を設定（直接パスは通常のパスより低い優先度）
	controller.set_movement_priority(_execution_order_counter)
	_execution_order_counter += 1

	# 空のビジョン/Run/Clear/Grenade/Doorポイントでパス開始
	var empty_vision: Array[Dictionary] = []
	var empty_run: Array[Dictionary] = []
	var empty_clear: Array[Dictionary] = []
	var empty_grenade: Array[Dictionary] = []
	var empty_door: Array[Dictionary] = []

	return controller.start_path(path, empty_vision, empty_run, run, empty_clear, empty_grenade, empty_door)


## 特定キャラクターの保留パスをクリア（公開API）
func clear_pending_path_for_character(character: Node) -> void:
	if not character:
		return
	_clear_pending_path_for_character(character.get_instance_id())


## 特定キャラクターの保留パスをクリア（内部）
func _clear_pending_path_for_character(char_id: int) -> void:
	if not pending_paths.has(char_id):
		return

	_free_pending_path_data(pending_paths[char_id])
	pending_paths.erase(char_id)


## 全てのパスメッシュとマーカーを削除
func _clear_all_path_meshes() -> void:
	for char_id in pending_paths:
		_free_pending_path_data(pending_paths[char_id])
	# 延長パスのメッシュも削除
	for char_id in _extension_path_meshes.keys():
		_free_extension_mesh(char_id)
	# アクティブパスメッシュも削除
	for char_id in _active_path_meshes.keys():
		_free_active_path_meshes(char_id)


## pending_pathsのデータからメッシュとマーカーを解放
func _free_pending_path_data(data: Dictionary) -> void:
	if data.has("path_mesh") and is_instance_valid(data["path_mesh"]):
		data["path_mesh"].queue_free()

	# 全マーカータイプを一括解放
	var marker_keys = ["vision_markers", "run_markers", "clear_markers", "grenade_markers", "smoke_grenade_markers", "door_markers", "wait_markers"]
	for key in marker_keys:
		if data.has(key):
			free_marker_meshes(data[key])


## PathDrawerからマーカーデータを取得
func _get_marker_data_from_drawer(path_drawer: Node) -> Dictionary:
	var smoke_grenade = []
	if path_drawer.has_method("get_smoke_grenade_markers"):
		smoke_grenade = path_drawer.get_smoke_grenade_markers().duplicate()

	return {
		"vision": path_drawer.get_vision_points().duplicate(),
		"run": path_drawer.get_run_segments().duplicate(),
		"clear": path_drawer.get_clear_points().duplicate(),
		"grenade": path_drawer.get_grenade_markers().duplicate(),
		"smoke_grenade": smoke_grenade,
		"door": path_drawer.get_door_markers().duplicate(),
		"wait": path_drawer.get_wait_markers().duplicate()
	}


## PathConfirmMessageからマーカーデータを取得
func _get_marker_data_from_path_message(path_msg: NetworkMessages.PathConfirmMessage) -> Dictionary:
	return {
		"vision": _copy_dict_array(path_msg.vision_markers),
		"run": _copy_dict_array(path_msg.run_segments),
		"clear": _copy_dict_array(path_msg.clear_markers),
		"grenade": _copy_dict_array(path_msg.grenade_markers),
		"smoke_grenade": _copy_dict_array(path_msg.smoke_grenade_markers),
		"door": _copy_dict_array(path_msg.door_markers),
		"wait": _copy_dict_array(path_msg.wait_markers)
	}


## 接続線を含むパスを構築
func _build_connected_paths(char_pos: Vector3, base_path: Array[Vector3], display_path: Array[Vector3]) -> Dictionary:
	var path_start = base_path[0] if base_path.size() > 0 else Vector3.ZERO
	var base_length = _calculate_path_length(base_path)

	var full_path: Array[Vector3] = []
	var full_display_path: Array[Vector3] = []
	var connect_length: float = 0.0

	if char_pos.distance_to(path_start) > 0.1:
		full_path.append(char_pos)
		full_display_path.append(char_pos)
		connect_length = char_pos.distance_to(path_start)
	full_path.append_array(base_path)
	full_display_path.append_array(display_path)

	return {
		"full_path": full_path,
		"full_display_path": full_display_path,
		"connect_length": connect_length,
		"base_length": base_length
	}


## 接続線を考慮してマーカーデータを調整
func _adjust_marker_data_for_connection(marker_data: Dictionary, connect_length: float, base_length: float) -> Dictionary:
	return {
		"vision": _adjust_ratios_for_connection(marker_data.get("vision", []), connect_length, base_length),
		"run": _adjust_run_ratios_for_connection(marker_data.get("run", []), connect_length, base_length),
		"clear": _adjust_clear_ratios_for_connection(marker_data.get("clear", []), connect_length, base_length),
		"grenade": _adjust_grenade_ratios_for_connection(marker_data.get("grenade", []), connect_length, base_length),
		"smoke_grenade": _adjust_grenade_ratios_for_connection(marker_data.get("smoke_grenade", []), connect_length, base_length),
		"door": _adjust_door_ratios_for_connection(marker_data.get("door", []), connect_length, base_length),
		"wait": _adjust_wait_ratios_for_connection(marker_data.get("wait", []), connect_length, base_length)
	}


## マーカーを一括生成
func _create_marker_nodes_for_path(path: Array[Vector3], marker_data: Dictionary, character: Node) -> Dictionary:
	return {
		"vision": _create_vision_markers_for_path(path, marker_data.get("vision", []), character),
		"run": _create_run_markers_for_path(path, marker_data.get("run", []), character),
		"clear": _create_clear_markers_for_path(path, marker_data.get("clear", []), character),
		"grenade": _create_grenade_markers_for_path(path, marker_data.get("grenade", []), character),
		"smoke_grenade": _create_smoke_grenade_markers_for_path(path, marker_data.get("smoke_grenade", []), character),
		"door": _create_door_markers_for_path(path, marker_data.get("door", []), character),
		"wait": _create_wait_markers_for_path(path, marker_data.get("wait", []), character)
	}


## PathDrawer側のマーカーメッシュを解放
func _free_drawer_marker_meshes(path_drawer: Node) -> void:
	free_marker_meshes(path_drawer.take_vision_markers())
	free_marker_meshes(path_drawer.take_run_markers())
	free_marker_meshes(path_drawer.take_clear_markers())
	free_marker_meshes(path_drawer.take_grenade_markers())
	if path_drawer.has_method("take_smoke_grenade_markers"):
		free_marker_meshes(path_drawer.take_smoke_grenade_markers())
	free_marker_meshes(path_drawer.take_door_markers())
	free_marker_meshes(path_drawer.take_wait_markers())


## pending_pathsへの登録
func _register_pending_path(
	char_id: int,
	character: Node,
	full_path: Array[Vector3],
	adjusted_markers: Dictionary,
	marker_nodes: Dictionary,
	path_mesh: MeshInstance3D,
	player_id: int = -1
) -> void:
	var pending_data := {
		"character": character,
		"path": full_path,
		"vision_points": adjusted_markers.get("vision", []),
		"run_segments": adjusted_markers.get("run", []),
		"clear_points": adjusted_markers.get("clear", []),
		"grenade_markers_data": adjusted_markers.get("grenade", []),
		"smoke_grenade_markers_data": adjusted_markers.get("smoke_grenade", []),
		"door_markers_data": adjusted_markers.get("door", []),
		"wait_markers_data": adjusted_markers.get("wait", []),
		"path_mesh": path_mesh,
		"vision_markers": marker_nodes.get("vision", []),
		"run_markers": marker_nodes.get("run", []),
		"clear_markers": marker_nodes.get("clear", []),
		"grenade_markers": marker_nodes.get("grenade", []),
		"smoke_grenade_markers": marker_nodes.get("smoke_grenade", []),
		"door_markers": marker_nodes.get("door", []),
		"wait_markers": marker_nodes.get("wait", [])
	}

	if player_id >= 0:
		pending_data["player_id"] = player_id

	pending_paths[char_id] = pending_data


func _copy_vector3_array(source) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for item in source:
		result.append(item)
	return result


func _copy_dict_array(source: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in source:
		result.append(item)
	return result


## パスの長さを計算
func _calculate_path_length(path: Array[Vector3]) -> float:
	var length: float = 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length


## 単一の比率を接続線を考慮して調整（共通ヘルパー）
## @param old_ratio: 元の比率 (0.0 ~ 1.0)
## @param connect_length: 接続線の長さ
## @param base_length: 元のパスの長さ
## @return: 調整後の比率
func _adjust_single_ratio(old_ratio: float, connect_length: float, base_length: float) -> float:
	var new_length = connect_length + base_length
	return (connect_length + old_ratio * base_length) / new_length


## 接続線を考慮して視線ポイントの比率を調整（ターゲットポイントモード対応）
func _adjust_ratios_for_connection(vision_points: Array[Dictionary], connect_length: float, base_length: float) -> Array[Dictionary]:
	if connect_length < 0.01 or base_length < 0.01:
		return vision_points.duplicate()

	var adjusted: Array[Dictionary] = []

	for vp in vision_points:
		var new_ratio: float = _adjust_single_ratio(vp.path_ratio, connect_length, base_length)

		# ターゲットポイントモードか固定方向モードかをチェック
		if vp.has("target_point"):
			adjusted.append({
				"path_ratio": new_ratio,
				"anchor": vp.anchor,
				"target_point": vp.target_point  # ターゲット地点はそのまま（絶対座標）
			})
		elif vp.has("direction"):
			# 後方互換: 固定方向モード
			adjusted.append({
				"path_ratio": new_ratio,
				"anchor": vp.anchor,
				"direction": vp.direction
			})

	return adjusted


## 接続線を考慮してRun区間の比率を調整
func _adjust_run_ratios_for_connection(run_segments: Array[Dictionary], connect_length: float, base_length: float) -> Array[Dictionary]:
	if connect_length < 0.01 or base_length < 0.01:
		return run_segments.duplicate()

	var adjusted: Array[Dictionary] = []

	for seg in run_segments:
		adjusted.append({
			"start_ratio": _adjust_single_ratio(seg.start_ratio, connect_length, base_length),
			"end_ratio": _adjust_single_ratio(seg.end_ratio, connect_length, base_length)
		})

	return adjusted


## パスメッシュを作成（キャラクター色対応）
func _create_path_mesh(path: Array[Vector3], character: Node = null) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	mesh.set_script(PathLineMeshScript)

	# キャラクター色を適用（ない場合はデフォルト水色）
	if character:
		var char_color = CharacterColorManager.get_character_color(character)
		mesh.line_color = Color(char_color.r, char_color.g, char_color.b, 0.8)
	else:
		mesh.line_color = Color(0.3, 0.8, 1.0, 0.8)

	mesh.line_width = 0.04
	_mesh_parent.add_child(mesh)

	# パスを描画
	var packed_path = PackedVector3Array()
	for point in path:
		packed_path.append(point)
	mesh.update_from_points(packed_path)

	return mesh


## path_ratioからパス上の絶対座標を計算
func _calculate_position_on_path(path: Array[Vector3], ratio: float) -> Vector3:
	if path.is_empty():
		return Vector3.ZERO
	if path.size() == 1:
		return path[0]

	# パス全体の長さを計算
	var total_length = _calculate_path_length(path)
	if total_length < 0.001:
		return path[0]

	# ratio位置までの累積距離
	var target_distance = ratio * total_length
	var accumulated: float = 0.0

	for i in range(1, path.size()):
		var segment_length = path[i - 1].distance_to(path[i])
		if accumulated + segment_length >= target_distance:
			# このセグメント内に目標位置がある
			var segment_ratio = (target_distance - accumulated) / segment_length if segment_length > 0 else 0.0
			return path[i - 1].lerp(path[i], segment_ratio)
		accumulated += segment_length

	# ratioが1.0を超える場合は終点を返す
	return path[path.size() - 1]


## anchorが保存されているVisionマーカーの比率を、パス上の位置から再計算
func _recalculate_vision_ratios_from_anchors(path: Array[Vector3], vision_points: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for vp in vision_points:
		var new_vp = vp.duplicate()

		# anchorが保存されている場合、そこからpath_ratioを再計算
		if vp.has("anchor") and vp.anchor != Vector3.ZERO:
			var recalculated_ratio = _calculate_ratio_from_position(path, vp.anchor)
			new_vp["path_ratio"] = recalculated_ratio

		result.append(new_vp)

	return result


## ワールド座標からパス上の比率を計算（最近点を使用）
func _calculate_ratio_from_position(path: Array[Vector3], position: Vector3) -> float:
	if path.is_empty():
		return 0.0
	if path.size() == 1:
		return 0.0

	var total_length = _calculate_path_length(path)
	if total_length < 0.001:
		return 0.0

	# パス上の最近点を見つける
	var best_ratio: float = 0.0
	var best_distance: float = INF
	var accumulated: float = 0.0

	for i in range(1, path.size()):
		var segment_start = path[i - 1]
		var segment_end = path[i]
		var segment_length = segment_start.distance_to(segment_end)

		if segment_length < 0.001:
			accumulated += segment_length
			continue

		# セグメント上の最近点を計算
		var segment_dir = (segment_end - segment_start).normalized()
		var to_pos = position - segment_start
		var proj_length = to_pos.dot(segment_dir)
		proj_length = clamp(proj_length, 0.0, segment_length)

		var closest_point = segment_start + segment_dir * proj_length
		var dist = position.distance_to(closest_point)

		if dist < best_distance:
			best_distance = dist
			best_ratio = (accumulated + proj_length) / total_length

		accumulated += segment_length

	return clamp(best_ratio, 0.0, 1.0)


## 調整済み視線ポイントから新しいVisionMarkerを生成（ターゲットポイントモード対応）
func _create_vision_markers_for_path(
	path: Array[Vector3],
	adjusted_vision_points: Array[Dictionary],
	character: Node
) -> Array[MeshInstance3D]:
	var markers: Array[MeshInstance3D] = []

	for vp in adjusted_vision_points:
		var ratio: float = vp.path_ratio

		# anchorが保存されている場合はそれを使用、なければpath_ratioから計算
		var anchor: Vector3
		if vp.has("anchor") and vp.anchor != Vector3.ZERO:
			anchor = vp.anchor
		else:
			anchor = _calculate_position_on_path(path, ratio)

		# VisionMarkerを作成
		var marker = MeshInstance3D.new()
		marker.set_script(VisionMarkerScript)
		_mesh_parent.add_child(marker)

		# キャラクター色を取得
		var char_color = CharacterColorManager.get_character_color(character)
		var bg_color = Color(char_color.r * 0.3, char_color.g * 0.3, char_color.b * 0.3, 0.95)

		# ターゲットポイントモードか固定方向モードかをチェック
		if vp.has("target_point"):
			# ターゲットポイントモード
			marker.set_position_and_target(anchor, vp.target_point)
			# ターゲット線の色を設定
			marker.set_target_line_color(Color(char_color.r, char_color.g * 0.7, char_color.b * 0.5, 0.8))
		elif vp.has("direction"):
			# 後方互換: 固定方向モード
			marker.set_position_and_direction(anchor, vp.direction)

		# 背景は暗い色、矢印はキャラクター色
		marker.set_colors(bg_color, char_color)

		markers.append(marker)

	return markers


## 調整済みRun区間から新しいRunMarkerを生成
func _create_run_markers_for_path(
	path: Array[Vector3],
	adjusted_run_segments: Array[Dictionary],
	character: Node
) -> Array[MeshInstance3D]:
	var markers: Array[MeshInstance3D] = []

	for seg in adjusted_run_segments:
		var start_ratio: float = seg.start_ratio
		var end_ratio: float = seg.end_ratio

		# パス上の位置を計算
		var start_pos = _calculate_position_on_path(path, start_ratio)
		var end_pos = _calculate_position_on_path(path, end_ratio)

		# キャラクター色を取得
		var char_color = CharacterColorManager.get_character_color(character)

		# STARTマーカーを作成
		var start_marker = MeshInstance3D.new()
		start_marker.set_script(RunMarkerScript)
		_mesh_parent.add_child(start_marker)
		start_marker.set_position_and_type(start_pos, 0)  # 0 = MarkerType.START
		start_marker.set_colors(char_color, Color.WHITE)
		markers.append(start_marker)

		# ENDマーカーを作成
		var end_marker = MeshInstance3D.new()
		end_marker.set_script(RunMarkerScript)
		_mesh_parent.add_child(end_marker)
		end_marker.set_position_and_type(end_pos, 1)  # 1 = MarkerType.END
		# 終点は少し暗い色に
		var end_bg_color = Color(char_color.r * 0.8, char_color.g * 0.5, char_color.b * 0.3, 0.95)
		end_marker.set_colors(end_bg_color, Color.WHITE)
		markers.append(end_marker)

	return markers


## 接続線を考慮してClearポイントの比率を調整
func _adjust_clear_ratios_for_connection(clear_points: Array[Dictionary], connect_length: float, base_length: float) -> Array[Dictionary]:
	if connect_length < 0.01 or base_length < 0.01:
		return clear_points.duplicate()

	var adjusted: Array[Dictionary] = []

	for cp in clear_points:
		adjusted.append({
			"path_ratio": _adjust_single_ratio(cp.path_ratio, connect_length, base_length)
		})

	return adjusted


## 調整済みClearポイントから新しいClearMarkerを生成
func _create_clear_markers_for_path(
	path: Array[Vector3],
	adjusted_clear_points: Array[Dictionary],
	character: Node
) -> Array[MeshInstance3D]:
	var markers: Array[MeshInstance3D] = []

	for cp in adjusted_clear_points:
		var ratio: float = cp.path_ratio

		# パス上の位置を計算
		var pos = _calculate_position_on_path(path, ratio)

		# ClearMarkerを作成
		var marker = MeshInstance3D.new()
		marker.set_script(ClearMarkerScript)
		_mesh_parent.add_child(marker)

		# 位置を設定
		marker.set_marker_position(pos)

		# キャラクター色を取得して適用
		var char_color = CharacterColorManager.get_character_color(character)
		marker.set_colors(char_color, Color.WHITE)

		markers.append(marker)

	return markers


## 接続線を考慮してグレネードマーカーの比率を調整
func _adjust_grenade_ratios_for_connection(grenade_markers: Array[Dictionary], connect_length: float, base_length: float) -> Array[Dictionary]:
	if connect_length < 0.01 or base_length < 0.01:
		return grenade_markers.duplicate()

	var adjusted: Array[Dictionary] = []

	for gm in grenade_markers:
		var new_marker: Dictionary = {
			"path_ratio": _adjust_single_ratio(gm.path_ratio, connect_length, base_length),
			"anchor": gm.anchor,
			"target_pos": gm.target_pos
		}
		# バウンスポイントがある場合はコピー
		if gm.has("bounce_point"):
			new_marker["bounce_point"] = gm.bounce_point
		if gm.has("bounce_normal"):
			new_marker["bounce_normal"] = gm.bounce_normal
		adjusted.append(new_marker)

	return adjusted


## 接続線を考慮してドアマーカーの比率を調整
func _adjust_door_ratios_for_connection(door_markers: Array[Dictionary], connect_length: float, base_length: float) -> Array[Dictionary]:
	if connect_length < 0.01 or base_length < 0.01:
		return door_markers.duplicate()

	var adjusted: Array[Dictionary] = []

	for dm in door_markers:
		adjusted.append({
			"path_ratio": _adjust_single_ratio(dm.path_ratio, connect_length, base_length),
			"door_node": dm.door_node if dm.has("door_node") else dm.get("door")
		})

	return adjusted


## 調整済みグレネードマーカーから新しいGrenadeMarkerを生成
func _create_grenade_markers_for_path(
	path: Array[Vector3],
	adjusted_grenade_markers: Array[Dictionary],
	character: Node
) -> Array[MeshInstance3D]:
	var markers: Array[MeshInstance3D] = []

	for gm in adjusted_grenade_markers:
		var ratio: float = gm.path_ratio

		# パス上の位置を計算
		var anchor = _calculate_position_on_path(path, ratio)

		# GrenadeMarkerを作成
		var marker = MeshInstance3D.new()
		marker.set_script(GrenadeMarkerScript)
		_mesh_parent.add_child(marker)

		# バウンスポイントがあるかチェック
		var bounce_point = Vector3.ZERO
		if gm.has("bounce_point"):
			bounce_point = gm.bounce_point

		# 位置とターゲットを設定
		marker.set_position_and_target(anchor, gm.target_pos, bounce_point)

		# キャラクター色を取得して適用（背景色は暗く、アイコン色はキャラクター色）
		var char_color = CharacterColorManager.get_character_color(character)
		marker.set_colors(Color(0.1, 0.1, 0.1, 0.95), char_color)

		markers.append(marker)

	return markers


## 調整済みスモークグレネードマーカーから新しいSmokeGrenadeMarkerを生成
func _create_smoke_grenade_markers_for_path(
	path: Array[Vector3],
	adjusted_smoke_grenade_markers: Array[Dictionary],
	_character: Node
) -> Array[MeshInstance3D]:
	var markers: Array[MeshInstance3D] = []

	for sgm in adjusted_smoke_grenade_markers:
		var ratio: float = sgm.path_ratio

		# パス上の位置を計算
		var anchor = _calculate_position_on_path(path, ratio)

		# SmokeGrenadeMarkerを作成
		var marker = MeshInstance3D.new()
		marker.set_script(SmokeGrenadeMarkerScript)
		_mesh_parent.add_child(marker)

		# バウンスポイントがあるかチェック
		var bounce_point = Vector3.ZERO
		if sgm.has("bounce_point"):
			bounce_point = sgm.bounce_point

		# 位置とターゲットを設定
		marker.set_position_and_target(anchor, sgm.target_pos, bounce_point)

		# スモークグレネードは灰色/白色（デフォルト設定を使用）

		markers.append(marker)

	return markers


## 調整済みドアマーカーから新しいDoorMarkerを生成
func _create_door_markers_for_path(
	path: Array[Vector3],
	adjusted_door_markers: Array[Dictionary],
	character: Node
) -> Array[MeshInstance3D]:
	var markers: Array[MeshInstance3D] = []

	for dm in adjusted_door_markers:
		var ratio: float = dm.path_ratio

		# パス上の位置を計算
		var anchor = _calculate_position_on_path(path, ratio)

		# DoorMarkerを作成
		var marker = MeshInstance3D.new()
		marker.set_script(DoorMarkerScript)
		_mesh_parent.add_child(marker)

		# ドアノードを取得（door_nodeキー）
		var door_node = dm.door_node if dm.has("door_node") else dm.get("door")

		# 位置とドアを設定
		marker.set_position_and_door(anchor, door_node)

		# キャラクター色を取得して適用（背景色は暗く、アイコン色はキャラクター色）
		var char_color = CharacterColorManager.get_character_color(character)
		marker.set_colors(Color(0.1, 0.1, 0.1, 0.95), char_color)

		markers.append(marker)

	return markers


## 接続線を考慮してWaitマーカーの比率を調整
func _adjust_wait_ratios_for_connection(wait_markers: Array[Dictionary], connect_length: float, base_length: float) -> Array[Dictionary]:
	if connect_length < 0.01 or base_length < 0.01:
		return wait_markers.duplicate()

	var adjusted: Array[Dictionary] = []

	for wm in wait_markers:
		adjusted.append({
			"path_ratio": _adjust_single_ratio(wm.path_ratio, connect_length, base_length),
			"anchor": wm.get("anchor", Vector3.ZERO),
			"wait_duration": wm.get("wait_duration", 1.0)
		})

	return adjusted


## 調整済みWaitマーカーから新しいWaitMarkerを生成
func _create_wait_markers_for_path(
	path: Array[Vector3],
	adjusted_wait_markers: Array[Dictionary],
	character: Node
) -> Array[MeshInstance3D]:
	var markers: Array[MeshInstance3D] = []

	for wm in adjusted_wait_markers:
		var ratio: float = wm.path_ratio

		# パス上の位置を計算
		var anchor = _calculate_position_on_path(path, ratio)

		# WaitMarkerを作成
		var marker = MeshInstance3D.new()
		marker.set_script(WaitMarkerScript)
		_mesh_parent.add_child(marker)

		# 位置を設定
		marker.set_marker_position(anchor)

		# 待機時間を設定
		var duration = wm.get("wait_duration", 1.0)
		marker.set_wait_duration(duration)

		# キャラクター色を取得して適用（背景色はキャラクター色、アイコン色は白）
		var char_color = CharacterColorManager.get_character_color(character)
		marker.set_colors(char_color, Color(1.0, 1.0, 1.0, 1.0))

		markers.append(marker)

	return markers


#region 統一マーカーAPI
## マーカータイプのエイリアス
const MarkerType = ActionMarkerDataScript.Type


## 指定タイプのマーカー比率を一括調整
func adjust_marker_ratios_for_type(
	marker_data: Array[Dictionary],
	marker_type: int,
	connect_length: float,
	base_length: float
) -> Array[Dictionary]:
	match marker_type:
		MarkerType.VISION:
			return _adjust_ratios_for_connection(marker_data, connect_length, base_length)
		MarkerType.RUN:
			return _adjust_run_ratios_for_connection(marker_data, connect_length, base_length)
		MarkerType.CLEAR:
			return _adjust_clear_ratios_for_connection(marker_data, connect_length, base_length)
		MarkerType.GRENADE:
			return _adjust_grenade_ratios_for_connection(marker_data, connect_length, base_length)
		MarkerType.DOOR:
			return _adjust_door_ratios_for_connection(marker_data, connect_length, base_length)
		_:
			return marker_data.duplicate()


## 指定タイプのマーカーを一括生成
func create_markers_for_type(
	path: Array[Vector3],
	marker_data: Array[Dictionary],
	marker_type: int,
	character: Node
) -> Array[MeshInstance3D]:
	match marker_type:
		MarkerType.VISION:
			return _create_vision_markers_for_path(path, marker_data, character)
		MarkerType.RUN:
			return _create_run_markers_for_path(path, marker_data, character)
		MarkerType.CLEAR:
			return _create_clear_markers_for_path(path, marker_data, character)
		MarkerType.GRENADE:
			return _create_grenade_markers_for_path(path, marker_data, character)
		MarkerType.DOOR:
			return _create_door_markers_for_path(path, marker_data, character)
		_:
			return []


## PathDrawerから統一APIでマーカーデータを取得
func get_all_markers_from_drawer(path_drawer: Node, is_multi_mode: bool) -> Dictionary:
	var result: Dictionary = {}

	for type_value in MarkerType.values():
		if is_multi_mode:
			result[type_value] = {
				"data": path_drawer.get_all_markers_by_type(type_value),
				"meshes": path_drawer.take_all_markers_by_type(type_value)
			}
		else:
			result[type_value] = {
				"data": path_drawer.get_markers_by_type(type_value).duplicate(),
				"meshes": path_drawer.take_markers_by_type(type_value)
			}

	return result


## マーカーメッシュを一括削除
func free_marker_meshes(meshes: Array) -> void:
	for mesh in meshes:
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
#endregion


# ============================================
# Multiplayer API
# ============================================

## プレイヤーIDでパスを確定（ネットワーク同期用）
## PathConfirmMessageから直接パスを登録する
func confirm_path_for_player(
	player_id: int,
	path_msg: NetworkMessages.PathConfirmMessage,
	character: Node
) -> bool:
	if not character or path_msg.path.is_empty():
		return false

	var char_id = character.get_instance_id()
	var char_pos = character.global_position

	var base_path := _copy_vector3_array(path_msg.path)

	# 既存のパスがあれば削除
	_clear_pending_path_for_character(char_id)

	# 接続線を含むパスを作成
	var connected := _build_connected_paths(char_pos, base_path, base_path)
	var full_path: Array[Vector3] = connected.full_path
	var connect_length: float = connected.connect_length
	var base_length: float = connected.base_length

	# マーカーデータを変換
	var marker_data := _get_marker_data_from_path_message(path_msg)

	# マーカーの比率を再計算
	var adjusted_markers := _adjust_marker_data_for_connection(marker_data, connect_length, base_length)

	# anchorが保存されているVisionマーカーの比率を、実際のパス上の位置から再計算
	adjusted_markers["vision"] = _recalculate_vision_ratios_from_anchors(full_path, adjusted_markers.get("vision", []))

	# パスメッシュを作成
	var path_mesh = _create_path_mesh(full_path, character)

	# マーカーを生成
	var marker_nodes := _create_marker_nodes_for_path(full_path, adjusted_markers, character)

	_register_pending_path(char_id, character, full_path, adjusted_markers, marker_nodes, path_mesh, player_id)

	# プレイヤーごとのパス管理に追加
	if not _pending_paths_by_player.has(player_id):
		_pending_paths_by_player[player_id] = {}
	_pending_paths_by_player[player_id][char_id] = path_msg

	path_confirmed.emit(1)
	return true


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
		_clear_pending_path_for_character(char_id)

	_pending_paths_by_player.erase(player_id)


## 保留パスをPathConfirmMessageに変換
func to_path_confirm_message(character: Node, player_id: int) -> NetworkMessages.PathConfirmMessage:
	if not character:
		return null

	var char_id = character.get_instance_id()
	if not pending_paths.has(char_id):
		return null

	var data: Dictionary = pending_paths[char_id]
	var msg := NetworkMessages.PathConfirmMessage.new()
	msg.player_id = player_id
	msg.character_id = char_id
	msg.timestamp = Time.get_ticks_msec()

	# パスをコピー
	if data.has("path"):
		for p in data["path"]:
			msg.path.append(p)

	# マーカーデータをコピー
	if data.has("vision_points"):
		msg.vision_markers.assign(data["vision_points"])
	if data.has("run_segments"):
		msg.run_segments.assign(data["run_segments"])
	if data.has("clear_points"):
		msg.clear_markers.assign(data["clear_points"])
	if data.has("grenade_markers_data"):
		msg.grenade_markers.assign(data["grenade_markers_data"])
	if data.has("smoke_grenade_markers_data"):
		msg.smoke_grenade_markers.assign(data["smoke_grenade_markers_data"])
	if data.has("door_markers_data"):
		msg.door_markers.assign(data["door_markers_data"])
	if data.has("wait_markers_data"):
		msg.wait_markers.assign(data["wait_markers_data"])

	return msg


## 全保留パスをPathConfirmMessage配列に変換
func get_all_pending_paths_as_messages(player_id: int) -> Array[NetworkMessages.PathConfirmMessage]:
	var result: Array[NetworkMessages.PathConfirmMessage] = []

	for char_id in pending_paths:
		var data = pending_paths[char_id]
		if not data.has("character"):
			continue

		var character = data["character"]
		var msg = to_path_confirm_message(character, player_id)
		if msg:
			result.append(msg)

	return result


## パス実行状態をPathSnapshotに変換
func get_path_snapshot(character: Node) -> SyncState.PathSnapshot:
	if not character:
		return null

	var char_id = character.get_instance_id()
	var snapshot := SyncState.PathSnapshot.new()
	snapshot.character_id = char_id
	snapshot.timestamp = Time.get_ticks_msec()

	# 実行中かどうか
	if _path_controllers.has(char_id):
		var controller = _path_controllers[char_id]
		snapshot.is_executing = controller.is_following_path()
		if controller.has_method("get_current_progress"):
			snapshot.progress = controller.get_current_progress()

	# 元のパスメッセージを参照
	if _pending_paths_by_player.has(PlayerState.get_local_peer_id()):
		var player_paths = _pending_paths_by_player[PlayerState.get_local_peer_id()]
		if player_paths.has(char_id):
			snapshot.path_message = player_paths[char_id]

	return snapshot
