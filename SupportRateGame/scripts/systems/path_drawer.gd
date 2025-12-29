extends Node3D

## パス描画システム
## Door Kickers 2スタイルのパス描画を実現
## 3D描画（深度テスト有効）でキャラクターの後ろに隠れる

signal path_confirmed(waypoints: Array[Vector3])
signal path_cleared

@export_group("描画設定")
@export var min_point_distance: float = 0.5  # ウェイポイント間の最小距離
@export var path_color: Color = Color(0.0, 1.0, 0.0, 0.5)  # パスの色（半透明で影が透ける）
@export var path_width: float = 0.15  # パスの太さ
@export var path_height_offset: float = 0.001  # 地面からのオフセット（影を受けるため最小限に）
@export var smoothing_segments: int = 5  # 各ポイント間の補間セグメント数

@export_group("入力設定")
@export var draw_button: MouseButton = MOUSE_BUTTON_LEFT
@export var run_modifier_button: MouseButton = MOUSE_BUTTON_RIGHT

# ジェスチャー状態
enum GestureState { NONE, PENDING, DRAWING, CAMERA }
var gesture_state: GestureState = GestureState.NONE

# タッチ管理
var touch_points: Dictionary = {}  # index -> position
var gesture_start_time: float = 0.0
var pending_position: Vector2 = Vector2.ZERO
var drawing_finger_index: int = -1  # 描画用の指を追跡
const GESTURE_CONFIRM_DELAY: float = 0.1  # 100ms

# パス状態
var current_path: Array[Vector3] = []
var is_run_mode: bool = false

# 3D表示用
var path_mesh_instance: MeshInstance3D = null
var immediate_mesh: ImmediateMesh = null

# カメラ参照
var camera: Camera3D = null


func _ready() -> void:
	# ImmediateMeshを作成
	immediate_mesh = ImmediateMesh.new()
	path_mesh_instance = MeshInstance3D.new()
	path_mesh_instance.mesh = immediate_mesh
	path_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# マテリアル設定（深度テスト有効、影を受ける）
	var material := StandardMaterial3D.new()
	material.albedo_color = path_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL  # 影を受けるために必要
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.disable_receive_shadows = false  # 影を受ける
	material.emission_enabled = true  # 発光で視認性を維持
	material.emission = Color(0.0, 1.0, 0.0, 1.0)
	material.emission_energy_multiplier = 0.5  # 影が透けて見えるよう控えめに
	path_mesh_instance.material_override = material

	add_child(path_mesh_instance)


func _process(_delta: float) -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()

	# ペンディング状態：遅延後にジェスチャーを確定
	if gesture_state == GestureState.PENDING:
		var elapsed := (Time.get_ticks_msec() / 1000.0) - gesture_start_time
		if elapsed >= GESTURE_CONFIRM_DELAY:
			if touch_points.size() == 1:
				# 1本指のまま → パス描画開始
				gesture_state = GestureState.DRAWING
				_start_drawing(pending_position)
			else:
				# 2本指以上 → カメラ操作
				gesture_state = GestureState.CAMERA


