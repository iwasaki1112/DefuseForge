extends Node3D
## Test scene: Bot on map with rifle_idle animation + Path Drawing
## CharacterBase APIを使用したパス追従移動テスト

const TestPathManagerClass = preload("res://scripts/tests/test_path_manager.gd")

@onready var bot: CharacterBase = $Bot
@onready var camera: Camera3D = $OrbitCamera
@onready var map_node: Node3D = $Map

# カメラ移動
const CAMERA_MOVE_SPEED: float = 10.0
var camera_target_pos: Vector3 = Vector3.ZERO

# パス描画
var path_manager: Node3D = null


func _ready() -> void:
	_apply_ct_spawn_position()

	# CharacterBase._ready()でキャラクターセットアップが自動実行される
	# 武器装備はCharacterAPIを使用
	CharacterAPI.equip_weapon(bot, CharacterSetup.WeaponId.AK47)

	# テストシーンでは直接AnimationPlayerを使用するためAnimationTreeを無効化
	# これによりAnimationPlayerのブレンド機能が正しく動作する
	bot.use_animation_tree = false
	if bot.anim_tree:
		bot.anim_tree.active = false

	# CharacterBaseのシグナルに接続
	bot.path_completed.connect(_on_bot_path_completed)
	bot.waypoint_reached.connect(_on_bot_waypoint_reached)

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

	# CharacterBase APIを使用してパスを設定
	# CharacterBaseが自動的にパス追従移動を処理する
	bot.set_path(waypoints)


## パスクリア時のコールバック
func _on_path_cleared() -> void:
	print("[TestBotOnMap] Path cleared")
	# CharacterBase APIを使用して移動を停止
	bot.stop()


## CharacterBase: パス完了時のコールバック
func _on_bot_path_completed() -> void:
	print("[TestBotOnMap] Bot path complete")


## CharacterBase: ウェイポイント到達時のコールバック
func _on_bot_waypoint_reached(index: int) -> void:
	print("[TestBotOnMap] Bot reached waypoint %d" % index)


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
