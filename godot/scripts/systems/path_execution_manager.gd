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

## 保留中のパス（キャラクターごと）
## { character_id: { "character": Node, "path": Array[Vector3], "vision_points": Array, "run_segments": Array, "clear_points": Array,
##                   "grenade_markers_data": Array, "smoke_grenade_markers_data": Array, "door_markers_data": Array, "wait_markers_data": Array,
##                   "path_mesh": Node3D, "vision_markers": Array, "run_markers": Array, "clear_markers": Array,
##                   "grenade_markers": Array, "smoke_grenade_markers": Array, "door_markers": Array, "wait_markers": Array } }
var pending_paths: Dictionary = {}

## パス追従コントローラー { character_id -> PathFollowingController }
var _path_controllers: Dictionary = {}

## パスメッシュを追加する親ノード
var _mesh_parent: Node3D = null


## セットアップ
func setup(mesh_parent: Node3D) -> void:
	_mesh_parent = mesh_parent


## パスを確定して保存（対象キャラクターに同じパスを適用）
## マルチキャラクターモードの場合、各キャラクター固有のマーカーを適用
func confirm_path(
	target_characters: Array[Node],
	path_drawer: Node,
	_primary_character: Node
) -> bool:
	if not path_drawer.has_pending_path():
		return false

	if target_characters.is_empty():
		return false

	# 表示用パス（生パス）を取得
	var display_path: Array[Vector3] = []
	var drawn = path_drawer.get_drawn_path()
	for point in drawn:
		display_path.append(point)

	# 移動用パス（スムージング済み）を取得
	var base_path: Array[Vector3] = []
	var pending = path_drawer.get_smoothed_path()
	for point in pending:
		base_path.append(point)

	# マルチキャラクターモードかどうかで処理を分岐
	var is_multi_mode = path_drawer.is_multi_character_mode()

	# マルチモードの場合、キャラクター別のマーカーを取得
	var all_vision_points: Dictionary = {}
	var all_run_segments: Dictionary = {}
	var all_clear_points: Dictionary = {}
	var all_grenade_markers_data: Dictionary = {}
	var all_smoke_grenade_markers_data: Dictionary = {}
	var all_door_markers_data: Dictionary = {}
	var all_wait_markers_data: Dictionary = {}
	var all_vision_markers: Dictionary = {}
	var all_run_markers: Dictionary = {}
	var all_clear_markers: Dictionary = {}
	var all_grenade_markers: Dictionary = {}
	var all_smoke_grenade_markers: Dictionary = {}
	var all_door_markers: Dictionary = {}
	var all_wait_markers: Dictionary = {}

	if is_multi_mode:
		all_vision_points = path_drawer.get_all_vision_points()
		all_run_segments = path_drawer.get_all_run_segments()
		all_clear_points = path_drawer.get_all_clear_points()
		all_grenade_markers_data = path_drawer.get_all_grenade_markers()
		all_smoke_grenade_markers_data = path_drawer.get_all_smoke_grenade_markers()
		all_door_markers_data = path_drawer.get_all_door_markers()
		all_wait_markers_data = path_drawer.get_all_wait_markers()
		all_vision_markers = path_drawer.take_all_vision_markers()
		all_run_markers = path_drawer.take_all_run_markers()
		all_clear_markers = path_drawer.take_all_clear_markers()
		all_grenade_markers = path_drawer.take_all_grenade_markers()
		if path_drawer.has_method("take_all_smoke_grenade_markers"):
			all_smoke_grenade_markers = path_drawer.take_all_smoke_grenade_markers()
		all_door_markers = path_drawer.take_all_door_markers()
		# Note: Waitマーカーのメッシュは別途取得（take_all_wait_markersがあれば）
		if path_drawer.has_method("take_all_wait_markers"):
			all_wait_markers = path_drawer.take_all_wait_markers()
	else:
		# シングルモードの場合、従来通り
		var base_vision = path_drawer.get_vision_points().duplicate()
		var base_run = path_drawer.get_run_segments().duplicate()
		var base_clear = path_drawer.get_clear_points().duplicate()
		var base_grenade = path_drawer.get_grenade_markers().duplicate()
		var base_smoke_grenade = path_drawer.get_smoke_grenade_markers().duplicate()
		var base_door = path_drawer.get_door_markers().duplicate()
		var base_wait = path_drawer.get_wait_markers().duplicate()
		var original_vision_markers = path_drawer.take_vision_markers()
		var original_run_markers = path_drawer.take_run_markers()
		var original_clear_markers = path_drawer.take_clear_markers()
		var original_grenade_markers = path_drawer.take_grenade_markers()
		var original_smoke_grenade_markers = path_drawer.take_smoke_grenade_markers() if path_drawer.has_method("take_smoke_grenade_markers") else []
		var original_door_markers = path_drawer.take_door_markers()
		var original_wait_markers = path_drawer.take_wait_markers()

		# 全キャラクターに同じマーカーを適用するため、一時的に格納
		for character in target_characters:
			var cid = character.get_instance_id()
			all_vision_points[cid] = base_vision.duplicate()
			all_run_segments[cid] = base_run.duplicate()
			all_clear_points[cid] = base_clear.duplicate()
			all_grenade_markers_data[cid] = base_grenade.duplicate()
			all_smoke_grenade_markers_data[cid] = base_smoke_grenade.duplicate()
			all_door_markers_data[cid] = base_door.duplicate()
			all_wait_markers_data[cid] = base_wait.duplicate()

		# 元のマーカーは後で削除
		free_marker_meshes(original_vision_markers)
		free_marker_meshes(original_run_markers)
		free_marker_meshes(original_clear_markers)
		free_marker_meshes(original_grenade_markers)
		free_marker_meshes(original_smoke_grenade_markers)
		free_marker_meshes(original_door_markers)
		free_marker_meshes(original_wait_markers)

	var path_start = base_path[0] if base_path.size() > 0 else Vector3.ZERO

	# 元のパスの長さを計算
	var base_length = _calculate_path_length(base_path)

	# 対象キャラクターにパスを適用
	var processed_count = 0

	for character in target_characters:
		var char_id = character.get_instance_id()
		var char_pos = Vector3(character.global_position.x, 0, character.global_position.z)

		# 既存のパスがあれば削除
		_clear_pending_path_for_character(char_id)

		# キャラクター位置からパス開始点への接続を含むパスを作成
		var full_path: Array[Vector3] = []  # 移動用（スムージング済み）
		var full_display_path: Array[Vector3] = []  # 表示用（生パス）
		var connect_length: float = 0.0

		if char_pos.distance_to(path_start) > 0.1:
			# キャラクターがパス開始点にいない場合、接続線を追加
			full_path.append(char_pos)
			full_display_path.append(char_pos)
			connect_length = char_pos.distance_to(path_start)
		full_path.append_array(base_path)
		full_display_path.append_array(display_path)

		# キャラクター固有の視線ポイントとRun区間を取得
		var char_vision_points: Array[Dictionary] = []
		if all_vision_points.has(char_id):
			for vp in all_vision_points[char_id]:
				char_vision_points.append(vp)

		var char_run_segments: Array[Dictionary] = []
		if all_run_segments.has(char_id):
			for seg in all_run_segments[char_id]:
				char_run_segments.append(seg)

		var char_clear_points: Array[Dictionary] = []
		if all_clear_points.has(char_id):
			for cp in all_clear_points[char_id]:
				char_clear_points.append(cp)

		var char_grenade_markers: Array[Dictionary] = []
		if all_grenade_markers_data.has(char_id):
			for gm in all_grenade_markers_data[char_id]:
				char_grenade_markers.append(gm)

		var char_smoke_grenade_markers: Array[Dictionary] = []
		if all_smoke_grenade_markers_data.has(char_id):
			for sgm in all_smoke_grenade_markers_data[char_id]:
				char_smoke_grenade_markers.append(sgm)

		var char_door_markers: Array[Dictionary] = []
		if all_door_markers_data.has(char_id):
			for dm in all_door_markers_data[char_id]:
				char_door_markers.append(dm)

		var char_wait_markers: Array[Dictionary] = []
		if all_wait_markers_data.has(char_id):
			for wm in all_wait_markers_data[char_id]:
				char_wait_markers.append(wm)

		# 視線ポイントとRun区間とClearポイントとグレネード/スモークグレネード/ドア/Waitマーカーの比率を再計算
		var adjusted_vision_points = _adjust_ratios_for_connection(char_vision_points, connect_length, base_length)
		var adjusted_run_segments = _adjust_run_ratios_for_connection(char_run_segments, connect_length, base_length)
		var adjusted_clear_points = _adjust_clear_ratios_for_connection(char_clear_points, connect_length, base_length)
		var adjusted_grenade_markers = _adjust_grenade_ratios_for_connection(char_grenade_markers, connect_length, base_length)
		var adjusted_smoke_grenade_markers = _adjust_grenade_ratios_for_connection(char_smoke_grenade_markers, connect_length, base_length)
		var adjusted_door_markers = _adjust_door_ratios_for_connection(char_door_markers, connect_length, base_length)
		var adjusted_wait_markers = _adjust_wait_ratios_for_connection(char_wait_markers, connect_length, base_length)

		# パスメッシュを作成（表示用の生パスを使用）
		var path_mesh = _create_path_mesh(full_display_path, character)

		# マルチモードの場合、元のマーカーを削除して新しいマーカーを生成
		if is_multi_mode:
			if all_vision_markers.has(char_id):
				free_marker_meshes(all_vision_markers[char_id])
			if all_run_markers.has(char_id):
				free_marker_meshes(all_run_markers[char_id])
			if all_clear_markers.has(char_id):
				free_marker_meshes(all_clear_markers[char_id])
			if all_grenade_markers.has(char_id):
				free_marker_meshes(all_grenade_markers[char_id])
			if all_smoke_grenade_markers.has(char_id):
				free_marker_meshes(all_smoke_grenade_markers[char_id])
			if all_door_markers.has(char_id):
				free_marker_meshes(all_door_markers[char_id])
			if all_wait_markers.has(char_id):
				free_marker_meshes(all_wait_markers[char_id])

		# 各キャラクター用にマーカーを新規生成
		var char_vision_markers_nodes = _create_vision_markers_for_path(
			full_path, adjusted_vision_points, character
		)
		var char_run_markers_nodes = _create_run_markers_for_path(
			full_path, adjusted_run_segments, character
		)
		var char_clear_markers_nodes = _create_clear_markers_for_path(
			full_path, adjusted_clear_points, character
		)
		var char_grenade_markers_nodes = _create_grenade_markers_for_path(
			full_path, adjusted_grenade_markers, character
		)
		var char_smoke_grenade_markers_nodes = _create_smoke_grenade_markers_for_path(
			full_path, adjusted_smoke_grenade_markers, character
		)
		var char_door_markers_nodes = _create_door_markers_for_path(
			full_path, adjusted_door_markers, character
		)
		var char_wait_markers_nodes = _create_wait_markers_for_path(
			full_path, adjusted_wait_markers, character
		)

		pending_paths[char_id] = {
			"character": character,
			"path": full_path,
			"vision_points": adjusted_vision_points,
			"run_segments": adjusted_run_segments,
			"clear_points": adjusted_clear_points,
			"grenade_markers_data": adjusted_grenade_markers,
			"smoke_grenade_markers_data": adjusted_smoke_grenade_markers,
			"door_markers_data": adjusted_door_markers,
			"wait_markers_data": adjusted_wait_markers,
			"path_mesh": path_mesh,
			"vision_markers": char_vision_markers_nodes,
			"run_markers": char_run_markers_nodes,
			"clear_markers": char_clear_markers_nodes,
			"grenade_markers": char_grenade_markers_nodes,
			"smoke_grenade_markers": char_smoke_grenade_markers_nodes,
			"door_markers": char_door_markers_nodes,
			"wait_markers": char_wait_markers_nodes
		}

		processed_count += 1
	path_confirmed.emit(processed_count)
	return true


