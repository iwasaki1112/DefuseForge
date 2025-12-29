extends Node3D

## パス描画システム
## Door Kickers 2スタイルのパス描画を実現
## 3D描画（深度テスト有効）でキャラクターの後ろに隠れる

signal path_confirmed(waypoints: Array)  # Array of {position: Vector3, run: bool}
signal path_cleared

@export_group("描画設定")
@export var min_point_distance: float = 0.5  # ウェイポイント間の最小距離
@export var path_color_walk: Color = Color(0.0, 1.0, 0.0, 0.5)  # 歩きパスの色
@export var path_color_run: Color = Color(1.0, 0.5, 0.0, 0.5)  # 走りパスの色（オレンジ）
@export var path_width: float = 0.15  # パスの太さ
@export var path_height_offset: float = 0.001  # 地面からのオフセット（影を受けるため最小限に）
@export var smoothing_segments: int = 5  # 各ポイント間の補間セグメント数

@export_group("直線判定設定")
@export var straight_angle_threshold: float = 15.0  # この角度（度）以下なら直線とみなす
@export var min_straight_distance: float = 2.0  # この距離以上の直線で走り判定

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
var segment_run_flags: Array[bool] = []  # 各セグメントが走りかどうか

# 3D表示用
var path_mesh_instance_walk: MeshInstance3D = null
var path_mesh_instance_run: MeshInstance3D = null
var immediate_mesh_walk: ImmediateMesh = null
var immediate_mesh_run: ImmediateMesh = null

# カメラ参照
var camera: Camera3D = null


func _ready() -> void:
	# 歩き用メッシュを作成
	immediate_mesh_walk = ImmediateMesh.new()
	path_mesh_instance_walk = MeshInstance3D.new()
	path_mesh_instance_walk.mesh = immediate_mesh_walk
	path_mesh_instance_walk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	path_mesh_instance_walk.material_override = _create_path_material(path_color_walk, Color(0.0, 1.0, 0.0, 1.0))
	add_child(path_mesh_instance_walk)

	# 走り用メッシュを作成
	immediate_mesh_run = ImmediateMesh.new()
	path_mesh_instance_run = MeshInstance3D.new()
	path_mesh_instance_run.mesh = immediate_mesh_run
	path_mesh_instance_run.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	path_mesh_instance_run.material_override = _create_path_material(path_color_run, Color(1.0, 0.5, 0.0, 1.0))
	add_child(path_mesh_instance_run)


