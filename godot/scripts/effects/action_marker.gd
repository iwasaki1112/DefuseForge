class_name ActionMarker
extends MeshInstance3D

## アクションマーカーの基底クラス
## Vision, Clear, Run, Door, Grenadeマーカーの共通機能を提供

## マーカータイプ定義
enum MarkerType {
	VISION,
	CLEAR,
	RUN,
	DOOR,
	GRENADE,
	WAIT,
	SMOKE_GRENADE
}

@export var circle_radius: float = 0.3  ## 円の半径
@export var circle_color: Color = Color(0.1, 0.1, 0.1, 0.95)  ## 円の背景色
@export var icon_color: Color = Color(1.0, 1.0, 1.0, 1.0)  ## アイコンの色
@export var height_offset: float = 0.03  ## 地面からの高さ
@export var segments: int = 32  ## 円のセグメント数

var _array_mesh: ArrayMesh
var _circle_material: StandardMaterial3D
var _icon_material: StandardMaterial3D


func _ready() -> void:
	_setup_mesh()


## マーカータイプを取得（子クラスでオーバーライド）
func get_action_marker_type() -> MarkerType:
	return MarkerType.VISION


## メッシュとマテリアルの初期化
func _setup_mesh() -> void:
	_array_mesh = ArrayMesh.new()
	mesh = _array_mesh

	# 円のマテリアル
	_circle_material = _create_circle_material()

	# アイコンのマテリアル
	_icon_material = _create_icon_material()

	_build_mesh()


## 円のマテリアルを作成
func _create_circle_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = circle_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 10
	return mat


## アイコンのマテリアルを作成
func _create_icon_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = icon_color
	mat.emission_enabled = true
	mat.emission = icon_color
	mat.emission_energy_multiplier = 1.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 11
	return mat


## メッシュを構築（子クラスでオーバーライド）
func _build_mesh() -> void:
	_array_mesh.clear_surfaces()
	_build_filled_circle()
	_build_icon()


## 塗りつぶし円を構築（共通実装）
func _build_filled_circle() -> void:
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()

	# 中心点
	vertices.append(Vector3(0, 0, 0))

	# 円周上の頂点
	for i in range(segments):
		var angle = TAU * i / segments
		vertices.append(Vector3(
			cos(angle) * circle_radius,
			0,
			sin(angle) * circle_radius
		))

	# 三角形で塗りつぶし
	for i in range(segments):
		var curr = i + 1
		var next = (i + 1) % segments + 1
		indices.append(0)  # 中心
		indices.append(curr)
		indices.append(next)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_array_mesh.surface_set_material(0, _circle_material)


## アイコンを構築（子クラスでオーバーライド）
func _build_icon() -> void:
	pass


## マーカー位置を設定
func set_marker_position(pos: Vector3) -> void:
	global_position = Vector3(pos.x, height_offset, pos.z)


## 色を変更
## @param bg_color: 背景円の色
## @param fg_color: アイコンの色
func set_colors(bg_color: Color, fg_color: Color) -> void:
	circle_color = bg_color
	icon_color = fg_color
	if _circle_material:
		_circle_material.albedo_color = bg_color
	if _icon_material:
		_icon_material.albedo_color = fg_color
		_icon_material.emission = fg_color
