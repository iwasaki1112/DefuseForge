class_name InputController
extends Node
## ゲーム画面の入力処理をまとめたコントローラー

var game_manager: GameManager = null
var camera_pan_controller: CameraPanController = null


func setup(manager: GameManager, pan_controller: CameraPanController) -> void:
	game_manager = manager
	camera_pan_controller = pan_controller


func _unhandled_input(event: InputEvent) -> void:
	if not game_manager:
		return

	# カメラドラッグ移動
	if camera_pan_controller and camera_pan_controller.handle_input(event):
		return

	# 回転モード中
	if game_manager.is_rotation_active() and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			game_manager.handle_rotation_input(event.position)
		return

	# パスモード中：パス描画後にキャラクター以外をクリックでキャンセル
	if game_manager.is_path_mode() and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if game_manager.has_pending_path():
				# 視線/Run設定中はPathDrawerに入力を渡す
				if game_manager.path_service and game_manager.path_service.is_marker_mode():
					return
				var clicked = game_manager.raycast_character(event.position)
				if game_manager.path_service:
					game_manager.path_service.handle_click_to_cancel(clicked)
		return

	# 通常クリック処理（左クリックのみ）
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not game_manager.is_rotation_active() and not game_manager.is_path_mode():
				game_manager.handle_click(event.position, event.button_index)


func _input(event: InputEvent) -> void:
	if not game_manager:
		return

	# ESCキー処理
	if event.is_action_pressed("ui_cancel"):
		if game_manager.is_any_path_following_active():
			game_manager.cancel_all_path_following()
		elif game_manager.is_rotation_active():
			game_manager.cancel_rotation()
		elif game_manager.is_path_mode():
			game_manager.cancel_path()
