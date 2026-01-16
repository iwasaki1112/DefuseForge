extends MixamoCharacter
## Simple Mixamo player using AnimCtrl API
## Demonstrates the clean API usage with MixamoCharacter

const AnimCtrl = preload("res://scripts/animation/strafe_animation_controller.gd")

@onready var model: Node3D = $CharacterModel
@onready var anim_player: AnimationPlayer = $CharacterModel/AnimationPlayer

var aim_position := Vector3.ZERO
var ground_plane := Plane(Vector3.UP, 0)

func _ready() -> void:
	super._ready()
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)

	# Setup animation controller
	anim_ctrl = AnimCtrl.new()
	add_child(anim_ctrl)
	anim_ctrl.setup(model, anim_player)
	anim_ctrl.set_weapon(AnimCtrl.Weapon.RIFLE)

	# Register controller with MixamoCharacter
	set_anim_controller(anim_ctrl)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CONFINED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)

	# Weapon switching: 1 = Rifle, 2 = Pistol
	# Death test: K = instant kill via take_damage
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			anim_ctrl.set_weapon(AnimCtrl.Weapon.RIFLE)
		elif event.keycode == KEY_2:
			anim_ctrl.set_weapon(AnimCtrl.Weapon.PISTOL)
		elif event.keycode == KEY_K:
			take_damage(max_health)  # Instant kill via MixamoCharacter

func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	_update_aim_position()

	# Get input
	var move_dir := Vector3(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		0,
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	var aim_dir := (aim_position - global_position)
	aim_dir.y = 0
	var is_running := Input.is_key_pressed(KEY_SHIFT)

	# Update animation (one simple call!)
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
		velocity.x = move_dir.normalized().x * speed
		velocity.z = move_dir.normalized().z * speed
	else:
		velocity.x = 0
		velocity.z = 0

	if not is_on_floor():
		velocity.y -= 9.8 * delta

	move_and_slide()

func _update_aim_position() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)

	var intersection = ground_plane.intersects_ray(ray_origin, ray_dir)
	if intersection:
		aim_position = intersection
