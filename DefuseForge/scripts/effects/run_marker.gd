class_name RunMarker
extends MeshInstance3D

## Runマーカー（開始点 = 三角再生アイコン、終点 = 四角停止アイコン）
## パス上のRun区間の開始/終了位置に表示される

enum MarkerType { START, END }

@export var circle_radius: float = 0.3  ## 円の半径
@export var start_color: Color = Color(1.0, 0.5, 0.0, 0.95)  ## 開始点の色（オレンジ）
@export var end_color: Color = Color(0.9, 0.3, 0.1, 0.95)  ## 終点の色（赤オレンジ）
@export var icon_color: Color = Color(1.0, 1.0, 1.0, 1.0)  ## アイコンの色（白）
@export var height_offset: float = 0.03  ## 地面からの高さ
@export var segments: int = 32  ## 円のセグメント数

var _marker_type: MarkerType = MarkerType.START
var _array_mesh: ArrayMesh
var _circle_material: StandardMaterial3D
var _icon_material: StandardMaterial3D


func _ready() -> void:
	_setup_mesh()


func _setup_mesh() -> void:
	_array_mesh = ArrayMesh.new()
	mesh = _array_mesh

	# 円のマテリアル
	_circle_material = StandardMaterial3D.new()
	_circle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_circle_material.albedo_color = start_color
	_circle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_circle_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_circle_material.render_priority = 10

	# アイコンのマテリアル
	_icon_material = StandardMaterial3D.new()
	_icon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_icon_material.albedo_color = icon_color
	_icon_material.emission_enabled = true
	_icon_material.emission = icon_color
	_icon_material.emission_energy_multiplier = 1.2
	_icon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_icon_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_icon_material.render_priority = 11  # 円より上にレンダリング

	_build_mesh()


func _build_mesh() -> void:
	_array_mesh.clear_surfaces()

	# 塗りつぶし円を生成
	_build_filled_circle()

	# アイコンを生成（タイプに応じて三角または四角）
	if _marker_type == MarkerType.START:
		_build_play_icon()
	else:
		_build_stop_icon()


## 塗りつぶし円を構築
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


## 再生アイコン（三角形、右向き）を構築
func _build_play_icon() -> void:
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()

	var icon_size = circle_radius * 0.6
	var y_offset = 0.02  # 円より上（Z-fighting防止）

	# 三角形の頂点（右向き再生アイコン）
	# 中心を基準に配置
	var left_top = Vector3(-icon_size * 0.4, y_offset, -icon_size * 0.5)
	var left_bottom = Vector3(-icon_size * 0.4, y_offset, icon_size * 0.5)
	var right_center = Vector3(icon_size * 0.6, y_offset, 0)

	vertices.append(left_top)      # 0
	vertices.append(left_bottom)   # 1
	vertices.append(right_center)  # 2

	indices.append(0)
	indices.append(1)
	indices.append(2)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_array_mesh.surface_set_material(1, _icon_material)


## 停止アイコン（四角形）を構築
func _build_stop_icon() -> void:
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()

	var icon_size = circle_radius * 0.5
	var y_offset = 0.02  # 円より上（Z-fighting防止）
	var half = icon_size * 0.5

	# 四角形の頂点
	vertices.append(Vector3(-half, y_offset, -half))  # 0: 左上
	vertices.append(Vector3(half, y_offset, -half))   # 1: 右上
	vertices.append(Vector3(half, y_offset, half))    # 2: 右下
	vertices.append(Vector3(-half, y_offset, half))   # 3: 左下

	# 2つの三角形で四角形を構成
	indices.append(0)
	indices.append(1)
	indices.append(2)

	indices.append(0)
	indices.append(2)
	indices.append(3)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_array_mesh.surface_set_material(1, _icon_material)


## マーカーを配置してタイプを設定
## @param pos: パス上の位置
## @param type: MarkerType.START または MarkerType.END
func set_position_and_type(pos: Vector3, type: MarkerType) -> void:
	# 位置を設定
	global_position = Vector3(pos.x, height_offset, pos.z)

	# タイプが変わったらメッシュを再構築
	if _marker_type != type:
		_marker_type = type
		_update_circle_color()
		_build_mesh()


## タイプを取得
func get_marker_type() -> MarkerType:
	return _marker_type


## 円の色をタイプに応じて更新
func _update_circle_color() -> void:
	if _circle_material:
		if _marker_type == MarkerType.START:
			_circle_material.albedo_color = start_color
		else:
			_circle_material.albedo_color = end_color


## 色を変更
## @param bg_color: 背景円の色
## @param fg_color: アイコンの色
func set_colors(bg_color: Color, fg_color: Color) -> void:
	start_color = bg_color
	end_color = bg_color  # 開始/終点とも同じ背景色に
	icon_color = fg_color
	if _circle_material:
		_circle_material.albedo_color = bg_color
	if _icon_material:
		_icon_material.albedo_color = fg_color
		_icon_material.emission = fg_color
