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

@onready var players_node: Node3D = $Players
@onready var enemies_node: Node3D = $Enemies
@onready var game_ui: CanvasLayer = $GameUI

var enemies: Array[CharacterBody3D] = []

# 選択インジケーター
var selection_indicator: MeshInstance3D = null
var selection_indicator_material: StandardMaterial3D = null

var path_manager: Node3D = null
var camera_controller: Node3D = null
var fog_renderer: Node3D = null
var fog_of_war_manager: Node = null
var match_manager: Node = null
var squad_manager: Node = null
var network_sync_manager: Node = null


func _ready() -> void:
	# システムノードを初期化（順序重要）
	_setup_squad_manager()
	_setup_fog_of_war_manager()
	_setup_match_manager()

	# プレイヤーを収集してSquadManagerに登録
	var players: Array[CharacterBody3D] = []
	for child in players_node.get_children():
		if child is CharacterBody3D:
			players.append(child)

	# SquadManagerで分隊を初期化
	if squad_manager:
		squad_manager.initialize_squad(players)
		squad_manager.player_selected.connect(_on_squad_player_selected)

	# 敵を収集（敵はenemyスクリプトでグループに自動追加される）
	for child in enemies_node.get_children():
		if child is CharacterBody3D:
			enemies.append(child)

	print("[GameScene] Players: %d, Enemies: %d" % [players.size(), enemies.size()])

	# 選択インジケーターを作成
	_create_selection_indicator()

	# 追加システムを初期化
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

	# カメラは自動追従しない（2本指/WASDでのみ移動）

	print("[GameScene] Player selected via SquadManager: %s" % selected_player.name)


func _exit_tree() -> void:
	# シーン終了時にクリーンアップ
	if network_sync_manager:
		network_sync_manager.deactivate()
	GameManager.unregister_match_manager()
	GameManager.unregister_squad_manager()
	GameManager.unregister_fog_of_war_manager()
	GameManager.stop_game()
	# 敵はグループで管理されるため、シーン離脱時に自動クリーンアップ


func _process(_delta: float) -> void:
	# 選択インジケーターを更新
	_update_selection_indicator()


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


## 選択インジケーターを更新
func _update_selection_indicator() -> void:
	var selected_player = squad_manager.get_selected_player_node() if squad_manager else null
	if selection_indicator and selected_player:
		selection_indicator.visible = true
		var pos = selected_player.global_position
		selection_indicator.global_position = Vector3(pos.x, pos.y + 0.05, pos.z)

		# 選択中のプレイヤーのキャラクターカラーでリングの色を更新
		_update_selection_indicator_color()
	elif selection_indicator:
		selection_indicator.visible = false


## 選択インジケーターの色を更新
func _update_selection_indicator_color() -> void:
	if not selection_indicator_material or not squad_manager:
		return

	var player_data = squad_manager.get_selected_player()
	if not player_data:
		return

	var color: Color = player_data.character_color if "character_color" in player_data else Color.GREEN

	# マテリアルの色を更新
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


## パスシステムをセットアップ
func _setup_path_system() -> void:
	path_manager = PathManagerScene.instantiate()
	add_child(path_manager)

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

	# プレイヤーのカメラを取得してCameraControllerに移動
	var player_camera: Camera3D = selected_player.get_node_or_null("Camera3D")
	if player_camera:
		# カメラをプレイヤーから切り離してシーンルートに配置
		player_camera.get_parent().remove_child(player_camera)

		camera_controller = CameraControllerScene.instantiate()
		add_child(camera_controller)

		# カメラをコントローラーに追加
		camera_controller.add_child(player_camera)
		camera_controller.camera = player_camera

		# カメラをアクティブに設定
		player_camera.current = true

		# 初期カメラ位置をプレイヤー位置に設定（追従はしない）
		camera_controller.snap_to_position(selected_player.global_position)


## Fog of Warレンダラーをセットアップ
func _setup_fog_of_war_renderer() -> void:
	fog_renderer = FogOfWarRendererScene.instantiate()
	add_child(fog_renderer)

	# マップ範囲を設定（dust3マップ用）
	# 必要に応じて調整
	fog_renderer.set_map_bounds(Vector3(0, 0, 0), Vector2(80, 80))

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

	print("[GameScene] NetworkSyncManager initialized for online match")


## リモートプレイヤー参加
func _on_remote_player_joined(user_id: String, username: String) -> void:
	print("[GameScene] Remote player joined: %s (%s)" % [username, user_id])
	# TODO: リモートプレイヤーのキャラクターを生成


## リモートプレイヤー離脱
func _on_remote_player_left(user_id: String) -> void:
	print("[GameScene] Remote player left: %s" % user_id)
	# TODO: リモートプレイヤーのキャラクターを削除


## リモートプレイヤー位置更新
func _on_remote_player_updated(user_id: String, position: Vector3, rotation: float) -> void:
	# TODO: リモートプレイヤーのキャラクターを更新
	pass


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
