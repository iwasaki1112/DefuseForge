class_name PathDrawer
extends Node3D

## 地面にパスを描画するコンポーネント
## マウスドラッグでパスを描き、キャラクター移動に使用
## Slice the Pie: パス上の任意の点から視線方向を設定可能

## 描画モード
enum DrawingMode { MOVEMENT, VISION_POINT, RUN_MARKER, CLEAR_MARKER, GRENADE_MARKER, DOOR_MARKER, WAIT_MARKER, SMOKE_GRENADE_MARKER }

## 視線ポイントデータ（ターゲットポイントモード）
## { "path_ratio": float, "anchor": Vector3, "target_point": Vector3 }

## Run区間データ
## { "start_ratio": float, "end_ratio": float }

signal drawing_finished(points: PackedVector3Array)

## 視線ポイント用シグナル（target_pointはキャラクターが見続ける地点）
signal vision_point_added(anchor: Vector3, target_point: Vector3)
signal mode_changed(mode: int)  # 0=MOVEMENT, 1=VISION_POINT, 2=RUN_MARKER

## Runマーカー用シグナル
signal run_segment_added(start_ratio: float, end_ratio: float)

## Clearマーカー用シグナル
signal clear_point_added(path_ratio: float)

## グレネードマーカー用シグナル
signal grenade_marker_added(path_ratio: float, target_pos: Vector3)

## スモークグレネードマーカー用シグナル
signal smoke_grenade_marker_added(path_ratio: float, target_pos: Vector3)

## ドアマーカー用シグナル
signal door_marker_added(path_ratio: float, door: Node3D)

## Waitマーカー用シグナル
signal wait_marker_added(path_ratio: float, wait_duration: float)

## パスがUndoされた時のシグナル
signal path_undone()

## タイムライン用データが変更された時のシグナル（リアルタイムプレビュー用）
signal timeline_data_changed()

## マーカー履歴用の種別（PATH = パス描画自体, PATH_EXTENSION = パス拡張）
enum MarkerType { VISION, RUN, CLEAR, PATH, GRENADE, DOOR, PATH_EXTENSION, WAIT, SMOKE_GRENADE }

@export var min_point_distance: float = 0.2  # ポイント間の最小距離
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.9)  # 白
@export var vision_line_color: Color = Color(0.7, 0.3, 0.9, 0.9)  # 紫
@export var vision_line_length: float = 2.0  # 視線ラインの長さ
@export var line_width: float = 0.04
@export var ground_plane_height: float = 0.0
@export var max_points: int = 500
@export var path_click_threshold: float = 0.5  # パスクリック判定距離
@export var path_endpoint_threshold: float = 0.3  # パス終点タップ検出距離（モバイル向けに大きめ）
@export_flags_3d_physics var wall_collision_mask: int = 2  # 壁検出用のコリジョンマスク

## スムージング設定
@export var enable_smoothing: bool = true  # パススムージングを有効化
@export var smoothing_epsilon: float = 0.15  # RDP間引き許容誤差（大きいほど間引き強）
@export var smoothing_segments: int = 4  # Catmull-Rom曲線の分割数（大きいほど滑らか）

const PathLineMeshScript = preload("res://scripts/effects/path_line_mesh.gd")
const VisionMarkerScript = preload("res://scripts/effects/vision_marker.gd")
const RunMarkerScript = preload("res://scripts/effects/run_marker.gd")
const ClearMarkerScript = preload("res://scripts/effects/clear_marker.gd")
const GrenadeMarkerScript = preload("res://scripts/effects/grenade_marker.gd")
const DoorMarkerScript = preload("res://scripts/effects/door_marker.gd")
const WaitMarkerScript = preload("res://scripts/effects/wait_marker.gd")
const SmokeGrenadeMarkerScript = preload("res://scripts/effects/smoke_grenade_marker.gd")
const ActionMarkerDataScript = preload("res://scripts/effects/action_marker_data.gd")
const MarkerCollectionScript = preload("res://scripts/effects/marker_collection.gd")

var _camera: Camera3D
var _character: Node3D
var _ground_plane: Plane
var _is_drawing: bool = false
var _is_extending_path: bool = false  # パス継続描画中フラグ
var _is_enabled: bool = false
var _drawing_mode: DrawingMode = DrawingMode.MOVEMENT
var _path_points: PackedVector3Array = PackedVector3Array()
var _path_mesh: MeshInstance3D

## 視線ポイント用
var _vision_points: Array[Dictionary] = []  # { path_ratio, anchor, direction }
var _vision_meshes: Array[MeshInstance3D] = []
var _current_vision_anchor: Vector3 = Vector3.ZERO
var _current_vision_ratio: float = 0.0
var _is_drawing_vision: bool = false

## Runマーカー用
var _run_segments: Array[Dictionary] = []  # { start_ratio, end_ratio }
var _run_meshes: Array[MeshInstance3D] = []
var _current_run_start: Dictionary = {}  # 未完成のrun開始点 { ratio, position }

## Clearマーカー用
var _clear_points: Array[Dictionary] = []  # { path_ratio }
var _clear_meshes: Array[MeshInstance3D] = []

## グレネードマーカー用
## { "path_ratio": float, "anchor": Vector3, "target_pos": Vector3, "bounce_point": Vector3?, "bounce_normal": Vector3? }
var _grenade_markers: Array[Dictionary] = []
var _grenade_meshes: Array[MeshInstance3D] = []

## ドアマーカー用
## { "path_ratio": float, "anchor": Vector3, "door_node": Node3D }
var _door_markers: Array[Dictionary] = []
var _door_meshes: Array[MeshInstance3D] = []

## Waitマーカー用
## { "path_ratio": float, "anchor": Vector3, "wait_duration": float }
var _wait_markers: Array[Dictionary] = []
var _wait_meshes: Array[MeshInstance3D] = []

## Wait長押し検出用
var _wait_press_start_time: float = 0.0
var _wait_is_pressing: bool = false
var _wait_preview_marker: MeshInstance3D = null
var _wait_pending_anchor: Vector3 = Vector3.ZERO
var _wait_pending_ratio: float = 0.0

## Wait設定
const WAIT_MIN_DURATION: float = 0.0  ## 最小待機時間（秒）
const WAIT_MAX_DURATION: float = 10.0  ## 最大待機時間（秒）

## スモークグレネードマーカー用
## { "path_ratio": float, "anchor": Vector3, "target_pos": Vector3, "bounce_point": Vector3?, "bounce_normal": Vector3? }
var _smoke_grenade_markers: Array[Dictionary] = []
var _smoke_grenade_meshes: Array[MeshInstance3D] = []

## スモークグレネードモード用の状態
var _smoke_grenade_pending_anchor: Vector3 = Vector3.ZERO
var _smoke_grenade_pending_ratio: float = 0.0
var _smoke_grenade_has_anchor: bool = false
var _smoke_grenade_bounce_point: Vector3 = Vector3.ZERO
var _smoke_grenade_bounce_normal: Vector3 = Vector3.ZERO
var _smoke_grenade_has_bounce: bool = false
var _smoke_grenade_trajectory_mesh: MeshInstance3D = null

## グレネードモード用の状態
var _grenade_pending_anchor: Vector3 = Vector3.ZERO
var _grenade_pending_ratio: float = 0.0
var _grenade_has_anchor: bool = false
var _grenade_bounce_point: Vector3 = Vector3.ZERO
var _grenade_bounce_normal: Vector3 = Vector3.ZERO
var _grenade_has_bounce: bool = false
var _grenade_trajectory_mesh: MeshInstance3D = null

## マーカー追加履歴（Undo用）- キャラクターID別に管理
## シングルモード: _marker_history に追加
## マルチモード: _character_markers[char_id].marker_history に追加
var _marker_history: Array[int] = []  # MarkerType の配列

## キャラクター別マーカー管理（マルチセレクト対応）
## { char_id: { "vision_points": Array[Dictionary], "vision_meshes": Array[MeshInstance3D],
##              "run_segments": Array[Dictionary], "run_meshes": Array[MeshInstance3D] } }
var _character_markers: Dictionary = {}
## キャラクター別マーカーコレクション（統一管理用）
## { char_id: MarkerCollection }
var _character_collections: Dictionary = {}
var _active_edit_character: Node = null  # 現在編集中のキャラクター
var _multi_character_mode: bool = false  # マルチキャラクターモード

## パス実行管理
var _pending_path: PackedVector3Array = PackedVector3Array()
var _pending_character: CharacterBody3D = null
var _executing_character: CharacterBody3D = null

## パス拡張Undo用（拡張前の状態を保存）
var _path_extension_snapshots: Array[PackedVector3Array] = []

## キャラクター色
var _character_color: Color = Color(1.0, 1.0, 1.0)  # デフォルト白

## タイムライン更新管理
var _timeline_manager: TimelineManager = null
## 頻度抑制用: 最後の更新時刻
var _last_timeline_update_time: float = 0.0
## 頻度抑制用: 更新間隔（ミリ秒）
const TIMELINE_UPDATE_THROTTLE_MS: float = 50.0  ## 50ms = 20fps


func _ready() -> void:
	_ground_plane = Plane(Vector3.UP, ground_plane_height)
	_setup_mesh()


func _process(_delta: float) -> void:
	# Wait長押し中は時間ベースでプレビューを更新
	if _wait_is_pressing and _wait_preview_marker:
		_update_wait_marker_preview()


func _setup_mesh() -> void:
	_path_mesh = MeshInstance3D.new()
	_path_mesh.set_script(PathLineMeshScript)
	_path_mesh.line_color = line_color
	_path_mesh.line_width = line_width
	add_child(_path_mesh)


func setup(camera: Camera3D, character: Node3D = null, timeline_manager: TimelineManager = null) -> void:
	_camera = camera
	_character = character
	_timeline_manager = timeline_manager


## タイムライン更新を通知（即時）
## マーカー追加・削除・パス完了など、確実に更新が必要な場合に使用
func _notify_timeline_changed() -> void:
	if _timeline_manager:
		_timeline_manager.mark_dirty()
	else:
		timeline_data_changed.emit()


## タイムライン更新を通知（頻度抑制あり）
## パス描画中・Wait長押し中など、高頻度更新の場合に使用
## @return: 実際に通知した場合true
func _notify_timeline_changed_throttled() -> bool:
	var current_time = Time.get_ticks_msec()
	if current_time - _last_timeline_update_time < TIMELINE_UPDATE_THROTTLE_MS:
		return false
	_last_timeline_update_time = current_time
	_notify_timeline_changed()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null or not _is_enabled:
		return

	# パス継続描画の入力処理（どのモードでも優先）
	if _handle_path_extension_input(event):
		return

	match _drawing_mode:
		DrawingMode.MOVEMENT:
			_handle_movement_input(event)
		DrawingMode.VISION_POINT:
			_handle_vision_point_input(event)
		DrawingMode.RUN_MARKER:
			_handle_run_marker_input(event)
		DrawingMode.CLEAR_MARKER:
			_handle_clear_marker_input(event)
		DrawingMode.GRENADE_MARKER:
			_handle_grenade_marker_input(event)
		DrawingMode.DOOR_MARKER:
			_handle_door_marker_input(event)
		DrawingMode.WAIT_MARKER:
			_handle_wait_marker_input(event)
		DrawingMode.SMOKE_GRENADE_MARKER:
			_handle_smoke_grenade_marker_input(event)


## パス継続描画の入力処理（全モード共通、優先処理）
## @return: 入力を処理した場合true
func _handle_path_extension_input(event: InputEvent) -> bool:
	# 継続描画中のマウス移動・解放処理
	if _is_extending_path:
		if event is InputEventMouseMotion:
			var ground_pos = _get_ground_position(event.position)
			if ground_pos != null:
				_add_extend_point(ground_pos)
			get_viewport().set_input_as_handled()
			return true
		elif event is InputEventMouseButton:
			var mouse_event = event as InputEventMouseButton
			if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
				_finish_extending_path()
				get_viewport().set_input_as_handled()
				return true

	# 継続描画開始判定（左クリック押下時）
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			# パス終点付近をタップした場合、継続描画を開始
			if has_pending_path() and not _is_drawing:
				var ground_pos = _get_ground_position(mouse_event.position)
				if ground_pos != null and _is_near_path_endpoint(ground_pos):
					_start_extending_path()
					get_viewport().set_input_as_handled()
					return true

	return false


## 移動パス描画の入力処理
## Note: パス継続描画は_handle_path_extension_inputで優先処理済み
func _handle_movement_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# 通常の新規描画開始
				var start_pos: Vector3
				if _character:
					start_pos = Vector3(_character.global_position.x, 0, _character.global_position.z)
				else:
					var ground_pos = _get_ground_position(mouse_event.position)
					if ground_pos == null:
						return
					start_pos = ground_pos
				_start_drawing(start_pos)
				get_viewport().set_input_as_handled()
			else:
				# マウス解放時
				if _is_drawing:
					_finish_drawing()
					get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		if _is_drawing:
			var ground_pos = _get_ground_position(event.position)
			if ground_pos != null:
				_add_point(ground_pos)


## 視線ポイント設定の入力処理
func _handle_vision_point_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# パス上の最も近い点を見つける
				var ground_pos = _get_ground_position(mouse_event.position)
				if ground_pos == null:
					return

				var result = _find_closest_point_on_path(ground_pos)
				if result.distance > path_click_threshold:
					return

				_current_vision_anchor = result.point
				_current_vision_ratio = result.ratio
				_is_drawing_vision = true
				get_viewport().set_input_as_handled()
			else:
				if _is_drawing_vision:
					var ground_pos = _get_ground_position(mouse_event.position)
					if ground_pos != null:
						_finish_vision_point(ground_pos)
					_is_drawing_vision = false
					get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		if _is_drawing_vision:
			var ground_pos = _get_ground_position(event.position)
			if ground_pos != null:
				# ターゲットポイントモード: ドラッグ位置をターゲット地点として表示
				_update_temp_vision_marker(_current_vision_anchor, ground_pos)


