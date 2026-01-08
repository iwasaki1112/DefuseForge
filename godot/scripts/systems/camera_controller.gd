extends Node3D

## カメラコントローラー
## ズーム、パン操作を管理（自動追従なし）

@export_group("カメラ設定")
@export var camera_distance: float = 15.0
@export var camera_angle: float = -60.0  # 斜めアングル（度）
@export var min_zoom: float = 4.0
@export var max_zoom: float = 25.0
@export var pan_scale: float = 0.002  # パン感度（タッチ用）
@export var keyboard_pan_speed: float = 20.0  # キーボードパン速度

# カメラ参照
var camera: Camera3D = null

# 内部状態
var target_zoom: float = 5.0
var camera_position: Vector3 = Vector3.ZERO  # カメラ注視点のワールド座標


func _ready() -> void:
	# カメラを探す（子ノードまたは外部から設定）
	camera = get_node_or_null("Camera3D")
	if camera == null:
		camera = get_viewport().get_camera_3d()

	target_zoom = camera_distance

	# InputManagerに接続
	if has_node("/root/InputManager"):
		var input_manager = get_node("/root/InputManager")
		input_manager.camera_zoom.connect(_on_camera_zoom)
		input_manager.camera_pan.connect(_on_camera_pan)


func _physics_process(delta: float) -> void:
	if camera == null:
		return

	_handle_keyboard_input(delta)
	_update_camera()


## キーボード入力でカメラパン（WASD）
func _handle_keyboard_input(delta: float) -> void:
	# プレイ中でない場合は入力を無視
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	var move_dir := Vector3.ZERO

	if Input.is_action_pressed("move_forward"):
		move_dir.z -= 1
	if Input.is_action_pressed("move_backward"):
		move_dir.z += 1
	if Input.is_action_pressed("move_left"):
		move_dir.x -= 1
	if Input.is_action_pressed("move_right"):
		move_dir.x += 1

	if move_dir != Vector3.ZERO:
		move_dir = move_dir.normalized()
		camera_position += move_dir * keyboard_pan_speed * delta


## カメラ位置を更新
func _update_camera() -> void:
	# 斜めからのトップダウンビュー
	var elevation_rad := deg_to_rad(-camera_angle)
	var cam_y := camera_distance * sin(elevation_rad)
	var cam_z := camera_distance * cos(elevation_rad)

	var cam_pos := camera_position + Vector3(0, cam_y, cam_z)
	camera.global_position = cam_pos

	# 注視点を見る
	camera.look_at(camera_position + Vector3(0, 1, 0), Vector3.UP)


## ズーム処理
func _on_camera_zoom(zoom_delta: float) -> void:
	target_zoom = clamp(target_zoom + zoom_delta, min_zoom, max_zoom)
	camera_distance = target_zoom


## パン処理（2本指ドラッグ）
func _on_camera_pan(delta: Vector2) -> void:
	var pan_factor := camera_distance * pan_scale
	camera_position.x -= delta.x * pan_factor
	camera_position.z -= delta.y * pan_factor


## カメラを指定位置に即座に配置
func snap_to_position(pos: Vector3) -> void:
	if camera == null:
		return

	camera_position = pos
	_update_camera()


## カメラを即座に配置（初期化用 - 後方互換）
func snap_to_target() -> void:
	# 初期位置は原点、または現在の位置をそのまま使用
	_update_camera()


## カメラ位置をリセット
func reset_position(pos: Vector3 = Vector3.ZERO) -> void:
	camera_position = pos


## ズームをリセット
func reset_zoom(new_zoom: float = -1) -> void:
	if new_zoom > 0:
		target_zoom = clamp(new_zoom, min_zoom, max_zoom)
	else:
		target_zoom = camera_distance
	camera_distance = target_zoom


## 現在のカメラ注視点を取得
func get_camera_position() -> Vector3:
	return camera_position


## Camera3Dを取得
func get_camera() -> Camera3D:
	return camera
