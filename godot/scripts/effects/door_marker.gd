class_name DoorMarker
extends ActionMarker

## ドアマーカー（円形背景 + ドアアイコン + ドアへの接続線）
## パス上のドアキック位置に表示され、対象ドアへの接続線を示す

@export var connection_line_color: Color = Color(0.8, 0.6, 0.3, 0.8)  ## 接続線の色
@export var connection_line_width: float = 0.02  ## 接続線の太さ

var _connection_material: StandardMaterial3D
var _door_node: Node3D = null  ## 対象ドア
var _door_position: Vector3 = Vector3.ZERO  ## ドアの位置
var _connection_mesh: MeshInstance3D = null  ## 接続線用メッシュ


func _init() -> void:
	# デフォルト色を設定
	circle_color = Color(0.1, 0.1, 0.1, 0.95)
	icon_color = Color(0.8, 0.6, 0.3, 1.0)  # ブラウン系


func get_action_marker_type() -> MarkerType:
	return MarkerType.DOOR


func _setup_mesh() -> void:
	super._setup_mesh()

	# 接続線のマテリアル
	_connection_material = StandardMaterial3D.new()
	_connection_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_connection_material.albedo_color = connection_line_color
	_connection_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_connection_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_connection_material.render_priority = 9


## アイコン（ドアアイコン）を構築
func _build_icon() -> void:
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()

	var y_offset = 0.02  # 円より上
	var door_width = circle_radius * 0.5
	var door_height = circle_radius * 0.8
	var handle_size = circle_radius * 0.1

	# ドア本体（長方形）
	var half_w = door_width * 0.5
	var half_h = door_height * 0.5

	vertices.append(Vector3(-half_w, y_offset, -half_h))  # 0: 左上
	vertices.append(Vector3(half_w, y_offset, -half_h))   # 1: 右上
	vertices.append(Vector3(half_w, y_offset, half_h))    # 2: 右下
	vertices.append(Vector3(-half_w, y_offset, half_h))   # 3: 左下

	# ドア本体の枠線（外側）
	var frame_thickness = 0.015
	# 上辺
	vertices.append(Vector3(-half_w - frame_thickness, y_offset, -half_h - frame_thickness))  # 4
	vertices.append(Vector3(half_w + frame_thickness, y_offset, -half_h - frame_thickness))   # 5
	vertices.append(Vector3(half_w + frame_thickness, y_offset, -half_h))                      # 6
	vertices.append(Vector3(-half_w - frame_thickness, y_offset, -half_h))                     # 7

	# 下辺
	vertices.append(Vector3(-half_w - frame_thickness, y_offset, half_h))                      # 8
	vertices.append(Vector3(half_w + frame_thickness, y_offset, half_h))                       # 9
	vertices.append(Vector3(half_w + frame_thickness, y_offset, half_h + frame_thickness))    # 10
	vertices.append(Vector3(-half_w - frame_thickness, y_offset, half_h + frame_thickness))   # 11

	# 左辺
	vertices.append(Vector3(-half_w - frame_thickness, y_offset, -half_h))                     # 12
	vertices.append(Vector3(-half_w, y_offset, -half_h))                                        # 13
	vertices.append(Vector3(-half_w, y_offset, half_h))                                         # 14
	vertices.append(Vector3(-half_w - frame_thickness, y_offset, half_h))                      # 15

	# 右辺
	vertices.append(Vector3(half_w, y_offset, -half_h))                                         # 16
	vertices.append(Vector3(half_w + frame_thickness, y_offset, -half_h))                      # 17
	vertices.append(Vector3(half_w + frame_thickness, y_offset, half_h))                       # 18
	vertices.append(Vector3(half_w, y_offset, half_h))                                          # 19

	# 取っ手（小さな正方形）
	var handle_offset_x = half_w * 0.6
	var handle_offset_z = 0.0
	vertices.append(Vector3(handle_offset_x - handle_size, y_offset + 0.001, handle_offset_z - handle_size))  # 20
	vertices.append(Vector3(handle_offset_x + handle_size, y_offset + 0.001, handle_offset_z - handle_size))  # 21
	vertices.append(Vector3(handle_offset_x + handle_size, y_offset + 0.001, handle_offset_z + handle_size))  # 22
	vertices.append(Vector3(handle_offset_x - handle_size, y_offset + 0.001, handle_offset_z + handle_size))  # 23

	# インデックス
	# 枠線（上）
	indices.append_array([4, 5, 6, 4, 6, 7])
	# 枠線（下）
	indices.append_array([8, 9, 10, 8, 10, 11])
	# 枠線（左）
	indices.append_array([12, 13, 14, 12, 14, 15])
	# 枠線（右）
	indices.append_array([16, 17, 18, 16, 18, 19])
	# 取っ手
	indices.append_array([20, 21, 22, 20, 22, 23])

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_array_mesh.surface_set_material(1, _icon_material)


