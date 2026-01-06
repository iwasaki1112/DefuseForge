extends Node3D
## Bot animation viewer - simple animation testing for bot.glb

@onready var camera: Camera3D = $OrbitCamera
@onready var button_container: VBoxContainer = $CanvasLayer/Panel/ScrollContainer/VBoxContainer
@onready var character_body: CharacterBody3D = $CharacterBody

var anim_player: AnimationPlayer = null
var skeleton: Skeleton3D = null
var _animations: Array[String] = []
const GRAVITY: float = 9.8
const DEFAULT_BLEND_TIME: float = 0.3
var blend_time: float = DEFAULT_BLEND_TIME
var blend_time_label: Label = null

# Upper body rotation
var spine_bone_idx: int = -1
var upper_body_rotation: float = 0.0  # -45 to 45 degrees
var upper_body_rotation_label: Label = null
const UPPER_BODY_ROTATION_MIN: float = -45.0
const UPPER_BODY_ROTATION_MAX: float = 45.0

# Walk sequence test
enum WalkState { NONE, START, LOOP, END }
var walk_state: WalkState = WalkState.NONE
var walk_base_name: String = "walk"  # "walk" or "sprint"
var walk_status_label: Label = null

# Weapon attachment
var right_hand_bone_idx: int = -1
var weapon_attachment: BoneAttachment3D = null
var muzzle_flash: Node3D = null
const AK47_SCENE_PATH: String = "res://scenes/weapons/ak47_new.tscn"

# Shooting / Recoil
var is_shooting: bool = false
var recoil_amount: float = 0.0  # Current recoil (0.0 - 1.0)
const RECOIL_MAX_ANGLE: float = 8.0  # Max recoil rotation in degrees
const RECOIL_RECOVERY_SPEED: float = 15.0  # How fast recoil recovers
var recoil_tween: Tween = null

# Left hand IK
var left_hand_ik: SkeletonIK3D = null
var left_hand_grip_target: Marker3D = null
var left_hand_ik_offset: Vector3 = Vector3(-0.02, -0.06, -0.07)  # 手首→手のひらのオフセット（ローカル座標）
var left_hand_ik_rotation: Vector3 = Vector3(-67, -165, 4)  # 手の角度オフセット（度数）


func _ready() -> void:
	_setup_character()

	if camera.has_method("set_target") and character_body:
		camera.set_target(character_body)

	_create_animation_buttons()

	# Play idle animation first
	if anim_player and anim_player.has_animation("rifle_idle"):
		_play_animation("rifle_idle")
	elif _animations.size() > 0:
		_play_animation(_animations[0])


func _physics_process(delta: float) -> void:
	if character_body:
		if not character_body.is_on_floor():
			character_body.velocity.y -= GRAVITY * delta
		else:
			character_body.velocity.y = 0
		character_body.move_and_slide()

	# IKターゲットを物理フレームで更新（遅延を減らす）
	_update_left_hand_ik_target()


func _process(_delta: float) -> void:
	_apply_upper_body_rotation()


func _apply_upper_body_rotation() -> void:
	if not skeleton or spine_bone_idx < 0:
		return

	# Clear any previous override first
	skeleton.clear_bones_global_pose_override()

	# Check if any modification is needed
	if abs(upper_body_rotation) < 0.01 and abs(recoil_amount) < 0.01:
		return

	# Get the current global bone transform (from animation)
	var bone_global_transform := skeleton.get_bone_global_pose(spine_bone_idx)

	# Start with identity rotation
	var combined_rotation := Quaternion.IDENTITY

	# Apply horizontal twist (Y axis) for aiming
	if abs(upper_body_rotation) >= 0.01:
		var twist_rotation := Quaternion(Vector3.UP, deg_to_rad(upper_body_rotation))
		combined_rotation = combined_rotation * twist_rotation

	# Apply recoil (X axis - backward pitch)
	if abs(recoil_amount) >= 0.01:
		var recoil_angle := recoil_amount * RECOIL_MAX_ANGLE
		var recoil_rotation := Quaternion(Vector3.RIGHT, deg_to_rad(-recoil_angle))
		combined_rotation = combined_rotation * recoil_rotation

	# Apply combined rotation to the bone's global transform
	var combined_basis := Basis(combined_rotation)
	var new_transform := Transform3D(bone_global_transform.basis * combined_basis, bone_global_transform.origin)

	# Use global pose override (amount 1.0 = full override)
	skeleton.set_bone_global_pose_override(spine_bone_idx, new_transform, 1.0, true)


