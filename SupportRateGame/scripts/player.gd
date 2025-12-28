extends CharacterBody3D

## TPSスタイルのプレイヤー操作コントローラー
## モバイル対応（タッチ操作 + スワイプカメラ）

@export_group("移動設定")
@export var move_speed: float = 5.0
@export var rotation_speed: float = 10.0

@export_group("カメラ設定")
@export var camera_distance: float = 5.0
@export var camera_height: float = 3.0
@export var camera_smooth_speed: float = 5.0
@export var camera_sensitivity: float = 0.002
@export var min_vertical_angle: float = -20.0
@export var max_vertical_angle: float = 60.0

var gravity: float = -9.81
var vertical_velocity: float = 0.0

# カメラ回転用
var camera_yaw: float = 0.0
var camera_pitch: float = 20.0

# モバイル入力用
var joystick_input: Vector2 = Vector2.ZERO
var is_camera_dragging: bool = false
var last_touch_position: Vector2 = Vector2.ZERO
var camera_touch_id: int = -1

# アニメーション
var anim_player: AnimationPlayer = null
var is_walking: bool = false
const ANIM_BLEND_TIME: float = 0.3  # アニメーションブレンド時間

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	# カメラが無ければメインカメラを取得
	if camera == null:
		camera = get_viewport().get_camera_3d()

	# アニメーションプレイヤーを取得
	var model = get_node_or_null("CharacterModel")
	if model:
		anim_player = model.get_node_or_null("AnimationPlayer")
		if anim_player:
			# アニメーションを読み込んで追加
			_load_walking_animation()
			print("AnimationPlayer found, animations: ", anim_player.get_animation_list())
			# 初期状態でIdleを再生
			if anim_player.has_animation("idle"):
				anim_player.play("idle")


func _physics_process(delta: float) -> void:
	if GameManager.is_game_over:
		return

	_handle_input()
	_handle_camera_input()
	_handle_movement(delta)
	_handle_camera_follow(delta)
	_update_animation()


func _handle_input() -> void:
	# キーボード入力
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_forward", "move_backward")

	# モバイルジョイスティック入力がある場合はそちらを優先
	if joystick_input.length() > 0.1:
		input_dir = joystick_input

	# カメラの向きを基準にした移動方向を計算
	var forward := -camera.global_transform.basis.z
	var right := camera.global_transform.basis.x
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()

	var move_direction := (forward * -input_dir.y + right * input_dir.x).normalized()
	velocity.x = move_direction.x * move_speed
	velocity.z = move_direction.z * move_speed


func _handle_camera_input() -> void:
	# マウス入力（エディタ/PC用）
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mouse_motion := Input.get_last_mouse_velocity() * camera_sensitivity * 0.1
		camera_yaw -= mouse_motion.x
		camera_pitch -= mouse_motion.y
		camera_pitch = clampf(camera_pitch, min_vertical_angle, max_vertical_angle)


func _input(event: InputEvent) -> void:
	# マウスモーション
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		camera_yaw -= event.relative.x * camera_sensitivity
		camera_pitch -= event.relative.y * camera_sensitivity
		camera_pitch = clampf(camera_pitch, min_vertical_angle, max_vertical_angle)

	# タッチ入力（モバイル用）- 画面右半分でのスワイプ
	if event is InputEventScreenTouch:
		var screen_width := get_viewport().get_visible_rect().size.x
		if event.position.x > screen_width * 0.5:
			if event.pressed:
				if not is_camera_dragging:
					is_camera_dragging = true
					camera_touch_id = event.index
					last_touch_position = event.position
			else:
				if event.index == camera_touch_id:
					is_camera_dragging = false
					camera_touch_id = -1

	if event is InputEventScreenDrag:
		if is_camera_dragging and event.index == camera_touch_id:
			var touch_delta: Vector2 = event.position - last_touch_position
			camera_yaw -= touch_delta.x * camera_sensitivity
			camera_pitch -= touch_delta.y * camera_sensitivity
			camera_pitch = clampf(camera_pitch, min_vertical_angle, max_vertical_angle)
			last_touch_position = event.position


func _handle_movement(delta: float) -> void:
	# 重力処理
	if is_on_floor():
		vertical_velocity = -2.0
	else:
		vertical_velocity += gravity * delta

	velocity.y = vertical_velocity
	move_and_slide()

	# キャラクターの向きを移動方向に合わせる
	var horizontal_velocity := Vector3(velocity.x, 0, velocity.z)
	if horizontal_velocity.length() > 0.1:
		var target_rotation := atan2(horizontal_velocity.x, horizontal_velocity.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)


func _handle_camera_follow(delta: float) -> void:
	if camera == null:
		return

	# カメラの回転をクォータニオンに変換
	var camera_rotation := Quaternion.from_euler(Vector3(deg_to_rad(camera_pitch), deg_to_rad(camera_yaw), 0))

	# カメラのオフセット位置を計算
	var offset := camera_rotation * Vector3(0, 0, camera_distance)
	offset.y += camera_height

	# TPSカメラの位置を計算
	var target_position := global_position + offset
	camera.global_position = camera.global_position.lerp(target_position, camera_smooth_speed * delta)
	camera.look_at(global_position + Vector3.UP * 1.5)


## モバイルジョイスティックからの入力を受け取る
func set_joystick_input(input: Vector2) -> void:
	joystick_input = input


## コイン取得時の効果
func on_coin_collected() -> void:
	# エフェクトを追加可能
	pass


## アニメーションを読み込む
func _load_walking_animation() -> void:
	var lib = anim_player.get_animation_library("")
	if lib == null:
		return

	# Walkingアニメーション
	var walking_scene = load("res://assets/characters/animations/walking.fbx")
	if walking_scene:
		var walking_instance = walking_scene.instantiate()
		var walking_anim_player = walking_instance.get_node_or_null("AnimationPlayer")
		if walking_anim_player:
			for anim_name in walking_anim_player.get_animation_list():
				var anim = walking_anim_player.get_animation(anim_name)
				if anim:
					var anim_copy = anim.duplicate()
					anim_copy.loop_mode = Animation.LOOP_LINEAR  # ループ設定
					lib.add_animation("walking", anim_copy)
					print("Walking animation added!")
					break
		walking_instance.queue_free()

	# Idleアニメーション
	var idle_scene = load("res://assets/characters/animations/idle.fbx")
	if idle_scene:
		var idle_instance = idle_scene.instantiate()
		var idle_anim_player = idle_instance.get_node_or_null("AnimationPlayer")
		if idle_anim_player:
			for anim_name in idle_anim_player.get_animation_list():
				var anim = idle_anim_player.get_animation(anim_name)
				if anim:
					var anim_copy = anim.duplicate()
					anim_copy.loop_mode = Animation.LOOP_LINEAR  # ループ設定
					lib.add_animation("idle", anim_copy)
					print("Idle animation added!")
					break
		idle_instance.queue_free()


## アニメーションを更新
func _update_animation() -> void:
	if anim_player == null:
		return

	var horizontal_velocity := Vector3(velocity.x, 0, velocity.z)
	var should_walk := horizontal_velocity.length() > 0.1

	if should_walk and not is_walking:
		is_walking = true
		if anim_player.has_animation("walking"):
			anim_player.play("walking", ANIM_BLEND_TIME)
	elif not should_walk and is_walking:
		is_walking = false
		if anim_player.has_animation("idle"):
			anim_player.play("idle", ANIM_BLEND_TIME)
