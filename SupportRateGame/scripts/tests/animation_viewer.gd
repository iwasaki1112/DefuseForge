extends Node3D
## Animation viewer controller - manages UI and animation playback
## Uses CharacterBody3D with physics to ensure character stays grounded

@onready var camera: Camera3D = $OrbitCamera
@onready var button_container: VBoxContainer = $CanvasLayer/Panel/ScrollContainer/VBoxContainer
@onready var character_body: CharacterBody3D = $CharacterBody

var character_model: Node3D = null
var anim_player: AnimationPlayer = null
var skeleton: Skeleton3D = null

var _animations: Array[String] = []
const GRAVITY: float = 9.8


func _ready() -> void:
	# Setup character
	_setup_character()

	# Set camera target
	if camera.has_method("set_target") and character_body:
		camera.set_target(character_body)

	# Create UI buttons
	_create_animation_buttons()

	# Play idle_none animation first (standing pose)
	if anim_player and anim_player.has_animation("idle_none"):
		_play_animation("idle_none")
	elif _animations.size() > 0:
		_play_animation(_animations[0])


func _physics_process(delta: float) -> void:
	# Apply gravity to keep character grounded
	if character_body:
		if not character_body.is_on_floor():
			character_body.velocity.y -= GRAVITY * delta
		else:
			character_body.velocity.y = 0
		character_body.move_and_slide()


func _setup_character() -> void:
	character_model = $CharacterBody/CharacterModel
	if not character_model:
		push_warning("CharacterModel not found")
		return

	# Setup materials
	CharacterSetup.setup_materials(character_model, "AnimViewer")

	# Find skeleton
	skeleton = CharacterSetup.find_skeleton(character_model)
	if skeleton:
		# Fix skin bindings
		CharacterSetup.fix_skin_bindings(character_model, skeleton, "AnimViewer")

	# Get AnimationPlayer and load animations
	anim_player = CharacterSetup.find_animation_player(character_model)
	if anim_player:
		CharacterSetup.load_animations(anim_player, character_model, "AnimViewer")
		_collect_animations()

	print("[AnimViewer] Character setup complete - using physics for grounding")


func _collect_animations() -> void:
	if not anim_player:
		push_warning("AnimationPlayer not found")
		return

	_animations.clear()
	for anim_name in anim_player.get_animation_list():
		# Skip RESET and Mixamo raw animations (Armature|...)
		if anim_name == "RESET" or anim_name.begins_with("Armature"):
			continue
		_animations.append(anim_name)

	_animations.sort()
	print("Found animations: ", _animations)


func _create_animation_buttons() -> void:
	if not button_container:
		push_warning("Button container not found")
		return

	# Clear existing buttons
	for child in button_container.get_children():
		child.queue_free()

	# Add label
	var label := Label.new()
	label.text = "Animations"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	button_container.add_child(label)

	# Add separator
	var separator := HSeparator.new()
	button_container.add_child(separator)

	# Create button for each animation
	for anim_name in _animations:
		var button := Button.new()
		button.text = anim_name
		button.pressed.connect(_on_animation_button_pressed.bind(anim_name))
		button_container.add_child(button)

	# Add spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	button_container.add_child(spacer)

	# Add character switch buttons
	var char_label := Label.new()
	char_label.text = "Character"
	char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_label.add_theme_font_size_override("font_size", 18)
	button_container.add_child(char_label)

	var char_separator := HSeparator.new()
	button_container.add_child(char_separator)

	var gsg9_button := Button.new()
	gsg9_button.text = "GSG9 (CT)"
	gsg9_button.pressed.connect(_on_character_button_pressed.bind("res://assets/characters/gsg9/gsg9.fbx"))
	button_container.add_child(gsg9_button)

	var leet_button := Button.new()
	leet_button.text = "Leet (T)"
	leet_button.pressed.connect(_on_character_button_pressed.bind("res://assets/characters/leet/leet.fbx"))
	button_container.add_child(leet_button)

	var leet_rigged_button := Button.new()
	leet_rigged_button.text = "Leet Rigged (ARP)"
	leet_rigged_button.pressed.connect(_on_character_button_pressed.bind("res://assets/characters/leet/leet_rigged.fbx"))
	button_container.add_child(leet_rigged_button)

	# Add spacer
	var test_spacer := Control.new()
	test_spacer.custom_minimum_size.y = 20
	button_container.add_child(test_spacer)

	# Add retarget test section
	var retarget_label := Label.new()
	retarget_label.text = "Retarget Test"
	retarget_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	retarget_label.add_theme_font_size_override("font_size", 18)
	button_container.add_child(retarget_label)

	var retarget_separator := HSeparator.new()
	button_container.add_child(retarget_separator)

	var retarget_button := Button.new()
	retarget_button.text = "Rifle_Idle (Retargeted)"
	retarget_button.pressed.connect(_on_retarget_test_pressed)
	button_container.add_child(retarget_button)

	# Add test.glb animation section
	var glb_spacer := Control.new()
	glb_spacer.custom_minimum_size.y = 20
	button_container.add_child(glb_spacer)

	var glb_label := Label.new()
	glb_label.text = "GLB Animations"
	glb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glb_label.add_theme_font_size_override("font_size", 18)
	button_container.add_child(glb_label)

	var glb_separator := HSeparator.new()
	button_container.add_child(glb_separator)

	var load_glb_button := Button.new()
	load_glb_button.text = "Load test_animations.glb"
	load_glb_button.pressed.connect(_on_load_glb_animations_pressed)
	button_container.add_child(load_glb_button)