## 全キャラクターのパスを同時実行
func execute_all_paths(run: bool) -> int:
	if pending_paths.is_empty():
		return 0

	var executed_count = 0
	for char_id in pending_paths:
		var data = pending_paths[char_id]
		# 既に実行済み（characterキーなし）のエントリはスキップ
		if not data.has("character"):
			continue
		var character = data["character"] as CharacterBody3D

		# パスを明示的にArray[Vector3]に変換
		var path: Array[Vector3] = []
		if data.has("path"):
			for p in data["path"]:
				path.append(p)

		# 視線ポイントを明示的にArray[Dictionary]に変換
		var vision_points: Array[Dictionary] = []
		if data.has("vision_points"):
			for vp in data["vision_points"]:
				vision_points.append(vp)

		# Run区間を明示的にArray[Dictionary]に変換
		var run_segments: Array[Dictionary] = []
		if data.has("run_segments"):
			for seg in data["run_segments"]:
				run_segments.append(seg)

		# Clearポイントを明示的にArray[Dictionary]に変換
		var clear_points: Array[Dictionary] = []
		if data.has("clear_points"):
			for cp in data["clear_points"]:
				clear_points.append(cp)

		# グレネードマーカーを明示的にArray[Dictionary]に変換
		var grenade_markers_data: Array[Dictionary] = []
		if data.has("grenade_markers_data"):
			for gm in data["grenade_markers_data"]:
				grenade_markers_data.append(gm)

		# スモークグレネードマーカーを明示的にArray[Dictionary]に変換
		var smoke_grenade_markers_data: Array[Dictionary] = []
		if data.has("smoke_grenade_markers_data"):
			for sgm in data["smoke_grenade_markers_data"]:
				smoke_grenade_markers_data.append(sgm)

		# ドアマーカーを明示的にArray[Dictionary]に変換
		var door_markers_data: Array[Dictionary] = []
		if data.has("door_markers_data"):
			for dm in data["door_markers_data"]:
				door_markers_data.append(dm)

		# Waitマーカーを明示的にArray[Dictionary]に変換
		var wait_markers_data: Array[Dictionary] = []
		if data.has("wait_markers_data"):
			for wm in data["wait_markers_data"]:
				wait_markers_data.append(wm)

		if not is_instance_valid(character):
			continue

		# コントローラーを取得または作成
		var controller = _get_or_create_path_controller(character)
		controller.setup(character)

		if controller.start_path(path, vision_points, run_segments, run, clear_points, grenade_markers_data, door_markers_data, wait_markers_data, smoke_grenade_markers_data):
			executed_count += 1

	# パスデータのみクリア（メッシュは残す）
	for char_id in pending_paths:
		var data = pending_paths[char_id]
		data.erase("path")
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


