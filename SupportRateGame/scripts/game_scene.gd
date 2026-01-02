extends Node3D

## ゲームシーンのメイン管理
## 各システムの初期化と接続を担当
## プレイヤー管理はSquadManagerに委譲
## ラウンド/経済はMatchManagerに委譲

# システムノードのPackedScene（instantiate()で生成）
const SquadManagerScene = preload("res://scenes/systems/squad_manager.tscn")
const MatchManagerScene = preload("res://scenes/systems/match_manager.tscn")
const PathManagerScene = preload("res://scenes/systems/path_manager.tscn")
const CameraControllerScene = preload("res://scenes/systems/camera_controller.tscn")
const FogOfWarManagerScene = preload("res://scenes/systems/fog_of_war_manager.tscn")
const FogOfWarRendererScene = preload("res://scenes/systems/fog_of_war_renderer.tscn")
const NetworkSyncManagerScript = preload("res://scripts/systems/network_sync_manager.gd")
const GridManagerClass = preload("res://scripts/systems/grid/grid_manager.gd")

@onready var ct_node: Node3D = $CT
@onready var t_node: Node3D = $T
@onready var game_ui: CanvasLayer = $GameUI
@onready var map_node: Node3D = $Wall/MapModel  # Blenderからエクスポートしたマップ（スポーンポイント含む）

var enemies: Array[CharacterBody3D] = []

# 選択インジケーター
var selection_indicator: MeshInstance3D = null
var selection_indicator_material: StandardMaterial3D = null
var _cached_indicator_color: Color = Color.BLACK  # 色変更検出用

var path_manager: Node3D = null
var camera_controller: Node3D = null
var fog_renderer: Node3D = null
var fog_of_war_manager: Node = null
var match_manager: Node = null
var squad_manager: Node = null
var network_sync_manager: Node = null
var grid_manager: Node3D = null

# デバッグ用
var _debug_printed_children: bool = false

# リモートプレイヤー補間用
var _remote_player_targets: Dictionary = {}  # character_name -> {position, rotation, node}
const INTERPOLATION_SPEED: float = 15.0  # 補間速度


func _ready() -> void:
	# システムノードを初期化（順序重要）
	_setup_squad_manager()
	_setup_fog_of_war_manager()
	_setup_match_manager()

	# オンラインマッチの場合、割り当てられたチームに基づいて初期化
	var my_team_node: Node3D = ct_node
	var enemy_team_node: Node3D = t_node

	if GameManager.is_online_match:
		# 割り当てられたチームに応じてノードを入れ替え
		if GameManager.assigned_team == GameManager.Team.TERRORIST:
			my_team_node = t_node
			enemy_team_node = ct_node
		print("[GameScene] Online match - My team: %s" % ("CT" if GameManager.assigned_team == GameManager.Team.CT else "TERRORIST"))

	# 自分のチームを収集してSquadManagerに登録
	var my_team_members: Array[CharacterBody3D] = []
	for child in my_team_node.get_children():
		if child is CharacterBody3D:
			my_team_members.append(child)
			# オンラインマッチで自分のチームを操作する場合、AIを無効化
			if GameManager.is_online_match:
				if "is_player_controlled" in child:
					child.is_player_controlled = true
					print("[GameScene] Set is_player_controlled=true for %s" % child.name)

	# SquadManagerで分隊を初期化
	if squad_manager:
		squad_manager.initialize_squad(my_team_members)
		squad_manager.player_selected.connect(_on_squad_player_selected)

	# 敵チームを収集（enemyスクリプトでグループに自動追加される）
	for child in enemy_team_node.get_children():
		if child is CharacterBody3D:
			enemies.append(child)
			# オンラインマッチでは敵チームのAIも無効化（相手プレイヤーが操作する）
			if GameManager.is_online_match:
				if "is_player_controlled" in child:
					child.is_player_controlled = true
					print("[GameScene] Disabled AI for enemy: %s" % child.name)

	print("[GameScene] My team: %d, Enemies: %d" % [my_team_members.size(), enemies.size()])

	# マップのスポーンポイントからキャラクターの位置を設定
	_apply_spawn_positions_from_map(my_team_members, enemies)

	# デバッグ用：近接スポーン（スポーンポイントより優先）
	if GameManager.debug_spawn_nearby:
		_apply_debug_spawn_positions(my_team_members, enemies)

	# 選択インジケーターを作成
	_create_selection_indicator()
	# 初回の色を設定（キャッシュ初期値との比較でスキップされないように）
	_update_selection_indicator_color()

	# 追加システムを初期化
	_setup_grid_system()  # パスシステムより先にGridManagerを初期化
	_setup_path_system()
	_setup_camera_system()
	_setup_fog_of_war_renderer()

	# オンラインマッチの場合はネットワーク同期を初期化
	if GameManager.is_online_match:
		_setup_network_sync()

	# ゲームを開始（すべてのノードがreadyになった後に実行）
	GameManager.start_game.call_deferred()