## Runマーカー設定の入力処理
func _handle_run_marker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			# パス上の最も近い点を見つける
			var ground_pos = _get_ground_position(mouse_event.position)
			if ground_pos == null:
				return

			var result = _find_closest_point_on_path(ground_pos)
			if result.distance > path_click_threshold:
				return

			if _current_run_start.is_empty():
				# 開始点を設定
				_current_run_start = { "ratio": result.ratio, "position": result.point }
				_create_run_marker(result.point, RunMarkerScript.RunMarkerType.START)
			else:
				# 終点を設定してセグメントを完成
				var start_ratio = _current_run_start.ratio
				var end_ratio = result.ratio

				# 開始点が終点より後ろなら入れ替え
				if start_ratio > end_ratio:
					var tmp = start_ratio
					start_ratio = end_ratio
					end_ratio = tmp

				# Run区間を追加
				var new_segment = { "start_ratio": start_ratio, "end_ratio": end_ratio }

				# マルチキャラクターモードの場合、アクティブキャラクターのデータに追加
				if _multi_character_mode and _active_edit_character:
					var char_id = _active_edit_character.get_instance_id()
					if _character_markers.has(char_id):
						var char_data = _character_markers[char_id]
						char_data.run_segments.append(new_segment)
						# 履歴に追加
						char_data.marker_history.append(MarkerType.RUN)

						# MarkerCollectionにも追加（新システム）
						# Note: Runは1セグメント=2メッシュ(START/END)の特殊構造
						# MarkerCollectionは1データ=1メッシュを前提としているため、
						# Runのメッシュ管理は従来のrun_meshes配列で行う
						# take_run_meshes()を使う場合は従来のAPIを使用すること
						var run_data = ActionMarkerDataScript.RunMarkerData.new()
						run_data.start_ratio = start_ratio
						run_data.end_ratio = end_ratio
						_add_marker_to_collection(_active_edit_character, run_data, null)
				else:
					_run_segments.append(new_segment)
					# 履歴に追加
					_marker_history.append(MarkerType.RUN)

				# 終点マーカーを作成
				_create_run_marker(result.point, RunMarkerScript.RunMarkerType.END)

				run_segment_added.emit(start_ratio, end_ratio)
				_notify_timeline_changed()

				# 開始点をクリア
				_current_run_start = {}

			get_viewport().set_input_as_handled()


## Clearマーカー設定の入力処理
func _handle_clear_marker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			# パス上の最も近い点を見つける
			var ground_pos = _get_ground_position(mouse_event.position)
			if ground_pos == null:
				return

			var result = _find_closest_point_on_path(ground_pos)
			if result.distance > path_click_threshold:
				return

			# Clearポイントを追加
			var new_point = { "path_ratio": result.ratio }

			# マルチキャラクターモードの場合、アクティブキャラクターのデータに追加
			if _multi_character_mode and _active_edit_character:
				var char_id = _active_edit_character.get_instance_id()
				if _character_markers.has(char_id):
					var char_data = _character_markers[char_id]
					# ソート位置を見つけて挿入
					var multi_insert_idx = 0
					for i in range(char_data.clear_points.size()):
						if char_data.clear_points[i].path_ratio > result.ratio:
							break
						multi_insert_idx = i + 1
					char_data.clear_points.insert(multi_insert_idx, new_point)
					# マーカーを作成
					var marker = _create_clear_marker_node(result.point)
					char_data.clear_meshes.insert(multi_insert_idx, marker)
					# 履歴に追加
					char_data.marker_history.append(MarkerType.CLEAR)

					# MarkerCollectionにも追加（新システム）
					var clear_data = ActionMarkerDataScript.ClearMarkerData.new()
					clear_data.path_ratio = result.ratio
					clear_data.anchor = result.point
					_add_marker_to_collection(_active_edit_character, clear_data, marker)
			else:
				# シングルモードの場合
				var single_insert_idx = 0
				for i in range(_clear_points.size()):
					if _clear_points[i].path_ratio > result.ratio:
						break
					single_insert_idx = i + 1
				_clear_points.insert(single_insert_idx, new_point)
				# マーカーを作成
				_create_clear_marker(result.point, single_insert_idx)
				# 履歴に追加
				_marker_history.append(MarkerType.CLEAR)

			clear_point_added.emit(result.ratio)
			_notify_timeline_changed()
			get_viewport().set_input_as_handled()


## Clearマーカーノードを作成して返す
func _create_clear_marker_node(pos: Vector3) -> MeshInstance3D:
	var marker = MeshInstance3D.new()
	marker.set_script(ClearMarkerScript)
	add_child(marker)
	marker.set_marker_position(pos)
	marker.set_colors(_character_color, Color.WHITE)
	return marker


## Clearマーカーを指定位置に作成
func _create_clear_marker(pos: Vector3, index: int) -> void:
	var marker = _create_clear_marker_node(pos)
	_clear_meshes.insert(index, marker)


## Runマーカーを作成
func _create_run_marker(pos: Vector3, type: int) -> void:
	var marker = MeshInstance3D.new()
	marker.set_script(RunMarkerScript)
	add_child(marker)

	# マーカーの位置とタイプを設定
	marker.set_position_and_type(pos, type)

	# キャラクター色を適用
	marker.set_colors(_character_color, Color.WHITE)

	# マルチキャラクターモードの場合、アクティブキャラクターのメッシュ配列に追加
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			_character_markers[char_id].run_meshes.append(marker)
			return

	# シングルモードの場合
	_run_meshes.append(marker)


func _get_ground_position(screen_pos: Vector2) -> Variant:
	var ray_origin = _camera.project_ray_origin(screen_pos)
	var ray_direction = _camera.project_ray_normal(screen_pos)

	var intersection = _ground_plane.intersects_ray(ray_origin, ray_direction)
	if intersection:
		return intersection as Vector3
	return null


## 2点間に壁があるかチェック（ドアは除外）
## @return: { "hit": bool, "position": Vector3 (ヒット位置、hitがtrueの場合) }
func _check_wall_between(from: Vector3, to: Vector3) -> Dictionary:
	var space_state = get_world_3d().direct_space_state
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


## オブジェクトがドアかどうかをチェック
func _is_door_object(obj: Object) -> bool:
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


## パス上で最も近い点を見つける
func _find_closest_point_on_path(pos: Vector3) -> Dictionary:
	if _pending_path.size() < 2:
		return { "point": Vector3.ZERO, "distance": INF, "ratio": 0.0 }

	var closest_point: Vector3 = _pending_path[0]
	var closest_distance: float = INF
	var closest_ratio: float = 0.0

	var total_length: float = 0.0
	var lengths: Array[float] = [0.0]

	# パスの総距離を計算
	for i in range(1, _pending_path.size()):
		var segment_length = _pending_path[i - 1].distance_to(_pending_path[i])
		total_length += segment_length
		lengths.append(total_length)

	# 各セグメントで最も近い点を探す
	for i in range(1, _pending_path.size()):
		var p1 = _pending_path[i - 1]
		var p2 = _pending_path[i]

		# セグメント上の最近点を計算
		var segment = p2 - p1
		var segment_length = segment.length()
		if segment_length < 0.001:
			continue

		var t = clampf((pos - p1).dot(segment) / (segment_length * segment_length), 0.0, 1.0)
		var point_on_segment = p1 + segment * t

		var distance = pos.distance_to(point_on_segment)
		if distance < closest_distance:
			closest_distance = distance
			closest_point = point_on_segment
			# このセグメント上での進行率を計算
			var distance_to_point = lengths[i - 1] + segment_length * t
			closest_ratio = distance_to_point / total_length if total_length > 0 else 0.0

	return { "point": closest_point, "distance": closest_distance, "ratio": closest_ratio }


## パス上の指定された比率から距離オフセットした点を探す
## @param base_ratio: 基準となるパス上の比率 (0.0-1.0)
## @param offset_distance: オフセット距離（負の値で開始方向へ）
## @return: { "point": Vector3, "ratio": float }
func _find_offset_point_on_path(base_ratio: float, offset_distance: float) -> Dictionary:
	if _pending_path.size() < 2:
		return { "point": Vector3.ZERO, "ratio": 0.0 }

	# パスの総距離を計算
	var total_length: float = 0.0
	var lengths: Array[float] = [0.0]
	for i in range(1, _pending_path.size()):
		var segment_length = _pending_path[i - 1].distance_to(_pending_path[i])
		total_length += segment_length
		lengths.append(total_length)

	if total_length < 0.001:
		return { "point": _pending_path[0], "ratio": 0.0 }

	# 基準点の距離を計算
	var base_distance = base_ratio * total_length

	# オフセットを適用した距離を計算
	var target_distance = clampf(base_distance + offset_distance, 0.0, total_length)

	# 目標距離に対応するパス上の点を探す
	var target_ratio = target_distance / total_length

	for i in range(1, _pending_path.size()):
		if lengths[i] >= target_distance:
			var p1 = _pending_path[i - 1]
			var p2 = _pending_path[i]
			var segment_start_dist = lengths[i - 1]
			var segment_length = lengths[i] - segment_start_dist

			if segment_length < 0.001:
				return { "point": p1, "ratio": target_ratio }

			var t = (target_distance - segment_start_dist) / segment_length
			var point = p1 + (p2 - p1) * t
			return { "point": point, "ratio": target_ratio }

	# パスの終点を返す
	return { "point": _pending_path[_pending_path.size() - 1], "ratio": 1.0 }


## パス終点位置を取得
func _get_path_endpoint() -> Vector3:
	if _pending_path.size() < 1:
		return Vector3.ZERO
	return _pending_path[_pending_path.size() - 1]


## 指定位置がパス終点付近かどうか判定
func _is_near_path_endpoint(ground_pos: Vector3) -> bool:
	if _pending_path.size() < 2:
		return false
	var endpoint = _get_path_endpoint()
	var distance = Vector2(ground_pos.x - endpoint.x, ground_pos.z - endpoint.z).length()
	return distance <= path_endpoint_threshold


## 視線ポイントの設定を完了（ターゲットポイントモード）
## end_posがターゲット地点として保存される
func _finish_vision_point(end_pos: Vector3) -> void:
	var target_point = end_pos
	target_point.y = 0  # 地面高さに正規化

	var direction = (target_point - _current_vision_anchor)
	direction.y = 0

	if direction.length_squared() < 0.001:
		# 一時マーカーがあれば削除
		_remove_temp_vision_marker()
		return

	# 一時マーカーを削除（新しいマーカーを正しい位置に挿入するため）
	_remove_temp_vision_marker()

	# 視線ポイントを追加（path_ratio順にソート）- ターゲットポイントモード
	var new_point = {
		"path_ratio": _current_vision_ratio,
		"anchor": _current_vision_anchor,
		"target_point": target_point  # directionではなくtarget_pointを保存
	}

	# マルチキャラクターモードの場合、アクティブキャラクターのデータに追加
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			var vision_points: Array[Dictionary] = char_data.vision_points
			var vision_meshes: Array[MeshInstance3D] = char_data.vision_meshes

			# 挿入位置を見つける
			var multi_vision_idx = 0
			for i in range(vision_points.size()):
				if vision_points[i].path_ratio > _current_vision_ratio:
					break
				multi_vision_idx = i + 1

			vision_points.insert(multi_vision_idx, new_point)

			# 視線マーカーを作成（ターゲットポイントモード）
			var marker = _create_vision_marker_node(_current_vision_anchor, target_point)
			vision_meshes.insert(multi_vision_idx, marker)

			# 履歴に追加
			char_data.marker_history.append(MarkerType.VISION)

			# MarkerCollectionにも追加（新システム）
			var vision_data = ActionMarkerDataScript.VisionMarkerData.new()
			vision_data.path_ratio = _current_vision_ratio
			vision_data.anchor = _current_vision_anchor
			vision_data.target_point = target_point
			vision_data.has_target = true
			_add_marker_to_collection(_active_edit_character, vision_data, marker)

			vision_point_added.emit(_current_vision_anchor, target_point)
			_notify_timeline_changed()
			return

	# シングルモードの場合は従来通り
	var single_vision_idx = 0
	for i in range(_vision_points.size()):
		if _vision_points[i].path_ratio > _current_vision_ratio:
			break
		single_vision_idx = i + 1

	_vision_points.insert(single_vision_idx, new_point)

	# 視線マーカーを作成（同じ挿入位置に）
	_create_vision_marker_at_index(_current_vision_anchor, target_point, single_vision_idx)

	# 履歴に追加
	_marker_history.append(MarkerType.VISION)

	vision_point_added.emit(_current_vision_anchor, target_point)
	_notify_timeline_changed()


## 視線マーカーを作成（末尾に追加）
func _create_vision_marker(anchor: Vector3, direction: Vector3) -> void:
	_create_vision_marker_at_index(anchor, direction, _vision_meshes.size())


## 視線マーカーノードを作成して返す（ターゲットポイントモード対応）
## @param anchor: パス上のアンカー位置
## @param target_point: ターゲット地点（キャラクターが見続ける位置）
func _create_vision_marker_node(anchor: Vector3, target_point: Vector3) -> MeshInstance3D:
	var marker = MeshInstance3D.new()
	marker.set_script(VisionMarkerScript)
	add_child(marker)

	# マーカーの位置とターゲットを設定（ターゲットポイントモード）
	marker.set_position_and_target(anchor, target_point)

	# キャラクター色を適用
	marker.set_colors(_character_color, Color.WHITE)
	# ターゲット線の色もキャラクター色に基づいて設定
	marker.set_target_line_color(Color(_character_color.r, _character_color.g * 0.7, _character_color.b * 0.5, 0.8))

	return marker


## 視線マーカーを指定位置に作成
func _create_vision_marker_at_index(anchor: Vector3, direction: Vector3, index: int) -> void:
	var marker = _create_vision_marker_node(anchor, direction)
	_vision_meshes.insert(index, marker)


## 一時的な視線マーカーを削除
func _remove_temp_vision_marker() -> void:
	# 一時マーカーは _vision_meshes.size() > _vision_points.size() の場合に存在
	if _vision_meshes.size() > _vision_points.size():
		var temp_marker = _vision_meshes.pop_back()
		temp_marker.queue_free()


