class_name CharacterHealthRing
extends MeshInstance3D

## キャラクター足元のHP円形インジケーター
## HPの割合に応じてリングの塗りつぶし量と色が変化する

const RING_SIZE := 1.3  ## リングメッシュのサイズ（m）
const HEIGHT_OFFSET := 0.05  ## 地面からの高さ

var _character: GameCharacter = null
var _material: ShaderMaterial = null
var _prev_ratio: float = -1.0  ## 前フレームのHP割合（無駄な更新回避）


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


func _process(_delta: float) -> void:
	if not _character or not is_instance_valid(_character):
		return

	# 死亡時は非表示
	if not _character.is_alive:
		if visible:
			visible = false
		return

	if not visible:
		visible = true

	# HP割合が変わった時だけシェーダーパラメータを更新
	var ratio := _character.get_health_ratio()
	if absf(ratio - _prev_ratio) > 0.001:
		_prev_ratio = ratio
		_material.set_shader_parameter("health_ratio", ratio)
