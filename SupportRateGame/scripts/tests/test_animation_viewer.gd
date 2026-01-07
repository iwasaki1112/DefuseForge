extends Node3D
## Animation viewer - simple animation testing for character models

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

# Character selection
const CHARACTERS_DIR: String = "res://assets/characters/"
var available_characters: Array[String] = []  # 利用可能なキャラクターIDリスト
var current_character_id: String = "counter_terrorist"  # 現在選択中のキャラクターID
var character_model: Node3D = null  # 現在のキャラクターモデルノード
var character_option_button: OptionButton = null

# Upper body rotation
var spine_bone_idx: int = -1
var upper_body_rotation: float = 0.0  # -45 to 45 degrees
var upper_body_rotation_label: Label = null
const UPPER_BODY_ROTATION_MIN: float = -45.0
const UPPER_BODY_ROTATION_MAX: float = 45.0

# Weapon attachment
var right_hand_bone_idx: int = -1
var weapon_attachment: BoneAttachment3D = null
var muzzle_flash: Node3D = null

# Weapon resource - 武器の設定を .tres ファイルから読み込み
const WEAPONS_DIR: String = "res://resources/weapons/"
var available_weapons: Array[String] = []  # 利用可能な武器IDリスト
var current_weapon_id: String = "ak47"  # 現在選択中の武器ID
var weapon_resource: WeaponResource = null
var weapon_option_button: OptionButton = null

# Shooting / Recoil
var is_shooting: bool = false
var recoil_amount: float = 0.0  # Current recoil (0.0 - 1.0)
const RECOIL_MAX_ANGLE: float = 8.0  # Max recoil rotation in degrees
const RECOIL_RECOVERY_SPEED: float = 15.0  # How fast recoil recovers
var recoil_tween: Tween = null

# Left hand IK - 値は weapon_resource から読み込み
var left_hand_ik: SkeletonIK3D = null
var left_hand_grip_target: Marker3D = null
var left_hand_ik_offset: Vector3 = Vector3.ZERO
var left_hand_ik_rotation: Vector3 = Vector3.ZERO
var left_hand_ik_disabled_animations: PackedStringArray = []


func _ready() -> void:
	# Scan available characters first
	_scan_available_characters()

	_setup_character()

	if camera.has_method("set_target") and character_body:
		camera.set_target(character_body)

	_create_animation_buttons()

	# Play idle animation first
	if anim_player and anim_player.has_animation("Rifle_Idle"):
		_play_animation("Rifle_Idle")
	elif _animations.size() > 0:
		_play_animation(_animations[0])


func _scan_available_characters() -> void:
	available_characters.clear()
	var dir = DirAccess.open(CHARACTERS_DIR)
	if dir == null:
		push_warning("[AnimViewer] Cannot open characters directory: %s" % CHARACTERS_DIR)
		return

	dir.list_dir_begin()
	var folder_name = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			# Check if glb file exists
			var glb_path = CHARACTERS_DIR + folder_name + "/" + folder_name + ".glb"
			if ResourceLoader.exists(glb_path):
				available_characters.append(folder_name)
				print("[AnimViewer] Found character: %s" % folder_name)
		folder_name = dir.get_next()
	dir.list_dir_end()

	available_characters.sort()
	print("[AnimViewer] Available characters: ", available_characters)


