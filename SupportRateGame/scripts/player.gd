extends CharacterBody3D

## タクティカルシューター プレイヤーコントローラー
## パス追従移動 + 自動射撃

signal path_completed
signal waypoint_reached(index: int)

@export_group("移動設定")
@export var walk_speed: float = 3.0
@export var run_speed: float = 6.0
@export var rotation_speed: float = 10.0

@export_group("カメラ設定")
@export var camera_distance: float = 8.0
@export var camera_height: float = 0.0
@export var camera_smooth_speed: float = 5.0
@export var min_zoom: float = 5.0
@export var max_zoom: float = 25.0
@export var zoom_speed: float = 2.0

@export_group("地形追従設定")
@export var terrain_follow_enabled: bool = true
@export var terrain_ray_length: float = 20.0
@export var terrain_smooth_speed: float = 10.0
@export var ground_offset: float = 0.0  # 地面からのオフセット（通常は0）

var gravity: float = -20.0  # 重力（より強めに設定）
var vertical_velocity: float = 0.0

# 地形追従用
var target_ground_y: float = 0.0

# カメラ
var camera_yaw: float = 0.0
var camera_pitch: float = 90.0  # 真上からの視点
var target_zoom: float = 8.0

# パス追従用
var waypoints: Array[Vector3] = []
var current_waypoint_index: int = 0
var is_moving: bool = false
var is_running: bool = false

# アニメーション
var anim_player: AnimationPlayer = null
var current_move_state: int = 0  # 0: idle, 1: walk, 2: run
const ANIM_BLEND_TIME: float = 0.3

@onready var camera: Camera3D = $Camera3D
@onready var fake_shadow: MeshInstance3D = $FakeShadow


func _ready() -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()

	target_zoom = camera_distance

	if terrain_follow_enabled:
		floor_snap_length = 1.0

	# アニメーションプレイヤーを取得
	var model = get_node_or_null("CharacterModel")
	if model:
		# マテリアルを光対応に設定
		_setup_lit_materials(model)

		anim_player = model.get_node_or_null("AnimationPlayer")
		if anim_player:
			_load_animations()
			if anim_player.has_animation("idle"):
				anim_player.play("idle")


func _physics_process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	_handle_path_movement(delta)
	_handle_camera(delta)
	_update_animation()
	_update_fake_shadow()


## パス追従移動
func _handle_path_movement(delta: float) -> void:
	if is_moving and waypoints.size() > 0 and current_waypoint_index < waypoints.size():
		var target := waypoints[current_waypoint_index]
		var direction := (target - global_position)
		direction.y = 0  # 水平方向のみ
		var distance := direction.length()

		if distance < 0.3:  # ウェイポイント到達
			waypoint_reached.emit(current_waypoint_index)
			current_waypoint_index += 1
			if current_waypoint_index >= waypoints.size():
				# パス完了
				_stop_moving()
				path_completed.emit()
			return

		# 移動方向に回転
		if direction.length() > 0.1:
			var target_rotation := atan2(direction.x, direction.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)

		# 移動
		var speed := run_speed if is_running else walk_speed
		var move_dir := direction.normalized()
		velocity.x = move_dir.x * speed
		velocity.z = move_dir.z * speed
	else:
		velocity.x = 0
		velocity.z = 0

	# 地形追従
	_handle_terrain_follow(delta)

	move_and_slide()


## 地形追従処理（重力ベース）
func _handle_terrain_follow(delta: float) -> void:
	# 重力を適用
	if is_on_floor():
		vertical_velocity = -0.1  # 床に接地するための小さな下向き力
	else:
		vertical_velocity += gravity * delta
		vertical_velocity = max(vertical_velocity, -50.0)  # 最大落下速度を制限

	velocity.y = vertical_velocity


## フェイクシャドウを地面に追従させる
func _update_fake_shadow() -> void:
	if fake_shadow == null:
		return

	# レイキャストで地面を検出
	var space_state = get_world_3d().direct_space_state
	var ray_origin = global_position + Vector3(0, 1, 0)
	var ray_end = global_position + Vector3(0, -10, 0)

	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [self]
	query.collision_mask = 2  # マップのコリジョンレイヤー

	var result = space_state.intersect_ray(query)

	if result:
		# 地面の位置にシャドウを配置（法線方向に少し浮かせてZ-fighting防止）
		var ground_normal: Vector3 = result.normal
		fake_shadow.global_position = result.position + ground_normal * 0.05

		# 地面の法線に合わせてシャドウを傾ける
		_align_shadow_to_normal(ground_normal)
	else:
		# 地面が見つからない場合はプレイヤーの足元に配置
		fake_shadow.global_position = global_position + Vector3(0, 0.05, 0)
		fake_shadow.global_rotation = Vector3.ZERO


