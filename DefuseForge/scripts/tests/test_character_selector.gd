extends Node3D
## Test scene for character selection
## Debug tool to test different characters from CharacterRegistry

const AnimCtrl = preload("res://scripts/animation/strafe_animation_controller.gd")

@onready var camera: Camera3D = $Camera3D
@onready var character_dropdown: OptionButton = $UI/CharacterDropdown
@onready var info_label: Label = $UI/InfoLabel

var current_character: Node = null
var aim_position := Vector3.ZERO
var ground_plane := Plane(Vector3.UP, 0)

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
	_populate_dropdown()
	character_dropdown.item_selected.connect(_on_character_selected)

	# Spawn first character
	if character_dropdown.item_count > 0:
		_on_character_selected(0)

func _populate_dropdown() -> void:
	character_dropdown.clear()

	# Add CT characters
	var cts = CharacterRegistry.get_counter_terrorists()
	for preset in cts:
		character_dropdown.add_item("[CT] %s" % preset.display_name)
		character_dropdown.set_item_metadata(character_dropdown.item_count - 1, preset.id)

	# Add T characters
	var ts = CharacterRegistry.get_terrorists()
	for preset in ts:
		character_dropdown.add_item("[T] %s" % preset.display_name)
		character_dropdown.set_item_metadata(character_dropdown.item_count - 1, preset.id)

func _on_character_selected(index: int) -> void:
	var preset_id: String = character_dropdown.get_item_metadata(index)
	_spawn_character(preset_id)

func _spawn_character(preset_id: String) -> void:
	# Remove current character
	if current_character:
		current_character.queue_free()
		current_character = null

	# Create new character
	current_character = CharacterRegistry.create_character(preset_id, Vector3.ZERO)
	if current_character:
		add_child(current_character)
		_update_info_label(preset_id)

func _update_info_label(preset_id: String) -> void:
	var preset = CharacterRegistry.get_preset(preset_id)
	if preset:
		info_label.text = """Character: %s (%s)
Team: %s
HP: %.0f

Controls:
WASD: Move | Shift: Run | C: Crouch
F: Aim | Space+F: Fire
1/2: Weapon | K: Die | R: Respawn
Esc: Mouse mode""" % [
			preset.display_name,
			preset.id,
			"CT" if preset.team == 1 else "T",
			preset.max_health
		]

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CONFINED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)

	if not current_character:
		return

	var anim_ctrl = current_character.get_anim_controller()
	if not anim_ctrl:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				anim_ctrl.set_weapon(AnimCtrl.Weapon.RIFLE)
			KEY_2:
				anim_ctrl.set_weapon(AnimCtrl.Weapon.PISTOL)
			KEY_K:
				current_character.take_damage(current_character.max_health)
			KEY_R:
				# Respawn
				var index = character_dropdown.selected
				if index >= 0:
					_on_character_selected(index)

func _physics_process(delta: float) -> void:
	if not current_character:
		return

	if not current_character.is_alive:
		return

	var anim_ctrl = current_character.get_anim_controller()
	if not anim_ctrl:
		return

	_update_aim_position()

	# Get input
	var move_dir := Vector3(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		0,
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	var aim_dir: Vector3 = aim_position - current_character.global_position
	aim_dir.y = 0
	var is_running := Input.is_key_pressed(KEY_SHIFT)

	# Update animation
	anim_ctrl.update_animation(move_dir, aim_dir, is_running, delta)

	# Set state
	anim_ctrl.set_stance(
		AnimCtrl.Stance.CROUCH if Input.is_key_pressed(KEY_C)
		else AnimCtrl.Stance.STAND
	)
	anim_ctrl.set_aiming(Input.is_key_pressed(KEY_F))

	# Fire action
	if Input.is_key_pressed(KEY_SPACE) and Input.is_key_pressed(KEY_F):
		anim_ctrl.fire()

	# Movement
	var speed: float = anim_ctrl.get_current_speed()
	if move_dir.length() > 0.1:
		current_character.velocity.x = move_dir.normalized().x * speed
		current_character.velocity.z = move_dir.normalized().z * speed
	else:
		current_character.velocity.x = 0
		current_character.velocity.z = 0

	if not current_character.is_on_floor():
		current_character.velocity.y -= 9.8 * delta

	current_character.move_and_slide()

func _update_aim_position() -> void:
	if not camera:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)

	var intersection = ground_plane.intersects_ray(ray_origin, ray_dir)
	if intersection:
		aim_position = intersection