func _change_character(character_id: String) -> void:
	if character_id == current_character_id:
		return

	print("[AnimViewer] Changing character to: %s" % character_id)

	# Remove current character and IK
	if left_hand_ik:
		left_hand_ik.stop()
		left_hand_ik.queue_free()
		left_hand_ik = null

	if left_hand_grip_target:
		left_hand_grip_target.queue_free()
		left_hand_grip_target = null

	_left_hand_grip_source = null
	muzzle_flash = null

	if weapon_attachment:
		weapon_attachment.queue_free()
		weapon_attachment = null

	# Remove current character model
	if character_model:
		character_model.queue_free()
		character_model = null

	# Reset state
	anim_player = null
	skeleton = null
	spine_bone_idx = -1
	right_hand_bone_idx = -1
	_animations.clear()

	# Update current character ID
	current_character_id = character_id

	# Load and instantiate new character
	var glb_path = CHARACTERS_DIR + character_id + "/" + character_id + ".glb"
	var character_scene = load(glb_path)
	if not character_scene:
		push_warning("[AnimViewer] Failed to load character: %s" % glb_path)
		return

	character_model = character_scene.instantiate()
	character_model.name = character_id.capitalize() + "Model"
	character_body.add_child(character_model)

	# Setup the new character
	_setup_character_internal()

	# Recreate animation buttons
	_create_animation_buttons()

	# Play idle animation
	if anim_player and anim_player.has_animation("Rifle_Idle"):
		_play_animation("Rifle_Idle")
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
	# Scan available weapons and load current weapon resource
	_scan_available_weapons()
	_load_weapon_resource()

	# Get existing character model from scene or load dynamically
	character_model = character_body.get_node_or_null("CharacterModel")
	if not character_model:
		# Try to find any model node
		for child in character_body.get_children():
			if child is Node3D and not child is CollisionShape3D:
				character_model = child
				break

	if not character_model:
		# Load default character
		var glb_path = CHARACTERS_DIR + current_character_id + "/" + current_character_id + ".glb"
		if ResourceLoader.exists(glb_path):
			var character_scene = load(glb_path)
			if character_scene:
				character_model = character_scene.instantiate()
				character_model.name = current_character_id.capitalize() + "Model"
				character_body.add_child(character_model)

	if not character_model:
		push_warning("[AnimViewer] Character model not found")
		return

	_setup_character_internal()


func _setup_character_internal() -> void:
	if not character_model:
		push_warning("[AnimViewer] Character model not found")
		return

	# Debug: Print model structure
	print("[AnimViewer] Model structure:")
	_print_node_tree(character_model, 0)

	# Debug: Print model bounds
	var aabb := _get_model_aabb(character_model)
	print("[AnimViewer] Model AABB: ", aabb)
	print("[AnimViewer] Model size: ", aabb.size)
	print("[AnimViewer] Model position: ", character_model.global_position)
	print("[AnimViewer] CharacterBody position: ", character_body.global_position)

	# Find AnimationPlayer
	anim_player = _find_animation_player(character_model)
	if anim_player:
		_collect_animations()
		print("[AnimViewer] Found AnimationPlayer with %d animations" % _animations.size())
	else:
		push_warning("[AnimViewer] AnimationPlayer not found")

	# Find Skeleton3D and spine bone
	skeleton = _find_skeleton(character_model)
	if skeleton:
		print("[AnimViewer] Found Skeleton3D with %d bones" % skeleton.get_bone_count())
		_print_bone_hierarchy(skeleton)
		_find_spine_bone()
		_attach_weapon()
	else:
		push_warning("[AnimViewer] Skeleton3D not found")


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


func _scan_available_weapons() -> void:
	available_weapons.clear()
	var dir = DirAccess.open(WEAPONS_DIR)
	if dir == null:
		push_warning("[BotViewer] Cannot open weapons directory: %s" % WEAPONS_DIR)
		return

	dir.list_dir_begin()
	var folder_name = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var tres_path = WEAPONS_DIR + folder_name + "/" + folder_name + ".tres"
			if ResourceLoader.exists(tres_path):
				available_weapons.append(folder_name)
				print("[BotViewer] Found weapon: %s" % folder_name)
		folder_name = dir.get_next()
	dir.list_dir_end()

	available_weapons.sort()
	print("[BotViewer] Available weapons: ", available_weapons)


func _load_weapon_resource() -> void:
	_load_weapon_resource_by_id(current_weapon_id)


func _change_weapon(weapon_id: String) -> void:
	if weapon_id == current_weapon_id:
		return

	print("[BotViewer] Changing weapon to: %s" % weapon_id)

	# Remove current weapon and IK
	if left_hand_ik:
		left_hand_ik.stop()
		left_hand_ik.queue_free()
		left_hand_ik = null

	if left_hand_grip_target:
		left_hand_grip_target.queue_free()
		left_hand_grip_target = null

	_left_hand_grip_source = null
	muzzle_flash = null

	if weapon_attachment:
		weapon_attachment.queue_free()
		weapon_attachment = null

	# Update current weapon ID and load new resource
	current_weapon_id = weapon_id
	_load_weapon_resource_by_id(weapon_id)

	# Attach new weapon
	_attach_weapon()

	# Update IK sliders to reflect new weapon's values
	_update_ik_sliders()