## 一時的な視線マーカーを更新（ドラッグ中）- ターゲットポイントモード
## @param anchor: パス上のアンカー位置
## @param target_point: ターゲット地点（ドラッグ先）
func _update_temp_vision_marker(anchor: Vector3, target_point: Vector3) -> void:
	# 最後のマーカーが一時的なものかチェック
	if _vision_meshes.size() > _vision_points.size():
		var temp_marker = _vision_meshes[-1]
		temp_marker.set_position_and_target(anchor, target_point)
	else:
		# 一時的なマーカーを作成
		var marker = MeshInstance3D.new()
		marker.set_script(VisionMarkerScript)
		add_child(marker)
		_vision_meshes.append(marker)
		marker.set_position_and_target(anchor, target_point)
		# キャラクター色を適用
		marker.set_colors(_character_color, Color.WHITE)
		# ターゲット線の色もキャラクター色に基づいて設定
		marker.set_target_line_color(Color(_character_color.r, _character_color.g * 0.7, _character_color.b * 0.5, 0.8))


func _start_drawing(start_pos: Vector3) -> void:
	# キャラクターが設定されている場合、キャラクター位置→開始点間の壁チェック
	if _character:
		var char_pos = Vector3(_character.global_position.x, ground_plane_height, _character.global_position.z)
		var hit_result = _check_wall_between(char_pos, start_pos)
		if hit_result.hit:
			return  # 描画開始を拒否

	_is_drawing = true
	_path_points.clear()
	_path_points.append(start_pos)
	_path_mesh.update_from_points(_path_points)


func _add_point(pos: Vector3) -> void:
	if _path_points.size() >= max_points:
		return

	var last_point = _path_points[_path_points.size() - 1]
	if pos.distance_to(last_point) < min_point_distance:
		return

	# 壁検出: 前のポイントから新しいポイントへ壁がないかチェック
	var hit_result = _check_wall_between(last_point, pos)
	if hit_result.hit:
		# 壁直前のポイントを追加して描画終了
		var wall_pos = hit_result.position
		# 壁に少し手前で止まる（0.1m手前）
		var to_wall = (wall_pos - last_point).normalized()
		var safe_pos = wall_pos - to_wall * 0.1
		safe_pos.y = ground_plane_height
		_path_points.append(safe_pos)
		_path_mesh.update_from_points(_path_points)
		_finish_drawing()
		return

	_path_points.append(pos)
	_path_mesh.update_from_points(_path_points)
	_notify_timeline_changed_throttled()


func _finish_drawing() -> void:
	_is_drawing = false

	if _path_points.size() >= 2 and _character:
		# 表示パスはそのまま、内部パスのみスムージング（より滑らかに補間）
		if enable_smoothing and _path_points.size() >= 3:
			_pending_path = PathSmoother.smooth_path(_path_points, smoothing_epsilon, smoothing_segments * 2)
		else:
			_pending_path = _path_points.duplicate()
		_pending_character = _character as CharacterBody3D

		# パス描画を履歴に追加（マルチモードでもシングル履歴に追加）
		_marker_history.append(MarkerType.PATH)

	drawing_finished.emit(_path_points)
	_notify_timeline_changed()


## ========================================
## パス継続描画 API
## ========================================

## パスの継続描画が可能か
func can_extend_path() -> bool:
	return has_pending_path() and not _is_drawing and not _is_extending_path


## 継続描画中かどうか
func is_extending_path() -> bool:
	return _is_extending_path


## 継続描画開始
func _start_extending_path() -> void:
	if not has_pending_path():
		return

	_is_extending_path = true
	# 拡張前のパスをスナップショットとして保存（Undo用）
	_path_extension_snapshots.append(_pending_path.duplicate())
	# _pending_pathを_path_pointsにコピー（既存パスを維持）
	_path_points = _pending_path.duplicate()
	# 表示メッシュを更新
	_path_mesh.update_from_points(_path_points)


## 継続描画中にポイントを追加
func _add_extend_point(pos: Vector3) -> void:
	if not _is_extending_path:
		return

	if _path_points.size() >= max_points:
		_finish_extending_path()
		return

	var last_point = _path_points[_path_points.size() - 1]
	if pos.distance_to(last_point) < min_point_distance:
		return

	# 壁検出: 前のポイントから新しいポイントへ壁がないかチェック
	var hit_result = _check_wall_between(last_point, pos)
	if hit_result.hit:
		# 壁直前のポイントを追加して継続描画終了
		var wall_pos = hit_result.position
		# 壁に少し手前で止まる（0.1m手前）
		var to_wall = (wall_pos - last_point).normalized()
		var safe_pos = wall_pos - to_wall * 0.1
		safe_pos.y = ground_plane_height
		_path_points.append(safe_pos)
		_path_mesh.update_from_points(_path_points)
		_finish_extending_path()
		return

	_path_points.append(pos)
	_path_mesh.update_from_points(_path_points)
	_notify_timeline_changed_throttled()


## 継続描画完了
func _finish_extending_path() -> void:
	_is_extending_path = false

	if _path_points.size() >= 2 and _character:
		# 拡張されたパスでスムージング再適用
		if enable_smoothing and _path_points.size() >= 3:
			_pending_path = PathSmoother.smooth_path(_path_points, smoothing_epsilon, smoothing_segments * 2)
		else:
			_pending_path = _path_points.duplicate()

		# マーカーのpath_ratio再計算（パスが延長されたため）
		_recalculate_marker_ratios()

		# 履歴にパス拡張を追加（Undo対応）
		_marker_history.append(MarkerType.PATH_EXTENSION)

	drawing_finished.emit(_path_points)
	_notify_timeline_changed()


## マーカーのpath_ratioを再計算
## パスが延長されると総距離が変わるため、既存マーカーのpath_ratioを再計算する
func _recalculate_marker_ratios() -> void:
	if _pending_path.size() < 2:
		return

	# シングルモードのマーカーを再計算
	_recalculate_marker_ratios_for_array(_vision_points)
	_recalculate_marker_ratios_for_array(_clear_points)
	_recalculate_marker_ratios_for_array(_grenade_markers)
	_recalculate_marker_ratios_for_array(_door_markers)
	# Run区間は start_ratio と end_ratio の両方を再計算
	for segment in _run_segments:
		if segment.has("start_ratio") and segment.has("end_ratio"):
			# Start位置を推定して再計算（元のratioから位置を推定）
			# Note: Runセグメントはanchorを持たないため、start/end_ratioをそのまま維持
			# （延長部分にRunセグメントを追加する場合は新たに設定する）
			pass

	# マルチキャラクターモードのマーカーを再計算
	for char_id in _character_markers:
		var char_data = _character_markers[char_id]
		_recalculate_marker_ratios_for_array(char_data.vision_points)
		_recalculate_marker_ratios_for_array(char_data.clear_points)
		if char_data.has("grenade_markers"):
			_recalculate_marker_ratios_for_array(char_data.grenade_markers)
		if char_data.has("door_markers"):
			_recalculate_marker_ratios_for_array(char_data.door_markers)


## マーカー配列のpath_ratioを再計算（anchor位置ベース）
func _recalculate_marker_ratios_for_array(markers: Array) -> void:
	for marker in markers:
		if marker.has("anchor"):
			var result = _find_closest_point_on_path(marker.anchor)
			marker.path_ratio = result.ratio


## パスをクリア
func clear() -> void:
	_path_points.clear()
	_path_mesh.clear()
	_is_drawing = false
	_is_extending_path = false
	_is_drawing_vision = false
	_drawing_mode = DrawingMode.MOVEMENT
	_pending_path.clear()
	_pending_character = null
	_path_extension_snapshots.clear()
	_clear_vision_points()
	_clear_run_markers()
	_clear_clear_markers()
	_clear_grenade_markers()
	_clear_smoke_grenade_markers()
	_clear_door_markers()
	_clear_wait_markers()
	_marker_history.clear()
	# マルチキャラクターモードもクリア
	_clear_multi_character_markers()


func _clear_vision_points() -> void:
	_vision_points.clear()
	for mesh in _vision_meshes:
		mesh.queue_free()
	_vision_meshes.clear()


func _clear_run_markers() -> void:
	_run_segments.clear()
	_current_run_start = {}
	for mesh in _run_meshes:
		mesh.queue_free()
	_run_meshes.clear()


func _clear_clear_markers() -> void:
	_clear_points.clear()
	for mesh in _clear_meshes:
		mesh.queue_free()
	_clear_meshes.clear()


func _clear_grenade_markers() -> void:
	_grenade_markers.clear()
	for mesh in _grenade_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_grenade_meshes.clear()
	# グレネードモードの状態をリセット
	_grenade_has_anchor = false
	_grenade_pending_anchor = Vector3.ZERO
	_grenade_pending_ratio = 0.0
	_grenade_has_bounce = false
	_grenade_bounce_point = Vector3.ZERO
	_grenade_bounce_normal = Vector3.ZERO
	if _grenade_trajectory_mesh:
		_grenade_trajectory_mesh.queue_free()
		_grenade_trajectory_mesh = null


func _clear_smoke_grenade_markers() -> void:
	_smoke_grenade_markers.clear()
	for mesh in _smoke_grenade_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_smoke_grenade_meshes.clear()
	# スモークグレネードモードの状態をリセット
	_smoke_grenade_has_anchor = false
	_smoke_grenade_pending_anchor = Vector3.ZERO
	_smoke_grenade_pending_ratio = 0.0
	_smoke_grenade_has_bounce = false
	_smoke_grenade_bounce_point = Vector3.ZERO
	_smoke_grenade_bounce_normal = Vector3.ZERO
	if _smoke_grenade_trajectory_mesh:
		_smoke_grenade_trajectory_mesh.queue_free()
		_smoke_grenade_trajectory_mesh = null


func _clear_door_markers() -> void:
	_door_markers.clear()
	for mesh in _door_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_door_meshes.clear()


## 視線マーカーの所有権を移譲（呼び出し元が管理責任を持つ）
func take_vision_markers() -> Array[MeshInstance3D]:
	var markers = _vision_meshes.duplicate()
	_vision_meshes.clear()
	return markers


## Runマーカーの所有権を移譲（呼び出し元が管理責任を持つ）
func take_run_markers() -> Array[MeshInstance3D]:
	var markers = _run_meshes.duplicate()
	_run_meshes.clear()
	return markers


## Clearマーカーの所有権を移譲（呼び出し元が管理責任を持つ）
func take_clear_markers() -> Array[MeshInstance3D]:
	var markers = _clear_meshes.duplicate()
	_clear_meshes.clear()
	return markers


## グレネードマーカーの所有権を移譲（呼び出し元が管理責任を持つ）
func take_grenade_markers() -> Array[MeshInstance3D]:
	var markers = _grenade_meshes.duplicate()
	_grenade_meshes.clear()
	return markers


## ドアマーカーの所有権を移譲（呼び出し元が管理責任を持つ）
func take_door_markers() -> Array[MeshInstance3D]:
	var markers = _door_meshes.duplicate()
	_door_meshes.clear()
	return markers


## スモークグレネードマーカーの所有権を移譲（呼び出し元が管理責任を持つ）
func take_smoke_grenade_markers() -> Array[MeshInstance3D]:
	var markers = _smoke_grenade_meshes.duplicate()
	_smoke_grenade_meshes.clear()
	return markers


func get_drawn_path() -> PackedVector3Array:
	return _path_points


## スムージング済みの内部パスを取得（キャラクター移動用）
func get_smoothed_path() -> PackedVector3Array:
	return _pending_path


## 基準位置からの相対パスを取得
## 各キャラクターの開始位置にオフセットして使用可能
func get_relative_path() -> PackedVector3Array:
	if _pending_path.size() < 2:
		return PackedVector3Array()
	var start = _pending_path[0]
	var relative = PackedVector3Array()
	for point in _pending_path:
		relative.append(point - start)
	return relative


## 相対視線ポイントを取得（アンカー位置とターゲット位置を相対座標に変換）
func get_relative_vision_points() -> Array[Dictionary]:
	if _pending_path.size() < 2:
		return []
	var start = _pending_path[0]
	var relative_points: Array[Dictionary] = []
	for vp in _vision_points:
		relative_points.append({
			"path_ratio": vp.path_ratio,
			"anchor": vp.anchor - start,  # 相対座標に変換
			"target_point": vp.target_point - start  # ターゲット地点も相対座標に変換
		})
	return relative_points


func is_drawing() -> bool:
	return _is_drawing or _is_drawing_vision or _is_extending_path


## 指定座標がパス上にあるかどうか判定
## @param ground_pos: 地面上の座標
## @return: path_click_threshold以内ならtrue
func is_point_on_path(ground_pos: Vector3) -> bool:
	if _pending_path.size() < 2:
		return false
	var result = _find_closest_point_on_path(ground_pos)
	return result.distance <= path_click_threshold


## マーカーモード（VISION_POINT, RUN_MARKER, CLEAR_MARKER）かどうか
func is_marker_mode() -> bool:
	return _drawing_mode != DrawingMode.MOVEMENT


func set_line_color(color: Color) -> void:
	line_color = color
	if _path_mesh:
		_path_mesh.set_line_color(color)


## キャラクター色を設定（パス線・マーカーに適用）
## @param color: キャラクター固有色
func set_character_color(color: Color) -> void:
	_character_color = color
	# パス線の色も更新
	set_line_color(Color(color.r, color.g, color.b, 0.9))


func enable(character: Node3D) -> void:
	_character = character
	_is_enabled = true
	_drawing_mode = DrawingMode.MOVEMENT
	clear()


