extends Node3D
class_name EnvironmentSetup
## マップ環境セットアップ
## ライティング・影・レンダリング設定を統合管理するコンポーネント

@export var preset: EnvironmentPreset:
	set(value):
		preset = value
		if is_inside_tree():
			_apply_preset()

var _directional_light: DirectionalLight3D
var _world_environment: WorldEnvironment
var _environment: Environment


func _ready() -> void:
	_create_nodes()
	_apply_preset()


func _create_nodes() -> void:
	# DirectionalLight3D
	_directional_light = DirectionalLight3D.new()
	_directional_light.name = "DirectionalLight"
	add_child(_directional_light)

	# Environment
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	# WorldEnvironment
	_world_environment = WorldEnvironment.new()
	_world_environment.name = "WorldEnvironment"
	_world_environment.environment = _environment
	add_child(_world_environment)


func _apply_preset() -> void:
	if not preset:
		return
	if not _directional_light or not _environment:
		return

	_apply_lighting()
	_apply_shadow()
	_apply_ambient()
	_apply_rendering()
	_apply_post_processing()


func _apply_lighting() -> void:
	_directional_light.position = Vector3(0, 10, 0)
	_directional_light.light_energy = preset.light_energy
	_directional_light.light_color = preset.light_color
	_directional_light.rotation_degrees = Vector3(preset.light_pitch, preset.light_yaw, 0)


func _apply_shadow() -> void:
	_directional_light.shadow_enabled = preset.shadow_enabled
	_directional_light.shadow_blur = preset.shadow_blur
	_directional_light.shadow_bias = preset.shadow_bias
	_directional_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_directional_light.directional_shadow_max_distance = preset.shadow_distance

	# 影の解像度をプロジェクト設定に適用
	var shadow_size_value := preset.get_shadow_size_value()
	RenderingServer.directional_shadow_atlas_set_size(shadow_size_value, true)


func _apply_ambient() -> void:
	_environment.ambient_light_energy = preset.ambient_energy
	_environment.ambient_light_color = preset.ambient_color
	_environment.background_color = preset.background_color


func _apply_rendering() -> void:
	# 解像度スケーリング
	get_viewport().scaling_3d_scale = preset.resolution_scale

	# Compatibilityレンダラーでは一部機能が未対応
	var rendering_method: String = ProjectSettings.get_setting("rendering/renderer/rendering_method", "")
	if rendering_method == "gl_compatibility":
		get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED

	# FSRアップスケーリング
	if preset.use_fsr:
		if rendering_method == "forward_plus":
			get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		else:
			get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	else:
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR


func _apply_post_processing() -> void:
	_environment.ssao_enabled = preset.ssao_enabled
	_environment.ssil_enabled = preset.ssil_enabled
	_environment.sdfgi_enabled = preset.sdfgi_enabled

	# Glow
	_environment.glow_enabled = preset.glow_enabled
	_environment.glow_intensity = preset.glow_intensity
	_environment.glow_bloom = preset.glow_bloom
	_environment.glow_blend_mode = preset.glow_blend_mode
	_environment.glow_hdr_threshold = preset.glow_hdr_threshold

	# Fog
	_environment.fog_enabled = preset.fog_enabled
	_environment.fog_light_color = preset.fog_light_color
	_environment.fog_density = preset.fog_density
	_environment.fog_aerial_perspective = preset.fog_aerial_perspective

	# Color Adjustment
	_environment.adjustment_enabled = preset.adjustment_enabled
	_environment.adjustment_brightness = preset.adjustment_brightness
	_environment.adjustment_contrast = preset.adjustment_contrast
	_environment.adjustment_saturation = preset.adjustment_saturation


## プリセットを動的に変更
func set_preset(new_preset: EnvironmentPreset) -> void:
	preset = new_preset


## DirectionalLight3Dを取得
func get_directional_light() -> DirectionalLight3D:
	return _directional_light


## Environmentを取得
func get_environment() -> Environment:
	return _environment


## WorldEnvironmentを取得
func get_world_environment() -> WorldEnvironment:
	return _world_environment