func _load_weapon_resource_by_id(weapon_id: String) -> void:
	var resource_path = WEAPONS_DIR + weapon_id + "/" + weapon_id + ".tres"

	if ResourceLoader.exists(resource_path):
		weapon_resource = load(resource_path) as WeaponResource
		if weapon_resource:
			# IK設定を武器リソースから読み込み
			left_hand_ik_offset = weapon_resource.left_hand_ik_position
			left_hand_ik_rotation = weapon_resource.left_hand_ik_rotation
			left_hand_ik_disabled_animations = weapon_resource.left_hand_ik_disabled_anims
			print("[BotViewer] Loaded weapon resource: %s" % weapon_resource.weapon_name)
			print("[BotViewer]   IK Position: %s" % left_hand_ik_offset)
			print("[BotViewer]   IK Rotation: %s" % left_hand_ik_rotation)
			print("[BotViewer]   IK Disabled Anims: ", Array(left_hand_ik_disabled_animations))
		else:
			push_warning("[BotViewer] Failed to load weapon resource: %s" % resource_path)
	else:
		push_warning("[BotViewer] Weapon resource not found: %s" % resource_path)


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

	# Load weapon scene from resource or fallback
	var weapon_scene_path := ""
	if weapon_resource:
		weapon_scene_path = weapon_resource.scene_path
	else:
		weapon_scene_path = "res://scenes/weapons/ak47.tscn"  # fallback

	var weapon_scene = load(weapon_scene_path)
	if not weapon_scene:
		push_warning("[BotViewer] Failed to load weapon scene: %s" % weapon_scene_path)
		return

	var weapon = weapon_scene.instantiate()
	weapon.name = weapon_resource.weapon_id.to_upper() if weapon_resource else "Weapon"
	weapon_attachment.add_child(weapon)

	# Compensate for skeleton's global scale to ensure weapon renders at correct size
	var skeleton_global_scale = skeleton.global_transform.basis.get_scale()
	if skeleton_global_scale.x < 0.5:  # If skeleton is scaled down significantly
		var compensation_scale = 1.0 / skeleton_global_scale.x
		weapon.scale = Vector3(compensation_scale, compensation_scale, compensation_scale)
		print("[BotViewer] Applied weapon scale compensation: %s" % compensation_scale)

	# Get MuzzleFlash reference (find_childで再帰的に探す)
	muzzle_flash = weapon.find_child("MuzzleFlash", true, false)
	if muzzle_flash:
		print("[BotViewer] Found MuzzleFlash")
	else:
		push_warning("[BotViewer] MuzzleFlash not found in weapon")

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

	# Search for LeftHandGrip_{WeaponID} node in the model hierarchy
	# 命名規則: LeftHandGrip_{weapon_id.to_upper()} (例: LeftHandGrip_AK47, LeftHandGrip_M4A1)
	var grip_name = "LeftHandGrip_%s" % current_weapon_id.to_upper()
	var left_hand_grip = _find_node_by_name(model_node, grip_name)
	if not left_hand_grip:
		# Try searching in weapon root as well
		left_hand_grip = _find_node_by_name(weapon, grip_name)
	if not left_hand_grip:
		# Fallback: 旧命名規則 "LeftHandGrip" も試す（後方互換性）
		left_hand_grip = _find_node_by_name(model_node, "LeftHandGrip")
		if not left_hand_grip:
			left_hand_grip = _find_node_by_name(weapon, "LeftHandGrip")

	if not left_hand_grip:
		push_warning("[BotViewer] LeftHandGrip not found in weapon model (tried: %s)" % grip_name)
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

	# IKが無効の場合はスキップ
	if left_hand_ik and not left_hand_ik.is_running():
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
		push_warning("[AnimViewer] Button container not found")
		return

	# Clear existing buttons
	for child in button_container.get_children():
		child.queue_free()

	# Title
	var label := Label.new()
	label.text = "Animation Viewer"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	button_container.add_child(label)

	var separator := HSeparator.new()
	button_container.add_child(separator)

	# Character selection
	var char_label := Label.new()
	char_label.text = "Character"
	char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_label.add_theme_font_size_override("font_size", 18)
	button_container.add_child(char_label)

	character_option_button = OptionButton.new()
	character_option_button.custom_minimum_size.x = 180
	for i in range(available_characters.size()):
		var char_id = available_characters[i]
		character_option_button.add_item(char_id.capitalize(), i)
		if char_id == current_character_id:
			character_option_button.select(i)
	character_option_button.item_selected.connect(_on_character_selected)
	button_container.add_child(character_option_button)

	var char_sep := HSeparator.new()
	button_container.add_child(char_sep)

	# Weapon selection
	var weapon_label := Label.new()
	weapon_label.text = "Weapon"
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weapon_label.add_theme_font_size_override("font_size", 18)
	button_container.add_child(weapon_label)

	weapon_option_button = OptionButton.new()
	weapon_option_button.custom_minimum_size.x = 180
	for i in range(available_weapons.size()):
		var weapon_id = available_weapons[i]
		weapon_option_button.add_item(weapon_id.to_upper(), i)
		if weapon_id == current_weapon_id:
			weapon_option_button.select(i)
	weapon_option_button.item_selected.connect(_on_weapon_selected)
	button_container.add_child(weapon_option_button)

	var weapon_sep := HSeparator.new()
	button_container.add_child(weapon_sep)

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


