class_name TracerEffect
extends Node3D

## 弾道トレーサーエフェクト
## 発砲時にマズルから着弾点まで伸び縮みするトレーサー

@export var tracer_color: Color = Color(1.0, 1.0, 0.9, 0.9)
@export var core_radius: float = 0.003
@export var glow_radius: float = 0.012  # ぼかし用の太さ
@export var max_range: float = 100.0
@export var extend_time: float = 0.03  # 伸びる時間
@export var shrink_time: float = 0.08  # 縮む時間

var _ray_cast: RayCast3D
var _core_mesh: MeshInstance3D
var _glow_mesh: MeshInstance3D
var _core_cylinder: CylinderMesh
var _glow_cylinder: CylinderMesh
var _target_distance: float = 0.0


func _ready() -> void:
	_setup_raycast()
	_setup_mesh()


func _setup_raycast() -> void:
	_ray_cast = RayCast3D.new()
	_ray_cast.target_position = Vector3(0, 0, -max_range)
	_ray_cast.enabled = true
	add_child(_ray_cast)


func _setup_mesh() -> void:
	# グロー（外側のぼかし）- 先に追加して後ろに描画
	_glow_mesh = MeshInstance3D.new()
	_glow_cylinder = CylinderMesh.new()
	_glow_cylinder.top_radius = glow_radius
	_glow_cylinder.bottom_radius = glow_radius
	_glow_cylinder.height = 0.01
	_glow_cylinder.radial_segments = 8
	_glow_mesh.mesh = _glow_cylinder
	_glow_mesh.rotation_degrees.x = 90

	var glow_material = StandardMaterial3D.new()
	glow_material.albedo_color = Color(tracer_color.r, tracer_color.g, tracer_color.b, 0.25)
	glow_material.emission_enabled = true
	glow_material.emission = Color(tracer_color.r, tracer_color.g, tracer_color.b)
	glow_material.emission_energy_multiplier = 1.5
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mesh.material_override = glow_material
	_glow_mesh.visible = false
	add_child(_glow_mesh)

	# コア（中心の明るいライン）
	_core_mesh = MeshInstance3D.new()
	_core_cylinder = CylinderMesh.new()
	_core_cylinder.top_radius = core_radius
	_core_cylinder.bottom_radius = core_radius
	_core_cylinder.height = 0.01
	_core_cylinder.radial_segments = 6
	_core_mesh.mesh = _core_cylinder
	_core_mesh.rotation_degrees.x = 90

	var core_material = StandardMaterial3D.new()
	core_material.albedo_color = tracer_color
	core_material.emission_enabled = true
	core_material.emission = Color(tracer_color.r, tracer_color.g, tracer_color.b)
	core_material.emission_energy_multiplier = 3.0
	core_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mesh.material_override = core_material
	_core_mesh.visible = false
	add_child(_core_mesh)


func fire() -> void:
	_ray_cast.force_raycast_update()

	if _ray_cast.is_colliding():
		var hit_point := _ray_cast.get_collision_point()
		_target_distance = global_position.distance_to(hit_point)
	else:
		_target_distance = max_range

	_animate_tracer()


func _animate_tracer() -> void:
	_core_cylinder.height = 0.01
	_glow_cylinder.height = 0.01
	_core_mesh.position = Vector3.ZERO
	_glow_mesh.position = Vector3.ZERO
	_core_mesh.visible = true
	_glow_mesh.visible = true

	var tween := create_tween()
	tween.set_parallel(false)

	# フェーズ1: 先端が伸びる
	tween.tween_method(_update_extend, 0.0, 1.0, extend_time)
	tween.tween_method(_update_shrink, 0.0, 1.0, shrink_time)
	tween.tween_callback(_hide_tracer)


func _update_extend(progress: float) -> void:
	var current_length: float = _target_distance * progress
	var height: float = maxf(current_length, 0.01)
	var pos := Vector3(0, 0, -current_length / 2.0)

	_core_cylinder.height = height
	_core_mesh.position = pos
	_glow_cylinder.height = height
	_glow_mesh.position = pos


func _update_shrink(progress: float) -> void:
	var tail_pos: float = _target_distance * progress
	var current_length: float = _target_distance - tail_pos
	var height: float = maxf(current_length, 0.01)
	var center_pos: float = tail_pos + current_length / 2.0
	var pos := Vector3(0, 0, -center_pos)

	_core_cylinder.height = height
	_core_mesh.position = pos
	_glow_cylinder.height = height
	_glow_mesh.position = pos


func _hide_tracer() -> void:
	_core_mesh.visible = false
	_glow_mesh.visible = false
