extends Node3D
## TPSアニメーションテスト
## WASDで移動、マウスで視点操作
## RootMotionアニメーションの動作確認用

@onready var camera: Camera3D = $Camera3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var info_label: Label = $UI/InfoLabel

var _character: CharacterBody3D
var _anim_ctrl: CharacterAnimationController
var _model: Node3D
var _skeleton: Skeleton3D
var _hips_bone_idx: int = -1
var _frame_count: int = 0

# カメラ設定（固定俯瞰視点）
var camera_distance: float = 8.0
var camera_height: float = 6.0
var camera_pitch: float = -0.6  # 俯瞰角度

# 移動設定
var move_speed: float = 2.0
var run_speed: float = 5.0

# 状態
var _is_running: bool = false


func _ready() -> void:
	# マウスは最初から自由に動かせる状態
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_spawn_character()
	_setup_camera()
	_setup_ui()


func _spawn_character() -> void:
	# CharacterRegistryからキャラクターを生成
	var registry = get_node_or_null("/root/CharacterRegistry")
	if not registry:
		push_error("[TestTPS] CharacterRegistry not found")
		return

	var presets = registry.get_all()
	if presets.is_empty():
		push_error("[TestTPS] No character presets available")
		return

	# 最初のプリセットを使用
	var preset = presets[0]
	_character = registry.create_character(preset.id, Vector3.ZERO)
	if _character:
		add_child(_character)
		_anim_ctrl = _character.get_anim_controller()
		_model = _character.get_node_or_null("CharacterModel")
		print("[TestTPS] Spawned character: %s" % preset.id)
		print("[TestTPS] RootMotion enabled: %s" % (_anim_ctrl.use_root_motion if _anim_ctrl else "N/A"))

		# Debug animation setup
		var anim_player = _model.get_node_or_null("AnimationPlayer") if _model else null
		if anim_player:
			print("[TestTPS] AnimationPlayer found")
			print("[TestTPS]   root_node: %s" % anim_player.root_node)
			print("[TestTPS]   Libraries: %s" % str(anim_player.get_animation_library_list()))
			print("[TestTPS]   Has rifle_idle: %s" % anim_player.has_animation("rifle_idle"))
		else:
			print("[TestTPS] WARNING: No AnimationPlayer found!")

		var anim_tree = _model.get_node_or_null("AnimationTree")
		if anim_tree:
			print("[TestTPS] AnimationTree found")
			print("[TestTPS]   active: %s" % anim_tree.active)
			print("[TestTPS]   anim_player path: %s" % anim_tree.anim_player)
			print("[TestTPS]   tree_root: %s" % anim_tree.tree_root)

			# Check if anim_player path resolves
			var resolved_player = anim_tree.get_node_or_null(anim_tree.anim_player)
			print("[TestTPS]   anim_player resolves to: %s" % resolved_player)

			# Check BlendTree nodes
			var blend_tree = anim_tree.tree_root as AnimationNodeBlendTree
			if blend_tree:
				print("[TestTPS]   BlendTree nodes: %s" % str(blend_tree.get_node_list()))

				# Check RifleIdle animation
				var rifle_idle_node = blend_tree.get_node("RifleIdle") as AnimationNodeAnimation
				if rifle_idle_node:
					print("[TestTPS]   RifleIdle animation: %s" % rifle_idle_node.animation)

				# Check RifleWalkBlend points
				var rifle_walk = blend_tree.get_node("RifleWalkBlend") as AnimationNodeBlendSpace2D
				if rifle_walk:
					print("[TestTPS]   RifleWalkBlend point count: %d" % rifle_walk.get_blend_point_count())

		else:
			print("[TestTPS] WARNING: No AnimationTree found!")

		# Find skeleton for bone position debugging
		_skeleton = _find_skeleton(_model)
		if _skeleton:
			_hips_bone_idx = _skeleton.find_bone("mixamorig_Hips")
			print("[TestTPS] Skeleton found, Hips bone index: %d" % _hips_bone_idx)
		else:
			print("[TestTPS] WARNING: No Skeleton3D found!")


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null


