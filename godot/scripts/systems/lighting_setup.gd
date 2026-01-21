extends Node3D
class_name LightingSetup
## ライティングセットアップコンポーネント
## マップに追加するだけでライティングを適用

@export var preset: LightingPreset:
	set(value):
		preset = value
		if is_inside_tree():
			_apply_preset()

var _directional_light: DirectionalLight3D
var _world_environment: WorldEnvironment
var _environment: Environment


func _ready() -> void:
	_create_lighting_nodes()
	_apply_preset()


func _create_lighting_nodes() -> void:
	# DirectionalLight3D
	_directional_light = DirectionalLight3D.new()
	_directional_light.name = "DirectionalLight"
	add_child(_directional_light)

	# Environment
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Mobile optimization
	_environment.ssao_enabled = false
	_environment.ssil_enabled = false
	_environment.sdfgi_enabled = false
	_environment.glow_enabled = false
	_environment.fog_enabled = false

	# WorldEnvironment
	_world_environment = WorldEnvironment.new()
	_world_environment.name = "WorldEnvironment"
	_world_environment.environment = _environment
	add_child(_world_environment)


func _apply_preset() -> void:
	if not preset:
		print("[LightingSetup] No preset set")
		return
	if not _directional_light or not _environment:
		print("[LightingSetup] Nodes not ready")
		return

	print("[LightingSetup] Applying preset: %s" % preset.id)
	print("[LightingSetup] shadow_enabled: %s, shadow_blur: %s" % [preset.shadow_enabled, preset.shadow_blur])

	# Directional Light
	_directional_light.position = Vector3(0, 10, 0)
	_directional_light.light_energy = preset.light_energy
	_directional_light.light_color = preset.light_color
	_directional_light.shadow_enabled = preset.shadow_enabled
	_directional_light.shadow_blur = preset.shadow_blur
	_directional_light.shadow_bias = preset.shadow_bias
	_directional_light.rotation_degrees = Vector3(preset.light_pitch, preset.light_yaw, 0)
	_directional_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_directional_light.directional_shadow_max_distance = preset.shadow_distance

	print("[LightingSetup] Light shadow_enabled after set: %s" % _directional_light.shadow_enabled)

	# Environment
	_environment.ambient_light_energy = preset.ambient_energy
	_environment.ambient_light_color = preset.ambient_color
	_environment.background_color = preset.background_color


## プリセットを動的に変更
func set_preset(new_preset: LightingPreset) -> void:
	preset = new_preset


## 個別パラメータを取得（UI調整用）
func get_directional_light() -> DirectionalLight3D:
	return _directional_light


func get_environment() -> Environment:
	return _environment


func get_world_environment() -> WorldEnvironment:
	return _world_environment