## 既存の確定済みパスを読み込んで編集モードに入る
## @param character: 対象キャラクター
## @param path_data: PathExecutionManagerから取得したパスデータ
func restore_pending_path(character: Node3D, path_data: Dictionary) -> bool:
	if path_data.is_empty():
		return false

	# 既存の描画・マーカー状態をクリア
	clear()

	_character = character
	_is_enabled = true
	_drawing_mode = DrawingMode.MOVEMENT
	_pending_character = character as CharacterBody3D

	# パスを復元
	if path_data.has("path"):
		_pending_path.clear()
		for point in path_data["path"]:
			_pending_path.append(point)
		_path_points = _pending_path.duplicate()
	if _path_points.size() < 2:
		return false

	# パスメッシュをポイントから再描画（元の_path_meshを維持）
	if _path_mesh and _path_points.size() > 0:
		_path_mesh.update_from_points(_path_points)

	# PathExecutionManagerの古いpath_meshは削除
	if path_data.has("path_mesh") and is_instance_valid(path_data["path_mesh"]):
		path_data["path_mesh"].queue_free()

	# 履歴にPATHを追加（Undoでパスごと削除可能に）
	_marker_history.append(MarkerType.PATH)

	# Visionマーカーを復元（データとメッシュを同期して追加）
	var vision_points_list = path_data.get("vision_points", [])
	var vision_markers_list = path_data.get("vision_markers", [])
	for i in range(mini(vision_points_list.size(), vision_markers_list.size())):
		var marker = vision_markers_list[i]
		if is_instance_valid(marker):
			_vision_points.append(vision_points_list[i])
			if marker.get_parent():
				marker.get_parent().remove_child(marker)
			add_child(marker)
			_vision_meshes.append(marker)
			_marker_history.append(MarkerType.VISION)

	# Runマーカーを復元（データとメッシュを同期して追加）
	# Run: 1セグメント = 2マーカー（開始点・終了点）
	var run_segments_list = path_data.get("run_segments", [])
	var run_markers_list = path_data.get("run_markers", [])
	var run_marker_idx = 0
	for i in range(run_segments_list.size()):
		# 各セグメントには2つのマーカーが対応
		if run_marker_idx + 1 >= run_markers_list.size():
			break
		var start_marker = run_markers_list[run_marker_idx]
		var end_marker = run_markers_list[run_marker_idx + 1]
		if is_instance_valid(start_marker) and is_instance_valid(end_marker):
			_run_segments.append(run_segments_list[i])
			for marker in [start_marker, end_marker]:
				if marker.get_parent():
					marker.get_parent().remove_child(marker)
				add_child(marker)
				_run_meshes.append(marker)
			_marker_history.append(MarkerType.RUN)
		run_marker_idx += 2

	# Clearマーカーを復元（データとメッシュを同期して追加）
	var clear_points_list = path_data.get("clear_points", [])
	var clear_markers_list = path_data.get("clear_markers", [])
	for i in range(mini(clear_points_list.size(), clear_markers_list.size())):
		var marker = clear_markers_list[i]
		if is_instance_valid(marker):
			_clear_points.append(clear_points_list[i])
			if marker.get_parent():
				marker.get_parent().remove_child(marker)
			add_child(marker)
			_clear_meshes.append(marker)
			_marker_history.append(MarkerType.CLEAR)

	# Grenadeマーカーを復元（データとメッシュを同期して追加）
	var grenade_data_list = path_data.get("grenade_markers_data", [])
	var grenade_markers_list = path_data.get("grenade_markers", [])
	for i in range(mini(grenade_data_list.size(), grenade_markers_list.size())):
		var marker = grenade_markers_list[i]
		if is_instance_valid(marker):
			_grenade_markers.append(grenade_data_list[i])
			if marker.get_parent():
				marker.get_parent().remove_child(marker)
			add_child(marker)
			_grenade_meshes.append(marker)
			_marker_history.append(MarkerType.GRENADE)

	# Doorマーカーを復元（データとメッシュを同期して追加）
	var door_data_list = path_data.get("door_markers_data", [])
	var door_markers_list = path_data.get("door_markers", [])
	for i in range(mini(door_data_list.size(), door_markers_list.size())):
		var marker = door_markers_list[i]
		if is_instance_valid(marker):
			_door_markers.append(door_data_list[i])
			if marker.get_parent():
				marker.get_parent().remove_child(marker)
			add_child(marker)
			_door_meshes.append(marker)
			_marker_history.append(MarkerType.DOOR)

	# 復元完了後にパス準備完了を通知
	call_deferred("_emit_drawing_finished_after_restore")
	return true


func _emit_drawing_finished_after_restore() -> void:
	if _path_points.size() >= 2:
		drawing_finished.emit(_path_points)
		_notify_timeline_changed()


func disable() -> void:
	_is_enabled = false
	_is_drawing = false
	_is_extending_path = false
	_is_drawing_vision = false


func is_enabled() -> bool:
	return _is_enabled


func get_drawing_mode() -> DrawingMode:
	return _drawing_mode


## ========================================
## 視線ポイントモード API
## ========================================

## 視線ポイント設定モードに切り替え（ターゲットポイントモード）
## パス上をクリック→ドラッグでターゲット地点を設定
## キャラクターはマーカー到達後、移動しながらターゲット地点を見続ける
func start_vision_mode() -> bool:
	if _pending_path.size() < 2:
		return false

	_drawing_mode = DrawingMode.VISION_POINT
	_is_enabled = true
	mode_changed.emit(int(DrawingMode.VISION_POINT))
	return true


## 移動パス描画モードに戻る
func start_movement_mode() -> void:
	_drawing_mode = DrawingMode.MOVEMENT
	_path_points.clear()
	mode_changed.emit(int(DrawingMode.MOVEMENT))


## 視線ポイントがあるか
func has_vision_points() -> bool:
	return _vision_points.size() > 0


## 視線ポイントを取得
func get_vision_points() -> Array[Dictionary]:
	return _vision_points


## 視線ポイント数を取得（マルチモードの場合はアクティブキャラクターのカウント）
func get_vision_point_count() -> int:
	if _multi_character_mode and _active_edit_character:
		return get_vision_point_count_for_character(_active_edit_character)
	return _vision_points.size()


## 最後の視線ポイントを削除
func remove_last_vision_point() -> void:
	# マルチキャラクターモードの場合、アクティブキャラクターのデータから削除
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			if char_data.vision_points.size() > 0:
				char_data.vision_points.pop_back()
				if char_data.vision_meshes.size() > 0:
					var mesh = char_data.vision_meshes.pop_back()
					mesh.queue_free()
		return

	# シングルモード
	if _vision_points.size() > 0:
		_vision_points.pop_back()
		if _vision_meshes.size() > 0:
			var mesh = _vision_meshes.pop_back()
			mesh.queue_free()


## ========================================
## Runマーカーモード API
## ========================================

## Runマーカー設定モードに切り替え
func start_run_mode() -> bool:
	if _pending_path.size() < 2:
		return false

	_drawing_mode = DrawingMode.RUN_MARKER
	_is_enabled = true
	_current_run_start = {}  # 未完成の開始点をクリア
	mode_changed.emit(int(DrawingMode.RUN_MARKER))
	return true


## Run区間があるか
func has_run_segments() -> bool:
	return _run_segments.size() > 0


## Run区間を取得
func get_run_segments() -> Array[Dictionary]:
	return _run_segments


## Run区間数を取得（マルチモードの場合はアクティブキャラクターのカウント）
func get_run_segment_count() -> int:
	if _multi_character_mode and _active_edit_character:
		return get_run_segment_count_for_character(_active_edit_character)
	return _run_segments.size()


## 最後のRun区間を削除
func remove_last_run_segment() -> void:
	# マルチキャラクターモードの場合、アクティブキャラクターのデータから削除
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			if char_data.run_segments.size() > 0:
				char_data.run_segments.pop_back()
				# 終点マーカーを削除
				if char_data.run_meshes.size() > 0:
					var mesh = char_data.run_meshes.pop_back()
					mesh.queue_free()
				# 開始点マーカーも削除
				if char_data.run_meshes.size() > 0:
					var mesh = char_data.run_meshes.pop_back()
					mesh.queue_free()
			elif not _current_run_start.is_empty():
				# 未完成の開始点がある場合はそれを削除
				_current_run_start = {}
				if char_data.run_meshes.size() > 0:
					var mesh = char_data.run_meshes.pop_back()
					mesh.queue_free()
		return

	# シングルモード
	if _run_segments.size() > 0:
		_run_segments.pop_back()
		# 終点マーカーを削除
		if _run_meshes.size() > 0:
			var mesh = _run_meshes.pop_back()
			mesh.queue_free()
		# 開始点マーカーも削除
		if _run_meshes.size() > 0:
			var mesh = _run_meshes.pop_back()
			mesh.queue_free()
	elif not _current_run_start.is_empty():
		# 未完成の開始点がある場合はそれを削除
		_current_run_start = {}
		if _run_meshes.size() > 0:
			var mesh = _run_meshes.pop_back()
			mesh.queue_free()


## 未完成のRun開始点があるか
func has_incomplete_run_start() -> bool:
	return not _current_run_start.is_empty()


## ========================================
## Clearマーカーモード API
## ========================================

## Clearマーカー設定モードに切り替え
## パス上をクリックでClearポイントを設定
## このポイント以降はVision/Runがクリアされ、進行方向を向く
func start_clear_mode() -> bool:
	if _pending_path.size() < 2:
		return false

	_drawing_mode = DrawingMode.CLEAR_MARKER
	_is_enabled = true
	mode_changed.emit(int(DrawingMode.CLEAR_MARKER))
	return true


## Clearポイントがあるか
func has_clear_points() -> bool:
	return _clear_points.size() > 0


## Clearポイントを取得
func get_clear_points() -> Array[Dictionary]:
	return _clear_points


## Clearポイント数を取得（マルチモードの場合はアクティブキャラクターのカウント）
func get_clear_point_count() -> int:
	if _multi_character_mode and _active_edit_character:
		return get_clear_point_count_for_character(_active_edit_character)
	return _clear_points.size()


## 最後のClearポイントを削除
func remove_last_clear_point() -> void:
	# マルチキャラクターモードの場合、アクティブキャラクターのデータから削除
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			if char_data.clear_points.size() > 0:
				char_data.clear_points.pop_back()
				if char_data.clear_meshes.size() > 0:
					var mesh = char_data.clear_meshes.pop_back()
					mesh.queue_free()
		return

	# シングルモード
	if _clear_points.size() > 0:
		_clear_points.pop_back()
		if _clear_meshes.size() > 0:
			var mesh = _clear_meshes.pop_back()
			mesh.queue_free()


## 最後に追加したマーカーを削除（種別を問わない統一Undo）
## @return: 削除したマーカーの種別（何もなければ-1）
func undo_last_marker() -> int:
	var last_type: int = -1

	# マルチキャラクターモードの場合
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_history: Array[int] = _character_markers[char_id].marker_history
			# キャラクター別履歴にマーカーがあればそれをUndo
			if char_history.size() > 0:
				last_type = char_history.pop_back()
			# キャラクター別履歴が空なら、共通履歴（PATH）をチェック
			elif _marker_history.size() > 0:
				last_type = _marker_history.pop_back()
	else:
		# シングルモードは共通履歴を使用
		if _marker_history.size() > 0:
			last_type = _marker_history.pop_back()

	if last_type == -1:
		return -1

	match last_type:
		MarkerType.VISION:
			_undo_vision_marker()
		MarkerType.RUN:
			_undo_run_marker()
		MarkerType.CLEAR:
			_undo_clear_marker()
		MarkerType.PATH:
			_undo_path()
		MarkerType.GRENADE:
			_undo_grenade_marker()
		MarkerType.SMOKE_GRENADE:
			_undo_smoke_grenade_marker()
		MarkerType.DOOR:
			_undo_door_marker()
		MarkerType.PATH_EXTENSION:
			_undo_path_extension()
		MarkerType.WAIT:
			_undo_wait_marker()

	# MarkerCollectionもUndo（同期を保つ）
	# Note: PATH/PATH_EXTENSIONは共通履歴なのでMarkerCollectionには影響なし
	if last_type != MarkerType.PATH and last_type != MarkerType.PATH_EXTENSION and _multi_character_mode and _active_edit_character:
		_undo_last_marker_from_collection(_active_edit_character)

	# タイムライン更新シグナルを発火（PATHは_undo_path内で発火済み）
	if last_type != MarkerType.PATH:
		_notify_timeline_changed()

	return last_type


## Vision マーカーをUndo（内部用、履歴は操作しない）
func _undo_vision_marker() -> void:
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			if char_data.vision_points.size() > 0:
				char_data.vision_points.pop_back()
				if char_data.vision_meshes.size() > 0:
					var mesh = char_data.vision_meshes.pop_back()
					mesh.queue_free()
		return

	if _vision_points.size() > 0:
		_vision_points.pop_back()
		if _vision_meshes.size() > 0:
			var mesh = _vision_meshes.pop_back()
			mesh.queue_free()


## Run マーカーをUndo（内部用、履歴は操作しない）
func _undo_run_marker() -> void:
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			if char_data.run_segments.size() > 0:
				char_data.run_segments.pop_back()
				# 終点マーカーを削除
				if char_data.run_meshes.size() > 0:
					var mesh = char_data.run_meshes.pop_back()
					mesh.queue_free()
				# 開始点マーカーも削除
				if char_data.run_meshes.size() > 0:
					var mesh = char_data.run_meshes.pop_back()
					mesh.queue_free()
			elif not _current_run_start.is_empty():
				# 未完成の開始点がある場合はそれを削除
				_current_run_start = {}
				if char_data.run_meshes.size() > 0:
					var mesh = char_data.run_meshes.pop_back()
					mesh.queue_free()
		return

	if _run_segments.size() > 0:
		_run_segments.pop_back()
		# 終点マーカーを削除
		if _run_meshes.size() > 0:
			var mesh = _run_meshes.pop_back()
			mesh.queue_free()
		# 開始点マーカーも削除
		if _run_meshes.size() > 0:
			var mesh = _run_meshes.pop_back()
			mesh.queue_free()
	elif not _current_run_start.is_empty():
		# 未完成の開始点がある場合はそれを削除
		_current_run_start = {}
		if _run_meshes.size() > 0:
			var mesh = _run_meshes.pop_back()
			mesh.queue_free()


## Clear マーカーをUndo（内部用、履歴は操作しない）
func _undo_clear_marker() -> void:
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			if char_data.clear_points.size() > 0:
				char_data.clear_points.pop_back()
				if char_data.clear_meshes.size() > 0:
					var mesh = char_data.clear_meshes.pop_back()
					mesh.queue_free()
		return

	if _clear_points.size() > 0:
		_clear_points.pop_back()
		if _clear_meshes.size() > 0:
			var mesh = _clear_meshes.pop_back()
			mesh.queue_free()


