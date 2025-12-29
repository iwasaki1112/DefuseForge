extends Node3D

## ゲームシーンのメイン管理
## 各システムの初期化と接続を担当

const PathManager = preload("res://scripts/systems/path/path_manager.gd")
const CameraController = preload("res://scripts/systems/camera_controller.gd")
const FogOfWarRendererScript = preload("res://scripts/systems/vision/fog_of_war_renderer.gd")

@onready var player: CharacterBody3D = $Player
@onready var enemy: CharacterBody3D = $Enemy
@onready var game_ui: CanvasLayer = $GameUI

var path_manager: Node3D = null
var camera_controller: Node3D = null
var fog_renderer: Node3D = null


func _ready() -> void:
	# プレイヤー参照をGameManagerに設定
	GameManager.player = player

	# 敵を敵リストに追加
	if enemy:
		GameManager.enemies.append(enemy)

	# システムを初期化
	_setup_path_system()
	_setup_camera_system()
	_setup_fog_of_war()

	# ゲームを開始
	GameManager.start_game()


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
	path_manager.set_player(player)

	# シグナル接続
	path_manager.path_confirmed.connect(_on_path_confirmed)
	path_manager.path_cleared.connect(_on_path_cleared)


## カメラシステムをセットアップ
func _setup_camera_system() -> void:
	# プレイヤーのカメラを取得してCameraControllerに移動
	var player_camera: Camera3D = player.get_node_or_null("Camera3D")
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
		camera_controller.follow_target = player

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


## 敵のFog of War初期化
func _initialize_enemy_fog_of_war() -> void:
	await get_tree().process_frame

	if FogOfWarManager:
		for e in GameManager.enemies:
			if e and is_instance_valid(e):
				FogOfWarManager._set_character_visible(e, false)
				FogOfWarManager.enemy_visibility[e] = false
				print("[GameScene] Enemy '%s' hidden by Fog of War" % e.name)


## パス確定時のコールバック
func _on_path_confirmed(waypoints: Array) -> void:
	if player and player.has_method("set_path"):
		player.set_path(waypoints)


## パスクリア時のコールバック
func _on_path_cleared() -> void:
	pass
