class_name GrenadePoint
extends ActionPoint

## グレネードポイント（円形背景 + 爆発アイコン + 軌道線）
## パス上のグレネード投擲位置に表示され、投擲目標への軌道を示す

@export var trajectory_line_color: Color = Color(1.0, 0.5, 0.0, 0.8)  ## 軌道線の色
@export var trajectory_line_width: float = 0.02  ## 軌道線の太さ

var _trajectory_material: StandardMaterial3D
var _target_pos: Vector3 = Vector3.ZERO  ## 投擲目標位置
var _bounce_point: Vector3 = Vector3.ZERO  ## バウンスポイント（壁に当たる位置）
var _has_bounce: bool = false  ## バウンスポイントがあるか
var _trajectory_mesh: MeshInstance3D = null  ## 軌道線用メッシュ


func _init() -> void:
	# デフォルト色を設定
	circle_color = Color(0.1, 0.1, 0.1, 0.95)
	icon_color = Color(1.0, 0.5, 0.0, 1.0)  # オレンジ


func get_action_point_type() -> PointType:
	return PointType.GRENADE


func _setup_mesh() -> void:
	super._setup_mesh()

	# 軌道線のマテリアル
	_trajectory_material = StandardMaterial3D.new()
	_trajectory_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trajectory_material.albedo_color = trajectory_line_color
	_trajectory_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trajectory_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trajectory_material.render_priority = 9


## アイコン（爆発アイコン）を構築
func _build_icon() -> void:
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()

	var y_offset = 0.02  # 円より上
	var outer_radius = circle_radius * 0.6  # 外側の頂点
	var inner_radius = circle_radius * 0.25  # 内側の頂点
	var num_points = 8  # 爆発の尖った部分の数

	var center_idx = 0
	vertices.append(Vector3(0, y_offset, 0))

	# スターバースト形状（外側と内側を交互に）
	for i in range(num_points * 2):
		var angle = TAU * i / (num_points * 2)
		var radius = outer_radius if i % 2 == 0 else inner_radius
		vertices.append(Vector3(
			cos(angle) * radius,
			y_offset,
			sin(angle) * radius
		))

	# 三角形で塗りつぶし
	for i in range(num_points * 2):
		var curr = i + 1
		var next = (i + 1) % (num_points * 2) + 1
		indices.append(center_idx)
		indices.append(curr)
		indices.append(next)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_array_mesh.surface_set_material(1, _icon_material)


## ポイントを配置してターゲット位置を設定
## @param anchor: パス上のアンカー位置
## @param target: 投擲目標位置
## @param bounce: バウンスポイント（壁に当たる位置、省略可）
func set_position_and_target(anchor: Vector3, target: Vector3, bounce: Vector3 = Vector3.ZERO) -> void:
	_target_pos = target
	_bounce_point = bounce
	_has_bounce = bounce.length_squared() > 0.001

	# 位置を設定
	global_position = Vector3(anchor.x, height_offset, anchor.z)

	# 軌道線を構築
	_build_trajectory_line()


## ターゲット位置を取得
func get_target_position() -> Vector3:
	return _target_pos


## バウンスポイントを取得
func get_bounce_point() -> Vector3:
	return _bounce_point


## バウンスポイントがあるか
func has_bounce_point() -> bool:
	return _has_bounce


## 軌道線の色を設定
func set_trajectory_color(color: Color) -> void:
	trajectory_line_color = color
	if _trajectory_material:
		_trajectory_material.albedo_color = color


## 軌道線を構築
func _build_trajectory_line() -> void:
	# 既存の軌道メッシュを削除
	if _trajectory_mesh:
		_trajectory_mesh.queue_free()
		_trajectory_mesh = null

	if _target_pos.length_squared() < 0.001:
		return

	# 軌道線用のメッシュを作成
	_trajectory_mesh = MeshInstance3D.new()
	add_child(_trajectory_mesh)

	var line_mesh = ArrayMesh.new()
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()

	# アンカーからの相対座標で軌道を描画
	var anchor_local = Vector3.ZERO  # ローカル座標での原点

	if _has_bounce:
		# バウンスあり: アンカー → バウンス → ターゲット
		_build_line_segment(vertices, indices, anchor_local, _bounce_point - global_position)
		var v_start = vertices.size()
		_build_line_segment(vertices, indices, _bounce_point - global_position, _target_pos - global_position, v_start)

		# バウンスポイントにダイヤモンドマーカー
		_add_diamond_marker(vertices, indices, _bounce_point - global_position)
	else:
		# 直接投擲: アンカー → ターゲット
		_build_line_segment(vertices, indices, anchor_local, _target_pos - global_position)

	# ターゲット位置にダイヤモンドマーカー
	_add_diamond_marker(vertices, indices, _target_pos - global_position)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	line_mesh.surface_set_material(0, _trajectory_material)

	_trajectory_mesh.mesh = line_mesh
	_trajectory_mesh.position = Vector3.ZERO


## ライン（四角形）を構築
func _build_line_segment(vertices: PackedVector3Array, indices: PackedInt32Array, from: Vector3, to: Vector3, _v_offset: int = 0) -> void:
	var direction = (to - from).normalized()
	var perpendicular = Vector3(-direction.z, 0, direction.x).normalized() * trajectory_line_width

	# 開始点
	var start_pos = from + Vector3(0, height_offset * 0.5, 0)
	var end_pos = to + Vector3(0, height_offset * 0.5, 0)

	var curr_size = vertices.size()
	vertices.append(start_pos - perpendicular)
	vertices.append(start_pos + perpendicular)
	vertices.append(end_pos + perpendicular)
	vertices.append(end_pos - perpendicular)

	indices.append(curr_size + 0)
	indices.append(curr_size + 1)
	indices.append(curr_size + 2)
	indices.append(curr_size + 0)
	indices.append(curr_size + 2)
	indices.append(curr_size + 3)


## ダイヤモンドマーカーを追加
func _add_diamond_marker(vertices: PackedVector3Array, indices: PackedInt32Array, pos: Vector3) -> void:
	var diamond_size = 0.12
	var diamond_center = pos
	diamond_center.y = height_offset

	var v_start = vertices.size()
	vertices.append(diamond_center + Vector3(0, 0, -diamond_size))  # 上
	vertices.append(diamond_center + Vector3(diamond_size, 0, 0))   # 右
	vertices.append(diamond_center + Vector3(0, 0, diamond_size))   # 下
	vertices.append(diamond_center + Vector3(-diamond_size, 0, 0))  # 左

	# ダイヤモンドの4つの三角形
	indices.append(v_start)
	indices.append(v_start + 1)
	indices.append(v_start + 2)
	indices.append(v_start)
	indices.append(v_start + 2)
	indices.append(v_start + 3)