func _setup_camera() -> void:
	# カメラピボットを初期化
	camera_pivot.global_position = Vector3.ZERO
	_update_camera()


func _setup_ui() -> void:
	pass


func _input(event: InputEvent) -> void:
	# マウスホイールでカメラズーム
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(2.0, camera_distance - 0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(15.0, camera_distance + 0.5)


func _physics_process(delta: float) -> void:
	if not _character or not _anim_ctrl:
		return

	_frame_count += 1

	# 入力取得
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		input_dir.y += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		input_dir.x += 1
	_is_running = Input.is_key_pressed(KEY_SHIFT)

	# マウス位置からワールド座標上のターゲットを計算
	var look_target := _get_mouse_world_position()
	var look_dir := Vector3.FORWARD
	if look_target != Vector3.ZERO:
		look_dir = (look_target - _character.global_position)
		look_dir.y = 0
		if look_dir.length_squared() > 0.01:
			look_dir = look_dir.normalized()
		else:
			look_dir = Vector3.FORWARD

	# カメラ基準で移動方向を計算（キャラクターからマウス方向を前方とする）
	var move_dir := Vector3.ZERO
	if input_dir.length() > 0.1:
		input_dir = input_dir.normalized()
		# look_dirを前方として、入力方向を変換
		var forward := look_dir
		var right := forward.cross(Vector3.UP).normalized()
		move_dir = right * input_dir.x + forward * (-input_dir.y)
		move_dir.y = 0
		if move_dir.length_squared() > 0.01:
			move_dir = move_dir.normalized()

	# アニメーション更新
	_anim_ctrl.update_animation(move_dir, look_dir, _is_running, delta)

	# 移動処理
	var speed := run_speed if _is_running else move_speed
	if _anim_ctrl.use_root_motion:
		# RootMotionから移動量を取得
		var root_motion: Vector3 = _anim_ctrl.get_root_motion_delta()
		if root_motion.length_squared() > 0.0001:
			_character.velocity.x = root_motion.x / delta
			_character.velocity.z = root_motion.z / delta
		elif move_dir.length_squared() > 0.01:
			# RootMotionが0だが入力がある場合はフォールバック
			_character.velocity.x = move_dir.x * speed
			_character.velocity.z = move_dir.z * speed
		else:
			_character.velocity.x = 0
			_character.velocity.z = 0
	else:
		# 従来方式
		_character.velocity.x = move_dir.x * speed
		_character.velocity.z = move_dir.z * speed

	# 重力
	if not _character.is_on_floor():
		_character.velocity.y -= 9.8 * delta

	_character.move_and_slide()

	# カメラ追従
	camera_pivot.global_position = _character.global_position
	_update_camera()

	# 情報更新
	_update_info()


func _update_camera() -> void:
	# 固定俯瞰カメラ（キャラクターを追従）
	var offset := Vector3(0, camera_height, camera_distance)
	var rot := Basis(Vector3.RIGHT, camera_pitch)
	camera.global_position = camera_pivot.global_position + rot * offset
	camera.look_at(camera_pivot.global_position + Vector3.UP * 1.0)


func _update_info() -> void:
	if not info_label or not _character or not _anim_ctrl:
		return

	var velocity := _character.velocity
	var speed := Vector2(velocity.x, velocity.z).length()

	var text := ""
	text += "=== TPS Animation Test ===\n"
	text += "WASD: Move, Shift: Run\n"
	text += "Mouse: Look direction\n"
	text += "Wheel: Zoom\n\n"
	text += "Running: %s\n" % ("Yes" if _is_running else "No")
	text += "Speed: %.2f m/s\n" % speed

	info_label.text = text




## マウス位置からワールド座標を取得（地面との交点）
func _get_mouse_world_position() -> Vector3:
	if not camera or not _character:
		return Vector3.ZERO

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)

	# キャラクターの高さの水平面との交点を計算
	var plane_y := _character.global_position.y
	if absf(ray_dir.y) < 0.001:
		return Vector3.ZERO  # 水平なレイは交点なし

	var t := (plane_y - ray_origin.y) / ray_dir.y
	if t < 0:
		return Vector3.ZERO  # カメラの後ろ

	return ray_origin + ray_dir * t