## SquadManagerからプレイヤー選択変更通知
func _on_squad_player_selected(player_data: RefCounted, _index: int) -> void:
	var selected_player = player_data.player_node
	if not selected_player:
		return

	# PathManagerのプレイヤー参照を更新
	if path_manager:
		path_manager.set_player(selected_player)

	# 選択インジケーターの色を更新（選択変更時のみ）
	_update_selection_indicator_color()

	# カメラは自動追従しない（2本指/WASDでのみ移動）

	print("[GameScene] Player selected via SquadManager: %s" % selected_player.name)


## WallCollisionGeneratorからのコリジョン生成完了通知
func _on_wall_collisions_generated(count: int) -> void:
	print("[GameScene] Wall collisions generated: %d meshes" % count)
	if grid_manager and count > 0:
		# 物理エンジンへの登録を待ってから再スキャン
		await get_tree().physics_frame
		await get_tree().physics_frame  # 念のため2フレーム待つ
		grid_manager.rescan_obstacles()
		print("[GameScene] GridManager rescanned obstacles")


func _exit_tree() -> void:
	# シーン終了時にクリーンアップ
	if network_sync_manager:
		network_sync_manager.deactivate()
	GameManager.unregister_match_manager()
	GameManager.unregister_squad_manager()
	GameManager.unregister_fog_of_war_manager()
	GameManager.unregister_grid_manager()
	GameManager.stop_game()
	# 敵はグループで管理されるため、シーン離脱時に自動クリーンアップ


func _process(delta: float) -> void:
	# 選択インジケーターを更新
	_update_selection_indicator()

	# オンラインマッチの場合、リモートプレイヤーの位置を補間
	if GameManager.is_online_match:
		_interpolate_remote_players(delta)


## 選択インジケーターを作成
func _create_selection_indicator() -> void:
	selection_indicator = MeshInstance3D.new()
	selection_indicator.name = "SelectionIndicator"

	# リング状のメッシュを作成
	var torus := TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.0
	torus.rings = 16
	torus.ring_segments = 32
	selection_indicator.mesh = torus

	# マテリアル設定（初期色は後で更新される）
	selection_indicator_material = StandardMaterial3D.new()
	selection_indicator_material.albedo_color = Color(0, 1, 0, 0.8)
	selection_indicator_material.emission_enabled = true
	selection_indicator_material.emission = Color(0, 1, 0)
	selection_indicator_material.emission_energy_multiplier = 2.0
	selection_indicator_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	selection_indicator.material_override = selection_indicator_material

	add_child(selection_indicator)


## 選択インジケーターを更新（位置のみ、色は選択変更時に更新）
func _update_selection_indicator() -> void:
	var selected_player = squad_manager.get_selected_player_node() if squad_manager else null
	if selection_indicator and selected_player:
		selection_indicator.visible = true
		var pos = selected_player.global_position
		selection_indicator.global_position = Vector3(pos.x, pos.y + 0.05, pos.z)
	elif selection_indicator:
		selection_indicator.visible = false


## 選択インジケーターの色を更新（選択変更時のみ呼び出し）
## 注: キャラクターカラーが動的に変わる仕様がある場合は、
##     _on_squad_player_selected以外からも呼び出すか、_processでの呼び出しを復活させる必要あり
func _update_selection_indicator_color() -> void:
	if not selection_indicator_material or not squad_manager:
		return

	var player_data = squad_manager.get_selected_player()
	if not player_data:
		return

	var color: Color = player_data.character_color if "character_color" in player_data else Color.GREEN

	# 色が変わった時だけマテリアルを更新
	if color.is_equal_approx(_cached_indicator_color):
		return

	_cached_indicator_color = color
	selection_indicator_material.albedo_color = Color(color.r, color.g, color.b, 0.8)
	selection_indicator_material.emission = color


