class_name CharacterHealthRing
extends MeshInstance3D

## キャラクター足元のHP円形インジケーター
## HPの割合に応じてリングの塗りつぶし量と色が変化する

const RING_SIZE := 1.3  ## リングメッシュのサイズ（m）
const HEIGHT_OFFSET := 0.05  ## 地面からの高さ
const DRAIN_SPEED := 5.0  ## HP減少アニメーション速度（大きいほど速い）

var _character: GameCharacter = null
var _material: ShaderMaterial = null
var _display_ratio: float = 1.0  ## 表示用HP割合（実際のHPに向かって補間）
var _prev_ratio: float = -1.0  ## 前フレームの表示HP割合（無駄な更新回避）


func setup(character: GameCharacter) -> void:
	_character = character
	_setup_mesh()


func _setup_mesh() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(RING_SIZE, RING_SIZE)
	mesh = plane

	var shader: Shader = load("res://shaders/health_ring.gdshader")
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("health_ratio", 1.0)
	material_override = _material

	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position = Vector3(0, HEIGHT_OFFSET, 0)


func _process(delta: float) -> void:
	if not _character or not is_instance_valid(_character):
		return

	# 死亡時は非表示
	if not _character.is_alive:
		if visible:
			visible = false
		return

	if not visible:
		visible = true

	# 表示用HP割合を実際のHP割合に向かって滑らかに補間
	var target_ratio := _character.get_health_ratio()
	_display_ratio = lerpf(_display_ratio, target_ratio, 1.0 - exp(-DRAIN_SPEED * delta))

	# 表示値が変わった時だけシェーダーパラメータを更新
	if absf(_display_ratio - _prev_ratio) > 0.001:
		_prev_ratio = _display_ratio
		_material.set_shader_parameter("health_ratio", _display_ratio)
