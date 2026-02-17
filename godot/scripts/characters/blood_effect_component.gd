class_name BloodEffectComponent
extends RefCounted

## 被弾時の血しぶきエフェクトコンポーネント
## GPUParticles3Dによるワンショットバーストで血しぶきを表現
## GameCharacterから呼び出される

# ============================================
# Constants
# ============================================

const BLOOD_TEXTURE_PATHS: Array[String] = [
	"res://assets/effects/bloods/1.png",
	"res://assets/effects/bloods/2.png",
]
const PARTICLE_AMOUNT: int = 8
const PARTICLE_LIFETIME: float = 0.35
const PARTICLE_SIZE: float = 0.5
const EMIT_HEIGHT: float = 0.8  ## 胴体高さ（キャラクター原点からのY）

# ============================================
# References
# ============================================

var _character: Node3D = null
var _blood_textures: Array[Texture2D] = []

# ============================================
# State
# ============================================

var _particles: GPUParticles3D = null
var _material: ParticleProcessMaterial = null
var _mesh_material: StandardMaterial3D = null

# ============================================
# Setup
# ============================================

func _init() -> void:
	for path in BLOOD_TEXTURE_PATHS:
		if ResourceLoader.exists(path):
			_blood_textures.append(load(path))


func setup(character: Node3D) -> void:
	_character = character


func warm_up() -> void:
	if not _particles or not is_instance_valid(_particles):
		_create()

# ============================================
# Public API
# ============================================

## 血しぶきエフェクトを再生
func play() -> void:
	if not _character or not is_instance_valid(_character):
		return
	if not _particles or not is_instance_valid(_particles):
		_create()
	if not _particles:
		return

	# テクスチャをランダムに切り替え
	if _mesh_material and _blood_textures.size() > 0:
		_mesh_material.albedo_texture = _blood_textures[randi() % _blood_textures.size()]

	_particles.position = Vector3(0, EMIT_HEIGHT, 0)
	_particles.restart()
	_particles.emitting = true

# ============================================
# Internal
# ============================================

func _create() -> void:
	if not _character or not is_instance_valid(_character):
		return

	_particles = GPUParticles3D.new()
	_particles.name = "BloodEffect"
	_particles.emitting = false
	_particles.amount = PARTICLE_AMOUNT
	_particles.lifetime = PARTICLE_LIFETIME
	_particles.one_shot = true
	_particles.explosiveness = 1.0
	_particles.position = Vector3(0, EMIT_HEIGHT, 0)

	# パーティクルプロセスマテリアル
	_material = ParticleProcessMaterial.new()
	_material.direction = Vector3(0, 0, 0)
	_material.spread = 180.0
	_material.initial_velocity_min = 0.0
	_material.initial_velocity_max = 0.1
	_material.gravity = Vector3.ZERO
	_material.damping_min = 0.0
	_material.damping_max = 0.0
	_material.scale_min = 0.8
	_material.scale_max = 2.0
	_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_material.emission_sphere_radius = 0.15
	_material.color = Color(0.6, 0.0, 0.0, 0.9)

	# サイズカーブ: 徐々に小さくなる
	var scale_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.5, 0.8))
	curve.add_point(Vector2(1.0, 0.2))
	scale_curve.curve = curve
	_material.scale_curve = scale_curve

	# アルファカーブ: 後半でフェードアウト
	var alpha_curve := CurveTexture.new()
	var alpha := Curve.new()
	alpha.add_point(Vector2(0.0, 1.0))
	alpha.add_point(Vector2(0.6, 0.8))
	alpha.add_point(Vector2(1.0, 0.0))
	alpha_curve.curve = alpha
	_material.alpha_curve = alpha_curve

	_particles.process_material = _material

	# メッシュ（ビルボードクワッド）
	var quad := QuadMesh.new()
	quad.size = Vector2(PARTICLE_SIZE, PARTICLE_SIZE)
	_particles.draw_pass_1 = quad

	# メッシュマテリアル
	_mesh_material = StandardMaterial3D.new()
	_mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mesh_material.vertex_color_use_as_albedo = true
	if _blood_textures.size() > 0:
		_mesh_material.albedo_texture = _blood_textures[0]
	else:
		_mesh_material.albedo_color = Color(0.6, 0.0, 0.0, 0.9)
	_particles.material_override = _mesh_material

	_character.add_child(_particles)