## Grenade マーカーをUndo（内部用、履歴は操作しない）
func _undo_grenade_marker() -> void:
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			if char_data.grenade_markers.size() > 0:
				char_data.grenade_markers.pop_back()
				if char_data.grenade_meshes.size() > 0:
					var mesh = char_data.grenade_meshes.pop_back()
					if is_instance_valid(mesh):
						mesh.queue_free()
		return

	if _grenade_markers.size() > 0:
		_grenade_markers.pop_back()
		if _grenade_meshes.size() > 0:
			var mesh = _grenade_meshes.pop_back()
			if is_instance_valid(mesh):
				mesh.queue_free()


## Smoke Grenade マーカーをUndo（内部用、履歴は操作しない）
func _undo_smoke_grenade_marker() -> void:
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			if char_data.smoke_grenade_markers.size() > 0:
				char_data.smoke_grenade_markers.pop_back()
				if char_data.smoke_grenade_meshes.size() > 0:
					var mesh = char_data.smoke_grenade_meshes.pop_back()
					if is_instance_valid(mesh):
						mesh.queue_free()
		return

	if _smoke_grenade_markers.size() > 0:
		_smoke_grenade_markers.pop_back()
		if _smoke_grenade_meshes.size() > 0:
			var mesh = _smoke_grenade_meshes.pop_back()
			if is_instance_valid(mesh):
				mesh.queue_free()


## Door マーカーをUndo（内部用、履歴は操作しない）
func _undo_door_marker() -> void:
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			if char_data.door_markers.size() > 0:
				char_data.door_markers.pop_back()
				if char_data.door_meshes.size() > 0:
					var mesh = char_data.door_meshes.pop_back()
					if is_instance_valid(mesh):
						mesh.queue_free()
		return

	if _door_markers.size() > 0:
		_door_markers.pop_back()
		if _door_meshes.size() > 0:
			var mesh = _door_meshes.pop_back()
			if is_instance_valid(mesh):
				mesh.queue_free()


## パス拡張をUndo（内部用、履歴は操作しない）
## 拡張前のパス状態に戻す
func _undo_path_extension() -> void:
	if _path_extension_snapshots.size() == 0:
		return

	# 拡張前のパスに戻す
	var previous_path = _path_extension_snapshots.pop_back()
	_pending_path = previous_path
	_path_points = previous_path.duplicate()

	# パスメッシュを更新
	if _path_mesh:
		_path_mesh.update_from_points(_path_points)

	# マーカーのpath_ratioを再計算（パスが短くなったため）
	_recalculate_marker_ratios()


## パス描画をUndo（内部用、履歴は操作しない）
## パスとすべてのマーカーをクリアする
func _undo_path() -> void:
	# パスをクリア
	_path_points.clear()
	_path_mesh.clear()
	_pending_path.clear()
	_pending_character = null
	_path_extension_snapshots.clear()
	_is_drawing = false
	_is_drawing_vision = false
	_drawing_mode = DrawingMode.MOVEMENT

	# すべてのマーカーをクリア
	_clear_vision_points()
	_clear_run_markers()
	_clear_clear_markers()
	_clear_grenade_markers()
	_clear_door_markers()

	# マルチキャラクターモードのマーカーもクリア
	if _multi_character_mode:
		for char_id in _character_markers:
			var data = _character_markers[char_id]
			for mesh in data.vision_meshes:
				if is_instance_valid(mesh):
					mesh.queue_free()
			for mesh in data.run_meshes:
				if is_instance_valid(mesh):
					mesh.queue_free()
			for mesh in data.clear_meshes:
				if is_instance_valid(mesh):
					mesh.queue_free()
			for mesh in data.grenade_meshes:
				if is_instance_valid(mesh):
					mesh.queue_free()
			for mesh in data.door_meshes:
				if is_instance_valid(mesh):
					mesh.queue_free()
			if data.has("wait_meshes"):
				for mesh in data.wait_meshes:
					if is_instance_valid(mesh):
						mesh.queue_free()
			data.vision_points.clear()
			data.vision_meshes.clear()
			data.run_segments.clear()
			data.run_meshes.clear()
			data.clear_points.clear()
			data.clear_meshes.clear()
			data.grenade_markers.clear()
			data.grenade_meshes.clear()
			data.door_markers.clear()
			data.door_meshes.clear()
			if data.has("wait_markers"):
				data.wait_markers.clear()
			if data.has("wait_meshes"):
				data.wait_meshes.clear()
			data.marker_history.clear()

		# MarkerCollectionもクリア（メッシュは上で既にfreeしているので履歴・データのみ）
		for char_id in _character_collections:
			var collection = _character_collections[char_id]
			if collection:
				collection.clear_all()

	# シグナルを発火
	path_undone.emit()
	_notify_timeline_changed()


## ========================================
## パス実行 API
## ========================================

func execute(run: bool = false) -> bool:
	if _pending_path.size() < 2 or _pending_character == null:
		return false

	var path_array: Array[Vector3] = []
	for point in _pending_path:
		path_array.append(point)
	_pending_character.set_path(path_array, run)

	_executing_character = _pending_character

	if not _executing_character.path_completed.is_connected(_on_path_completed):
		_executing_character.path_completed.connect(_on_path_completed)

	_pending_path.clear()
	_pending_character = null

	return true


## 視線ポイント付きでパスを実行
func execute_with_vision(run: bool = false) -> bool:
	if _pending_path.size() < 2 or _pending_character == null:
		return false

	var path_array: Array[Vector3] = []
	for point in _pending_path:
		path_array.append(point)

	# 視線ポイント付きで移動開始
	if _vision_points.size() > 0:
		_pending_character.set_path_with_vision_points(path_array, _vision_points.duplicate(), run)
	else:
		_pending_character.set_path(path_array, run)

	_executing_character = _pending_character

	if not _executing_character.path_completed.is_connected(_on_path_completed):
		_executing_character.path_completed.connect(_on_path_completed)

	var _vision_count = _vision_points.size()
	_pending_path.clear()
	_vision_points.clear()
	_pending_character = null

	return true


func has_pending_path() -> bool:
	return _pending_path.size() >= 2 and _pending_character != null


## プレビュー用パスがあるか（描画中/拡張中/確定済みを含む）
func has_preview_path() -> bool:
	# 描画中または拡張中は_path_pointsを使用
	if _is_drawing or _is_extending_path:
		return _path_points.size() >= 2 and _character != null
	# それ以外は確定済みパスを使用
	return has_pending_path()


## プレビュー用パスを取得（描画中は_path_points、それ以外は_pending_path）
func get_preview_path() -> PackedVector3Array:
	if _is_drawing or _is_extending_path:
		return _path_points
	return _pending_path


func clear_pending() -> void:
	_pending_path.clear()
	_pending_character = null
	_clear_vision_points()
	_clear_run_markers()
	_clear_clear_markers()


func _on_path_completed() -> void:
	if _executing_character:
		if _executing_character.path_completed.is_connected(_on_path_completed):
			_executing_character.path_completed.disconnect(_on_path_completed)
		_executing_character = null

	clear()


## ========================================
## マルチキャラクターマーカー管理 API
## ========================================

## マルチキャラクターモードを開始
## @param characters: 対象キャラクター配列
func start_multi_character_mode(characters: Array[Node]) -> void:
	_multi_character_mode = true
	_character_markers.clear()
	_character_collections.clear()

	# 各キャラクター用のマーカーストレージを初期化
	for character in characters:
		var char_id = character.get_instance_id()
		# 従来のDictionary形式（後方互換）
		_character_markers[char_id] = {
			"character": character,
			"vision_points": [] as Array[Dictionary],
			"vision_meshes": [] as Array[MeshInstance3D],
			"run_segments": [] as Array[Dictionary],
			"run_meshes": [] as Array[MeshInstance3D],
			"clear_points": [] as Array[Dictionary],
			"clear_meshes": [] as Array[MeshInstance3D],
			"grenade_markers": [] as Array[Dictionary],
			"grenade_meshes": [] as Array[MeshInstance3D],
			"smoke_grenade_markers": [] as Array[Dictionary],
			"smoke_grenade_meshes": [] as Array[MeshInstance3D],
			"door_markers": [] as Array[Dictionary],
			"door_meshes": [] as Array[MeshInstance3D],
			"marker_history": [] as Array[int]
		}
		# 新しいMarkerCollection形式
		_character_collections[char_id] = MarkerCollectionScript.new()

	# 最初のキャラクターをアクティブに設定
	if characters.size() > 0:
		set_active_edit_character(characters[0])



## マルチキャラクターモードを終了
func end_multi_character_mode() -> void:
	_multi_character_mode = false
	_active_edit_character = null
	# マーカーデータはclear時にクリーンアップ


## 編集対象キャラクターを設定
## @param character: 編集対象キャラクター
func set_active_edit_character(character: Node) -> void:
	if not _multi_character_mode:
		_active_edit_character = character
		return

	if not character:
		return

	var char_id = character.get_instance_id()
	if not _character_markers.has(char_id):
		return

	_active_edit_character = character

	# キャラクター色を適用
	var char_color = CharacterColorManager.get_character_color(character)
	_character_color = char_color



## アクティブな編集キャラクターを取得
func get_active_edit_character() -> Node:
	return _active_edit_character


## マルチキャラクターモードかどうか
func is_multi_character_mode() -> bool:
	return _multi_character_mode


## キャラクター別の視線ポイント数を取得
func get_vision_point_count_for_character(character: Node) -> int:
	if not character:
		return 0
	var char_id = character.get_instance_id()
	if _character_markers.has(char_id):
		return _character_markers[char_id].vision_points.size()
	return 0


## キャラクター別のRun区間数を取得
func get_run_segment_count_for_character(character: Node) -> int:
	if not character:
		return 0
	var char_id = character.get_instance_id()
	if _character_markers.has(char_id):
		return _character_markers[char_id].run_segments.size()
	return 0


## キャラクター別の視線ポイントを取得
func get_vision_points_for_character(character: Node) -> Array[Dictionary]:
	if not character:
		return []
	var char_id = character.get_instance_id()
	if _character_markers.has(char_id):
		return _character_markers[char_id].vision_points
	return []


## キャラクター別のRun区間を取得
func get_run_segments_for_character(character: Node) -> Array[Dictionary]:
	if not character:
		return []
	var char_id = character.get_instance_id()
	if _character_markers.has(char_id):
		return _character_markers[char_id].run_segments
	return []


## キャラクター別のClearポイント数を取得
func get_clear_point_count_for_character(character: Node) -> int:
	if not character:
		return 0
	var char_id = character.get_instance_id()
	if _character_markers.has(char_id):
		return _character_markers[char_id].clear_points.size()
	return 0


## キャラクター別のClearポイントを取得
func get_clear_points_for_character(character: Node) -> Array[Dictionary]:
	if not character:
		return []
	var char_id = character.get_instance_id()
	if _character_markers.has(char_id):
		return _character_markers[char_id].clear_points
	return []


## 全キャラクターの視線ポイントを取得
## @return { char_id: Array[Dictionary] }
func get_all_vision_points() -> Dictionary:
	if not _multi_character_mode:
		# シングルモードの場合、現在のキャラクターIDで返す
		if _active_edit_character:
			return { _active_edit_character.get_instance_id(): _vision_points }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		result[char_id] = _character_markers[char_id].vision_points
	return result


## 全キャラクターのRun区間を取得
## @return { char_id: Array[Dictionary] }
func get_all_run_segments() -> Dictionary:
	if not _multi_character_mode:
		if _active_edit_character:
			return { _active_edit_character.get_instance_id(): _run_segments }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		result[char_id] = _character_markers[char_id].run_segments
	return result


## 全キャラクターのClearポイントを取得
## @return { char_id: Array[Dictionary] }
func get_all_clear_points() -> Dictionary:
	if not _multi_character_mode:
		if _active_edit_character:
			return { _active_edit_character.get_instance_id(): _clear_points }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		result[char_id] = _character_markers[char_id].clear_points
	return result


## マルチキャラクターモードで全マーカーをクリア
func _clear_multi_character_markers() -> void:
	for char_id in _character_markers:
		var data = _character_markers[char_id]
		for mesh in data.vision_meshes:
			if is_instance_valid(mesh):
				mesh.queue_free()
		for mesh in data.run_meshes:
			if is_instance_valid(mesh):
				mesh.queue_free()
		for mesh in data.clear_meshes:
			if is_instance_valid(mesh):
				mesh.queue_free()
		if data.has("grenade_meshes"):
			for mesh in data.grenade_meshes:
				if is_instance_valid(mesh):
					mesh.queue_free()
		if data.has("smoke_grenade_meshes"):
			for mesh in data.smoke_grenade_meshes:
				if is_instance_valid(mesh):
					mesh.queue_free()
		if data.has("door_meshes"):
			for mesh in data.door_meshes:
				if is_instance_valid(mesh):
					mesh.queue_free()
		if data.has("wait_meshes"):
			for mesh in data.wait_meshes:
				if is_instance_valid(mesh):
					mesh.queue_free()
	_character_markers.clear()

	# MarkerCollectionもクリア
	for char_id in _character_collections:
		var collection = _character_collections[char_id]
		if collection:
			collection.clear_all()
	_character_collections.clear()

	_active_edit_character = null
	_multi_character_mode = false


## 全キャラクターのVisionMarkersを移譲
## @return { char_id: Array[MeshInstance3D] }
func take_all_vision_markers() -> Dictionary:
	if not _multi_character_mode:
		if _active_edit_character:
			var markers = _vision_meshes.duplicate()
			_vision_meshes.clear()
			return { _active_edit_character.get_instance_id(): markers }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		result[char_id] = _character_markers[char_id].vision_meshes.duplicate()
		_character_markers[char_id].vision_meshes.clear()
	return result


## 全キャラクターのRunMarkersを移譲
## @return { char_id: Array[MeshInstance3D] }
func take_all_run_markers() -> Dictionary:
	if not _multi_character_mode:
		if _active_edit_character:
			var markers = _run_meshes.duplicate()
			_run_meshes.clear()
			return { _active_edit_character.get_instance_id(): markers }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		result[char_id] = _character_markers[char_id].run_meshes.duplicate()
		_character_markers[char_id].run_meshes.clear()
	return result


