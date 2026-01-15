extends Node3D

## ストレイフ（8方向移動）テストシーン
## WASD移動 + マウスで視線方向を制御
## Shiftで走る（走り中はストレイフ無効）

@onready var camera: Camera3D = $Camera3D
@onready var character: CharacterBase = $CharacterBody

var _strafe_enabled: bool = true

# UI
var _info_label: Label
var _blend_label: Label


func _ready() -> void:
	# UI作成
	_setup_ui()

	# キャラクター初期化を待つ
	await get_tree().process_frame

	# ストレイフモードを有効化（+Zが前方）
	if character:
		var facing = character.global_transform.basis.z
		character.enable_strafe(facing)

	print("[TestStrafe] Ready")
	print("[TestStrafe] WASD: Move, Mouse: Look direction, Shift: Run")


func _setup_ui() -> void:
	var canvas = CanvasLayer.new()
	canvas.name = "CanvasLayer"
	add_child(canvas)

	var panel = PanelContainer.new()
	panel.position = Vector2(10, 10)
	canvas.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "Strafe Test"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var controls = Label.new()
	controls.text = "WASD: Move\nMouse: Look\nShift: Run"
	vbox.add_child(controls)

	vbox.add_child(HSeparator.new())

	_info_label = Label.new()
	_info_label.text = "State: Idle"
	vbox.add_child(_info_label)

	_blend_label = Label.new()
	_blend_label.text = "Blend: (0.0, 0.0)"
	vbox.add_child(_blend_label)


func _physics_process(_delta: float) -> void:
	if not character or not character.movement:
		return

	# WASD移動入力
	var input_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		input_dir.z -= 1
	if Input.is_key_pressed(KEY_S):
		input_dir.z += 1
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1

	if input_dir.length_squared() > 0:
		input_dir = input_dir.normalized()

	# Shiftで走る
	var is_running = Input.is_key_pressed(KEY_SHIFT)

	# マウス位置で視線方向を更新
	_update_facing_direction()

	# 走り中はストレイフを一時無効
	if is_running and character.movement.strafe_mode:
		character.movement.strafe_mode = false
	elif not is_running and _strafe_enabled and not character.movement.strafe_mode:
		# このプロジェクトでは+Zが前方
		var facing = character.global_transform.basis.z
		character.movement.enable_strafe_mode(facing)

	# 移動
	character.movement.set_input_direction(input_dir, is_running)

	# UI更新
	_update_ui(input_dir, is_running)


func _update_facing_direction() -> void:
	# スクリーン中心からのマウスオフセットを計算
	var viewport_size = get_viewport().get_visible_rect().size
	var viewport_center = viewport_size / 2.0
	var mouse_pos = get_viewport().get_mouse_position()
	var screen_offset = mouse_pos - viewport_center

	# カメラの右方向と前方向（XZ平面上）を取得
	var cam_right = camera.global_transform.basis.x
	cam_right.y = 0
	cam_right = cam_right.normalized() if cam_right.length_squared() > 0.001 else Vector3.RIGHT

	var cam_forward = -camera.global_transform.basis.z
	cam_forward.y = 0
	cam_forward = cam_forward.normalized() if cam_forward.length_squared() > 0.001 else Vector3.FORWARD

	# スクリーンオフセットをワールド方向に変換
	# +Z前方座標系に合わせて調整:
	# - screen X はそのまま
	# - screen Y を反転（前後を正しくマッピング）
	var world_dir = cam_right * screen_offset.x + cam_forward * (-screen_offset.y)

	if world_dir.length_squared() > 0.001:
		world_dir = world_dir.normalized()

		# キャラクターをこの方向に向ける
		# look_atは-Zをターゲットに向けるが、このプロジェクトでは+Zが前方
		# そのため反対方向を指定
		var target = character.global_position - world_dir
		target.y = character.global_position.y
		character.look_at(target, Vector3.UP)

		# ストレイフモードの視線方向 = キャラクターの前方向（+Z local）
		var actual_facing = character.global_transform.basis.z
		actual_facing.y = 0
		actual_facing = actual_facing.normalized()
		character.movement._facing_direction = actual_facing

		# デバッグ出力（必要時のみ有効化）
		#if Engine.get_process_frames() % 120 == 0:
		#	print("[TestStrafe] facing: (%.2f, %.2f), rot: %.1f deg" % [
		#		actual_facing.x, actual_facing.z, rad_to_deg(character.rotation.y)])


func _update_ui(input_dir: Vector3, is_running: bool) -> void:
	# 状態表示
	var state = "Idle"
	if input_dir.length_squared() > 0:
		state = "Running" if is_running else "Walking"
		if character.movement.strafe_mode:
			state += " (Strafe)"
	_info_label.text = "State: %s" % state

	# ブレンド座標表示
	var blend = character.movement.get_strafe_blend()
	_blend_label.text = "Blend: (%.2f, %.2f)" % [blend.x, blend.y]