## パス追従中のコントローラーがあるかチェック
func is_any_path_following_active() -> bool:
	for controller in _path_controllers.values():
		if controller.is_following_path():
			return true
	return false


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

	# Connect combat awareness for automatic enemy aiming during movement
	if character.combat_awareness:
		controller.set_combat_awareness(character.combat_awareness)

	_path_controllers[char_id] = controller
	return controller


func _on_path_completed(character: Node) -> void:
	character_path_completed.emit(character)
	on_path_following_completed(character)


func _on_path_cancelled(_character: Node) -> void:
	pass


func _on_grenade_marker_reached(_index: int, marker_data: Dictionary, character: Node) -> void:
	grenade_marker_reached.emit(character, marker_data)


func _on_smoke_grenade_marker_reached(_index: int, marker_data: Dictionary, character: Node) -> void:
	smoke_grenade_marker_reached.emit(character, marker_data)


func _on_door_marker_reached(_index: int, door: Node3D, character: Node) -> void:
	door_marker_reached.emit(character, door)


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

	# 空のビジョン/Run/Clear/Grenade/Doorポイントでパス開始
	var empty_vision: Array[Dictionary] = []
	var empty_run: Array[Dictionary] = []
	var empty_clear: Array[Dictionary] = []
	var empty_grenade: Array[Dictionary] = []
	var empty_door: Array[Dictionary] = []

	return controller.start_path(path, empty_vision, empty_run, run, empty_clear, empty_grenade, empty_door)