## 全キャラクターのClearMarkersを移譲
## @return { char_id: Array[MeshInstance3D] }
func take_all_clear_markers() -> Dictionary:
	if not _multi_character_mode:
		if _active_edit_character:
			var markers = _clear_meshes.duplicate()
			_clear_meshes.clear()
			return { _active_edit_character.get_instance_id(): markers }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		result[char_id] = _character_markers[char_id].clear_meshes.duplicate()
		_character_markers[char_id].clear_meshes.clear()
	return result


## 全キャラクターのGrenadeMarkersを移譲
## @return { char_id: Array[MeshInstance3D] }
func take_all_grenade_markers() -> Dictionary:
	if not _multi_character_mode:
		if _active_edit_character:
			var markers = _grenade_meshes.duplicate()
			_grenade_meshes.clear()
			return { _active_edit_character.get_instance_id(): markers }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		if _character_markers[char_id].has("grenade_meshes"):
			result[char_id] = _character_markers[char_id].grenade_meshes.duplicate()
			_character_markers[char_id].grenade_meshes.clear()
		else:
			result[char_id] = []
	return result


## 全キャラクターのDoorMarkersを移譲
## @return { char_id: Array[MeshInstance3D] }
func take_all_door_markers() -> Dictionary:
	if not _multi_character_mode:
		if _active_edit_character:
			var markers = _door_meshes.duplicate()
			_door_meshes.clear()
			return { _active_edit_character.get_instance_id(): markers }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		if _character_markers[char_id].has("door_meshes"):
			result[char_id] = _character_markers[char_id].door_meshes.duplicate()
			_character_markers[char_id].door_meshes.clear()
		else:
			result[char_id] = []
	return result


## 全キャラクターのSmokeGrenadeMarkersを移譲
## @return { char_id: Array[MeshInstance3D] }
func take_all_smoke_grenade_markers() -> Dictionary:
	if not _multi_character_mode:
		if _active_edit_character:
			var markers = _smoke_grenade_meshes.duplicate()
			_smoke_grenade_meshes.clear()
			return { _active_edit_character.get_instance_id(): markers }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		if _character_markers[char_id].has("smoke_grenade_meshes"):
			result[char_id] = _character_markers[char_id].smoke_grenade_meshes.duplicate()
			_character_markers[char_id].smoke_grenade_meshes.clear()
		else:
			result[char_id] = []
	return result


## ========================================
## グレネードマーカーモード API
## ========================================

## グレネードマーカー設定モードに切り替え
## 1. パス上をクリック → 投擲位置（path_ratio）設定
## 2. 目標クリック → 床なら完了、壁ならバウンスポイント設定
## 3. （壁の場合）最終目標クリック → バウンス投擲設定完了
func start_grenade_mode() -> bool:
	if _pending_path.size() < 2:
		return false

	_drawing_mode = DrawingMode.GRENADE_MARKER
	_is_enabled = true
	# グレネードモード状態をリセット
	_grenade_has_anchor = false
	_grenade_pending_anchor = Vector3.ZERO
	_grenade_pending_ratio = 0.0
	_grenade_has_bounce = false
	_grenade_bounce_point = Vector3.ZERO
	_grenade_bounce_normal = Vector3.ZERO
	mode_changed.emit(int(DrawingMode.GRENADE_MARKER))
	return true


## グレネードマーカー入力処理
func _handle_grenade_marker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_process_grenade_click(mouse_event.position)
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		# 軌道プレビュー更新
		_update_grenade_trajectory_preview_at(event.position)


## グレネードクリック処理
func _process_grenade_click(screen_pos: Vector2) -> void:
	if not _grenade_has_anchor:
		# 1. パス上クリック → 投擲位置を設定
		var ground_pos = _get_ground_position(screen_pos)
		if ground_pos == null:
			return

		var result = _find_closest_point_on_path(ground_pos)
		if result.distance > path_click_threshold:
			return

		_grenade_pending_anchor = result.point
		_grenade_pending_ratio = result.ratio
		_grenade_has_anchor = true
		_setup_grenade_trajectory_mesh()
	elif not _grenade_has_bounce:
		# 2. 目標クリック
		var target_result = _raycast_wall_or_floor(screen_pos)
		if target_result.is_empty():
			return

		var hit_pos: Vector3 = target_result.position
		var hit_normal: Vector3 = target_result.normal

		# 壁かどうか判定
		var is_wall = abs(hit_normal.y) < 0.5

		if is_wall:
			# 壁の場合: バウンスポイントを設定
			hit_pos.y = 1.0  # グレネードが壁に当たる高さ
			_grenade_bounce_point = hit_pos
			_grenade_bounce_normal = hit_normal
			_grenade_has_bounce = true
		else:
			# 床の場合: 直接投擲完了
			_finish_grenade_marker(hit_pos, Vector3.ZERO, Vector3.ZERO)
	else:
		# 3. バウンス後の最終目標クリック
		var ground_pos = _get_ground_position(screen_pos)
		if ground_pos == null:
			return

		_finish_grenade_marker(ground_pos, _grenade_bounce_point, _grenade_bounce_normal)


## グレネードマーカーを完成させる
func _finish_grenade_marker(target_pos: Vector3, bounce_point: Vector3, bounce_normal: Vector3) -> void:
	var has_bounce = bounce_point.length_squared() > 0.001
	var new_marker = {
		"path_ratio": _grenade_pending_ratio,
		"anchor": _grenade_pending_anchor,
		"target_pos": target_pos,
		"bounce_point": bounce_point if has_bounce else Vector3.ZERO,
		"bounce_normal": bounce_normal if has_bounce else Vector3.ZERO
	}

	# マルチキャラクターモードの場合
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			char_data.grenade_markers.append(new_marker)

			# マーカーメッシュを作成
			var marker = _create_grenade_marker_node(_grenade_pending_anchor, target_pos, bounce_point)
			char_data.grenade_meshes.append(marker)

			# 履歴に追加
			char_data.marker_history.append(MarkerType.GRENADE)

			# MarkerCollectionにも追加（新システム）
			var grenade_data = ActionMarkerDataScript.GrenadeMarkerData.new()
			grenade_data.path_ratio = _grenade_pending_ratio
			grenade_data.anchor = _grenade_pending_anchor
			grenade_data.target_pos = target_pos
			grenade_data.bounce_point = bounce_point if has_bounce else Vector3.ZERO
			grenade_data.bounce_normal = bounce_normal if has_bounce else Vector3.ZERO
			grenade_data.has_bounce = has_bounce
			_add_marker_to_collection(_active_edit_character, grenade_data, marker)
	else:
		# シングルモード
		_grenade_markers.append(new_marker)

		# マーカーメッシュを作成
		var marker = _create_grenade_marker_node(_grenade_pending_anchor, target_pos, bounce_point)
		_grenade_meshes.append(marker)

		# 履歴に追加
		_marker_history.append(MarkerType.GRENADE)

	grenade_marker_added.emit(_grenade_pending_ratio, target_pos)
	_notify_timeline_changed()

	# 状態をリセット
	_grenade_has_anchor = false
	_grenade_pending_anchor = Vector3.ZERO
	_grenade_pending_ratio = 0.0
	_grenade_has_bounce = false
	_grenade_bounce_point = Vector3.ZERO
	_grenade_bounce_normal = Vector3.ZERO
	_cleanup_grenade_trajectory_mesh()


## グレネードマーカーノードを作成
func _create_grenade_marker_node(anchor: Vector3, target: Vector3, bounce: Vector3) -> MeshInstance3D:
	var marker = MeshInstance3D.new()
	marker.set_script(GrenadeMarkerScript)
	add_child(marker)
	marker.set_position_and_target(anchor, target, bounce)
	marker.set_colors(_character_color, Color(1.0, 0.5, 0.0, 1.0))
	marker.set_trajectory_color(Color(_character_color.r, _character_color.g * 0.7, _character_color.b * 0.3, 0.8))
	return marker


## グレネード軌道プレビューメッシュをセットアップ
func _setup_grenade_trajectory_mesh() -> void:
	if _grenade_trajectory_mesh:
		return

	_grenade_trajectory_mesh = MeshInstance3D.new()
	_grenade_trajectory_mesh.name = "GrenadeTrajectoryPreview"
	add_child(_grenade_trajectory_mesh)

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.5, 0.0, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grenade_trajectory_mesh.material_override = mat


## グレネード軌道プレビューを更新
func _update_grenade_trajectory_preview_at(screen_pos: Vector2) -> void:
	if not _grenade_has_anchor or not _grenade_trajectory_mesh:
		return

	var target_pos = _get_ground_position(screen_pos)
	if target_pos == null:
		var wall_result = _raycast_wall_or_floor(screen_pos)
		if wall_result.is_empty():
			return
		target_pos = wall_result.position

	var im = ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	var start_pos = _grenade_pending_anchor + Vector3(0, 0.05, 0)

	if _grenade_has_bounce:
		# バウンスポイント設定済み: アンカー → バウンス → ターゲット
		im.surface_add_vertex(start_pos)
		im.surface_add_vertex(_grenade_bounce_point)
		im.surface_add_vertex(_grenade_bounce_point)
		im.surface_add_vertex(target_pos)
	else:
		# バウンスなし: アンカー → ターゲット
		im.surface_add_vertex(start_pos)
		im.surface_add_vertex(target_pos)

	im.surface_end()
	_grenade_trajectory_mesh.mesh = im


## グレネード軌道プレビューを削除
func _cleanup_grenade_trajectory_mesh() -> void:
	if _grenade_trajectory_mesh:
		_grenade_trajectory_mesh.queue_free()
		_grenade_trajectory_mesh = null


## 壁または床へのレイキャスト
func _raycast_wall_or_floor(screen_pos: Vector2) -> Dictionary:
	if not _camera:
		return {}

	var ray_origin = _camera.project_ray_origin(screen_pos)
	var ray_dir = _camera.project_ray_normal(screen_pos)
	var ray_end = ray_origin + ray_dir * 100.0

	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return {}

	# 壁と床の両方を検出
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 3)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	return space_state.intersect_ray(query)


## グレネードマーカーがあるか
func has_grenade_markers() -> bool:
	return _grenade_markers.size() > 0


## グレネードマーカーを取得
func get_grenade_markers() -> Array[Dictionary]:
	return _grenade_markers


## グレネードマーカー数を取得
func get_grenade_marker_count() -> int:
	if _multi_character_mode and _active_edit_character:
		return get_grenade_marker_count_for_character(_active_edit_character)
	return _grenade_markers.size()


## キャラクター別のグレネードマーカー数を取得
func get_grenade_marker_count_for_character(character: Node) -> int:
	if not character:
		return 0
	var char_id = character.get_instance_id()
	if _character_markers.has(char_id) and _character_markers[char_id].has("grenade_markers"):
		return _character_markers[char_id].grenade_markers.size()
	return 0


## キャラクター別のグレネードマーカーを取得
func get_grenade_markers_for_character(character: Node) -> Array[Dictionary]:
	if not character:
		return []
	var char_id = character.get_instance_id()
	if _character_markers.has(char_id) and _character_markers[char_id].has("grenade_markers"):
		return _character_markers[char_id].grenade_markers
	return []


## 全キャラクターのグレネードマーカーを取得
func get_all_grenade_markers() -> Dictionary:
	if not _multi_character_mode:
		if _active_edit_character:
			return { _active_edit_character.get_instance_id(): _grenade_markers }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		if _character_markers[char_id].has("grenade_markers"):
			result[char_id] = _character_markers[char_id].grenade_markers
		else:
			result[char_id] = []
	return result


## ========================================
## スモークグレネードマーカーモード API
## ========================================

## スモークグレネードマーカー設定モードに切り替え
func start_smoke_grenade_mode() -> bool:
	if _pending_path.size() < 2:
		return false

	_drawing_mode = DrawingMode.SMOKE_GRENADE_MARKER
	_is_enabled = true
	# スモークグレネードモード状態をリセット
	_smoke_grenade_has_anchor = false
	_smoke_grenade_pending_anchor = Vector3.ZERO
	_smoke_grenade_pending_ratio = 0.0
	_smoke_grenade_has_bounce = false
	_smoke_grenade_bounce_point = Vector3.ZERO
	_smoke_grenade_bounce_normal = Vector3.ZERO
	mode_changed.emit(int(DrawingMode.SMOKE_GRENADE_MARKER))
	return true


## スモークグレネードマーカー入力処理
func _handle_smoke_grenade_marker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_process_smoke_grenade_click(mouse_event.position)
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		# 軌道プレビュー更新
		_update_smoke_grenade_trajectory_preview_at(event.position)


## スモークグレネードクリック処理
func _process_smoke_grenade_click(screen_pos: Vector2) -> void:
	if not _smoke_grenade_has_anchor:
		# 1. パス上クリック → 投擲位置を設定
		var ground_pos = _get_ground_position(screen_pos)
		if ground_pos == null:
			return

		var result = _find_closest_point_on_path(ground_pos)
		if result.distance > path_click_threshold:
			return

		_smoke_grenade_pending_anchor = result.point
		_smoke_grenade_pending_ratio = result.ratio
		_smoke_grenade_has_anchor = true
		_setup_smoke_grenade_trajectory_mesh()
	elif not _smoke_grenade_has_bounce:
		# 2. 目標クリック
		var target_result = _raycast_wall_or_floor(screen_pos)
		if target_result.is_empty():
			return

		var hit_pos: Vector3 = target_result.position
		var hit_normal: Vector3 = target_result.normal

		# 壁かどうか判定
		var is_wall = abs(hit_normal.y) < 0.5

		if is_wall:
			# 壁の場合: バウンスポイントを設定
			hit_pos.y = 1.0
			_smoke_grenade_bounce_point = hit_pos
			_smoke_grenade_bounce_normal = hit_normal
			_smoke_grenade_has_bounce = true
		else:
			# 床の場合: 直接投擲完了
			_finish_smoke_grenade_marker(hit_pos, Vector3.ZERO, Vector3.ZERO)
	else:
		# 3. バウンス後の最終目標クリック
		var ground_pos = _get_ground_position(screen_pos)
		if ground_pos == null:
			return

		_finish_smoke_grenade_marker(ground_pos, _smoke_grenade_bounce_point, _smoke_grenade_bounce_normal)


