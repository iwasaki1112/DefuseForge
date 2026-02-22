extends Node3D
## 環境光調整用テストシーン
##
## マップとキャラクターを配置し、ライティング設定をリアルタイムに調整する機能を提供する。
##
## 主な機能:
## - DirectionalLight（太陽光）の調整：エネルギー、色、角度
## - AmbientLight（環境光）の調整：エネルギー、色
## - 背景色の調整
## - マップの選択とロード
## - キャラクターの配置

# UI References - Directional Light
@onready var light_energy_slider: HSlider = $UI/Panel/VBox/LightEnergy/HSlider
@onready var light_energy_spin: SpinBox = $UI/Panel/VBox/LightEnergy/SpinBox
@onready var light_pitch_slider: HSlider = $UI/Panel/VBox/LightPitch/HSlider
@onready var light_pitch_spin: SpinBox = $UI/Panel/VBox/LightPitch/SpinBox
@onready var light_yaw_slider: HSlider = $UI/Panel/VBox/LightYaw/HSlider
@onready var light_yaw_spin: SpinBox = $UI/Panel/VBox/LightYaw/SpinBox
@onready var light_color_picker: ColorPickerButton = $UI/Panel/VBox/LightColor/ColorPicker

# UI References - Ambient Light
@onready var ambient_energy_slider: HSlider = $UI/Panel/VBox/AmbientEnergy/HSlider
@onready var ambient_energy_spin: SpinBox = $UI/Panel/VBox/AmbientEnergy/SpinBox
@onready var ambient_color_picker: ColorPickerButton = $UI/Panel/VBox/AmbientColor/ColorPicker
@onready var background_color_picker: ColorPickerButton = $UI/Panel/VBox/BackgroundColor/ColorPicker

# UI References - Map/Character
@onready var map_option: OptionButton = $UI/Panel/VBox/MapOption
@onready var preset_label: Label = $UI/Panel/VBox/PresetValues

# Scene nodes
@onready var camera: Camera3D = $Camera3D
@onready var map_container: Node3D = $MapContainer
@onready var character_container: Node3D = $CharacterContainer

# Data
var _environment_setup: EnvironmentSetup = null
var _current_map: Node3D = null
var _characters: Array[GameCharacter] = []
var _animation_library: AnimationLibrary = null

const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"


func _ready() -> void:
	_setup_environment()
	_animation_library = _load_animation_library()
	_setup_ui()
	_load_default_map()


func _setup_environment() -> void:
	_environment_setup = EnvironmentSetup.new()
	_environment_setup.name = "EnvironmentSetup"
	if ResourceLoader.exists(DEFAULT_ENVIRONMENT_PRESET):
		var preset = load(DEFAULT_ENVIRONMENT_PRESET) as EnvironmentPreset
		if preset:
			_environment_setup.preset = preset
	add_child(_environment_setup)

	# Initialize UI with current values
	call_deferred("_sync_ui_from_environment")


func _sync_ui_from_environment() -> void:
	var preset = _environment_setup.preset
	if not preset:
		return

	# Directional Light
	light_energy_slider.set_value_no_signal(preset.light_energy)
	light_energy_spin.set_value_no_signal(preset.light_energy)
	light_pitch_slider.set_value_no_signal(preset.light_pitch)
	light_pitch_spin.set_value_no_signal(preset.light_pitch)
	light_yaw_slider.set_value_no_signal(preset.light_yaw)
	light_yaw_spin.set_value_no_signal(preset.light_yaw)
	light_color_picker.color = preset.light_color

	# Ambient Light
	ambient_energy_slider.set_value_no_signal(preset.ambient_energy)
	ambient_energy_spin.set_value_no_signal(preset.ambient_energy)
	ambient_color_picker.color = preset.ambient_color
	background_color_picker.color = preset.background_color

	_update_preset_label()