func _play_animation(anim_name: String) -> void:
	if not anim_player:
		return

	if anim_player.has_animation(anim_name):
		anim_player.play(anim_name)
	else:
		push_warning("Animation not found: ", anim_name)


func _on_animation_button_pressed(anim_name: String) -> void:
	_play_animation(anim_name)


func _on_character_button_pressed(model_path: String) -> void:
	# Load and replace character model
	var new_model_scene := load(model_path) as PackedScene
	if not new_model_scene:
		push_warning("Failed to load model: ", model_path)
		return

	# Remember current animation
	var current_anim := ""
	if anim_player and anim_player.current_animation:
		current_anim = anim_player.current_animation

	# Remove old model
	if character_model:
		character_model.queue_free()
		await get_tree().process_frame

	# Add new model to CharacterBody
	character_model = new_model_scene.instantiate()
	character_model.name = "CharacterModel"
	character_model.scale = Vector3(2, 2, 2)
	character_body.add_child(character_model)

	# Setup the new character
	_setup_new_character()

	# Refresh animations
	_collect_animations()
	_create_animation_buttons()

	# Play same animation if available
	if current_anim and anim_player and anim_player.has_animation(current_anim):
		_play_animation(current_anim)
	elif _animations.size() > 0:
		_play_animation(_animations[0])


func _setup_new_character() -> void:
	if not character_model:
		return

	# Setup materials
	CharacterSetup.setup_materials(character_model, "AnimViewer")

	# Find skeleton
	skeleton = CharacterSetup.find_skeleton(character_model)
	if skeleton:
		CharacterSetup.fix_skin_bindings(character_model, skeleton, "AnimViewer")

	# Get AnimationPlayer and load animations
	anim_player = CharacterSetup.find_animation_player(character_model)
	if anim_player:
		CharacterSetup.load_animations(anim_player, character_model, "AnimViewer")

	print("[AnimViewer] New character setup complete")


func _on_retarget_test_pressed() -> void:
	# Load the retargeted animation from Blender export
	var retarget_path := "res://assets/characters/animations/retargeted/rifle_idle_retargeted.fbx"
	if not ResourceLoader.exists(retarget_path):
		push_warning("Retargeted FBX not found: " + retarget_path)
		return

	var scene := load(retarget_path)
	if not scene:
		push_warning("Failed to load retargeted FBX")
		return

	var instance: Node = scene.instantiate()
	var fbx_anim_player := instance.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if not fbx_anim_player:
		push_warning("AnimationPlayer not found in retargeted FBX")
		instance.queue_free()
		return

	# Get the retargeted animation
	var anim_list := fbx_anim_player.get_animation_list()
	print("[Retarget Test] Found animations in retargeted FBX: ", anim_list)

	if anim_list.size() == 0:
		push_warning("No animations in retargeted FBX")
		instance.queue_free()
		return

	# Get first animation (should be Rifle_Idle_Retargeted)
	var source_anim_name := anim_list[0]
	var source_anim := fbx_anim_player.get_animation(source_anim_name)
	if not source_anim:
		push_warning("Failed to get animation from retargeted FBX")
		instance.queue_free()
		return

	# Copy and adjust the animation for our character
	var anim_copy := source_anim.duplicate() as Animation
	anim_copy.loop_mode = Animation.LOOP_LINEAR

	# Adjust animation paths for our model structure
	_adjust_retargeted_animation_paths(anim_copy)

	# Add to our AnimationPlayer
	if anim_player:
		var lib := anim_player.get_animation_library("")
		if lib:
			if lib.has_animation("retarget_test"):
				lib.remove_animation("retarget_test")
			lib.add_animation("retarget_test", anim_copy)
			print("[Retarget Test] Added retargeted animation as 'retarget_test'")

			# Play it
			anim_player.play("retarget_test")

	instance.queue_free()


