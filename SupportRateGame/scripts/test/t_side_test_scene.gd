extends Node3D
## T側テストシーン - T側キャラクターの表示、視野コーン、カメラ機能をテスト

@onready var t_node: Node3D = $T
@onready var test_ui: CanvasLayer = $TestUI
@onready var info_label: Label = $TestUI/InfoLabel

var current_player: CharacterBody3D
var current_player_index: int = 0
var players: Array[CharacterBody3D] = []

var player_camera: Camera3D
var camera_controller: Node

# FogOfWar用
var fog_of_war_manager: Node
var fog_of_war_renderer: Node3D

func _ready() -> void:
	print("[TSideTest] Starting T side test scene")

	# FogOfWarManagerをシーンに追加（VisionComponentの登録先）
	_setup_fog_of_war()

	# T側キャラクターを収集
	for child in t_node.get_children():
		if child is CharacterBody3D:
			players.append(child)
			# AIを無効化（プレイヤー操作テスト用）
			if "is_player_controlled" in child:
				child.is_player_controlled = true
			print("[TSideTest] Found T player: %s at %s" % [child.name, child.global_position])

	print("[TSideTest] Total T players: %d" % players.size())

	# 最初のプレイヤーを選択
	if players.size() > 0:
		_select_player(0)

	# UIを更新
	_update_info_label()


func _setup_fog_of_war() -> void:
	# FogOfWarManagerを作成
	var FogOfWarManagerScript = load("res://scripts/systems/vision/fog_of_war_manager.gd")
	fog_of_war_manager = FogOfWarManagerScript.new()
	fog_of_war_manager.name = "FogOfWarManager"
	add_child(fog_of_war_manager)

	# GameManagerに登録（VisionComponentがこれを参照する）
	GameManager.fog_of_war_manager = fog_of_war_manager
	print("[TSideTest] FogOfWarManager initialized and registered to GameManager")

	# FogOfWarRendererを作成（_readyでfog_of_war_managerに自動接続される）
	var FogOfWarRendererScript = load("res://scripts/systems/vision/fog_of_war_renderer.gd")
	fog_of_war_renderer = FogOfWarRendererScript.new()
	fog_of_war_renderer.name = "FogOfWarRenderer"
	add_child(fog_of_war_renderer)
	print("[TSideTest] FogOfWarRenderer initialized")


func _select_player(index: int) -> void:
	if index < 0 or index >= players.size():
		return

	current_player_index = index
	current_player = players[index]

	# カメラをセットアップ
	_setup_camera()

	print("[TSideTest] Selected player: %s" % current_player.name)


func _setup_camera() -> void:
	if not current_player:
		return

	# 既存のカメラを取得または作成
	player_camera = current_player.get_node_or_null("Camera3D")

	if player_camera:
		print("[TSideTest] Found existing Camera3D in player")
	else:
		# カメラがない場合は作成
		player_camera = Camera3D.new()
		player_camera.name = "Camera3D"
		player_camera.transform = Transform3D(
			Vector3(1, 0, 0),
			Vector3(0, 0, 1),
			Vector3(0, -1, 0),
			Vector3(0, 8, 0)
		)
		player_camera.fov = 45.0
		current_player.add_child(player_camera)
		print("[TSideTest] Created new Camera3D for player")

	player_camera.current = true

	# カメラコントローラーをセットアップ
	if camera_controller:
		camera_controller.queue_free()

	var CameraControllerScript = load("res://scripts/systems/camera_controller.gd")
	camera_controller = CameraControllerScript.new()
	camera_controller.name = "CameraController"
	add_child(camera_controller)

	camera_controller.camera = player_camera
	camera_controller.snap_to_position(current_player.global_position)
	print("[TSideTest] CameraController initialized for %s" % current_player.name)

	# カメラ位置をログ
	print("[TSideTest] Camera position: %s" % player_camera.global_position)


func _input(event: InputEvent) -> void:
	# 数字キーでプレイヤー切り替え
	if event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_5:
			var index = event.keycode - KEY_1
			if index < players.size():
				_select_player(index)
				_update_info_label()

		# Rキーでリロード
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()

		# Escでタイトルに戻る
		if event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/title.tscn")


func _update_info_label() -> void:
	if not info_label or not current_player:
		return

	var vision_comp = current_player.get_node_or_null("VisionComponent")
	var vision_info = "Not Found"
	if vision_comp:
		vision_info = "FOV: %.0f, Dist: %.1f, Points: %d" % [
			vision_comp.fov_angle,
			vision_comp.view_distance,
			vision_comp.visible_points.size()
		]

	var camera_info = "Not Found"
	if player_camera:
		camera_info = "FOV: %.0f" % player_camera.fov

	var fow_info = "Not Found"
	if fog_of_war_manager:
		fow_info = "Components: %d" % fog_of_war_manager.vision_components.size()

	info_label.text = """T Side Test Scene
===================
Current Player: %s (Press 1-5 to switch)
Position: %s
Vision: %s
Camera: %s
FogOfWar: %s

Controls:
- 1-5: Select player
- R: Reload scene
- ESC: Back to title
- Two-finger pinch: Zoom
- Two-finger drag: Pan
""" % [current_player.name, current_player.global_position, vision_info, camera_info, fow_info]


func _process(_delta: float) -> void:
	_update_info_label()