## スモークグレネードマーカーを完成させる
func _finish_smoke_grenade_marker(target_pos: Vector3, bounce_point: Vector3, bounce_normal: Vector3) -> void:
	var has_bounce = bounce_point.length_squared() > 0.001
	var new_marker = {
		"path_ratio": _smoke_grenade_pending_ratio,
		"anchor": _smoke_grenade_pending_anchor,
		"target_pos": target_pos,
		"bounce_point": bounce_point if has_bounce else Vector3.ZERO,
		"bounce_normal": bounce_normal if has_bounce else Vector3.ZERO
	}

	# マルチキャラクターモードの場合
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			if not char_data.has("smoke_grenade_markers"):
				char_data["smoke_grenade_markers"] = []
				char_data["smoke_grenade_meshes"] = []
			char_data.smoke_grenade_markers.append(new_marker)

			# マーカーメッシュを作成
			var marker = _create_smoke_grenade_marker_node(_smoke_grenade_pending_anchor, target_pos, bounce_point)
			char_data.smoke_grenade_meshes.append(marker)

			# 履歴に追加
			char_data.marker_history.append(MarkerType.SMOKE_GRENADE)

			# MarkerCollectionにも追加
			var smoke_data = ActionMarkerDataScript.SmokeGrenadeMarkerData.new()
			smoke_data.path_ratio = _smoke_grenade_pending_ratio
			smoke_data.anchor = _smoke_grenade_pending_anchor
			smoke_data.target_pos = target_pos
			smoke_data.bounce_point = bounce_point
			smoke_data.bounce_normal = bounce_normal
			smoke_data.has_bounce = has_bounce
			_add_marker_to_collection(_active_edit_character, smoke_data, marker)
	else:
		# シングルモード
		_smoke_grenade_markers.append(new_marker)

		# マーカーメッシュを作成
		var marker = _create_smoke_grenade_marker_node(_smoke_grenade_pending_anchor, target_pos, bounce_point)
		_smoke_grenade_meshes.append(marker)

		# 履歴に追加
		_marker_history.append(MarkerType.SMOKE_GRENADE)

	smoke_grenade_marker_added.emit(_smoke_grenade_pending_ratio, target_pos)
	_notify_timeline_changed()

	# 状態をリセット
	_smoke_grenade_has_anchor = false
	_smoke_grenade_pending_anchor = Vector3.ZERO
	_smoke_grenade_pending_ratio = 0.0
	_smoke_grenade_has_bounce = false
	_smoke_grenade_bounce_point = Vector3.ZERO
	_smoke_grenade_bounce_normal = Vector3.ZERO
	_cleanup_smoke_grenade_trajectory_mesh()


## スモークグレネードマーカーノードを作成
func _create_smoke_grenade_marker_node(anchor: Vector3, target: Vector3, bounce: Vector3) -> MeshInstance3D:
	var marker = MeshInstance3D.new()
	marker.set_script(SmokeGrenadeMarkerScript)
	add_child(marker)
	marker.set_position_and_target(anchor, target, bounce)
	# スモークグレネードは灰色/白（デフォルト色を使用）
	return marker


## スモークグレネード軌道プレビューメッシュをセットアップ
func _setup_smoke_grenade_trajectory_mesh() -> void:
	if _smoke_grenade_trajectory_mesh:
		return

	_smoke_grenade_trajectory_mesh = MeshInstance3D.new()
	_smoke_grenade_trajectory_mesh.name = "SmokeGrenadeTrajectoryPreview"
	add_child(_smoke_grenade_trajectory_mesh)

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.7, 0.7, 0.7, 0.6)  # 灰色
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_grenade_trajectory_mesh.material_override = mat


## スモークグレネード軌道プレビューを更新
func _update_smoke_grenade_trajectory_preview_at(screen_pos: Vector2) -> void:
	if not _smoke_grenade_has_anchor or not _smoke_grenade_trajectory_mesh:
		return

	var target_pos = _get_ground_position(screen_pos)
	if target_pos == null:
		var wall_result = _raycast_wall_or_floor(screen_pos)
		if wall_result.is_empty():
			return
		target_pos = wall_result.position

	var im = ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	var start_pos = _smoke_grenade_pending_anchor + Vector3(0, 0.05, 0)

	if _smoke_grenade_has_bounce:
		im.surface_add_vertex(start_pos)
		im.surface_add_vertex(_smoke_grenade_bounce_point)
		im.surface_add_vertex(_smoke_grenade_bounce_point)
		im.surface_add_vertex(target_pos)
	else:
		im.surface_add_vertex(start_pos)
		im.surface_add_vertex(target_pos)

	im.surface_end()
	_smoke_grenade_trajectory_mesh.mesh = im


## スモークグレネード軌道プレビューを削除
func _cleanup_smoke_grenade_trajectory_mesh() -> void:
	if _smoke_grenade_trajectory_mesh:
		_smoke_grenade_trajectory_mesh.queue_free()
		_smoke_grenade_trajectory_mesh = null


## スモークグレネードマーカーがあるか
func has_smoke_grenade_markers() -> bool:
	return _smoke_grenade_markers.size() > 0


## スモークグレネードマーカーを取得
func get_smoke_grenade_markers() -> Array[Dictionary]:
	return _smoke_grenade_markers


## スモークグレネードマーカー数を取得
func get_smoke_grenade_marker_count() -> int:
	if _multi_character_mode and _active_edit_character:
		return get_smoke_grenade_marker_count_for_character(_active_edit_character)
	return _smoke_grenade_markers.size()


## キャラクター別のスモークグレネードマーカー数を取得
func get_smoke_grenade_marker_count_for_character(character: Node) -> int:
	if not character:
		return 0
	var char_id = character.get_instance_id()
	if _character_markers.has(char_id) and _character_markers[char_id].has("smoke_grenade_markers"):
		return _character_markers[char_id].smoke_grenade_markers.size()
	return 0


## キャラクター別のスモークグレネードマーカーを取得
func get_smoke_grenade_markers_for_character(character: Node) -> Array[Dictionary]:
	if not character:
		return []
	var char_id = character.get_instance_id()
	if _character_markers.has(char_id) and _character_markers[char_id].has("smoke_grenade_markers"):
		return _character_markers[char_id].smoke_grenade_markers
	return []


## 全キャラクターのスモークグレネードマーカーを取得
func get_all_smoke_grenade_markers() -> Dictionary:
	if not _multi_character_mode:
		if _active_edit_character:
			return { _active_edit_character.get_instance_id(): _smoke_grenade_markers }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		if _character_markers[char_id].has("smoke_grenade_markers"):
			result[char_id] = _character_markers[char_id].smoke_grenade_markers
		else:
			result[char_id] = []
	return result


## ========================================
## ドアマーカーモード API
## ========================================

## ドアマーカー設定モードに切り替え
## ドアをクリック → パス上最近点に自動配置
func start_door_mode() -> bool:
	if _pending_path.size() < 2:
		return false

	_drawing_mode = DrawingMode.DOOR_MARKER
	_is_enabled = true
	mode_changed.emit(int(DrawingMode.DOOR_MARKER))
	return true


## ドアマーカー入力処理
func _handle_door_marker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_process_door_click(mouse_event.position)
			get_viewport().set_input_as_handled()


## ドアクリック処理
func _process_door_click(screen_pos: Vector2) -> void:
	# ドアをレイキャストで検出
	var door = _raycast_door(screen_pos)
	if not door:
		return

	# ドア位置からパス上の最近点を計算
	var door_pos = door.global_position
	door_pos.y = 0
	var result = _find_closest_point_on_path(door_pos)

	# パスから遠すぎる場合はキャンセル（パスがドアの0.6m以内にないとドアマーカーは配置できない）
	const DOOR_PROXIMITY_THRESHOLD: float = 0.6
	if result.distance > DOOR_PROXIMITY_THRESHOLD:
		return

	# ドアから離れた位置にマーカーを配置（キック距離を確保）
	# パスの開始方向に0.6mオフセット
	const DOOR_KICK_OFFSET: float = 0.6
	var offset_result = _find_offset_point_on_path(result.ratio, -DOOR_KICK_OFFSET)

	var new_marker = {
		"path_ratio": offset_result.ratio,
		"anchor": offset_result.point,
		"door_node": door
	}

	# マルチキャラクターモードの場合
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			char_data.door_markers.append(new_marker)

			# マーカーメッシュを作成（キック位置=offset_result.pointに配置）
			var marker = _create_door_marker_node(offset_result.point, door)
			char_data.door_meshes.append(marker)

			# 履歴に追加
			char_data.marker_history.append(MarkerType.DOOR)

			# MarkerCollectionにも追加（新システム）
			var door_data = ActionMarkerDataScript.DoorMarkerData.new()
			door_data.path_ratio = offset_result.ratio
			door_data.anchor = offset_result.point
			door_data.door_node = door
			_add_marker_to_collection(_active_edit_character, door_data, marker)
	else:
		# シングルモード
		_door_markers.append(new_marker)

		# マーカーメッシュを作成（キック位置=offset_result.pointに配置）
		var marker = _create_door_marker_node(offset_result.point, door)
		_door_meshes.append(marker)

		# 履歴に追加
		_marker_history.append(MarkerType.DOOR)

	door_marker_added.emit(offset_result.ratio, door)
	_notify_timeline_changed()


## ドアマーカーノードを作成
func _create_door_marker_node(anchor: Vector3, door: Node3D) -> MeshInstance3D:
	var marker = MeshInstance3D.new()
	marker.set_script(DoorMarkerScript)
	add_child(marker)
	marker.set_position_and_door(anchor, door)
	marker.set_colors(_character_color, Color(0.8, 0.6, 0.3, 1.0))
	marker.set_connection_color(Color(_character_color.r * 0.8, _character_color.g * 0.6, _character_color.b * 0.3, 0.8))
	return marker


## ドアをレイキャストで検出
func _raycast_door(screen_pos: Vector2) -> Node3D:
	if not _camera:
		return null

	var ray_origin = _camera.project_ray_origin(screen_pos)
	var ray_dir = _camera.project_ray_normal(screen_pos)
	var ray_end = ray_origin + ray_dir * 100.0

	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return null

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


## ドアマーカーがあるか
func has_door_markers() -> bool:
	return _door_markers.size() > 0


## ドアマーカーを取得
func get_door_markers() -> Array[Dictionary]:
	return _door_markers


## ドアマーカー数を取得
func get_door_marker_count() -> int:
	if _multi_character_mode and _active_edit_character:
		return get_door_marker_count_for_character(_active_edit_character)
	return _door_markers.size()


## キャラクター別のドアマーカー数を取得
func get_door_marker_count_for_character(character: Node) -> int:
	if not character:
		return 0
	var char_id = character.get_instance_id()
	if _character_markers.has(char_id) and _character_markers[char_id].has("door_markers"):
		return _character_markers[char_id].door_markers.size()
	return 0


## キャラクター別のドアマーカーを取得
func get_door_markers_for_character(character: Node) -> Array[Dictionary]:
	if not character:
		return []
	var char_id = character.get_instance_id()
	if _character_markers.has(char_id) and _character_markers[char_id].has("door_markers"):
		return _character_markers[char_id].door_markers
	return []


## 全キャラクターのドアマーカーを取得
func get_all_door_markers() -> Dictionary:
	if not _multi_character_mode:
		if _active_edit_character:
			return { _active_edit_character.get_instance_id(): _door_markers }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		if _character_markers[char_id].has("door_markers"):
			result[char_id] = _character_markers[char_id].door_markers
		else:
			result[char_id] = []
	return result


## ========================================
## Waitマーカーモード API
## ========================================

## Waitマーカー設定モードに切り替え
## パス上を長押しで待機時間を設定（押している時間 = 待機時間）
func start_wait_mode() -> bool:
	if _pending_path.size() < 2:
		return false

	_drawing_mode = DrawingMode.WAIT_MARKER
	_is_enabled = true
	mode_changed.emit(int(DrawingMode.WAIT_MARKER))
	return true


## Waitマーカー入力処理（長押し検出）
func _handle_wait_marker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# 長押し開始
				_start_wait_marker_press(mouse_event.position)
				get_viewport().set_input_as_handled()
			else:
				# 長押し終了
				if _wait_is_pressing:
					_finish_wait_marker_press()
					get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		# 長押し中のプレビュー更新
		if _wait_is_pressing:
			_update_wait_marker_preview()


## 長押し開始処理
func _start_wait_marker_press(screen_pos: Vector2) -> void:
	var ground_pos = _get_ground_position(screen_pos)
	if ground_pos == null:
		return

	var result = _find_closest_point_on_path(ground_pos)
	if result.distance > path_click_threshold:
		return

	_wait_pending_anchor = result.point
	_wait_pending_ratio = result.ratio
	_wait_press_start_time = Time.get_ticks_msec() / 1000.0
	_wait_is_pressing = true

	# プレビューマーカーを作成
	_create_wait_preview_marker()


## 長押し終了処理
func _finish_wait_marker_press() -> void:
	if not _wait_is_pressing:
		return

	var current_time = Time.get_ticks_msec() / 1000.0
	var duration = current_time - _wait_press_start_time
	_wait_is_pressing = false

	# 最小時間未満はキャンセル
	if duration < WAIT_MIN_DURATION:
		_remove_wait_preview_marker()
		return

	# 最大時間で制限
	duration = clampf(duration, WAIT_MIN_DURATION, WAIT_MAX_DURATION)

	# プレビューを削除
	_remove_wait_preview_marker()

	# Waitマーカーを追加
	var new_marker = {
		"path_ratio": _wait_pending_ratio,
		"anchor": _wait_pending_anchor,
		"wait_duration": duration
	}

	# マルチキャラクターモードの場合
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			if not char_data.has("wait_markers"):
				char_data.wait_markers = []
			if not char_data.has("wait_meshes"):
				char_data.wait_meshes = []
			char_data.wait_markers.append(new_marker)

			# マーカーメッシュを作成
			var marker = _create_wait_marker_node(_wait_pending_anchor, duration)
			char_data.wait_meshes.append(marker)

			# 履歴に追加
			char_data.marker_history.append(MarkerType.WAIT)

			# MarkerCollectionにも追加（新システム）
			var wait_data = ActionMarkerDataScript.WaitMarkerData.new()
			wait_data.path_ratio = _wait_pending_ratio
			wait_data.anchor = _wait_pending_anchor
			wait_data.wait_duration = duration
			_add_marker_to_collection(_active_edit_character, wait_data, marker)
	else:
		# シングルモード
		_wait_markers.append(new_marker)

		# マーカーメッシュを作成
		var marker = _create_wait_marker_node(_wait_pending_anchor, duration)
		_wait_meshes.append(marker)

		# 履歴に追加
		_marker_history.append(MarkerType.WAIT)

	wait_marker_added.emit(_wait_pending_ratio, duration)
	_notify_timeline_changed()


