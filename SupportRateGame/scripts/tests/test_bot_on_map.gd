extends Node3D
## Test scene: Bot on map with rifle_idle animation + Path Drawing

const TestPathManagerClass = preload("res://scripts/tests/test_path_manager.gd")

@onready var bot: CharacterBody3D = $Bot
@onready var camera: Camera3D = $OrbitCamera
@onready var map_node: Node3D = $Map

var anim_player: AnimationPlayer = null
var skeleton: Skeleton3D = null
const GRAVITY: float = 9.8

# カメラ移動
const CAMERA_MOVE_SPEED: float = 10.0
var camera_target_pos: Vector3 = Vector3.ZERO

# 武器装着
const AK47_SCENE_PATH: String = "res://scenes/weapons/ak47.tscn"

# パス描画
var path_manager: Node3D = null

# ボット移動
var current_waypoints: Array = []
var current_waypoint_index: int = 0
var is_moving: bool = false
const WALK_SPEED: float = 3.0
const RUN_SPEED: float = 6.0
const ARRIVAL_THRESHOLD: float = 0.3
const ROTATION_SPEED: float = 10.0  # 回転速度（ラジアン/秒）
const ANIMATION_BLEND_TIME: float = 0.25  # アニメーションブレンド時間（秒）
var current_speed: float = 0.0  # 現在の移動速度
var target_speed: float = 0.0  # 目標移動速度
var speed_transition_timer: float = 0.0  # 速度遷移タイマー
var speed_transition_start: float = 0.0  # 速度遷移開始時の速度

# アニメーション基準速度（アニメーションが自然に見える移動速度）
const ANIM_WALK_BASE_SPEED: float = 3.0  # walkアニメーションの基準速度
const ANIM_RUN_BASE_SPEED: float = 6.0   # sprintアニメーションの基準速度

# スタック検出
const STUCK_TIME_THRESHOLD: float = 0.5  # この時間進めなかったらスタックと判定
const STUCK_DISTANCE_THRESHOLD: float = 0.1  # この距離以下の移動はスタックと判定
var stuck_timer: float = 0.0
var last_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	_setup_bot()
	_apply_ct_spawn_position()
	_attach_weapon()
	_generate_map_collisions()
	# コリジョン生成完了後にパスシステムをセットアップ
	call_deferred("_setup_path_system_deferred")

	# GameManagerの状態をPLAYINGに設定（InputManagerが入力を受け付けるため）
	if GameManager:
		GameManager.current_state = GameManager.GameState.PLAYING
		print("[TestBotOnMap] GameManager.current_state = PLAYING")


## マップコリジョンを生成
func _generate_map_collisions() -> void:
	if not map_node:
		push_warning("[TestBotOnMap] Map node not found")
		return

	print("[TestBotOnMap] Generating map collisions...")

	# 地形コリジョン生成
	_generate_collisions_for_node(map_node, 2)  # collision_layer = 2 (地形)

	# 壁コリジョン生成（"Wall"を含むメッシュのみ）
	_generate_wall_collisions_for_node(map_node, 6)  # collision_layer = 6 (壁)

	print("[TestBotOnMap] Map collisions generated")


## ノードのメッシュにコリジョンを生成（再帰）
func _generate_collisions_for_node(node: Node, collision_layer: int) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			# 壁は別途処理するのでスキップ
			var name_lower := mesh_instance.name.to_lower()
			if name_lower.contains("wall"):
				return
			# 既にコリジョンがある場合はスキップ
			for child in mesh_instance.get_children():
				if child is StaticBody3D:
					return
			_create_mesh_collision(mesh_instance, collision_layer)

	for child in node.get_children():
		_generate_collisions_for_node(child, collision_layer)