## マーカーを配置してドアを設定
## @param anchor: パス上のアンカー位置
## @param door: 対象ドアのNode3D
func set_position_and_door(anchor: Vector3, door: Node3D) -> void:
	_door_node = door
	if door:
		_door_position = door.global_position
	else:
		_door_position = Vector3.ZERO

	# 位置を設定
	global_position = Vector3(anchor.x, height_offset, anchor.z)

	# 接続線を構築
	_build_connection_line()


## ドアノードを取得
func get_door_node() -> Node3D:
	return _door_node


## ドアの位置を取得
func get_door_position() -> Vector3:
	return _door_position


## 接続線の色を設定
func set_connection_color(color: Color) -> void:
	connection_line_color = color
	if _connection_material:
		_connection_material.albedo_color = color


## 接続線を構築
func _build_connection_line() -> void:
	# 既存の接続メッシュを削除
	if _connection_mesh:
		_connection_mesh.queue_free()
		_connection_mesh = null

	if _door_position.length_squared() < 0.001:
		return

	# 接続線用のメッシュを作成
	_connection_mesh = MeshInstance3D.new()
	add_child(_connection_mesh)

	var line_mesh = ArrayMesh.new()
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()

	# アンカーからドアへの接続線
	var anchor_local = Vector3.ZERO
	var door_local = _door_position - global_position
	door_local.y = height_offset * 0.5

	var direction = (door_local - anchor_local).normalized()
	var perpendicular = Vector3(-direction.z, 0, direction.x).normalized() * connection_line_width

	# 開始点（円の端から）
	var start_offset = circle_radius + 0.05
	var start_pos = direction * start_offset
	start_pos.y = height_offset * 0.5

	# 終点（ドア少し手前）
	var end_pos = door_local - direction * 0.2

	# 4頂点
	vertices.append(start_pos - perpendicular)
	vertices.append(start_pos + perpendicular)
	vertices.append(end_pos + perpendicular)
	vertices.append(end_pos - perpendicular)

	# 2つの三角形
	indices.append(0)
	indices.append(1)
	indices.append(2)
	indices.append(0)
	indices.append(2)
	indices.append(3)

	# ドア位置にダイヤモンドマーカー
	var diamond_size = 0.15
	var diamond_center = door_local
	diamond_center.y = height_offset

	var v_start = vertices.size()
	vertices.append(diamond_center + Vector3(0, 0, -diamond_size))
	vertices.append(diamond_center + Vector3(diamond_size, 0, 0))
	vertices.append(diamond_center + Vector3(0, 0, diamond_size))
	vertices.append(diamond_center + Vector3(-diamond_size, 0, 0))

	indices.append(v_start)
	indices.append(v_start + 1)
	indices.append(v_start + 2)
	indices.append(v_start)
	indices.append(v_start + 2)
	indices.append(v_start + 3)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	line_mesh.surface_set_material(0, _connection_material)

	_connection_mesh.mesh = line_mesh
	_connection_mesh.position = Vector3.ZERO