## シャドウを地面の法線に合わせて回転
func _align_shadow_to_normal(normal: Vector3) -> void:
	# 法線がほぼ真上の場合は回転不要
	if normal.is_equal_approx(Vector3.UP):
		fake_shadow.global_rotation = Vector3.ZERO
		return

	# 法線方向を上向きにするためのBasisを作成
	var up = normal.normalized()
	var forward = Vector3.FORWARD

	# 法線が前方向に近い場合は別の軸を使用
	if abs(up.dot(forward)) > 0.9:
		forward = Vector3.RIGHT

	var right = up.cross(forward).normalized()
	forward = right.cross(up).normalized()

	fake_shadow.global_basis = Basis(right, up, forward)


## 重力を適用
func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		vertical_velocity = -2.0
	else:
		vertical_velocity += gravity * delta
	velocity.y = vertical_velocity


## カメラ処理
func _handle_camera(delta: float) -> void:
	if camera == null:
		return

	# ズームをスムーズに適用
	camera_distance = lerp(camera_distance, target_zoom, zoom_speed * delta)

	# 真上からのトップダウンビュー（キャラクターの回転に影響されない）
	camera.global_position = global_position + Vector3(0, camera_distance, 0)
	camera.global_rotation_degrees = Vector3(-90, 0, 0)  # 常に固定向き


## パスを設定して移動開始
func set_path(new_waypoints: Array[Vector3], run: bool = false) -> void:
	waypoints = new_waypoints
	current_waypoint_index = 0
	is_running = run
	is_moving = waypoints.size() > 0


## 移動停止
func _stop_moving() -> void:
	is_moving = false
	waypoints.clear()
	current_waypoint_index = 0


## 移動を中断
func stop() -> void:
	_stop_moving()


## 単一地点への移動
func move_to(target: Vector3, run: bool = false) -> void:
	set_path([target], run)


## 入力処理（ズームのみ）
func _input(event: InputEvent) -> void:
	# マウスホイールでズーム
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom = max(min_zoom, target_zoom - 1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom = min(max_zoom, target_zoom + 1.0)

	# ピンチズーム（モバイル）
	if event is InputEventMagnifyGesture:
		target_zoom = clamp(target_zoom / event.factor, min_zoom, max_zoom)


## アニメーション読み込み
func _load_animations() -> void:
	var lib = anim_player.get_animation_library("")
	if lib == null:
		return

	_load_animation_from_fbx(lib, "res://assets/characters/animations/idle.fbx", "idle")
	_load_animation_from_fbx(lib, "res://assets/characters/animations/walking.fbx", "walking")
	_load_animation_from_fbx(lib, "res://assets/characters/animations/running.fbx", "running")


func _load_animation_from_fbx(lib: AnimationLibrary, path: String, anim_name: String) -> void:
	var scene = load(path)
	if scene == null:
		return

	var instance = scene.instantiate()
	var scene_anim_player = instance.get_node_or_null("AnimationPlayer")
	if scene_anim_player:
		for anim_name_in_lib in scene_anim_player.get_animation_list():
			var anim = scene_anim_player.get_animation(anim_name_in_lib)
			if anim:
				var anim_copy = anim.duplicate()
				anim_copy.loop_mode = Animation.LOOP_LINEAR
				lib.add_animation(anim_name, anim_copy)
				break
	instance.queue_free()


## アニメーション更新
func _update_animation() -> void:
	if anim_player == null:
		return

	var new_state: int = 0
	if is_moving:
		new_state = 2 if is_running else 1
	else:
		new_state = 0

	if new_state != current_move_state:
		current_move_state = new_state
		anim_player.speed_scale = 1.0
		match current_move_state:
			0:
				if anim_player.has_animation("idle"):
					anim_player.play("idle", ANIM_BLEND_TIME)
			1:
				if anim_player.has_animation("walking"):
					anim_player.play("walking", ANIM_BLEND_TIME)
			2:
				if anim_player.has_animation("running"):
					anim_player.play("running", ANIM_BLEND_TIME)
				elif anim_player.has_animation("walking"):
					anim_player.play("walking", ANIM_BLEND_TIME)
					anim_player.speed_scale = 1.5


## キャラクターモデルのマテリアルを光対応に設定
func _setup_lit_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		# 影をキャストするように設定
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		if mesh_instance.mesh:
			var surface_count = mesh_instance.mesh.get_surface_count()
			for i in range(surface_count):
				var mat = mesh_instance.get_active_material(i)

				# 新しいマテリアルを作成（元のテクスチャを保持）
				var new_mat = StandardMaterial3D.new()
				new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

				# 元のマテリアルからテクスチャをコピー
				if mat and mat is BaseMaterial3D:
					if mat.albedo_texture:
						new_mat.albedo_texture = mat.albedo_texture
					new_mat.albedo_color = mat.albedo_color

				mesh_instance.set_surface_override_material(i, new_mat)

	# 子ノードを再帰的に処理
	for child in node.get_children():
		_setup_lit_materials(child)