func _setup_character() -> void:
	var bot_model = $CharacterBody/BotModel
	if not bot_model:
		push_warning("[BotViewer] BotModel not found")
		return

	# Debug: Print model structure
	print("[BotViewer] Model structure:")
	_print_node_tree(bot_model, 0)

	# Debug: Print model bounds
	var aabb := _get_model_aabb(bot_model)
	print("[BotViewer] Model AABB: ", aabb)
	print("[BotViewer] Model size: ", aabb.size)
	print("[BotViewer] Model position: ", bot_model.global_position)
	print("[BotViewer] CharacterBody position: ", character_body.global_position)

	# Find AnimationPlayer
	anim_player = _find_animation_player(bot_model)
	if anim_player:
		_collect_animations()
		print("[BotViewer] Found AnimationPlayer with %d animations" % _animations.size())
		# Connect animation_finished for walk sequence
		if not anim_player.animation_finished.is_connected(_on_anim_finished):
			anim_player.animation_finished.connect(_on_anim_finished)
	else:
		push_warning("[BotViewer] AnimationPlayer not found")

	# Find Skeleton3D and spine bone
	skeleton = _find_skeleton(bot_model)
	if skeleton:
		print("[BotViewer] Found Skeleton3D with %d bones" % skeleton.get_bone_count())
		_print_bone_hierarchy(skeleton)
		_find_spine_bone()
		_attach_weapon()
	else:
		push_warning("[BotViewer] Skeleton3D not found")


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result:
			return result
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result := _find_skeleton(child)
		if result:
			return result
	return null


func _print_bone_hierarchy(skel: Skeleton3D) -> void:
	print("[BotViewer] Bone hierarchy:")
	for i in range(skel.get_bone_count()):
		var bone_name := skel.get_bone_name(i)
		var parent_idx := skel.get_bone_parent(i)
		var parent_name := skel.get_bone_name(parent_idx) if parent_idx >= 0 else "ROOT"
		print("  [%d] %s (parent: %s)" % [i, bone_name, parent_name])


func _find_spine_bone() -> void:
	if not skeleton:
		return

	# Look for spine bone - common names for Mixamo and other rigs
	# mixamorig_Spine1 is ideal for upper body rotation (chest level)
	var spine_names := ["mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Spine",
						"Spine1", "Spine2", "Spine", "spine1", "spine2", "spine",
						"mixamorig:Spine1", "mixamorig:Spine2", "mixamorig:Spine"]

	for bone_name in spine_names:
		var idx := skeleton.find_bone(bone_name)
		if idx >= 0:
			spine_bone_idx = idx
			print("[BotViewer] Found spine bone: %s (index: %d)" % [bone_name, idx])
			return

	push_warning("[BotViewer] Spine bone not found")


