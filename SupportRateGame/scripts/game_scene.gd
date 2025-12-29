extends Node3D

## ゲームシーンのメイン管理
## CS1.6 + Door Kickers 2 スタイル

const PathDrawer = preload("res://scripts/systems/path_drawer.gd")

@onready var player: CharacterBody3D = $Player
@onready var game_ui: CanvasLayer = $GameUI

var path_drawer: Node3D = null


func _ready() -> void:
	# プレイヤー参照をGameManagerに設定
	GameManager.player = player

	# パス描画システムの初期化
	_setup_path_system()

	# ゲームを開始
	GameManager.start_game()


func _exit_tree() -> void:
	# シーン終了時にゲームを停止
	GameManager.stop_game()


func _setup_path_system() -> void:
	# PathDrawerを作成（3D描画・深度テスト有効）
	path_drawer = Node3D.new()
	path_drawer.name = "PathDrawer"
	path_drawer.set_script(PathDrawer)
	add_child(path_drawer)

	# シグナル接続
	path_drawer.path_confirmed.connect(_on_path_confirmed)
	path_drawer.path_cleared.connect(_on_path_cleared)


## パス描画完了時のコールバック
## waypoints: Array of {position: Vector3, run: bool}
func _on_path_confirmed(waypoints: Array) -> void:
	if player and player.has_method("set_path"):
		player.set_path(waypoints)


## パスクリア時のコールバック
func _on_path_cleared() -> void:
	pass