## 位置からプレイヤーを検索してSquadManagerで選択
func _find_and_select_player_at_position(world_pos: Vector3) -> bool:
	if not squad_manager:
		return false
	return squad_manager.find_and_select_player_at_position(world_pos)


## SquadManagerをセットアップ
func _setup_squad_manager() -> void:
	squad_manager = SquadManagerScene.instantiate()
	add_child(squad_manager)

	# GameManagerに登録
	GameManager.register_squad_manager(squad_manager)

	print("[GameScene] SquadManager initialized")


## FogOfWarManagerをセットアップ
func _setup_fog_of_war_manager() -> void:
	fog_of_war_manager = FogOfWarManagerScene.instantiate()
	add_child(fog_of_war_manager)

	# GameManagerに登録
	GameManager.register_fog_of_war_manager(fog_of_war_manager)

	print("[GameScene] FogOfWarManager initialized")


## MatchManagerをセットアップ
func _setup_match_manager() -> void:
	match_manager = MatchManagerScene.instantiate()
	add_child(match_manager)

	# GameManagerに登録
	GameManager.register_match_manager(match_manager)

	print("[GameScene] MatchManager initialized")


## GridManagerをセットアップ（A*パスファインディング用）
func _setup_grid_system() -> void:
	grid_manager = Node3D.new()
	grid_manager.name = "GridManager"
	grid_manager.set_script(GridManagerClass)

	# grid_testマップ用の設定（16x16グリッド）
	grid_manager.grid_origin = Vector3(0, 0, 0)
	grid_manager.grid_width = 16
	grid_manager.grid_height = 16
	grid_manager.cell_size = 1.0
	grid_manager.obstacle_collision_layer = 4  # 壁のcollision_layer=6にはbit 2が含まれる

	add_child(grid_manager)

	# GameManagerに登録
	GameManager.register_grid_manager(grid_manager)

	# WallCollisionGeneratorのシグナルに接続（コリジョン生成後に再スキャン）
	var wall_node = get_node_or_null("Wall")
	if wall_node and wall_node.has_signal("collisions_generated"):
		wall_node.collisions_generated.connect(_on_wall_collisions_generated)

	print("[GameScene] GridManager initialized (16x16 grid)")


## パスシステムをセットアップ
func _setup_path_system() -> void:
	path_manager = PathManagerScene.instantiate()
	add_child(path_manager)

	# GridManagerを接続（A*パスファインディング用）
	if grid_manager:
		path_manager.set_grid_manager(grid_manager)

	# プレイヤー参照を設定
	var selected_player = squad_manager.get_selected_player_node() if squad_manager else null
	if selected_player:
		path_manager.set_player(selected_player)

	# シグナル接続
	path_manager.path_confirmed.connect(_on_path_confirmed)
	path_manager.path_cleared.connect(_on_path_cleared)

	# GameUIにPathManagerを接続
	if game_ui and game_ui.has_method("connect_path_manager"):
		game_ui.connect_path_manager(path_manager)

	# InputManagerのdraw_startedを自前で処理（プレイヤー選択のため）
	if has_node("/root/InputManager"):
		var input_manager = get_node("/root/InputManager")
		# PathManagerより先にこのシーンでdraw_startedを処理
		input_manager.draw_started.connect(_on_draw_started_for_selection, CONNECT_REFERENCE_COUNTED)

	# 実行フェーズ開始時に全プレイヤーのパスを適用
	if has_node("/root/GameEvents"):
		var events = get_node("/root/GameEvents")
		events.execution_phase_started.connect(_on_execution_phase_started)


