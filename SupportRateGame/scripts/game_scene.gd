extends Node3D

## ゲームシーンのメイン管理
## 各システムの初期化と接続を担当

const PathManager = preload("res://scripts/systems/path/path_manager.gd")
const CameraController = preload("res://scripts/systems/camera_controller.gd")
const FogOfWarRendererScript = preload("res://scripts/systems/vision/fog_of_war_renderer.gd")

@onready var players_node: Node3D = $Players
@onready var enemies_node: Node3D = $Enemies
@onready var game_ui: CanvasLayer = $GameUI

var players: Array[CharacterBody3D] = []
var enemies: Array[CharacterBody3D] = []
var selected_player: CharacterBody3D = null

var path_manager: Node3D = null
var camera_controller: Node3D = null
var fog_renderer: Node3D = null


func _ready() -> void:
	# プレイヤーを収集
	for child in players_node.get_children():
		if child is CharacterBody3D:
			players.append(child)

	# 敵を収集
	for child in enemies_node.get_children():
		if child is CharacterBody3D:
			enemies.append(child)

	# 最初のプレイヤーを選択
	if players.size() > 0:
		selected_player = players[0]
		GameManager.player = selected_player

	# 敵を敵リストに追加
	for enemy in enemies:
		GameManager.enemies.append(enemy)

	print("[GameScene] Players: %d, Enemies: %d" % [players.size(), enemies.size()])

	# システムを初期化
	_setup_path_system()
	_setup_camera_system()
	_setup_fog_of_war()

	# ゲームを開始（すべてのノードがreadyになった後に実行）
	GameManager.start_game.call_deferred()


func _exit_tree() -> void:
	# シーン終了時にクリーンアップ
	GameManager.stop_game()
	GameManager.enemies.clear()


## パスシステムをセットアップ
func _setup_path_system() -> void:
	path_manager = Node3D.new()
	path_manager.name = "PathManager"
	path_manager.set_script(PathManager)
	add_child(path_manager)

	# プレイヤー参照を設定
	if selected_player:
		path_manager.set_player(selected_player)

	# シグナル接続
	path_manager.path_confirmed.connect(_on_path_confirmed)
	path_manager.path_cleared.connect(_on_path_cleared)


## カメラシステムをセットアップ
func _setup_camera_system() -> void:
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
		camera_controller.follow_target = selected_player

		# カメラをアクティブに設定
		player_camera.current = true

		# 即座にカメラを配置
		camera_controller.snap_to_target()


## Fog of Warシステムをセットアップ
func _setup_fog_of_war() -> void:
	fog_renderer = Node3D.new()
	fog_renderer.name = "FogOfWarRenderer"
	fog_renderer.set_script(FogOfWarRendererScript)
	add_child(fog_renderer)

	# マップ範囲を設定（dust3マップ用）
	# 必要に応じて調整
	fog_renderer.set_map_bounds(Vector3(0, 0, 0), Vector2(80, 80))

	# 敵の初期可視性を設定（非表示から開始）
	_initialize_enemy_fog_of_war.call_deferred()

	print("[GameScene] Fog of War system initialized")


## 敵の視界初期化
func _initialize_enemy_fog_of_war() -> void:
	await get_tree().process_frame

	if FogOfWarManager:
		for e in GameManager.enemies:
			if e and is_instance_valid(e):
				FogOfWarManager.set_character_visible(e, false)
				FogOfWarManager.enemy_visibility[e] = false


## パス確定時のコールバック
func _on_path_confirmed(waypoints: Array) -> void:
	if selected_player and selected_player.has_method("set_path"):
		selected_player.set_path(waypoints)


## パスクリア時のコールバック
func _on_path_cleared() -> void:
	pass
