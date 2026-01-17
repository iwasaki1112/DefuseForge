extends Node
class_name PathExecutionManager
## パス実行管理
## パス確定・実行・pending_paths管理を担当

const PathLineMeshScript = preload("res://scripts/effects/path_line_mesh.gd")
const PathFollowingCtrl = preload("res://scripts/characters/path_following_controller.gd")
const VisionMarkerScript = preload("res://scripts/effects/vision_marker.gd")
const RunMarkerScript = preload("res://scripts/effects/run_marker.gd")

## パス確定時のシグナル
signal path_confirmed(character_count: int)
## 全パス実行開始時のシグナル
signal paths_execution_started(count: int)
## 全パス完了時のシグナル
signal all_paths_completed()
## パスクリア時のシグナル
signal paths_cleared()

## 保留中のパス（キャラクターごと）
## { character_id: { "character": Node, "path": Array[Vector3], "vision_points": Array, "run_segments": Array, "path_mesh": Node3D, "vision_markers": Array, "run_markers": Array } }
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
	primary_character: Node
) -> bool:
	if not path_drawer.has_pending_path():
		return false

	if target_characters.is_empty():
		print("[PathExecution] No target characters for path")
		return false

	# パス情報を取得（絶対座標のまま）
	var base_path: Array[Vector3] = []
	var pending = path_drawer.get_drawn_path()
	for point in pending:
		base_path.append(point)

	# マルチキャラクターモードかどうかで処理を分岐
	var is_multi_mode = path_drawer.is_multi_character_mode()

	# マルチモードの場合、キャラクター別のマーカーを取得
	var all_vision_points: Dictionary = {}
	var all_run_segments: Dictionary = {}
	var all_vision_markers: Dictionary = {}
	var all_run_markers: Dictionary = {}

	if is_multi_mode:
		all_vision_points = path_drawer.get_all_vision_points()
		all_run_segments = path_drawer.get_all_run_segments()
		all_vision_markers = path_drawer.take_all_vision_markers()
		all_run_markers = path_drawer.take_all_run_markers()
	else:
		# シングルモードの場合、従来通り
		var base_vision = path_drawer.get_vision_points().duplicate()
		var base_run = path_drawer.get_run_segments().duplicate()
		var original_vision_markers = path_drawer.take_vision_markers()
		var original_run_markers = path_drawer.take_run_markers()

		# 全キャラクターに同じマーカーを適用するため、一時的に格納
		for character in target_characters:
			var cid = character.get_instance_id()
			all_vision_points[cid] = base_vision.duplicate()
			all_run_segments[cid] = base_run.duplicate()

		# 元のマーカーは後で削除
		for marker in original_vision_markers:
			if is_instance_valid(marker):
				marker.queue_free()
		for marker in original_run_markers:
			if is_instance_valid(marker):
				marker.queue_free()

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
		var full_path: Array[Vector3] = []
		var connect_length: float = 0.0

		if char_pos.distance_to(path_start) > 0.1:
			# キャラクターがパス開始点にいない場合、接続線を追加
			full_path.append(char_pos)
			connect_length = char_pos.distance_to(path_start)
		full_path.append_array(base_path)

		# キャラクター固有の視線ポイントとRun区間を取得
		var char_vision_points: Array[Dictionary] = []
		if all_vision_points.has(char_id):
			for vp in all_vision_points[char_id]:
				char_vision_points.append(vp)

		var char_run_segments: Array[Dictionary] = []
		if all_run_segments.has(char_id):
			for seg in all_run_segments[char_id]:
				char_run_segments.append(seg)

		# 視線ポイントとRun区間の比率を再計算
		var adjusted_vision_points = _adjust_ratios_for_connection(char_vision_points, connect_length, base_length)
		var adjusted_run_segments = _adjust_run_ratios_for_connection(char_run_segments, connect_length, base_length)

		# パスメッシュを作成（各キャラクターごと、キャラクター色適用）
		var path_mesh = _create_path_mesh(full_path, character)

		# マルチモードの場合、元のマーカーを削除して新しいマーカーを生成
		if is_multi_mode and all_vision_markers.has(char_id):
			for marker in all_vision_markers[char_id]:
				if is_instance_valid(marker):
					marker.queue_free()
		if is_multi_mode and all_run_markers.has(char_id):
			for marker in all_run_markers[char_id]:
				if is_instance_valid(marker):
					marker.queue_free()

		# 各キャラクター用にマーカーを新規生成
		var char_vision_markers = _create_vision_markers_for_path(
			full_path, adjusted_vision_points, character
		)
		var char_run_markers = _create_run_markers_for_path(
			full_path, adjusted_run_segments, character
		)

		pending_paths[char_id] = {
			"character": character,
			"path": full_path,
			"vision_points": adjusted_vision_points,
			"run_segments": adjusted_run_segments,
			"path_mesh": path_mesh,
			"vision_markers": char_vision_markers,
			"run_markers": char_run_markers
		}

		processed_count += 1
		print("[PathExecution] Saved path for %s (%d points, connect: %.2f, vision: %d, run: %d)" % [
			character.name, full_path.size(), connect_length,
			char_vision_markers.size(), char_run_markers.size()
		])

	print("[PathExecution] Applied path to %d characters (%s mode)" % [
		processed_count,
		"multi-character" if is_multi_mode else "formation"
	])
	path_confirmed.emit(processed_count)
	return true