func _on_load_glb_animations_pressed() -> void:
	# Load animations from test_animations.glb
	var glb_path := "res://assets/characters/animations/test_animations.glb"
	print("[GLB Load] Loading: " + glb_path)

	if not ResourceLoader.exists(glb_path):
		push_warning("GLB file not found: " + glb_path)
		return

	var scene := load(glb_path)
	if not scene:
		push_warning("Failed to load GLB: " + glb_path)
		return

	print("[GLB Load] Scene loaded, instantiating...")
	var instance: Node = scene.instantiate()

	# Debug: print scene structure
	print("[GLB Load] Root node: ", instance.name, " (", instance.get_class(), ")")
	_print_node_tree(instance, 0)

	var glb_anim_player := _find_animation_player_recursive(instance)

	if not glb_anim_player:
		push_warning("AnimationPlayer not found in GLB")
		instance.queue_free()
		return

	print("[GLB Load] Found AnimationPlayer: ", glb_anim_player.name)

	var anim_list := glb_anim_player.get_animation_list()
	print("[GLB Load] Found animations: ", anim_list.size())

	# Debug: print track paths from first animation
	if anim_list.size() > 1:
		var sample_anim := glb_anim_player.get_animation(anim_list[1])  # Skip BindPose
		print("[GLB Load] Sample animation tracks (", anim_list[1], "):")
		for i in range(mini(sample_anim.get_track_count(), 5)):
			print("  Track ", i, ": ", sample_anim.track_get_path(i))

	# Debug: print character skeleton structure
	print("[GLB Load] Character model structure:")
	_print_node_tree(character_model, 0)

	# Debug: print character bone names
	if skeleton:
		print("[GLB Load] Character bones (first 10):")
		for i in range(mini(skeleton.get_bone_count(), 10)):
			print("  Bone ", i, ": ", skeleton.get_bone_name(i))

	if anim_list.size() == 0:
		push_warning("No animations in GLB")
		instance.queue_free()
		return

	# Copy animations to our AnimationPlayer
	if not anim_player:
		instance.queue_free()
		return

	var lib := anim_player.get_animation_library("")
	if not lib:
		lib = AnimationLibrary.new()
		anim_player.add_animation_library("", lib)

	var added_count := 0
	for anim_name in anim_list:
		if anim_name == "RESET" or anim_name.begins_with("BindPose"):
			continue

		var source_anim := glb_anim_player.get_animation(anim_name)
		if not source_anim:
			continue

		# Copy and adjust animation
		var anim_copy := source_anim.duplicate() as Animation
		anim_copy.loop_mode = Animation.LOOP_LINEAR
		_adjust_glb_animation_paths(anim_copy)

		# Add with glb_ prefix to distinguish
		var target_name := "glb_" + anim_name
		if lib.has_animation(target_name):
			lib.remove_animation(target_name)
		lib.add_animation(target_name, anim_copy)
		added_count += 1

	print("[GLB Load] Added %d animations" % added_count)
	instance.queue_free()

	# Refresh animation list and buttons
	_collect_animations()
	_create_animation_buttons()

	# Play first GLB animation
	if anim_player.has_animation("glb_Rifle_Idle"):
		_play_animation("glb_Rifle_Idle")
	else:
		for anim_name in _animations:
			if anim_name.begins_with("glb_"):
				_play_animation(anim_name)
				break


func _print_node_tree(node: Node, depth: int) -> void:
	var indent := ""
	for i in range(depth):
		indent += "  "
	print(indent + "- " + node.name + " (" + node.get_class() + ")")
	for child in node.get_children():
		if depth < 3:  # Limit depth
			_print_node_tree(child, depth + 1)