func _input(event: InputEvent) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	# マウス入力（PC用）
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	if event is InputEventMouseMotion and gesture_state == GestureState.DRAWING:
		_handle_mouse_motion(event)

	# タッチ入力
	if event is InputEventScreenTouch:
		_handle_touch(event)
	if event is InputEventScreenDrag:
		_handle_touch_drag(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == draw_button:
		if event.pressed:
			gesture_state = GestureState.DRAWING
			_start_drawing(event.position)
		else:
			_finish_drawing()
			gesture_state = GestureState.NONE

	if event.button_index == run_modifier_button and event.pressed:
		is_run_mode = true


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	_add_point_from_screen(event.position)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# タッチ開始
		touch_points[event.index] = event.position

		match gesture_state:
			GestureState.NONE:
				if touch_points.size() == 1:
					# 最初のタッチ → ペンディング状態
					gesture_state = GestureState.PENDING
					gesture_start_time = Time.get_ticks_msec() / 1000.0
					pending_position = event.position
					drawing_finger_index = event.index  # この指を追跡
				elif touch_points.size() >= 2:
					# いきなり2本指 → カメラ操作
					gesture_state = GestureState.CAMERA
					drawing_finger_index = -1

			GestureState.PENDING:
				if touch_points.size() >= 2:
					# ペンディング中に2本目 → カメラ操作に切り替え
					gesture_state = GestureState.CAMERA
					drawing_finger_index = -1

			GestureState.DRAWING:
				if touch_points.size() >= 2:
					# 描画中に2本目 → カメラ操作に切り替え（パスは保持）
					gesture_state = GestureState.CAMERA

			GestureState.CAMERA:
				# カメラ操作中 → 継続
				pass
	else:
		# タッチ終了
		touch_points.erase(event.index)

		if touch_points.size() == 0:
			# 全ての指が離れた → リセット
			if gesture_state == GestureState.DRAWING:
				_finish_drawing()
			gesture_state = GestureState.NONE
			drawing_finger_index = -1


func _handle_touch_drag(event: InputEventScreenDrag) -> void:
	# タッチ位置を更新
	if touch_points.has(event.index):
		touch_points[event.index] = event.position

	# 描画状態で、かつ描画用の指のみパスに追加
	if gesture_state == GestureState.DRAWING and event.index == drawing_finger_index:
		_add_point_from_screen(event.position)


## 描画を開始
func _start_drawing(screen_pos: Vector2) -> void:
	var world_pos := _get_world_position(screen_pos)
	if world_pos == Vector3.INF:
		return

	current_path.clear()

	# プレイヤーを停止してから描画開始
	if GameManager.player:
		GameManager.player.stop()

	# プレイヤーの足元からパスを開始
	if GameManager.player:
		var player_pos := GameManager.player.global_position
		player_pos.y = world_pos.y
		current_path.append(player_pos)

	current_path.append(world_pos)
	_update_path_visual()


## スクリーン座標からポイントを追加
func _add_point_from_screen(screen_pos: Vector2) -> void:
	var world_pos := _get_world_position(screen_pos)
	if world_pos == Vector3.INF:
		return

	if current_path.size() > 0:
		var last_pos := current_path[current_path.size() - 1]
		var distance := world_pos.distance_to(last_pos)
		if distance < min_point_distance:
			return

	current_path.append(world_pos)
	_update_path_visual()


## 描画を終了してパスを確定
func _finish_drawing() -> void:
	if current_path.size() >= 2:
		path_confirmed.emit(current_path.duplicate())


## パスをクリア
func clear_path() -> void:
	current_path.clear()
	is_run_mode = false
	_update_path_visual()
	path_cleared.emit()


## スクリーン座標からワールド座標を取得
func _get_world_position(screen_pos: Vector2) -> Vector3:
	if camera == null:
		return Vector3.INF

	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 100.0

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2  # 地形レイヤー

	var result := space_state.intersect_ray(query)
	if result:
		return result.position

	return Vector3.INF


## パスの視覚表示を更新
func _update_path_visual() -> void:
	immediate_mesh.clear_surfaces()

	if current_path.size() < 2:
		return

	var smooth_path := _generate_smooth_path(current_path)

	# メインのパス（TRIANGLE_STRIP）
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

	for i in range(smooth_path.size()):
		var point: Vector3 = smooth_path[i]
		point.y += path_height_offset

		var direction := Vector3.ZERO
		if i < smooth_path.size() - 1:
			direction = (smooth_path[i + 1] - smooth_path[i]).normalized()
		elif i > 0:
			direction = (smooth_path[i] - smooth_path[i - 1]).normalized()

		var up := Vector3.UP
		var right := direction.cross(up).normalized() * path_width * 0.5

		if right.length() < 0.01:
			right = Vector3.RIGHT * path_width * 0.5

		immediate_mesh.surface_add_vertex(point - right)
		immediate_mesh.surface_add_vertex(point + right)

	immediate_mesh.surface_end()

	# 角丸キャップを追加（先端のみ）
	if smooth_path.size() >= 2:
		# 終点のキャップ
		var end_point: Vector3 = smooth_path[smooth_path.size() - 1]
		end_point.y += path_height_offset
		var end_dir := (smooth_path[smooth_path.size() - 1] - smooth_path[smooth_path.size() - 2]).normalized()
		_draw_round_cap(end_point, end_dir, false)


## 角丸キャップを描画
func _draw_round_cap(center: Vector3, direction: Vector3, is_start: bool) -> void:
	var up := Vector3.UP
	var right := direction.cross(up).normalized()
	if right.length() < 0.01:
		right = Vector3.RIGHT

	var segments := 8  # キャップの滑らかさ
	var radius := path_width * 0.5

	# 半円を描画（TRIANGLE_FAN風にTRIANGLESで）
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var start_angle := PI * 0.5 if is_start else -PI * 0.5
	var end_angle := PI * 1.5 if is_start else PI * 0.5

	for i in range(segments):
		var angle1 := start_angle + (end_angle - start_angle) * float(i) / float(segments)
		var angle2 := start_angle + (end_angle - start_angle) * float(i + 1) / float(segments)

		# 中心点
		immediate_mesh.surface_add_vertex(center)

		# 外周の2点
		var offset1 := right * cos(angle1) * radius + direction * sin(angle1) * radius
		var offset2 := right * cos(angle2) * radius + direction * sin(angle2) * radius

		immediate_mesh.surface_add_vertex(center + offset1)
		immediate_mesh.surface_add_vertex(center + offset2)

	immediate_mesh.surface_end()


## Catmull-Romスプライン補間で滑らかなパスを生成
func _generate_smooth_path(points: Array[Vector3]) -> Array[Vector3]:
	if points.size() < 2:
		return points

	var smooth: Array[Vector3] = []

	for i in range(points.size() - 1):
		var p0 := points[max(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[min(i + 1, points.size() - 1)]
		var p3 := points[min(i + 2, points.size() - 1)]

		for j in range(smoothing_segments):
			var t := float(j) / float(smoothing_segments)
			var interpolated := _catmull_rom(p0, p1, p2, p3, t)
			smooth.append(interpolated)

	smooth.append(points[points.size() - 1])

	return smooth


## Catmull-Rom補間
func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t

	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


## 走りモードかどうか
func is_running() -> bool:
	return is_run_mode


## 現在描画中かどうか（外部参照用）
func is_gesture_drawing() -> bool:
	return gesture_state == GestureState.DRAWING


## カメラ操作中かどうか（外部参照用）
func is_gesture_camera() -> bool:
	return gesture_state == GestureState.CAMERA or gesture_state == GestureState.PENDING