## Waitプレビューマーカーを作成
func _create_wait_preview_marker() -> void:
	_remove_wait_preview_marker()

	_wait_preview_marker = MeshInstance3D.new()
	_wait_preview_marker.set_script(WaitMarkerScript)
	add_child(_wait_preview_marker)
	_wait_preview_marker.set_marker_position(_wait_pending_anchor)
	_wait_preview_marker.set_colors(Color(_character_color.r, _character_color.g, _character_color.b, 0.6), Color(1.0, 1.0, 1.0, 0.8))
	_wait_preview_marker.set_wait_duration(WAIT_MIN_DURATION)


## Waitプレビューマーカーを削除
func _remove_wait_preview_marker() -> void:
	if _wait_preview_marker:
		_wait_preview_marker.queue_free()
		_wait_preview_marker = null


## 長押し中のプレビュー更新
func _update_wait_marker_preview() -> void:
	if not _wait_is_pressing or not _wait_preview_marker:
		return

	var current_time = Time.get_ticks_msec() / 1000.0
	var duration = clampf(current_time - _wait_press_start_time, WAIT_MIN_DURATION, WAIT_MAX_DURATION)
	_wait_preview_marker.set_wait_duration(duration)
	_notify_timeline_changed_throttled()


## Waitマーカーノードを作成
func _create_wait_marker_node(anchor: Vector3, duration: float) -> MeshInstance3D:
	var marker = MeshInstance3D.new()
	marker.set_script(WaitMarkerScript)
	add_child(marker)
	marker.set_marker_position(anchor)
	marker.set_colors(_character_color, Color(1.0, 1.0, 1.0, 1.0))
	marker.set_wait_duration(duration)
	return marker


## Waitマーカーがあるか
func has_wait_markers() -> bool:
	return _wait_markers.size() > 0


## Waitマーカーを取得（プレビュー中のマーカーも含む）
func get_wait_markers() -> Array[Dictionary]:
	var result: Array[Dictionary] = _wait_markers.duplicate()
	# プレビュー中のマーカーがあれば追加
	if _wait_is_pressing and _wait_preview_marker:
		var current_time = Time.get_ticks_msec() / 1000.0
		var duration = clampf(current_time - _wait_press_start_time, WAIT_MIN_DURATION, WAIT_MAX_DURATION)
		result.append({
			"path_ratio": _wait_pending_ratio,
			"anchor": _wait_pending_anchor,
			"wait_duration": duration
		})
	return result


## Waitマーカー数を取得
func get_wait_marker_count() -> int:
	if _multi_character_mode and _active_edit_character:
		return get_wait_marker_count_for_character(_active_edit_character)
	return _wait_markers.size()


## キャラクター別のWaitマーカー数を取得
func get_wait_marker_count_for_character(character: Node) -> int:
	if not character:
		return 0
	var char_id = character.get_instance_id()
	if _character_markers.has(char_id) and _character_markers[char_id].has("wait_markers"):
		return _character_markers[char_id].wait_markers.size()
	return 0


## キャラクター別のWaitマーカーを取得（プレビュー中のマーカーも含む）
func get_wait_markers_for_character(character: Node) -> Array[Dictionary]:
	if not character:
		return []
	var char_id = character.get_instance_id()
	var result: Array[Dictionary] = []
	if _character_markers.has(char_id) and _character_markers[char_id].has("wait_markers"):
		result = _character_markers[char_id].wait_markers.duplicate()
	# アクティブキャラクターならプレビュー中のマーカーを追加
	if _active_edit_character and character.get_instance_id() == _active_edit_character.get_instance_id():
		if _wait_is_pressing and _wait_preview_marker:
			var current_time = Time.get_ticks_msec() / 1000.0
			var duration = clampf(current_time - _wait_press_start_time, WAIT_MIN_DURATION, WAIT_MAX_DURATION)
			result.append({
				"path_ratio": _wait_pending_ratio,
				"anchor": _wait_pending_anchor,
				"wait_duration": duration
			})
	return result


## 全キャラクターのWaitマーカーを取得（プレビュー中のマーカーも含む）
func get_all_wait_markers() -> Dictionary:
	# プレビュー中のマーカーを取得するヘルパー
	var preview_marker: Dictionary = {}
	if _wait_is_pressing and _wait_preview_marker:
		var current_time = Time.get_ticks_msec() / 1000.0
		var duration = clampf(current_time - _wait_press_start_time, WAIT_MIN_DURATION, WAIT_MAX_DURATION)
		preview_marker = {
			"path_ratio": _wait_pending_ratio,
			"anchor": _wait_pending_anchor,
			"wait_duration": duration
		}

	if not _multi_character_mode:
		if _active_edit_character:
			var markers: Array[Dictionary] = _wait_markers.duplicate()
			if not preview_marker.is_empty():
				markers.append(preview_marker)
			return { _active_edit_character.get_instance_id(): markers }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		var markers: Array[Dictionary] = []
		if _character_markers[char_id].has("wait_markers"):
			markers = _character_markers[char_id].wait_markers.duplicate()
		# アクティブキャラクターにプレビューマーカーを追加
		if _active_edit_character and char_id == _active_edit_character.get_instance_id() and not preview_marker.is_empty():
			markers.append(preview_marker)
		result[char_id] = markers
	return result


## Waitマーカーの所有権を移譲
func take_wait_markers() -> Array[MeshInstance3D]:
	var markers = _wait_meshes.duplicate()
	_wait_meshes.clear()
	return markers


## 全キャラクターのWaitMarkersを移譲
## @return { char_id: Array[MeshInstance3D] }
func take_all_wait_markers() -> Dictionary:
	if not _multi_character_mode:
		if _active_edit_character:
			var markers = _wait_meshes.duplicate()
			_wait_meshes.clear()
			return { _active_edit_character.get_instance_id(): markers }
		return {}

	var result: Dictionary = {}
	for char_id in _character_markers:
		if _character_markers[char_id].has("wait_meshes"):
			result[char_id] = _character_markers[char_id].wait_meshes.duplicate()
			_character_markers[char_id].wait_meshes.clear()
		else:
			result[char_id] = []
	return result


## Waitマーカーをクリア
func _clear_wait_markers() -> void:
	_wait_markers.clear()
	for mesh in _wait_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_wait_meshes.clear()
	_remove_wait_preview_marker()
	_wait_is_pressing = false
	_wait_press_start_time = 0.0


## WaitマーカーをUndo（内部用、履歴は操作しない）
func _undo_wait_marker() -> void:
	if _multi_character_mode and _active_edit_character:
		var char_id = _active_edit_character.get_instance_id()
		if _character_markers.has(char_id):
			var char_data = _character_markers[char_id]
			if char_data.has("wait_markers") and char_data.wait_markers.size() > 0:
				char_data.wait_markers.pop_back()
				if char_data.has("wait_meshes") and char_data.wait_meshes.size() > 0:
					var mesh = char_data.wait_meshes.pop_back()
					if is_instance_valid(mesh):
						mesh.queue_free()
		return

	if _wait_markers.size() > 0:
		_wait_markers.pop_back()
		if _wait_meshes.size() > 0:
			var mesh = _wait_meshes.pop_back()
			if is_instance_valid(mesh):
				mesh.queue_free()


#region 統一マーカーAPI
## 指定タイプのマーカーデータを取得（統一API）
func get_markers_by_type(marker_type: ActionMarkerDataScript.Type) -> Array[Dictionary]:
	match marker_type:
		ActionMarkerDataScript.Type.VISION:
			return get_vision_points()
		ActionMarkerDataScript.Type.RUN:
			return get_run_segments()
		ActionMarkerDataScript.Type.CLEAR:
			return get_clear_points()
		ActionMarkerDataScript.Type.GRENADE:
			return get_grenade_markers()
		ActionMarkerDataScript.Type.DOOR:
			return get_door_markers()
		ActionMarkerDataScript.Type.WAIT:
			return get_wait_markers()
		ActionMarkerDataScript.Type.SMOKE_GRENADE:
			return get_smoke_grenade_markers()
		_:
			return []


## 指定タイプのマーカーメッシュを取得して所有権を移譲（統一API）
func take_markers_by_type(marker_type: ActionMarkerDataScript.Type) -> Array[MeshInstance3D]:
	match marker_type:
		ActionMarkerDataScript.Type.VISION:
			return take_vision_markers()
		ActionMarkerDataScript.Type.RUN:
			return take_run_markers()
		ActionMarkerDataScript.Type.CLEAR:
			return take_clear_markers()
		ActionMarkerDataScript.Type.GRENADE:
			return take_grenade_markers()
		ActionMarkerDataScript.Type.DOOR:
			return take_door_markers()
		ActionMarkerDataScript.Type.WAIT:
			return take_wait_markers()
		ActionMarkerDataScript.Type.SMOKE_GRENADE:
			return take_smoke_grenade_markers()
		_:
			return []


## 指定キャラクターの指定タイプのマーカーデータを取得（統一API）
func get_markers_for_character_by_type(character: Node, marker_type: ActionMarkerDataScript.Type) -> Array[Dictionary]:
	match marker_type:
		ActionMarkerDataScript.Type.VISION:
			return get_vision_points_for_character(character)
		ActionMarkerDataScript.Type.RUN:
			return get_run_segments_for_character(character)
		ActionMarkerDataScript.Type.CLEAR:
			return get_clear_points_for_character(character)
		ActionMarkerDataScript.Type.GRENADE:
			return get_grenade_markers_for_character(character)
		ActionMarkerDataScript.Type.DOOR:
			return get_door_markers_for_character(character)
		ActionMarkerDataScript.Type.WAIT:
			return get_wait_markers_for_character(character)
		ActionMarkerDataScript.Type.SMOKE_GRENADE:
			return get_smoke_grenade_markers_for_character(character)
		_:
			return []


## 全キャラクターの指定タイプのマーカーデータを取得（統一API）
func get_all_markers_by_type(marker_type: ActionMarkerDataScript.Type) -> Dictionary:
	match marker_type:
		ActionMarkerDataScript.Type.VISION:
			return get_all_vision_points()
		ActionMarkerDataScript.Type.RUN:
			return get_all_run_segments()
		ActionMarkerDataScript.Type.CLEAR:
			return get_all_clear_points()
		ActionMarkerDataScript.Type.GRENADE:
			return get_all_grenade_markers()
		ActionMarkerDataScript.Type.DOOR:
			return get_all_door_markers()
		ActionMarkerDataScript.Type.WAIT:
			return get_all_wait_markers()
		ActionMarkerDataScript.Type.SMOKE_GRENADE:
			return get_all_smoke_grenade_markers()
		_:
			return {}


## 全キャラクターの指定タイプのマーカーメッシュを取得して所有権を移譲（統一API）
func take_all_markers_by_type(marker_type: ActionMarkerDataScript.Type) -> Dictionary:
	match marker_type:
		ActionMarkerDataScript.Type.VISION:
			return take_all_vision_markers()
		ActionMarkerDataScript.Type.RUN:
			return take_all_run_markers()
		ActionMarkerDataScript.Type.CLEAR:
			return take_all_clear_markers()
		ActionMarkerDataScript.Type.GRENADE:
			return take_all_grenade_markers()
		ActionMarkerDataScript.Type.DOOR:
			return take_all_door_markers()
		ActionMarkerDataScript.Type.WAIT:
			return take_all_wait_markers()
		ActionMarkerDataScript.Type.SMOKE_GRENADE:
			return take_all_smoke_grenade_markers()
		_:
			return {}


## 全タイプのマーカーデータを一括取得（統一API）
## @return: { Type: Array[Dictionary] }
func get_all_marker_types_data() -> Dictionary:
	var result: Dictionary = {}
	for type_value in ActionMarkerDataScript.Type.values():
		result[type_value] = get_markers_by_type(type_value)
	return result


## 全タイプのマーカーメッシュを一括取得して所有権を移譲（統一API）
## @return: { Type: Array[MeshInstance3D] }
func take_all_marker_types_meshes() -> Dictionary:
	var result: Dictionary = {}
	for type_value in ActionMarkerDataScript.Type.values():
		result[type_value] = take_markers_by_type(type_value)
	return result
#endregion


#region MarkerCollectionベース内部ヘルパー
## ========================================
## MarkerCollectionベース内部ヘルパー
## ========================================

## アクティブキャラクターのMarkerCollectionを取得
func _get_active_collection() -> MarkerCollectionScript:
	if not _multi_character_mode or _active_edit_character == null:
		return null
	var char_id = _active_edit_character.get_instance_id()
	return _character_collections.get(char_id, null)


## 指定キャラクターのMarkerCollectionを取得
func _get_collection_for_character(character: Node) -> MarkerCollectionScript:
	if character == null:
		return null
	var char_id = character.get_instance_id()
	return _character_collections.get(char_id, null)


## 全キャラクターのMarkerCollectionを取得
## @return: { instance_id: MarkerCollectionScript }
func _get_all_collections() -> Dictionary:
	return _character_collections.duplicate()


## MarkerCollectionにマーカーを追加（内部ヘルパー）
## 同時に従来の配列にも追加して後方互換性を保持
func _add_marker_to_collection(
	character: Node,
	marker_data: ActionMarkerDataScript,
	mesh: MeshInstance3D = null
) -> bool:
	var collection = _get_collection_for_character(character)
	if collection == null:
		return false

	collection.add_marker(marker_data, mesh)
	return true


## MarkerCollectionから最後のマーカーをUndo（内部ヘルパー）
func _undo_last_marker_from_collection(character: Node) -> Dictionary:
	var collection = _get_collection_for_character(character)
	if collection == null:
		return {"success": false}

	return collection.undo_last_marker()
#endregion