## 特定キャラクターの保留パスをクリア
func _clear_pending_path_for_character(char_id: int) -> void:
	if not pending_paths.has(char_id):
		return

	_free_pending_path_data(pending_paths[char_id])
	pending_paths.erase(char_id)


## 全てのパスメッシュとマーカーを削除
func _clear_all_path_meshes() -> void:
	for char_id in pending_paths:
		_free_pending_path_data(pending_paths[char_id])


## pending_pathsのデータからメッシュとマーカーを解放
func _free_pending_path_data(data: Dictionary) -> void:
	if data.has("path_mesh") and is_instance_valid(data["path_mesh"]):
		data["path_mesh"].queue_free()

	# 全マーカータイプを一括解放
	var marker_keys = ["vision_markers", "run_markers", "clear_markers", "grenade_markers", "smoke_grenade_markers", "door_markers", "wait_markers"]
	for key in marker_keys:
		if data.has(key):
			free_marker_meshes(data[key])


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


## 調整済み視線ポイントから新しいVisionMarkerを生成（ターゲットポイントモード対応）
func _create_vision_markers_for_path(
	path: Array[Vector3],
	adjusted_vision_points: Array[Dictionary],
	character: Node
) -> Array[MeshInstance3D]:
	var markers: Array[MeshInstance3D] = []

	for vp in adjusted_vision_points:
		var ratio: float = vp.path_ratio

		# パス上の位置を計算
		var anchor = _calculate_position_on_path(path, ratio)

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
