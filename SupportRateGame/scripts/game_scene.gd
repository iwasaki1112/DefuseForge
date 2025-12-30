extends Node3D

## ゲームシーンのメイン管理
## 各システムの初期化と接続を担当
## プレイヤー管理はSquadManagerに委譲
## ラウンド/経済はMatchManagerに委譲

const PathManager = preload("res://scripts/systems/path/path_manager.gd")
const CameraController = preload("res://scripts/systems/camera_controller.gd")
const FogOfWarRendererScript = preload("res://scripts/systems/vision/fog_of_war_renderer.gd")
const FogOfWarManagerScript = preload("res://scripts/systems/vision/fog_of_war_manager.gd")
const MatchManagerScript = preload("res://scripts/systems/match_manager.gd")
const SquadManagerScript = preload("res://scripts/systems/squad_manager.gd")

@onready var players_node: Node3D = $Players
@onready var enemies_node: Node3D = $Enemies
@onready var game_ui: CanvasLayer = $GameUI

var enemies: Array[CharacterBody3D] = []

# 選択インジケーター
var selection_indicator: MeshInstance3D = null
const SELECTION_RADIUS: float = 1.5  # プレイヤー選択の判定半径

var path_manager: Node3D = null
var camera_controller: Node3D = null
var fog_renderer: Node3D = null
var fog_of_war_manager: Node = null
var match_manager: Node = null
var squad_manager: Node = null


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

	# 敵を収集
	for child in enemies_node.get_children():
		if child is CharacterBody3D:
			enemies.append(child)

	# 敵を敵リストに追加
	for enemy in enemies:
		GameManager.enemies.append(enemy)

	print("[GameScene] Players: %d, Enemies: %d" % [players.size(), enemies.size()])

	# 選択インジケーターを作成
	_create_selection_indicator()

	# 追加システムを初期化
	_setup_path_system()
	_setup_camera_system()
	_setup_fog_of_war_renderer()

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
	GameManager.unregister_match_manager()
	GameManager.unregister_squad_manager()
	GameManager.unregister_fog_of_war_manager()
	GameManager.stop_game()
	GameManager.enemies.clear()


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

	# マテリアル設定
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0, 1, 0, 0.8)  # 緑色
	material.emission_enabled = true
	material.emission = Color(0, 1, 0)
	material.emission_energy_multiplier = 2.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	selection_indicator.material_override = material

	add_child(selection_indicator)


## 選択インジケーターを更新
func _update_selection_indicator() -> void:
	var selected_player = squad_manager.get_selected_player_node() if squad_manager else null
	if selection_indicator and selected_player:
		selection_indicator.visible = true
		var pos = selected_player.global_position
		selection_indicator.global_position = Vector3(pos.x, pos.y + 0.05, pos.z)
	elif selection_indicator:
		selection_indicator.visible = false


## 位置からプレイヤーを検索してSquadManagerで選択
func _find_and_select_player_at_position(world_pos: Vector3) -> bool:
	if not squad_manager:
		return false

	var closest_index: int = -1
	var closest_distance: float = SELECTION_RADIUS

	for i in range(squad_manager.squad.size()):
		var data = squad_manager.squad[i]
		if not data.is_alive or not data.player_node:
			continue
		var dist := world_pos.distance_to(data.player_node.global_position)
		if dist < closest_distance:
			closest_distance = dist
			closest_index = i

	if closest_index >= 0 and closest_index != squad_manager.selected_index:
		squad_manager.select_player(closest_index)
		return true

	return false


## SquadManagerをセットアップ
func _setup_squad_manager() -> void:
	squad_manager = Node.new()
	squad_manager.name = "SquadManager"
	squad_manager.set_script(SquadManagerScript)
	add_child(squad_manager)

	# GameManagerに登録
	GameManager.register_squad_manager(squad_manager)

	print("[GameScene] SquadManager initialized")


## FogOfWarManagerをセットアップ
func _setup_fog_of_war_manager() -> void:
	fog_of_war_manager = Node.new()
	fog_of_war_manager.name = "FogOfWarManager"
	fog_of_war_manager.set_script(FogOfWarManagerScript)
	add_child(fog_of_war_manager)

	# GameManagerに登録
	GameManager.register_fog_of_war_manager(fog_of_war_manager)

	print("[GameScene] FogOfWarManager initialized")


## MatchManagerをセットアップ
func _setup_match_manager() -> void:
	match_manager = Node.new()
	match_manager.name = "MatchManager"
	match_manager.set_script(MatchManagerScript)
	add_child(match_manager)

	# GameManagerに登録
	GameManager.register_match_manager(match_manager)

	print("[GameScene] MatchManager initialized")


## パスシステムをセットアップ
func _setup_path_system() -> void:
	path_manager = Node3D.new()
	path_manager.name = "PathManager"
	path_manager.set_script(PathManager)
	add_child(path_manager)

	# プレイヤー参照を設定
	var selected_player = squad_manager.get_selected_player_node() if squad_manager else null
	if selected_player:
		path_manager.set_player(selected_player)

	# シグナル接続
	path_manager.path_confirmed.connect(_on_path_confirmed)
	path_manager.path_cleared.connect(_on_path_cleared)

	# InputManagerのdraw_startedを自前で処理（プレイヤー選択のため）
	if has_node("/root/InputManager"):
		var input_manager = get_node("/root/InputManager")
		# PathManagerより先にこのシーンでdraw_startedを処理
		input_manager.draw_started.connect(_on_draw_started_for_selection, CONNECT_REFERENCE_COUNTED)


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

		camera_controller = Node3D.new()
		camera_controller.name = "CameraController"
		camera_controller.set_script(CameraController)
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
	fog_renderer = Node3D.new()
	fog_renderer.name = "FogOfWarRenderer"
	fog_renderer.set_script(FogOfWarRendererScript)
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
		for e in GameManager.enemies:
			if e and is_instance_valid(e):
				fog_of_war_manager.set_character_visible(e, false)
				fog_of_war_manager.enemy_visibility[e] = false


## 描画開始時のプレイヤー選択処理
func _on_draw_started_for_selection(_screen_pos: Vector2, world_pos: Vector3) -> void:
	if world_pos == Vector3.INF:
		return

	# タップ位置にプレイヤーがいるかチェックして選択
	_find_and_select_player_at_position(world_pos)


## パス確定時のコールバック
func _on_path_confirmed(waypoints: Array) -> void:
	var selected_player = squad_manager.get_selected_player_node() if squad_manager else null
	if selected_player and selected_player.has_method("set_path"):
		selected_player.set_path(waypoints)


## パスクリア時のコールバック
func _on_path_cleared() -> void:
	pass
