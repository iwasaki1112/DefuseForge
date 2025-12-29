extends Node3D

## カメラコントローラー
## ズーム、パン、ターゲット追従を管理

@export_group("カメラ設定")
@export var camera_distance: float = 5.0
@export var camera_angle: float = -60.0  # 斜めアングル（度）
@export var min_zoom: float = 4.0
@export var max_zoom: float = 25.0
@export var pan_scale: float = 0.002  # パン感度

@export_group("追従設定")
@export var follow_target: Node3D = null

# カメラ参照
var camera: Camera3D = null

# 内部状態
var target_zoom: float = 5.0
var camera_offset: Vector3 = Vector3.ZERO  # パンオフセット


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


func _physics_process(_delta: float) -> void:
	if camera == null:
		return

	_update_camera()


## カメラ位置を更新
func _update_camera() -> void:
	# ターゲット位置を取得
	var target_pos := Vector3.ZERO
	if follow_target:
		target_pos = follow_target.global_position

	# 斜めからのトップダウンビュー
	var elevation_rad := deg_to_rad(-camera_angle)
	var cam_y := camera_distance * sin(elevation_rad)
	var cam_z := camera_distance * cos(elevation_rad)

	var camera_pos := target_pos + camera_offset + Vector3(0, cam_y, cam_z)
	camera.global_position = camera_pos

	# ターゲットを見る
	camera.look_at(target_pos + camera_offset + Vector3(0, 1, 0), Vector3.UP)


## ズーム処理
func _on_camera_zoom(zoom_delta: float) -> void:
	target_zoom = clamp(target_zoom + zoom_delta, min_zoom, max_zoom)
	camera_distance = target_zoom


## パン処理
func _on_camera_pan(delta: Vector2) -> void:
	var pan_factor := camera_distance * pan_scale
	camera_offset.x -= delta.x * pan_factor
	camera_offset.z -= delta.y * pan_factor


## カメラを即座に配置（初期化用）
func snap_to_target() -> void:
	if camera == null or follow_target == null:
		return

	var target_pos := follow_target.global_position
	var elevation_rad := deg_to_rad(-camera_angle)
	var cam_y := camera_distance * sin(elevation_rad)
	var cam_z := camera_distance * cos(elevation_rad)

	camera.global_position = target_pos + camera_offset + Vector3(0, cam_y, cam_z)
	camera.look_at(target_pos + camera_offset + Vector3(0, 1, 0), Vector3.UP)


## パンオフセットをリセット
func reset_pan() -> void:
	camera_offset = Vector3.ZERO


## ズームをリセット
func reset_zoom(new_zoom: float = -1) -> void:
	if new_zoom > 0:
		target_zoom = clamp(new_zoom, min_zoom, max_zoom)
	else:
		target_zoom = camera_distance
	camera_distance = target_zoom


## 追従ターゲットを設定
func set_follow_target(target: Node3D) -> void:
	follow_target = target


## Camera3Dを取得
func get_camera() -> Camera3D:
	return camera