func _find_animation_player_recursive(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_animation_player_recursive(child)
		if result:
			return result
	return null


func _adjust_glb_animation_paths(anim: Animation) -> void:
	# Adjust animation track paths to match our character skeleton
	# GLB uses: RootNode/Skeleton3D:BoneName (e.g., Hips, Spine)
	# Character uses: Armature/Skeleton3D:mixamorig_BoneName
	var has_armature := character_model.get_node_or_null("Armature") != null

	# Bone name mapping: GLB -> Mixamo
	var bone_map := {
		"Root": "mixamorig_Hips",  # Root maps to Hips in Mixamo
		"Hips": "mixamorig_Hips",
		"Spine": "mixamorig_Spine",
		"Spine1": "mixamorig_Spine1",
		"Spine2": "mixamorig_Spine2",
		"Neck": "mixamorig_Neck",
		"Head": "mixamorig_Head",
		"HeadTop_End": "mixamorig_HeadTop_End",
		"LeftShoulder": "mixamorig_LeftShoulder",
		"LeftArm": "mixamorig_LeftArm",
		"LeftForeArm": "mixamorig_LeftForeArm",
		"LeftHand": "mixamorig_LeftHand",
		"LeftHandThumb1": "mixamorig_LeftHandThumb1",
		"LeftHandThumb2": "mixamorig_LeftHandThumb2",
		"LeftHandThumb3": "mixamorig_LeftHandThumb3",
		"LeftHandIndex1": "mixamorig_LeftHandIndex1",
		"LeftHandIndex2": "mixamorig_LeftHandIndex2",
		"LeftHandIndex3": "mixamorig_LeftHandIndex3",
		"LeftHandMiddle1": "mixamorig_LeftHandMiddle1",
		"LeftHandMiddle2": "mixamorig_LeftHandMiddle2",
		"LeftHandMiddle3": "mixamorig_LeftHandMiddle3",
		"LeftHandRing1": "mixamorig_LeftHandRing1",
		"LeftHandRing2": "mixamorig_LeftHandRing2",
		"LeftHandRing3": "mixamorig_LeftHandRing3",
		"LeftHandPinky1": "mixamorig_LeftHandPinky1",
		"LeftHandPinky2": "mixamorig_LeftHandPinky2",
		"LeftHandPinky3": "mixamorig_LeftHandPinky3",
		"RightShoulder": "mixamorig_RightShoulder",
		"RightArm": "mixamorig_RightArm",
		"RightForeArm": "mixamorig_RightForeArm",
		"RightHand": "mixamorig_RightHand",
		"RightHandThumb1": "mixamorig_RightHandThumb1",
		"RightHandThumb2": "mixamorig_RightHandThumb2",
		"RightHandThumb3": "mixamorig_RightHandThumb3",
		"RightHandIndex1": "mixamorig_RightHandIndex1",
		"RightHandIndex2": "mixamorig_RightHandIndex2",
		"RightHandIndex3": "mixamorig_RightHandIndex3",
		"RightHandMiddle1": "mixamorig_RightHandMiddle1",
		"RightHandMiddle2": "mixamorig_RightHandMiddle2",
		"RightHandMiddle3": "mixamorig_RightHandMiddle3",
		"RightHandRing1": "mixamorig_RightHandRing1",
		"RightHandRing2": "mixamorig_RightHandRing2",
		"RightHandRing3": "mixamorig_RightHandRing3",
		"RightHandPinky1": "mixamorig_RightHandPinky1",
		"RightHandPinky2": "mixamorig_RightHandPinky2",
		"RightHandPinky3": "mixamorig_RightHandPinky3",
		"LeftUpLeg": "mixamorig_LeftUpLeg",
		"LeftLeg": "mixamorig_LeftLeg",
		"LeftFoot": "mixamorig_LeftFoot",
		"LeftToeBase": "mixamorig_LeftToeBase",
		"LeftToe_End": "mixamorig_LeftToe_End",
		"RightUpLeg": "mixamorig_RightUpLeg",
		"RightLeg": "mixamorig_RightLeg",
		"RightFoot": "mixamorig_RightFoot",
		"RightToeBase": "mixamorig_RightToeBase",
		"RightToe_End": "mixamorig_RightToe_End",
	}

	for i in range(anim.get_track_count()):
		var track_path := str(anim.track_get_path(i))

		# Extract bone name from path like "RootNode/Skeleton3D:BoneName"
		if "Skeleton3D:" in track_path:
			var parts := track_path.split("Skeleton3D:")
			if parts.size() >= 2:
				var bone_name := parts[1]
				# Map bone name if mapping exists
				if bone_map.has(bone_name):
					bone_name = bone_map[bone_name]
				# Construct new path
				if has_armature:
					track_path = "Armature/Skeleton3D:" + bone_name
				else:
					track_path = "Skeleton3D:" + bone_name

		anim.track_set_path(i, NodePath(track_path))


func _adjust_retargeted_animation_paths(anim: Animation) -> void:
	# Check if our model has Armature node
	var has_armature := character_model.get_node_or_null("Armature") != null

	for i in range(anim.get_track_count()):
		var track_path := str(anim.track_get_path(i))

		# Convert bone names from Blender export format (mixamorig:) to Godot format (mixamorig_)
		track_path = track_path.replace("mixamorig:", "mixamorig_")

		# Add Armature prefix if needed
		if has_armature and track_path.begins_with("Skeleton3D:"):
			track_path = "Armature/" + track_path

		# Handle Armature.001 naming from Blender export
		track_path = track_path.replace("Armature.001/", "Armature/")

		anim.track_set_path(i, NodePath(track_path))