## 壁メッシュにコリジョンを生成（再帰）
func _generate_wall_collisions_for_node(node: Node, collision_layer: int) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var name_lower := mesh_instance.name.to_lower()
			if name_lower.contains("wall"):
				# 既にコリジョンがある場合はスキップ
				for child in mesh_instance.get_children():
					if child is StaticBody3D:
						return
				_create_mesh_collision(mesh_instance, collision_layer)

	for child in node.get_children():
		_generate_wall_collisions_for_node(child, collision_layer)


## メッシュにコリジョンを作成
func _create_mesh_collision(mesh_instance: MeshInstance3D, collision_layer: int) -> void:
	var static_body := StaticBody3D.new()
	static_body.name = mesh_instance.name + "_col"
	static_body.collision_layer = collision_layer
	static_body.collision_mask = 0

	# メッシュからコリジョンシェイプを生成
	var shape: Shape3D = mesh_instance.mesh.create_trimesh_shape()
	if shape == null:
		return

	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape
	static_body.add_child(collision_shape)
	mesh_instance.add_child(static_body)


## パスシステムをセットアップ（遅延実行）
func _setup_path_system_deferred() -> void:
	_setup_path_system()
	# カメラをセットアップ
	_setup_camera()


## カメラをセットアップ
func _setup_camera() -> void:
	# カメラターゲット用のダミーノードを作成
	var camera_target := Node3D.new()
	camera_target.name = "CameraTarget"
	add_child(camera_target)
	camera_target.global_position = bot.global_position
	camera_target_pos = bot.global_position

	if camera and camera.has_method("set_target"):
		camera.set_target(camera_target)
		# カメラを真上から85度の角度に設定
		camera._vertical_angle = 85.0
		# ズーム距離
		camera.distance = 12.0
		camera._update_camera_position()
		# ドラッグ回転を無効化
		camera.set_process_input(false)


func _process(delta: float) -> void:
	_handle_camera_movement(delta)
	_update_animation_speed()


func _physics_process(delta: float) -> void:
	if bot:
		# 重力
		if not bot.is_on_floor():
			bot.velocity.y -= GRAVITY * delta
		else:
			bot.velocity.y = 0

		# パス追従移動
		if is_moving and current_waypoints.size() > 0:
			_move_along_path(delta)

		bot.move_and_slide()


## パスシステムをセットアップ
func _setup_path_system() -> void:
	# PathManagerを作成（テスト用、グリッドシステムなし）
	path_manager = Node3D.new()
	path_manager.set_script(TestPathManagerClass)
	path_manager.name = "PathManager"
	add_child(path_manager)

	# プレイヤー（ボット）を設定
	if path_manager.has_method("set_player"):
		path_manager.set_player(bot)

	# パス確定シグナルに接続
	path_manager.path_confirmed.connect(_on_path_confirmed)
	path_manager.path_cleared.connect(_on_path_cleared)

	print("[TestBotOnMap] PathManager setup complete")


## パス確定時のコールバック
func _on_path_confirmed(waypoints: Array) -> void:
	print("[TestBotOnMap] Path confirmed with %d waypoints" % waypoints.size())

	current_waypoints = waypoints
	current_waypoint_index = 0

	# スタック検出をリセット
	stuck_timer = 0.0
	last_position = bot.global_position

	if current_waypoints.size() > 0:
		is_moving = true
		# 最初のウェイポイントに応じて初期速度とアニメーションを設定
		var first_waypoint = current_waypoints[0]
		var should_run: bool = first_waypoint.get("run", false)
		# 速度を即座に設定（開始時は遷移なし）
		target_speed = RUN_SPEED if should_run else WALK_SPEED
		current_speed = target_speed
		speed_transition_timer = ANIMATION_BLEND_TIME  # 遷移完了状態
		speed_transition_start = target_speed
		if should_run:
			_play_run_animation()
		else:
			_play_walk_animation()


## パスクリア時のコールバック
func _on_path_cleared() -> void:
	print("[TestBotOnMap] Path cleared")
	current_waypoints.clear()
	current_waypoint_index = 0
	is_moving = false
	_play_idle_animation()


