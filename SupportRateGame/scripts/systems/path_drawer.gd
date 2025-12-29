extends Node3D

## パス描画システム
## Door Kickers 2スタイルのパス描画を実現
## 3D描画（深度テスト有効）でキャラクターの後ろに隠れる

signal path_confirmed(waypoints: Array[Vector3])
signal path_cleared

@export_group("描画設定")
@export var min_point_distance: float = 0.5  # ウェイポイント間の最小距離
@export var path_color: Color = Color(0.0, 1.0, 0.0, 0.8)  # パスの色
@export var path_width: float = 0.15  # パスの太さ
@export var path_height_offset: float = 0.02  # 地面からのオフセット
@export var smoothing_segments: int = 5  # 各ポイント間の補間セグメント数

@export_group("入力設定")
@export var draw_button: MouseButton = MOUSE_BUTTON_LEFT
@export var run_modifier_button: MouseButton = MOUSE_BUTTON_RIGHT

# 内部状態
var is_drawing: bool = false
var current_path: Array[Vector3] = []
var is_run_mode: bool = false

# タッチ追跡（2本指以上はカメラ操作なので無視）
var touch_count: int = 0

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

	# マテリアル設定（深度テスト有効）
	var material := StandardMaterial3D.new()
	material.albedo_color = path_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # ライティング無効
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false  # 深度テスト有効（キャラの後ろに隠れる）
	material.disable_receive_shadows = true
	path_mesh_instance.material_override = material

	add_child(path_mesh_instance)


func _process(_delta: float) -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()


func _input(event: InputEvent) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event)

	if event is InputEventMouseMotion and is_drawing:
		_handle_mouse_motion(event)

	if event is InputEventScreenTouch:
		_handle_touch(event)

	if event is InputEventScreenDrag and is_drawing:
		_handle_touch_drag(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == draw_button:
		if event.pressed:
			_start_drawing(event.position)
		else:
			_finish_drawing()

	if event.button_index == run_modifier_button and event.pressed:
		is_run_mode = true


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	_add_point_from_screen(event.position)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		touch_count += 1
		# 2本指以上になったら描画をキャンセル
		if touch_count >= 2:
			if is_drawing:
				is_drawing = false
				clear_path()
			return
		# 1本指のみでパス描画
		if touch_count == 1:
			_start_drawing(event.position)
	else:
		touch_count = max(0, touch_count - 1)
		# 1本指のみで描画終了
		if touch_count == 0 and is_drawing:
			_finish_drawing()


func _handle_touch_drag(event: InputEventScreenDrag) -> void:
	# 2本指以上はカメラ操作なので無視
	if touch_count >= 2:
		return
	_add_point_from_screen(event.position)


## 描画を開始
func _start_drawing(screen_pos: Vector2) -> void:
	var world_pos := _get_world_position(screen_pos)
	if world_pos == Vector3.INF:
		return

	is_drawing = true
	current_path.clear()

	# プレイヤーを停止してから描画開始
	if GameManager.player:
		GameManager.player.stop()

	# プレイヤーの足元からパスを開始
	if GameManager.player:
		var player_pos := GameManager.player.global_position
		player_pos.y = world_pos.y  # 地面の高さに合わせる
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
	if not is_drawing:
		return

	is_drawing = false

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

	# スムーズなパスを生成
	var smooth_path := _generate_smooth_path(current_path)

	# ライン描画
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

	# 最後のポイントを追加
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