## カメラシステムをセットアップ
func _setup_camera_system() -> void:
	var selected_player = squad_manager.get_selected_player_node() if squad_manager else null
	if not selected_player:
		return

	# プレイヤーのカメラを取得、なければ新規作成
	var player_camera: Camera3D = selected_player.get_node_or_null("Camera3D")

	if player_camera:
		# カメラをプレイヤーから切り離してシーンルートに配置
		player_camera.get_parent().remove_child(player_camera)
	else:
		# カメラがない場合（enemy.tscnなど）は新規作成
		# player.tscnのCamera3Dと同じ設定を使用
		player_camera = Camera3D.new()
		player_camera.name = "Camera3D"
		# Transform3D(1, 0, 0, 0, 0, 1, 0, -1, 0, 0, 8, 0) = 90度X軸回転、Y=8の位置
		player_camera.transform = Transform3D(
			Vector3(1, 0, 0),
			Vector3(0, 0, 1),
			Vector3(0, -1, 0),
			Vector3(0, 8, 0)
		)
		player_camera.fov = 45.0
		print("[GameScene] Created new camera for player without Camera3D")

	# Zファイティング対策: nearプレーンを調整
	player_camera.near = 0.1
	player_camera.far = 100.0

	camera_controller = CameraControllerScene.instantiate()
	add_child(camera_controller)

	# カメラをコントローラーに追加
	camera_controller.add_child(player_camera)
	camera_controller.camera = player_camera

	# カメラをアクティブに設定
	player_camera.current = true

	# 初期カメラ位置をプレイヤー位置に設定（追従はしない）
	camera_controller.snap_to_position(selected_player.global_position)
	print("[GameScene] Camera snapped to player position: %s" % selected_player.global_position)


## Fog of Warレンダラーをセットアップ
func _setup_fog_of_war_renderer() -> void:
	fog_renderer = FogOfWarRendererScene.instantiate()
	add_child(fog_renderer)

	# マップ範囲はGridManagerから自動取得される

	# 敵の初期可視性を設定（非表示から開始）
	_initialize_enemy_fog_of_war.call_deferred()

	print("[GameScene] Fog of War renderer initialized")


## 敵の視界初期化
func _initialize_enemy_fog_of_war() -> void:
	await get_tree().process_frame

	if fog_of_war_manager:
		# グループから敵を取得し、公開APIで可視性を設定
		var enemy_nodes := get_tree().get_nodes_in_group("enemies")
		for e in enemy_nodes:
			if e and is_instance_valid(e):
				fog_of_war_manager.set_enemy_visibility(e, false)


## 描画開始時のプレイヤー選択処理
func _on_draw_started_for_selection(_screen_pos: Vector2, world_pos: Vector3) -> void:
	if world_pos == Vector3.INF:
		return

	# タップ位置にプレイヤーがいるかチェックして選択
	_find_and_select_player_at_position(world_pos)


## パス確定時のコールバック（戦略フェーズ中はパスを保存するのみ）
func _on_path_confirmed(_waypoints: Array) -> void:
	# パスはPathManagerに保存されている
	# 実行フェーズ開始時に全プレイヤーに適用される
	pass


## パスクリア時のコールバック
func _on_path_cleared() -> void:
	pass


## 実行フェーズ開始時のコールバック
func _on_execution_phase_started(_turn_number: int) -> void:
	if not path_manager or not squad_manager:
		return

	# 全プレイヤーのパスを適用
	for data in squad_manager.squad:
		if not data.is_alive or not data.player_node:
			continue

		var player_node = data.player_node
		if path_manager.has_player_path(player_node):
			var path_data = path_manager.get_player_path(player_node)
			var waypoints: Array = []
			var path: Array = path_data["path"]
			var run_flags: Array = path_data["run_flags"]

			for i in range(path.size()):
				var run := false
				if i > 0 and i - 1 < run_flags.size():
					run = run_flags[i - 1]
				waypoints.append({
					"position": path[i],
					"run": run
				})

			if player_node.has_method("set_path"):
				player_node.set_path(waypoints)
				print("[GameScene] Path applied to %s (%d waypoints)" % [player_node.name, waypoints.size()])


## ネットワーク同期をセットアップ
func _setup_network_sync() -> void:
	network_sync_manager = Node.new()
	network_sync_manager.name = "NetworkSyncManager"
	network_sync_manager.set_script(NetworkSyncManagerScript)
	add_child(network_sync_manager)

	# シグナル接続
	network_sync_manager.remote_player_joined.connect(_on_remote_player_joined)
	network_sync_manager.remote_player_left.connect(_on_remote_player_left)
	network_sync_manager.remote_player_updated.connect(_on_remote_player_updated)
	network_sync_manager.remote_player_action.connect(_on_remote_player_action)
	network_sync_manager.game_state_updated.connect(_on_game_state_updated)

	# 有効化
	network_sync_manager.activate()

	# チーム割り当ては既にlobby_screen.gdで完了している
	print("[GameScene] NetworkSyncManager initialized - My team: %s" % (
		"CT" if GameManager.assigned_team == GameManager.Team.CT else "TERRORIST"
	))