## パスに沿って移動
func _move_along_path(delta: float) -> void:
	if current_waypoint_index >= current_waypoints.size():
		_on_path_complete()
		return

	var waypoint = current_waypoints[current_waypoint_index]
	var target_pos: Vector3 = waypoint["position"]
	var should_run: bool = waypoint.get("run", false)

	# 目標への方向
	var direction := target_pos - bot.global_position
	direction.y = 0  # Y軸は無視
	var distance := direction.length()

	# 到着判定
	if distance < ARRIVAL_THRESHOLD:
		_advance_to_next_waypoint(should_run)
		return

	# スタック検出
	if _check_stuck(delta):
		print("[TestBotOnMap] Stuck detected, skipping to next waypoint")
		_advance_to_next_waypoint(should_run)
		return

	# 目標速度を決定し、アニメーションブレンドと同じ時間で遷移
	var new_target_speed := RUN_SPEED if should_run else WALK_SPEED
	if new_target_speed != target_speed:
		# 目標速度が変わったら遷移開始
		speed_transition_start = current_speed
		target_speed = new_target_speed
		speed_transition_timer = 0.0

	# 速度を線形補間（アニメーションブレンド時間と同期）
	if speed_transition_timer < ANIMATION_BLEND_TIME:
		speed_transition_timer += delta
		var t := clampf(speed_transition_timer / ANIMATION_BLEND_TIME, 0.0, 1.0)
		current_speed = lerpf(speed_transition_start, target_speed, t)
	else:
		current_speed = target_speed

	# 向きをスムーズに更新
	if direction.length() > 0.01:
		# 目標角度を計算（atan2でXZ平面上の角度を取得）
		var target_angle := atan2(direction.x, direction.z)
		# 現在の角度から目標角度へスムーズに補間
		bot.rotation.y = lerp_angle(bot.rotation.y, target_angle, ROTATION_SPEED * delta)

	# 移動
	direction = direction.normalized()
	bot.velocity.x = direction.x * current_speed
	bot.velocity.z = direction.z * current_speed


## スタック検出
func _check_stuck(delta: float) -> bool:
	var current_pos := bot.global_position
	current_pos.y = 0  # Y軸は無視

	var last_pos_flat := last_position
	last_pos_flat.y = 0

	var moved_distance := current_pos.distance_to(last_pos_flat)

	if moved_distance < STUCK_DISTANCE_THRESHOLD:
		stuck_timer += delta
		if stuck_timer >= STUCK_TIME_THRESHOLD:
			stuck_timer = 0.0
			last_position = bot.global_position
			return true
	else:
		stuck_timer = 0.0
		last_position = bot.global_position

	return false


## 次のウェイポイントに進む
func _advance_to_next_waypoint(current_should_run: bool) -> void:
	current_waypoint_index += 1
	stuck_timer = 0.0
	last_position = bot.global_position

	if current_waypoint_index < current_waypoints.size():
		# 次のウェイポイントのアニメーションを設定
		var next_waypoint = current_waypoints[current_waypoint_index]
		var next_run: bool = next_waypoint.get("run", false)
		if next_run != current_should_run:
			if next_run:
				_play_run_animation()
			else:
				_play_walk_animation()


## パス完了
func _on_path_complete() -> void:
	is_moving = false
	current_waypoints.clear()
	current_waypoint_index = 0
	current_speed = 0.0
	target_speed = 0.0
	speed_transition_timer = 0.0
	speed_transition_start = 0.0
	bot.velocity.x = 0
	bot.velocity.z = 0
	_play_idle_animation()
	print("[TestBotOnMap] Path complete")