func _on_character_selected(index: int) -> void:
	if index < 0 or index >= available_characters.size():
		return
	var char_id = available_characters[index]
	_change_character(char_id)


func _on_weapon_selected(index: int) -> void:
	if index < 0 or index >= available_weapons.size():
		return
	var weapon_id = available_weapons[index]
	_change_weapon(weapon_id)


func _update_ik_sliders() -> void:
	# Update IK slider values to match current weapon's settings
	if not button_container:
		return

	# Find and update position sliders
	var pos_x_slider = _find_slider_by_label("Pos X")
	var pos_y_slider = _find_slider_by_label("Pos Y")
	var pos_z_slider = _find_slider_by_label("Pos Z")
	var rot_x_slider = _find_slider_by_label("Rot X")
	var rot_y_slider = _find_slider_by_label("Rot Y")
	var rot_z_slider = _find_slider_by_label("Rot Z")

	if pos_x_slider:
		pos_x_slider.value = left_hand_ik_offset.x
	if pos_y_slider:
		pos_y_slider.value = left_hand_ik_offset.y
	if pos_z_slider:
		pos_z_slider.value = left_hand_ik_offset.z
	if rot_x_slider:
		rot_x_slider.value = left_hand_ik_rotation.x
	if rot_y_slider:
		rot_y_slider.value = left_hand_ik_rotation.y
	if rot_z_slider:
		rot_z_slider.value = left_hand_ik_rotation.z


func _find_slider_by_label(label_text: String) -> HSlider:
	for child in button_container.get_children():
		if child is HBoxContainer:
			for subchild in child.get_children():
				if subchild is Label and subchild.text == label_text:
					for sibling in child.get_children():
						if sibling is HSlider:
							return sibling
	return null


func _play_animation(anim_name: String) -> void:
	if not anim_player:
		return

	if anim_player.has_animation(anim_name):
		# ループアニメーションのloop_modeを強制設定
		var anim = anim_player.get_animation(anim_name)
		if anim and anim_name in ["Rifle_Idle", "Rifle_WalkFwdLoop", "Rifle_SprintLoop", "Rifle_CrouchLoop"]:
			if anim.loop_mode != Animation.LOOP_LINEAR:
				anim.loop_mode = Animation.LOOP_LINEAR
				print("[BotViewer] Set loop_mode to LINEAR for: %s" % anim_name)

		anim_player.play(anim_name, blend_time)
		print("[BotViewer] Playing: %s (blend: %.2fs)" % [anim_name, blend_time])

		# 左手IKの有効/無効を切り替え
		_update_left_hand_ik_enabled(anim_name)
	else:
		push_warning("[BotViewer] Animation not found: ", anim_name)


func _update_left_hand_ik_enabled(anim_name: String) -> void:
	if not left_hand_ik:
		return

	# 武器リソースの設定または変数から無効化アニメーションを確認
	var should_disable := anim_name in left_hand_ik_disabled_animations

	# weapon_resource が IK 無効の場合も無効化
	if weapon_resource and not weapon_resource.left_hand_ik_enabled:
		should_disable = true

	if should_disable:
		if left_hand_ik.is_running():
			left_hand_ik.stop()
			print("[BotViewer] Left hand IK disabled for: %s" % anim_name)
	else:
		if not left_hand_ik.is_running():
			left_hand_ik.start()
			print("[BotViewer] Left hand IK enabled for: %s" % anim_name)


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