## リモートプレイヤー参加
func _on_remote_player_joined(user_id: String, username: String) -> void:
	print("[GameScene] Remote player joined: %s (%s)" % [username, user_id])
	# TODO: リモートプレイヤーのキャラクターを生成


## リモートプレイヤー離脱
func _on_remote_player_left(user_id: String) -> void:
	print("[GameScene] Remote player left: %s" % user_id)
	# TODO: リモートプレイヤーのキャラクターを削除


## リモートプレイヤー位置更新
func _on_remote_player_updated(user_id: String, character_name: String, position: Vector3, rotation: float, is_moving: bool, is_running: bool) -> void:
	# 相手チームのキャラクターを探して位置を更新
	if character_name.is_empty():
		return

	# 相手チームのノードを取得
	var enemy_team_node: Node3D
	if GameManager.assigned_team == GameManager.Team.CT:
		enemy_team_node = t_node
	else:
		enemy_team_node = ct_node

	if not enemy_team_node:
		return

	# キャラクター名でノードを検索
	var target_node = enemy_team_node.get_node_or_null(character_name)
	if target_node and target_node is CharacterBody3D:
		# ターゲット位置とアニメーション状態を保存（_processで補間する）
		_remote_player_targets[character_name] = {
			"position": position,
			"rotation": rotation,
			"is_moving": is_moving,
			"is_running": is_running,
			"node": target_node
		}
	else:
		# デバッグ：1回だけ子ノード一覧を出力
		if not _debug_printed_children:
			_debug_printed_children = true
			var children_names = []
			for child in enemy_team_node.get_children():
				children_names.append(child.name)
			print("[GameScene] Looking for '%s' but enemy team (%s) has children: %s" % [character_name, enemy_team_node.name, children_names])


## リモートプレイヤーの位置を補間
func _interpolate_remote_players(delta: float) -> void:
	for char_name in _remote_player_targets:
		var target_data = _remote_player_targets[char_name]
		var node: CharacterBody3D = target_data.node
		if not is_instance_valid(node):
			continue

		var target_pos: Vector3 = target_data.position
		var target_rot: float = target_data.rotation

		# アニメーション状態を設定（送信元の状態を反映）
		if "is_moving" in node:
			node.is_moving = target_data.get("is_moving", false)
		if "is_running" in node:
			node.is_running = target_data.get("is_running", false)

		# 位置の補間
		node.global_position = node.global_position.lerp(target_pos, delta * INTERPOLATION_SPEED)

		# 回転の補間（角度のラップアラウンドを考慮）
		var current_rot = node.rotation.y
		var rot_diff = target_rot - current_rot
		# 角度を-PIからPIの範囲に正規化
		while rot_diff > PI:
			rot_diff -= TAU
		while rot_diff < -PI:
			rot_diff += TAU
		node.rotation.y = current_rot + rot_diff * delta * INTERPOLATION_SPEED


## リモートプレイヤーアクション
func _on_remote_player_action(user_id: String, action_type: String, data: Dictionary) -> void:
	print("[GameScene] Remote player action: %s -> %s" % [user_id, action_type])
	# TODO: アクションに応じた処理


## ゲーム状態更新
func _on_game_state_updated(state: Dictionary) -> void:
	var event_type = state.get("event", "")
	print("[GameScene] Game state updated: %s" % event_type)

	match event_type:
		"match_ready":
			# マッチ準備完了
			pass
		"game_start":
			# ゲーム開始
			if match_manager:
				match_manager.start_match()
		"phase_change":
			# フェーズ変更
			var phase = state.get("phase", "")
			var round_num = state.get("round", 0)
			print("[GameScene] Phase changed to: %s (Round %d)" % [phase, round_num])


# =====================================
# デバッグ用機能
# =====================================