func _attach_weapon() -> void:
	if not skeleton:
		return

	# Find right hand bone
	var right_hand_names := ["mixamorig_RightHand", "RightHand", "right_hand",
							"mixamorig:RightHand"]

	for bone_name in right_hand_names:
		var idx := skeleton.find_bone(bone_name)
		if idx >= 0:
			right_hand_bone_idx = idx
			print("[BotViewer] Found right hand bone: %s (index: %d)" % [bone_name, idx])
			break

	if right_hand_bone_idx < 0:
		push_warning("[BotViewer] Right hand bone not found")
		return

	# Create BoneAttachment3D
	weapon_attachment = BoneAttachment3D.new()
	weapon_attachment.name = "WeaponAttachment"
	weapon_attachment.bone_idx = right_hand_bone_idx
	skeleton.add_child(weapon_attachment)

	# Load and instance AK47 scene
	var ak47_scene = load(AK47_SCENE_PATH)
	if not ak47_scene:
		push_warning("[BotViewer] Failed to load AK47 scene: %s" % AK47_SCENE_PATH)
		return

	var weapon = ak47_scene.instantiate()
	weapon.name = "AK47"
	weapon_attachment.add_child(weapon)

	# Get MuzzleFlash reference
	var muzzle_point = weapon.get_node_or_null("MuzzlePoint")
	if muzzle_point:
		muzzle_flash = muzzle_point.get_node_or_null("MuzzleFlash")
		if muzzle_flash:
			print("[BotViewer] Found MuzzleFlash")
		else:
			push_warning("[BotViewer] MuzzleFlash not found in MuzzlePoint")
	else:
		push_warning("[BotViewer] MuzzlePoint not found in weapon")

	print("[BotViewer] Weapon attached to right hand")

	# Setup left hand IK
	_setup_left_hand_ik(weapon)


func _setup_left_hand_ik(weapon: Node3D) -> void:
	if not skeleton:
		push_warning("[BotViewer] Cannot setup left hand IK: no skeleton")
		return

	# Find left hand bone
	var left_hand_names := ["mixamorig_LeftHand", "LeftHand", "left_hand", "mixamorig:LeftHand"]
	var left_hand_bone_idx: int = -1

	for bone_name in left_hand_names:
		var idx := skeleton.find_bone(bone_name)
		if idx >= 0:
			left_hand_bone_idx = idx
			print("[BotViewer] Found left hand bone: %s (index: %d)" % [bone_name, idx])
			break

	if left_hand_bone_idx < 0:
		push_warning("[BotViewer] Left hand bone not found")
		return

	# Find LeftHandGrip in weapon model
	# The weapon scene has Model child which contains the GLB content
	var model_node = weapon.get_node_or_null("Model")
	if not model_node:
		push_warning("[BotViewer] Model node not found in weapon")
		return

	# Search for LeftHandGrip node in the model hierarchy
	var left_hand_grip = _find_node_by_name(model_node, "LeftHandGrip")
	if not left_hand_grip:
		# Try searching in weapon root as well
		left_hand_grip = _find_node_by_name(weapon, "LeftHandGrip")

	if not left_hand_grip:
		push_warning("[BotViewer] LeftHandGrip not found in weapon model")
		print("[BotViewer] Weapon model structure:")
		_print_node_tree(weapon, 0)
		return

	print("[BotViewer] Found LeftHandGrip: %s" % left_hand_grip.get_path())

	# Create a Marker3D as the actual IK target (child of skeleton for proper transform)
	left_hand_grip_target = Marker3D.new()
	left_hand_grip_target.name = "LeftHandIKTarget"
	skeleton.add_child(left_hand_grip_target)

	# Create SkeletonIK3D
	left_hand_ik = SkeletonIK3D.new()
	left_hand_ik.name = "LeftHandIK"

	# Find the tip bone name for IK
	var tip_bone_name := skeleton.get_bone_name(left_hand_bone_idx)
	left_hand_ik.set_tip_bone(tip_bone_name)

	# Find root bone for IK chain (left upper arm or shoulder)
	var root_bone_names := ["mixamorig_LeftArm", "LeftArm", "left_arm", "mixamorig:LeftArm",
						   "mixamorig_LeftShoulder", "LeftShoulder"]
	var root_bone_name := ""
	for bone_name in root_bone_names:
		if skeleton.find_bone(bone_name) >= 0:
			root_bone_name = bone_name
			break

	if root_bone_name.is_empty():
		push_warning("[BotViewer] Left arm root bone not found")
		return

	left_hand_ik.set_root_bone(root_bone_name)
	left_hand_ik.set_target_node(left_hand_grip_target.get_path())

	# Configure IK settings
	left_hand_ik.interpolation = 1.0  # Full IK influence
	left_hand_ik.override_tip_basis = true  # Override hand rotation to match target

	skeleton.add_child(left_hand_ik)

	print("[BotViewer] Left hand IK setup: root=%s, tip=%s" % [root_bone_name, tip_bone_name])

	# Start IK (will be updated in _process)
	left_hand_ik.start()

	# Store reference to original grip for position updates
	_left_hand_grip_source = left_hand_grip