## アニメーション再生速度を移動速度に合わせて調整
func _update_animation_speed() -> void:
	if not anim_player or not is_moving:
		if anim_player:
			anim_player.speed_scale = 1.0
		return

	var current_anim = anim_player.current_animation
	if current_anim.is_empty():
		return

	# 現在のアニメーションに応じて基準速度を決定
	var base_speed: float = ANIM_WALK_BASE_SPEED
	if current_anim == "Rifle_SprintLoop":
		base_speed = ANIM_RUN_BASE_SPEED
	elif current_anim == "Rifle_WalkFwdLoop":
		base_speed = ANIM_WALK_BASE_SPEED
	else:
		# idle等の場合は速度調整しない
		anim_player.speed_scale = 1.0
		return

	# 移動速度に応じてアニメーション速度をスケール
	if base_speed > 0:
		var speed_scale = current_speed / base_speed
		# 極端な値を防ぐためクランプ
		anim_player.speed_scale = clampf(speed_scale, 0.5, 2.0)


## アニメーションのloop_modeを強制設定
func _ensure_loop_mode(anim_name: String) -> void:
	if not anim_player:
		return
	var anim = anim_player.get_animation(anim_name)
	if anim and anim.loop_mode != Animation.LOOP_LINEAR:
		anim.loop_mode = Animation.LOOP_LINEAR
		print("[TestBotOnMap] Set loop_mode to LINEAR for: %s" % anim_name)


## アイドルアニメーション再生
func _play_idle_animation() -> void:
	if not anim_player:
		return
	const ANIM_NAME = "Rifle_Idle"
	if anim_player.has_animation(ANIM_NAME):
		_ensure_loop_mode(ANIM_NAME)
		if anim_player.current_animation != ANIM_NAME:
			anim_player.play(ANIM_NAME, ANIMATION_BLEND_TIME)


## 歩行アニメーション再生
func _play_walk_animation() -> void:
	if not anim_player:
		return
	const ANIM_NAME = "Rifle_WalkFwdLoop"
	if anim_player.has_animation(ANIM_NAME):
		_ensure_loop_mode(ANIM_NAME)
		if anim_player.current_animation != ANIM_NAME:
			anim_player.play(ANIM_NAME, ANIMATION_BLEND_TIME)


## 走りアニメーション再生
func _play_run_animation() -> void:
	if not anim_player:
		return
	const ANIM_NAME = "Rifle_SprintLoop"
	if anim_player.has_animation(ANIM_NAME):
		_ensure_loop_mode(ANIM_NAME)
		if anim_player.current_animation != ANIM_NAME:
			anim_player.play(ANIM_NAME, ANIMATION_BLEND_TIME)
	else:
		# フォールバック: 歩行アニメーションを使用
		_play_walk_animation()


## WASDでカメラを移動
func _handle_camera_movement(delta: float) -> void:
	if not camera:
		return

	var move_dir := Vector3.ZERO

	if Input.is_key_pressed(KEY_W):
		move_dir.z -= 1
	if Input.is_key_pressed(KEY_S):
		move_dir.z += 1
	if Input.is_key_pressed(KEY_A):
		move_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		move_dir.x += 1

	if move_dir != Vector3.ZERO:
		move_dir = move_dir.normalized()
		camera_target_pos += move_dir * CAMERA_MOVE_SPEED * delta

		# カメラのターゲットを更新（ダミーノードを使用）
		if camera.target:
			camera.target.global_position = camera_target_pos
			camera._update_camera_position()


func _setup_bot() -> void:
	var bot_model = bot.get_node_or_null("CharacterModel")
	if not bot_model:
		push_warning("[TestBotOnMap] CharacterModel not found")
		return

	# Find AnimationPlayer
	anim_player = _find_animation_player(bot_model)
	if anim_player:
		print("[TestBotOnMap] Found AnimationPlayer")
		_print_available_animations()  # アニメーション一覧とループ設定を表示
		# Play Rifle_Idle animation
		if anim_player.has_animation("Rifle_Idle"):
			anim_player.play("Rifle_Idle")
			print("[TestBotOnMap] Playing Rifle_Idle animation")
		else:
			push_warning("[TestBotOnMap] Rifle_Idle animation not found")
	else:
		push_warning("[TestBotOnMap] AnimationPlayer not found")

	# Find Skeleton3D
	skeleton = _find_skeleton(bot_model)
	if skeleton:
		print("[TestBotOnMap] Found Skeleton3D")
	else:
		push_warning("[TestBotOnMap] Skeleton3D not found")


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result:
			return result
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result := _find_skeleton(child)
		if result:
			return result
	return null