func _setup_ui() -> void:
	# Map dropdown
	map_option.clear()
	var map_ids = MapRegistry.get_all_ids()
	for map_id in map_ids:
		var preset = MapRegistry.get_preset(map_id)
		if preset:
			map_option.add_item(preset.display_name)
	map_option.item_selected.connect(_on_map_selected)

	# Directional Light controls
	_connect_slider_spin(light_energy_slider, light_energy_spin, _update_light_energy)
	_connect_slider_spin(light_pitch_slider, light_pitch_spin, _update_light_pitch)
	_connect_slider_spin(light_yaw_slider, light_yaw_spin, _update_light_yaw)
	light_color_picker.color_changed.connect(_update_light_color)

	# Ambient Light controls
	_connect_slider_spin(ambient_energy_slider, ambient_energy_spin, _update_ambient_energy)
	ambient_color_picker.color_changed.connect(_update_ambient_color)
	background_color_picker.color_changed.connect(_update_background_color)


func _connect_slider_spin(slider: HSlider, spin: SpinBox, callback: Callable) -> void:
	slider.value_changed.connect(func(v):
		spin.set_value_no_signal(v)
		callback.call(v)
	)
	spin.value_changed.connect(func(v):
		slider.set_value_no_signal(v)
		callback.call(v)
	)


func _load_default_map() -> void:
	var map_ids = MapRegistry.get_all_ids()
	if map_ids.size() > 0:
		_load_map(map_ids[0])


func _load_map(map_id: String) -> void:
	# Remove existing map
	if _current_map:
		_current_map.queue_free()
		_current_map = null

	# Remove existing characters
	for c in _characters:
		if is_instance_valid(c):
			c.queue_free()
	_characters.clear()

	# Load new map
	_current_map = MapRegistry.instantiate_map(map_id)
	if _current_map:
		map_container.add_child(_current_map)

		# Spawn characters at spawn points
		call_deferred("_spawn_characters", map_id)


func _spawn_characters(map_id: String) -> void:
	var map_preset = MapRegistry.get_preset(map_id)
	if not map_preset:
		return

	# Get character presets
	var ct_presets = CharacterRegistry.get_counter_terrorists()
	var t_presets = CharacterRegistry.get_terrorists()

	# Spawn CT characters
	var ct_spawns = map_preset.spawn_points_ct
	var ct_rotations = map_preset.spawn_rotations_ct
	for i in range(mini(ct_presets.size(), ct_spawns.size())):
		var character = _create_character(ct_presets[i], ct_spawns[i])
		if character:
			if i < ct_rotations.size():
				character.set_facing_direction(ct_rotations[i])
			character_container.add_child(character)
			_characters.append(character)

	# Spawn T characters
	var t_spawns = map_preset.spawn_points_t
	var t_rotations = map_preset.spawn_rotations_t
	for i in range(mini(t_presets.size(), t_spawns.size())):
		var character = _create_character(t_presets[i], t_spawns[i])
		if character:
			if i < t_rotations.size():
				character.set_facing_direction(t_rotations[i])
			character_container.add_child(character)
			_characters.append(character)


func _create_character(preset: Resource, spawn_pos: Vector3) -> GameCharacter:
	if not preset or not preset.model_scene:
		return null

	var model = preset.model_scene.instantiate()
	var character := GameCharacter.new()
	character.name = preset.id
	character.character_preset_id = preset.id
	character.position = spawn_pos
	character.team = preset.team

	model.name = "CharacterModel"
	character.add_child(model)

	# Setup AnimationPlayer with shared library
	var anim_player := model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if not anim_player:
		anim_player = AnimationPlayer.new()
		anim_player.name = "AnimationPlayer"
		model.add_child(anim_player)

	if _animation_library:
		if anim_player.has_animation_library(""):
			anim_player.remove_animation_library("")
		anim_player.add_animation_library("", _animation_library)

	# Setup animation controller
	var anim_ctrl := CharacterAnimationController.new()
	character.add_child(anim_ctrl)
	character.set_anim_controller(anim_ctrl)

	character.ready.connect(func():
		anim_ctrl.setup(model, anim_player)
		var facing = character.get_facing_direction()
		if facing.length_squared() > 0.001:
			anim_ctrl.set_model_direction(facing)
	, CONNECT_ONE_SHOT)

	return character