## マップのスポーンポイントからキャラクターの位置を設定
func _apply_spawn_positions_from_map(my_team: Array[CharacterBody3D], enemy_team: Array[CharacterBody3D]) -> void:
	if not map_node:
		print("[GameScene] Map node not found, skipping spawn position setup")
		return

	# マップからCTとTのスポーンポイントを取得
	var ct_spawns: Array[Node3D] = []
	var t_spawns: Array[Node3D] = []

	# CTRespone* と TRespone* ノードを検索（GLBからインポートされたEmpty）
	for child in map_node.get_children():
		_find_spawn_points_recursive(child, ct_spawns, t_spawns)

	# 直接の子ノードも確認
	_find_spawn_points_recursive(map_node, ct_spawns, t_spawns)

	print("[GameScene] Found spawn points - CT: %d, T: %d" % [ct_spawns.size(), t_spawns.size()])

	# オンラインマッチの場合、割り当てられたチームに基づいてスポーンポイントを選択
	var my_team_spawns: Array[Node3D]
	var enemy_team_spawns: Array[Node3D]

	if GameManager.is_online_match and GameManager.assigned_team == GameManager.Team.TERRORIST:
		my_team_spawns = t_spawns
		enemy_team_spawns = ct_spawns
	else:
		my_team_spawns = ct_spawns
		enemy_team_spawns = t_spawns

	# 自チームの位置と向きを設定
	for i in range(min(my_team.size(), my_team_spawns.size())):
		var spawn = my_team_spawns[i]
		var spawn_pos = spawn.global_position
		# Y座標は地面から少し上に（キャラクターの高さを考慮）
		spawn_pos.y = 1.0
		my_team[i].global_position = spawn_pos
		# Blenderからの回転を適用（BlenderのZ回転 → GodotのY回転）
		my_team[i].rotation.y = spawn.rotation.y
		# 初期武器を設定（AK47）
		if my_team[i].has_method("set_weapon"):
			my_team[i].set_weapon(CharacterSetup.WeaponId.AK47)
		print("[GameScene] Spawned %s at %s, rot=%.1f" % [my_team[i].name, spawn_pos, rad_to_deg(spawn.rotation.y)])

	# 敵チームの位置と向きを設定
	for i in range(min(enemy_team.size(), enemy_team_spawns.size())):
		var spawn = enemy_team_spawns[i]
		var spawn_pos = spawn.global_position
		spawn_pos.y = 1.0
		enemy_team[i].global_position = spawn_pos
		# Blenderからの回転を適用
		enemy_team[i].rotation.y = spawn.rotation.y
		# 初期武器を設定（AK47）
		if enemy_team[i].has_method("set_weapon"):
			enemy_team[i].set_weapon(CharacterSetup.WeaponId.AK47)
		print("[GameScene] Spawned %s at %s, rot=%.1f" % [enemy_team[i].name, spawn_pos, rad_to_deg(spawn.rotation.y)])


## スポーンポイントを再帰的に検索
## Blenderからエクスポートした命名規則: ResponseCT1, ResponseCT2, ResponseT1, ResponseT2, etc.
func _find_spawn_points_recursive(node: Node, ct_spawns: Array[Node3D], t_spawns: Array[Node3D]) -> void:
	if node.name.begins_with("ResponseCT"):
		ct_spawns.append(node as Node3D)
	elif node.name.begins_with("ResponseT"):
		t_spawns.append(node as Node3D)

	for child in node.get_children():
		_find_spawn_points_recursive(child, ct_spawns, t_spawns)


## デバッグ用：キャラクターを近くにスポーン
func _apply_debug_spawn_positions(my_team: Array[CharacterBody3D], enemy_team: Array[CharacterBody3D]) -> void:
	print("[GameScene] Applying debug spawn positions (nearby)")

	# 中心位置（マップの中央付近）
	var center_pos = Vector3(0, 1, 0)

	# 自チームは中心から-5の位置に配置
	var my_team_offset = Vector3(-5, 0, 0)
	for i in range(my_team.size()):
		var char = my_team[i]
		var spawn_pos = center_pos + my_team_offset + Vector3(0, 0, i * 2)
		char.global_position = spawn_pos
		print("[GameScene] Moved %s to %s" % [char.name, spawn_pos])

	# 敵チームは中心から+5の位置に配置
	var enemy_team_offset = Vector3(5, 0, 0)
	for i in range(enemy_team.size()):
		var char = enemy_team[i]
		var spawn_pos = center_pos + enemy_team_offset + Vector3(0, 0, i * 2)
		char.global_position = spawn_pos
		print("[GameScene] Moved %s to %s" % [char.name, spawn_pos])