## パス用マテリアルを作成
func _create_path_material(albedo: Color, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.disable_receive_shadows = false
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = 0.5
	return material


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

	# 右クリックは現在未使用（直線判定で自動的に走り/歩きが決まるため）


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
		# 直線判定を実行してフラグを更新
		_analyze_path_segments()

		# waypoints配列を作成（位置と走り情報を含む）
		var waypoints: Array = []
		for i in range(current_path.size()):
			var run := false
			if i > 0 and i - 1 < segment_run_flags.size():
				run = segment_run_flags[i - 1]
			waypoints.append({
				"position": current_path[i],
				"run": run
			})

		path_confirmed.emit(waypoints)


## パスをクリア
func clear_path() -> void:
	current_path.clear()
	segment_run_flags.clear()
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
	immediate_mesh_walk.clear_surfaces()
	immediate_mesh_run.clear_surfaces()

	if current_path.size() < 2:
		return

	# 描画中は直線判定を実行してフラグを更新
	_analyze_path_segments()

	# セグメントごとに歩き/走りを分けて描画
	for seg_idx in range(current_path.size() - 1):
		var p1 := current_path[seg_idx]
		var p2 := current_path[seg_idx + 1]

		var is_run := false
		if seg_idx < segment_run_flags.size():
			is_run = segment_run_flags[seg_idx]

		var mesh: ImmediateMesh = immediate_mesh_run if is_run else immediate_mesh_walk
		_draw_segment(mesh, p1, p2)

	# 終点キャップ（最後のセグメントの色で）
	if current_path.size() >= 2:
		var last_run := false
		if segment_run_flags.size() > 0:
			last_run = segment_run_flags[segment_run_flags.size() - 1]
		var mesh: ImmediateMesh = immediate_mesh_run if last_run else immediate_mesh_walk
		var end_point: Vector3 = current_path[current_path.size() - 1]
		end_point.y += path_height_offset
		var end_dir := (current_path[current_path.size() - 1] - current_path[current_path.size() - 2]).normalized()
		_draw_round_cap(mesh, end_point, end_dir)


## 1セグメントを描画
func _draw_segment(mesh: ImmediateMesh, p1: Vector3, p2: Vector3) -> void:
	# セグメント用のスムースパスを生成
	var segment_points: Array[Vector3] = [p1, p2]
	var smooth := _generate_smooth_path(segment_points)

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

	for i in range(smooth.size()):
		var point: Vector3 = smooth[i]
		point.y += path_height_offset

		var direction := Vector3.ZERO
		if i < smooth.size() - 1:
			direction = (smooth[i + 1] - smooth[i]).normalized()
		elif i > 0:
			direction = (smooth[i] - smooth[i - 1]).normalized()

		var up := Vector3.UP
		var right := direction.cross(up).normalized() * path_width * 0.5

		if right.length() < 0.01:
			right = Vector3.RIGHT * path_width * 0.5

		mesh.surface_add_vertex(point - right)
		mesh.surface_add_vertex(point + right)

	mesh.surface_end()


## 角丸キャップを描画
func _draw_round_cap(mesh: ImmediateMesh, center: Vector3, direction: Vector3) -> void:
	var up := Vector3.UP
	var right := direction.cross(up).normalized()
	if right.length() < 0.01:
		right = Vector3.RIGHT

	var segments := 8
	var radius := path_width * 0.5

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var start_angle := -PI * 0.5
	var end_angle := PI * 0.5

	for i in range(segments):
		var angle1 := start_angle + (end_angle - start_angle) * float(i) / float(segments)
		var angle2 := start_angle + (end_angle - start_angle) * float(i + 1) / float(segments)

		mesh.surface_add_vertex(center)
		var offset1 := right * cos(angle1) * radius + direction * sin(angle1) * radius
		var offset2 := right * cos(angle2) * radius + direction * sin(angle2) * radius
		mesh.surface_add_vertex(center + offset1)
		mesh.surface_add_vertex(center + offset2)

	mesh.surface_end()


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


## パスセグメントを解析して直線判定を行う
func _analyze_path_segments() -> void:
	segment_run_flags.clear()

	if current_path.size() < 2:
		return

	# 初期化：すべて歩き
	for i in range(current_path.size() - 1):
		segment_run_flags.append(false)

	# 各セグメントの角度変化を計算
	var angle_changes: Array[float] = []
	for i in range(current_path.size() - 1):
		var angle := _get_angle_change_at(i)
		angle_changes.append(angle)

	# 連続した直線区間を検出してグループ化
	var i := 0
	while i < angle_changes.size():
		# 直線的なセグメントの開始を探す
		if angle_changes[i] <= straight_angle_threshold:
			var start_idx := i
			var cumulative_distance := 0.0

			# 連続した直線セグメントをまとめる
			while i < angle_changes.size() and angle_changes[i] <= straight_angle_threshold:
				var p1 := current_path[i]
				var p2 := current_path[i + 1]
				cumulative_distance += p1.distance_to(p2)
				i += 1

			# 累積距離が閾値以上なら走りに設定
			if cumulative_distance >= min_straight_distance:
				for j in range(start_idx, i):
					segment_run_flags[j] = true
		else:
			i += 1


## 指定インデックスでの角度変化を取得（度）
func _get_angle_change_at(segment_index: int) -> float:
	if current_path.size() < 3:
		return 0.0

	# 最初のセグメント：次のセグメントとの角度
	if segment_index == 0:
		if current_path.size() < 3:
			return 0.0
		var dir_curr := (current_path[1] - current_path[0])
		var dir_next := (current_path[2] - current_path[1])
		dir_curr.y = 0
		dir_next.y = 0
		if dir_curr.length() < 0.01 or dir_next.length() < 0.01:
			return 0.0
		return rad_to_deg(acos(clamp(dir_curr.normalized().dot(dir_next.normalized()), -1.0, 1.0)))

	# 最後のセグメント：前のセグメントとの角度
	if segment_index == current_path.size() - 2:
		var dir_prev := (current_path[segment_index] - current_path[segment_index - 1])
		var dir_curr := (current_path[segment_index + 1] - current_path[segment_index])
		dir_prev.y = 0
		dir_curr.y = 0
		if dir_prev.length() < 0.01 or dir_curr.length() < 0.01:
			return 0.0
		return rad_to_deg(acos(clamp(dir_prev.normalized().dot(dir_curr.normalized()), -1.0, 1.0)))

	# 中間セグメント：前後の角度の大きい方
	var p0 := current_path[segment_index - 1]
	var p1 := current_path[segment_index]
	var p2 := current_path[segment_index + 1]

	var dir_prev := (p1 - p0)
	var dir_curr := (p2 - p1)
	dir_prev.y = 0
	dir_curr.y = 0

	if dir_prev.length() < 0.01 or dir_curr.length() < 0.01:
		return 0.0

	return rad_to_deg(acos(clamp(dir_prev.normalized().dot(dir_curr.normalized()), -1.0, 1.0)))


## 現在描画中かどうか（外部参照用）
func is_gesture_drawing() -> bool:
	return gesture_state == GestureState.DRAWING


## カメラ操作中かどうか（外部参照用）
func is_gesture_camera() -> bool:
	return gesture_state == GestureState.CAMERA or gesture_state == GestureState.PENDING