func _load_animation_library() -> AnimationLibrary:
	const ANIMATION_SOURCE := "res://assets/animations/character_anims_kubold.glb"
	const ANIMATION_SOURCE_MIXAMO := "res://assets/animations/character_anims_mixamo.glb"
	if not ResourceLoader.exists(ANIMATION_SOURCE):
		return null

	var anim_scene = load(ANIMATION_SOURCE) as PackedScene
	if not anim_scene:
		return null

	var anim_instance = anim_scene.instantiate()
	var source_player = _find_animation_player(anim_instance)
	var lib: AnimationLibrary = null
	if source_player:
		lib = source_player.get_animation_library("")
	anim_instance.queue_free()

	# Merge mixamo animations (override kubold for movement anims)
	if lib and ResourceLoader.exists(ANIMATION_SOURCE_MIXAMO):
		var mixamo_scene = load(ANIMATION_SOURCE_MIXAMO) as PackedScene
		if mixamo_scene:
			var mixamo_instance = mixamo_scene.instantiate()
			var mixamo_player = _find_animation_player(mixamo_instance)
			if mixamo_player:
				var mixamo_lib = mixamo_player.get_animation_library("")
				if mixamo_lib:
					for anim_name in mixamo_lib.get_animation_list():
						if lib.has_animation(anim_name):
							lib.remove_animation(anim_name)
						lib.add_animation(anim_name, mixamo_lib.get_animation(anim_name))
			mixamo_instance.queue_free()

	return lib


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	return null


# ============================================
# Update Functions
# ============================================

func _update_light_energy(value: float) -> void:
	var light = _environment_setup.get_directional_light()
	if light:
		light.light_energy = value
	_update_preset_label()


func _update_light_pitch(value: float) -> void:
	var light = _environment_setup.get_directional_light()
	if light:
		light.rotation_degrees.x = value
	_update_preset_label()


func _update_light_yaw(value: float) -> void:
	var light = _environment_setup.get_directional_light()
	if light:
		light.rotation_degrees.y = value
	_update_preset_label()


func _update_light_color(color: Color) -> void:
	var light = _environment_setup.get_directional_light()
	if light:
		light.light_color = color
	_update_preset_label()


func _update_ambient_energy(value: float) -> void:
	var env = _environment_setup.get_environment()
	if env:
		env.ambient_light_energy = value
	_update_preset_label()


func _update_ambient_color(color: Color) -> void:
	var env = _environment_setup.get_environment()
	if env:
		env.ambient_light_color = color
	_update_preset_label()


func _update_background_color(color: Color) -> void:
	var env = _environment_setup.get_environment()
	if env:
		env.background_color = color
	_update_preset_label()


func _update_preset_label() -> void:
	var light = _environment_setup.get_directional_light()
	var env = _environment_setup.get_environment()
	if not light or not env:
		return

	var text := "# Current Values (copy to preset):\n"
	text += "light_energy = %.2f\n" % light.light_energy
	text += "light_color = Color(%.2f, %.2f, %.2f, 1)\n" % [light.light_color.r, light.light_color.g, light.light_color.b]
	text += "light_pitch = %.1f\n" % light.rotation_degrees.x
	text += "light_yaw = %.1f\n" % light.rotation_degrees.y
	text += "ambient_energy = %.2f\n" % env.ambient_light_energy
	text += "ambient_color = Color(%.2f, %.2f, %.2f, 1)\n" % [env.ambient_light_color.r, env.ambient_light_color.g, env.ambient_light_color.b]
	text += "background_color = Color(%.2f, %.2f, %.2f, 1)" % [env.background_color.r, env.background_color.g, env.background_color.b]

	preset_label.text = text


func _on_map_selected(idx: int) -> void:
	var map_ids = MapRegistry.get_all_ids()
	if idx >= 0 and idx < map_ids.size():
		_load_map(map_ids[idx])