## AK47を右手に装着
func _attach_weapon() -> void:
	if not skeleton:
		push_warning("[TestBotOnMap] Cannot attach weapon - no skeleton")
		return

	# 右手のボーンを検索
	var right_hand_names := ["mixamorig_RightHand", "RightHand", "right_hand", "mixamorig:RightHand"]
	var right_hand_bone_idx: int = -1

	for bone_name in right_hand_names:
		var idx := skeleton.find_bone(bone_name)
		if idx >= 0:
			right_hand_bone_idx = idx
			print("[TestBotOnMap] Found right hand bone: %s (index: %d)" % [bone_name, idx])
			break

	if right_hand_bone_idx < 0:
		push_warning("[TestBotOnMap] Right hand bone not found")
		return

	# BoneAttachment3Dを作成
	var weapon_attachment := BoneAttachment3D.new()
	weapon_attachment.name = "WeaponAttachment"
	weapon_attachment.bone_idx = right_hand_bone_idx
	skeleton.add_child(weapon_attachment)

	# AK47シーンを読み込んで装着
	var ak47_scene = load(AK47_SCENE_PATH)
	if not ak47_scene:
		push_warning("[TestBotOnMap] Failed to load AK47 scene: %s" % AK47_SCENE_PATH)
		return

	var weapon = ak47_scene.instantiate()
	weapon.name = "AK47"
	weapon_attachment.add_child(weapon)

	print("[TestBotOnMap] AK47 attached to right hand")


func _print_available_animations() -> void:
	if anim_player:
		print("[TestBotOnMap] Available animations:")
		for anim_name in anim_player.get_animation_list():
			var anim = anim_player.get_animation(anim_name)
			var loop_mode = anim.loop_mode if anim else -1
			print("  - %s (loop_mode=%d)" % [anim_name, loop_mode])


## CTスポーン位置にbotを配置
func _apply_ct_spawn_position() -> void:
	if not map_node or not bot:
		push_warning("[TestBotOnMap] Map or Bot not found")
		return

	# マップからCTスポーンポイントを検索
	var ct_spawn = _find_ct_spawn_point(map_node)

	if ct_spawn:
		var spawn_pos = ct_spawn.global_position
		spawn_pos.y += 0.1  # スポーン位置より少し上に配置（重力で落下する）
		bot.global_position = spawn_pos
		# Blenderからの回転を適用（BlenderのY前方 → Godotの-Z前方のため180度オフセット）
		bot.rotation.y = ct_spawn.rotation.y + PI
		print("[TestBotOnMap] Bot spawned at CT position: %s" % spawn_pos)
	else:
		push_warning("[TestBotOnMap] CT spawn point not found in map")
		_print_map_children(map_node, 0)


## CTスポーンポイントを再帰的に検索
func _find_ct_spawn_point(node: Node) -> Node3D:
	if node.name.begins_with("ResponseCT"):
		return node as Node3D

	for child in node.get_children():
		var result = _find_ct_spawn_point(child)
		if result:
			return result

	return null


## デバッグ用：マップの子ノードを出力
func _print_map_children(node: Node, depth: int) -> void:
	var indent = ""
	for i in range(depth):
		indent += "  "
	print("%s- %s (%s)" % [indent, node.name, node.get_class()])
	if depth < 3:
		for child in node.get_children():
			_print_map_children(child, depth + 1)