## 全キャラクターのパスを同時実行
func execute_all_paths(run: bool) -> int:
	if pending_paths.is_empty():
		print("[PathExecution] No pending paths to execute")
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

		if not is_instance_valid(character):
			continue

		# コントローラーを取得または作成
		var controller = _get_or_create_path_controller(character)
		controller.setup(character)

		if controller.start_path(path, vision_points, run_segments, run):
			executed_count += 1
			print("[PathExecution] Started path for %s (%d points, run_segments: %d)" % [character.name, path.size(), run_segments.size()])
		else:
			print("[PathExecution] Failed to start path for %s" % character.name)

	# パスデータのみクリア（メッシュは残す）
	for char_id in pending_paths:
		var data = pending_paths[char_id]
		data.erase("path")
		data.erase("vision_points")
		data.erase("run_segments")
		data.erase("character")

	paths_execution_started.emit(executed_count)
	print("[PathExecution] Executed %d paths" % executed_count)
	return executed_count


## 全ての保留パスをクリア
func clear_all_pending_paths() -> void:
	_clear_all_path_meshes()
	pending_paths.clear()
	paths_cleared.emit()
	print("[PathExecution] Cleared all pending paths")


## 保留パス数を取得
func get_pending_path_count() -> int:
	return pending_paths.size()


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


## 全てのパス追従をキャンセル
func cancel_all_path_following() -> void:
	for controller in _path_controllers.values():
		if controller.is_following_path():
			controller.cancel()
	print("[PathExecution] Cancelled all path following")


## 全パス追従コントローラーを処理（毎フレーム呼ぶ）
func process_controllers(delta: float) -> void:
	for controller in _path_controllers.values():
		if controller.is_following_path():
			controller.process(delta)


## パス追従完了時のコールバック（外部から呼ばれる）
func on_path_following_completed(character: Node) -> void:
	print("[PathExecution] Path following completed for %s" % character.name)
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
		print("[PathExecution] All paths completed, meshes cleared")


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

	# Connect combat awareness for automatic enemy aiming during movement
	if character.combat_awareness:
		controller.set_combat_awareness(character.combat_awareness)

	_path_controllers[char_id] = controller
	return controller


func _on_path_completed(character: Node) -> void:
	on_path_following_completed(character)


func _on_path_cancelled(character: Node) -> void:
	print("[PathExecution] Path following cancelled for %s" % character.name)


## 特定キャラクターの保留パスをクリア
func _clear_pending_path_for_character(char_id: int) -> void:
	if not pending_paths.has(char_id):
		return

	var old_data = pending_paths[char_id]
	if old_data.has("path_mesh") and is_instance_valid(old_data["path_mesh"]):
		old_data["path_mesh"].queue_free()
	if old_data.has("vision_markers"):
		for marker in old_data["vision_markers"]:
			if is_instance_valid(marker):
				marker.queue_free()
	if old_data.has("run_markers"):
		for marker in old_data["run_markers"]:
			if is_instance_valid(marker):
				marker.queue_free()

	pending_paths.erase(char_id)


## 全てのパスメッシュと視線マーカーとRunマーカーを削除
func _clear_all_path_meshes() -> void:
	for char_id in pending_paths:
		var data = pending_paths[char_id]
		if data.has("path_mesh") and is_instance_valid(data["path_mesh"]):
			data["path_mesh"].queue_free()
		if data.has("vision_markers"):
			for marker in data["vision_markers"]:
				if is_instance_valid(marker):
					marker.queue_free()
		if data.has("run_markers"):
			for marker in data["run_markers"]:
				if is_instance_valid(marker):
					marker.queue_free()


## パスの長さを計算
func _calculate_path_length(path: Array[Vector3]) -> float:
	var length: float = 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length


## 接続線を考慮して視線ポイントの比率を調整
func _adjust_ratios_for_connection(vision_points: Array[Dictionary], connect_length: float, base_length: float) -> Array[Dictionary]:
	if connect_length < 0.01 or base_length < 0.01:
		return vision_points.duplicate()

	var new_length = connect_length + base_length
	var adjusted: Array[Dictionary] = []

	for vp in vision_points:
		var old_ratio: float = vp.path_ratio
		# 新しい比率 = (接続線の長さ + 元の比率 * 元のパス長さ) / 新しいパス長さ
		var new_ratio: float = (connect_length + old_ratio * base_length) / new_length
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

	var new_length = connect_length + base_length
	var adjusted: Array[Dictionary] = []

	for seg in run_segments:
		var old_start: float = seg.start_ratio
		var old_end: float = seg.end_ratio
		# 新しい比率を計算
		var new_start: float = (connect_length + old_start * base_length) / new_length
		var new_end: float = (connect_length + old_end * base_length) / new_length
		adjusted.append({
			"start_ratio": new_start,
			"end_ratio": new_end
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


## 調整済み視線ポイントから新しいVisionMarkerを生成
func _create_vision_markers_for_path(
	path: Array[Vector3],
	adjusted_vision_points: Array[Dictionary],
	character: Node
) -> Array[MeshInstance3D]:
	var markers: Array[MeshInstance3D] = []

	for vp in adjusted_vision_points:
		var ratio: float = vp.path_ratio
		var direction: Vector3 = vp.direction

		# パス上の位置を計算
		var anchor = _calculate_position_on_path(path, ratio)

		# VisionMarkerを作成
		var marker = MeshInstance3D.new()
		marker.set_script(VisionMarkerScript)
		_mesh_parent.add_child(marker)

		# 位置と方向を設定
		marker.set_position_and_direction(anchor, direction)

		# キャラクター色を適用
		var char_color = CharacterColorManager.get_character_color(character)
		# 背景は暗い色、矢印はキャラクター色
		var bg_color = Color(char_color.r * 0.3, char_color.g * 0.3, char_color.b * 0.3, 0.95)
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