var _left_hand_grip_source: Node3D = null


func _update_left_hand_ik_target() -> void:
	if not left_hand_grip_target or not _left_hand_grip_source:
		return

	# Update IK target to match LeftHandGrip global position with offset
	# オフセットを適用して手のひらがターゲットに来るように調整
	var grip_transform := _left_hand_grip_source.global_transform

	# 位置オフセットを適用
	var offset_global := grip_transform.basis * left_hand_ik_offset
	grip_transform.origin += offset_global

	# 角度オフセットを適用（度数→ラジアン）
	var rotation_offset := Basis.from_euler(Vector3(
		deg_to_rad(left_hand_ik_rotation.x),
		deg_to_rad(left_hand_ik_rotation.y),
		deg_to_rad(left_hand_ik_rotation.z)
	))
	grip_transform.basis = grip_transform.basis * rotation_offset

	left_hand_grip_target.global_transform = grip_transform


func _find_node_by_name(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child in root.get_children():
		var result = _find_node_by_name(child, target_name)
		if result:
			return result
	return null


func _collect_animations() -> void:
	if not anim_player:
		return

	_animations.clear()
	print("[BotViewer] Animation details:")
	for anim_name in anim_player.get_animation_list():
		if anim_name == "RESET":
			continue
		_animations.append(anim_name)
		var anim = anim_player.get_animation(anim_name)
		if anim:
			print("  - %s (loop_mode=%d, length=%.2fs)" % [anim_name, anim.loop_mode, anim.length])

	_animations.sort()
	print("[BotViewer] Animations: ", _animations)


func _create_animation_buttons() -> void:
	if not button_container:
		push_warning("[BotViewer] Button container not found")
		return

	# Clear existing buttons
	for child in button_container.get_children():
		child.queue_free()

	# Title
	var label := Label.new()
	label.text = "Bot Animations"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	button_container.add_child(label)

	var separator := HSeparator.new()
	button_container.add_child(separator)

	# Animation buttons
	for anim_name in _animations:
		var button := Button.new()
		button.text = anim_name
		button.pressed.connect(_on_animation_button_pressed.bind(anim_name))
		button_container.add_child(button)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	button_container.add_child(spacer)

	# Playback controls
	var controls_label := Label.new()
	controls_label.text = "Playback"
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_label.add_theme_font_size_override("font_size", 18)
	button_container.add_child(controls_label)

	var controls_sep := HSeparator.new()
	button_container.add_child(controls_sep)

	var stop_button := Button.new()
	stop_button.text = "Stop"
	stop_button.pressed.connect(_on_stop_pressed)
	button_container.add_child(stop_button)

	var pause_button := Button.new()
	pause_button.text = "Pause/Resume"
	pause_button.pressed.connect(_on_pause_pressed)
	button_container.add_child(pause_button)

	# Blend time controls
	var blend_spacer := Control.new()
	blend_spacer.custom_minimum_size.y = 10
	button_container.add_child(blend_spacer)

	var blend_label := Label.new()
	blend_label.text = "Blend Time"
	blend_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blend_label.add_theme_font_size_override("font_size", 18)
	button_container.add_child(blend_label)

	var blend_sep := HSeparator.new()
	button_container.add_child(blend_sep)

	blend_time_label = Label.new()
	blend_time_label.text = "%.2f sec" % blend_time
	blend_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button_container.add_child(blend_time_label)

	var blend_slider := HSlider.new()
	blend_slider.min_value = 0.0
	blend_slider.max_value = 1.0
	blend_slider.step = 0.05
	blend_slider.value = blend_time
	blend_slider.custom_minimum_size.x = 180
	blend_slider.value_changed.connect(_on_blend_time_changed)
	button_container.add_child(blend_slider)

	# Upper body rotation controls
	var rotation_spacer := Control.new()
	rotation_spacer.custom_minimum_size.y = 10
	button_container.add_child(rotation_spacer)

	var rotation_label := Label.new()
	rotation_label.text = "Upper Body Twist"
	rotation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rotation_label.add_theme_font_size_override("font_size", 18)
	button_container.add_child(rotation_label)

	var rotation_sep := HSeparator.new()
	button_container.add_child(rotation_sep)

	upper_body_rotation_label = Label.new()
	upper_body_rotation_label.text = "%.0f°" % upper_body_rotation
	upper_body_rotation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button_container.add_child(upper_body_rotation_label)

	var rotation_slider := HSlider.new()
	rotation_slider.min_value = UPPER_BODY_ROTATION_MIN
	rotation_slider.max_value = UPPER_BODY_ROTATION_MAX
	rotation_slider.step = 1.0
	rotation_slider.value = upper_body_rotation
	rotation_slider.custom_minimum_size.x = 180
	rotation_slider.value_changed.connect(_on_upper_body_rotation_changed)
	button_container.add_child(rotation_slider)

	var reset_rotation_btn := Button.new()
	reset_rotation_btn.text = "Reset (0°)"
	reset_rotation_btn.pressed.connect(_on_reset_rotation_pressed)
	button_container.add_child(reset_rotation_btn)

	# Walk sequence controls
	var walk_spacer := Control.new()
	walk_spacer.custom_minimum_size.y = 10
	button_container.add_child(walk_spacer)

	var walk_label := Label.new()
	walk_label.text = "Walk Sequence"
	walk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	walk_label.add_theme_font_size_override("font_size", 18)
	button_container.add_child(walk_label)

	var walk_sep := HSeparator.new()
	button_container.add_child(walk_sep)

	walk_status_label = Label.new()
	walk_status_label.text = "State: NONE"
	walk_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button_container.add_child(walk_status_label)

	var start_walk_btn := Button.new()
	start_walk_btn.text = "Start Walk"
	start_walk_btn.pressed.connect(_on_start_walk_pressed.bind("walk"))
	button_container.add_child(start_walk_btn)

	var start_sprint_btn := Button.new()
	start_sprint_btn.text = "Start Sprint"
	start_sprint_btn.pressed.connect(_on_start_walk_pressed.bind("sprint"))
	button_container.add_child(start_sprint_btn)

	var stop_walk_btn := Button.new()
	stop_walk_btn.text = "Stop Walk"
	stop_walk_btn.pressed.connect(_on_stop_walk_pressed)
	button_container.add_child(stop_walk_btn)

	# Shooting controls
	var shoot_spacer := Control.new()
	shoot_spacer.custom_minimum_size.y = 10
	button_container.add_child(shoot_spacer)

	var shoot_label := Label.new()
	shoot_label.text = "Shooting"
	shoot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shoot_label.add_theme_font_size_override("font_size", 18)
	button_container.add_child(shoot_label)

	var shoot_sep := HSeparator.new()
	button_container.add_child(shoot_sep)

	var shoot_btn := Button.new()
	shoot_btn.text = "Shoot (Single)"
	shoot_btn.pressed.connect(_on_shoot_pressed)
	button_container.add_child(shoot_btn)

	var auto_fire_btn := Button.new()
	auto_fire_btn.text = "Auto-Fire (Toggle)"
	auto_fire_btn.pressed.connect(_on_auto_fire_pressed)
	button_container.add_child(auto_fire_btn)

	# Left Hand IK controls
	var ik_spacer := Control.new()
	ik_spacer.custom_minimum_size.y = 10
	button_container.add_child(ik_spacer)

	var ik_label := Label.new()
	ik_label.text = "Left Hand IK"
	ik_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ik_label.add_theme_font_size_override("font_size", 18)
	button_container.add_child(ik_label)

	var ik_sep := HSeparator.new()
	button_container.add_child(ik_sep)

	# Position offset sliders
	_create_ik_slider(button_container, "Pos X", left_hand_ik_offset.x, -0.2, 0.2, _on_ik_pos_x_changed)
	_create_ik_slider(button_container, "Pos Y", left_hand_ik_offset.y, -0.2, 0.2, _on_ik_pos_y_changed)
	_create_ik_slider(button_container, "Pos Z", left_hand_ik_offset.z, -0.2, 0.2, _on_ik_pos_z_changed)

	# Rotation offset sliders
	_create_ik_slider(button_container, "Rot X", left_hand_ik_rotation.x, -180, 180, _on_ik_rot_x_changed)
	_create_ik_slider(button_container, "Rot Y", left_hand_ik_rotation.y, -180, 180, _on_ik_rot_y_changed)
	_create_ik_slider(button_container, "Rot Z", left_hand_ik_rotation.z, -180, 180, _on_ik_rot_z_changed)

	# Print current values button
	var print_ik_btn := Button.new()
	print_ik_btn.text = "Print IK Values"
	print_ik_btn.pressed.connect(_on_print_ik_values)
	button_container.add_child(print_ik_btn)


func _create_ik_slider(container: VBoxContainer, label_text: String, initial_value: float, min_val: float, max_val: float, callback: Callable) -> void:
	var hbox := HBoxContainer.new()

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 50
	hbox.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = 0.01 if max_val <= 1.0 else 1.0
	slider.value = initial_value
	slider.custom_minimum_size.x = 100
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(callback)
	hbox.add_child(slider)

	var value_label := Label.new()
	value_label.text = "%.2f" % initial_value if max_val <= 1.0 else "%.0f" % initial_value
	value_label.custom_minimum_size.x = 40
	value_label.name = label_text.replace(" ", "") + "Value"
	hbox.add_child(value_label)

	container.add_child(hbox)


func _on_ik_pos_x_changed(value: float) -> void:
	left_hand_ik_offset.x = value
	_update_ik_value_label("PosX", value, true)

func _on_ik_pos_y_changed(value: float) -> void:
	left_hand_ik_offset.y = value
	_update_ik_value_label("PosY", value, true)

func _on_ik_pos_z_changed(value: float) -> void:
	left_hand_ik_offset.z = value
	_update_ik_value_label("PosZ", value, true)

func _on_ik_rot_x_changed(value: float) -> void:
	left_hand_ik_rotation.x = value
	_update_ik_value_label("RotX", value, false)

func _on_ik_rot_y_changed(value: float) -> void:
	left_hand_ik_rotation.y = value
	_update_ik_value_label("RotY", value, false)

func _on_ik_rot_z_changed(value: float) -> void:
	left_hand_ik_rotation.z = value
	_update_ik_value_label("RotZ", value, false)

func _update_ik_value_label(name: String, value: float, is_position: bool) -> void:
	var label = button_container.find_child(name + "Value", true, false)
	if label:
		label.text = "%.2f" % value if is_position else "%.0f" % value

func _on_print_ik_values() -> void:
	print("[BotViewer] Left Hand IK Values:")
	print("  Position Offset: Vector3(%.3f, %.3f, %.3f)" % [left_hand_ik_offset.x, left_hand_ik_offset.y, left_hand_ik_offset.z])
	print("  Rotation Offset: Vector3(%.1f, %.1f, %.1f)" % [left_hand_ik_rotation.x, left_hand_ik_rotation.y, left_hand_ik_rotation.z])


func _play_animation(anim_name: String) -> void:
	if not anim_player:
		return

	if anim_player.has_animation(anim_name):
		# ループアニメーションのloop_modeを強制設定
		var anim = anim_player.get_animation(anim_name)
		if anim and anim_name in ["rifle_idle", "rifle_walk", "rifle_sprint", "rifle_crouch"]:
			if anim.loop_mode != Animation.LOOP_LINEAR:
				anim.loop_mode = Animation.LOOP_LINEAR
				print("[BotViewer] Set loop_mode to LINEAR for: %s" % anim_name)

		anim_player.play(anim_name, blend_time)
		print("[BotViewer] Playing: %s (blend: %.2fs)" % [anim_name, blend_time])
	else:
		push_warning("[BotViewer] Animation not found: ", anim_name)


func _on_animation_button_pressed(anim_name: String) -> void:
	_play_animation(anim_name)


func _on_stop_pressed() -> void:
	if anim_player:
		anim_player.stop()


func _on_pause_pressed() -> void:
	if anim_player:
		if anim_player.is_playing():
			anim_player.pause()
		else:
			anim_player.play()


func _on_blend_time_changed(value: float) -> void:
	blend_time = value
	if blend_time_label:
		blend_time_label.text = "%.2f sec" % blend_time


func _on_upper_body_rotation_changed(value: float) -> void:
	upper_body_rotation = value
	if upper_body_rotation_label:
		upper_body_rotation_label.text = "%.0f°" % upper_body_rotation


func _on_reset_rotation_pressed() -> void:
	upper_body_rotation = 0.0
	if upper_body_rotation_label:
		upper_body_rotation_label.text = "0°"
	# Find and reset the slider
	for child in button_container.get_children():
		if child is HSlider and child.min_value == UPPER_BODY_ROTATION_MIN:
			child.value = 0.0
			break


## ========================================
## Walk Sequence Handlers
## ========================================

func _on_start_walk_pressed(base_name: String) -> void:
	if not anim_player:
		return

	walk_base_name = base_name
	var start_anim = "rifle_" + base_name + "_start"
	var loop_anim = "rifle_" + base_name

	if anim_player.has_animation(start_anim):
		walk_state = WalkState.START
		anim_player.play(start_anim, blend_time)
		print("[BotViewer] Walk sequence: START -> %s" % start_anim)
	elif anim_player.has_animation(loop_anim):
		walk_state = WalkState.LOOP
		anim_player.play(loop_anim, blend_time)
		print("[BotViewer] Walk sequence: LOOP -> %s" % loop_anim)
	else:
		push_warning("[BotViewer] No walk animation found for: %s" % base_name)
		walk_state = WalkState.NONE

	_update_walk_status()


func _on_stop_walk_pressed() -> void:
	if not anim_player or walk_state == WalkState.NONE:
		return

	var end_anim = "rifle_" + walk_base_name + "_end"

	if anim_player.has_animation(end_anim):
		walk_state = WalkState.END
		anim_player.play(end_anim, blend_time)
		print("[BotViewer] Walk sequence: END -> %s" % end_anim)
	else:
		# No end animation, go directly to idle
		walk_state = WalkState.NONE
		if anim_player.has_animation("rifle_idle"):
			anim_player.play("rifle_idle", blend_time)
		print("[BotViewer] Walk sequence: STOPPED (no end anim)")

	_update_walk_status()


func _on_anim_finished(anim_name: String) -> void:
	print("[BotViewer] animation_finished: %s (walk_state=%s)" % [anim_name, WalkState.keys()[walk_state]])

	# アニメーションのloop_modeを確認
	var anim = anim_player.get_animation(anim_name)
	if anim:
		print("[BotViewer]   -> loop_mode=%d, length=%.2fs" % [anim.loop_mode, anim.length])

	if walk_state == WalkState.NONE:
		return

	var expected_start = "rifle_" + walk_base_name + "_start"
	var expected_end = "rifle_" + walk_base_name + "_end"
	var loop_anim = "rifle_" + walk_base_name

	match walk_state:
		WalkState.START:
			if anim_name == expected_start:
				walk_state = WalkState.LOOP
				if anim_player.has_animation(loop_anim):
					anim_player.play(loop_anim, 0.1)
					print("[BotViewer] Walk sequence: START -> LOOP (%s)" % loop_anim)
				_update_walk_status()

		WalkState.END:
			if anim_name == expected_end:
				walk_state = WalkState.NONE
				if anim_player.has_animation("rifle_idle"):
					anim_player.play("rifle_idle", blend_time)
				print("[BotViewer] Walk sequence: END -> IDLE")
				_update_walk_status()

		WalkState.LOOP:
			# ループアニメーションが終了した場合（loop_modeが効いていない場合）
			# 再度再生する
			if anim_name == loop_anim:
				print("[BotViewer] WARNING: Loop animation finished unexpectedly, restarting...")
				anim_player.play(loop_anim, 0.0)



func _update_walk_status() -> void:
	if walk_status_label:
		var state_name = WalkState.keys()[walk_state]
		walk_status_label.text = "State: %s" % state_name


## ========================================
## Shooting Handlers
## ========================================

func _on_shoot_pressed() -> void:
	_shoot()


func _shoot() -> void:
	# Trigger muzzle flash
	if muzzle_flash and muzzle_flash.has_method("flash"):
		muzzle_flash.flash()

	# Apply recoil
	_apply_recoil()

	print("[BotViewer] Shot fired!")


func _apply_recoil() -> void:
	# Cancel any existing recoil tween
	if recoil_tween and recoil_tween.is_valid():
		recoil_tween.kill()

	# Create new recoil tween
	recoil_tween = create_tween()

	# Quick recoil up (0 -> 1)
	recoil_tween.tween_property(self, "recoil_amount", 1.0, 0.05)

	# Slower recovery (1 -> 0)
	recoil_tween.tween_property(self, "recoil_amount", 0.0, 0.15).set_ease(Tween.EASE_OUT)


func _on_auto_fire_pressed() -> void:
	is_shooting = not is_shooting
	if is_shooting:
		_start_auto_fire()
	print("[BotViewer] Auto-fire: %s" % ("ON" if is_shooting else "OFF"))


func _start_auto_fire() -> void:
	if not is_shooting:
		return
	_shoot()
	# Schedule next shot (fire rate: ~600 RPM = 100ms interval)
	get_tree().create_timer(0.1).timeout.connect(_start_auto_fire)


func _print_node_tree(node: Node, depth: int) -> void:
	var indent := ""
	for i in range(depth):
		indent += "  "
	var extra := ""
	if node is MeshInstance3D:
		extra = " [Mesh]"
	elif node is Skeleton3D:
		extra = " [Skeleton: %d bones]" % node.get_bone_count()
	print(indent + "- " + node.name + " (" + node.get_class() + ")" + extra)
	if depth < 6:
		for child in node.get_children():
			_print_node_tree(child, depth + 1)


func _get_model_aabb(node: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_inst := child as MeshInstance3D
			var mesh_aabb: AABB = mesh_inst.get_aabb()
			if first:
				aabb = mesh_aabb
				first = false
			else:
				aabb = aabb.merge(mesh_aabb)
		if child is Node3D:
			var child_aabb: AABB = _get_model_aabb(child as Node3D)
			if child_aabb.size != Vector3.ZERO:
				if first:
					aabb = child_aabb
					first = false
				else:
					aabb = aabb.merge(child_aabb)
	return aabb
