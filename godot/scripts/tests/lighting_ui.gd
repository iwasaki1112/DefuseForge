extends Control
## ライティング調整UI

@export var directional_light_path: NodePath
@export var world_environment_path: NodePath

var _directional_light: DirectionalLight3D
var _environment: Environment

@onready var energy_slider: HSlider = $Panel/VBox/EnergyRow/Slider
@onready var energy_label: Label = $Panel/VBox/EnergyRow/Value
@onready var shadow_slider: HSlider = $Panel/VBox/ShadowRow/Slider
@onready var shadow_label: Label = $Panel/VBox/ShadowRow/Value
@onready var ambient_slider: HSlider = $Panel/VBox/AmbientRow/Slider
@onready var ambient_label: Label = $Panel/VBox/AmbientRow/Value
@onready var pitch_slider: HSlider = $Panel/VBox/PitchRow/Slider
@onready var pitch_label: Label = $Panel/VBox/PitchRow/Value
@onready var yaw_slider: HSlider = $Panel/VBox/YawRow/Slider
@onready var yaw_label: Label = $Panel/VBox/YawRow/Value


func _ready() -> void:
	if directional_light_path:
		_directional_light = get_node(directional_light_path) as DirectionalLight3D
	if world_environment_path:
		var world_env := get_node(world_environment_path) as WorldEnvironment
		if world_env:
			_environment = world_env.environment

	_setup_sliders()
	_connect_signals()


func _setup_sliders() -> void:
	if _directional_light:
		energy_slider.value = _directional_light.light_energy
		shadow_slider.value = _directional_light.shadow_blur

		var rot := _directional_light.rotation_degrees
		pitch_slider.value = rot.x
		yaw_slider.value = rot.y

	if _environment:
		ambient_slider.value = _environment.ambient_light_energy

	_update_labels()


func _connect_signals() -> void:
	energy_slider.value_changed.connect(_on_energy_changed)
	shadow_slider.value_changed.connect(_on_shadow_changed)
	ambient_slider.value_changed.connect(_on_ambient_changed)
	pitch_slider.value_changed.connect(_on_pitch_changed)
	yaw_slider.value_changed.connect(_on_yaw_changed)


func _on_energy_changed(value: float) -> void:
	if _directional_light:
		_directional_light.light_energy = value
	energy_label.text = "%.2f" % value


func _on_shadow_changed(value: float) -> void:
	if _directional_light:
		_directional_light.shadow_blur = value
	shadow_label.text = "%.2f" % value


func _on_ambient_changed(value: float) -> void:
	if _environment:
		_environment.ambient_light_energy = value
	ambient_label.text = "%.2f" % value


func _on_pitch_changed(value: float) -> void:
	if _directional_light:
		var rot := _directional_light.rotation_degrees
		rot.x = value
		_directional_light.rotation_degrees = rot
	pitch_label.text = "%.0f°" % value


func _on_yaw_changed(value: float) -> void:
	if _directional_light:
		var rot := _directional_light.rotation_degrees
		rot.y = value
		_directional_light.rotation_degrees = rot
	yaw_label.text = "%.0f°" % value


func _update_labels() -> void:
	energy_label.text = "%.2f" % energy_slider.value
	shadow_label.text = "%.2f" % shadow_slider.value
	ambient_label.text = "%.2f" % ambient_slider.value
	pitch_label.text = "%.0f°" % pitch_slider.value
	yaw_label.text = "%.0f°" % yaw_slider.value
