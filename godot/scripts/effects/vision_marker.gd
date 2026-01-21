class_name VisionMarker
extends MeshInstance3D

## 視線ポイントマーカー（円形 + 矢印 + ターゲット線）
## パス上の視線ポイント位置に表示され、視線方向を矢印で示す
## ターゲットポイントモードでは、ターゲット地点への線も描画

@export var circle_radius: float = 0.3  ## 円の半径
@export var circle_color: Color = Color(0.1, 0.1, 0.1, 0.95)  ## 円の背景色（暗い色）
@export var arrow_color: Color = Color(1.0, 1.0, 1.0, 1.0)  ## 矢印の色（白）
@export var arrow_thickness: float = 0.04  ## 矢印の太さ
@export var height_offset: float = 0.03  ## 地面からの高さ
@export var segments: int = 32  ## 円のセグメント数
@export var target_line_color: Color = Color(1.0, 0.5, 0.0, 0.8)  ## ターゲット線の色（オレンジ）
@export var target_line_width: float = 0.02  ## ターゲット線の太さ

var _array_mesh: ArrayMesh
var _circle_material: StandardMaterial3D
var _arrow_material: StandardMaterial3D
var _target_line_material: StandardMaterial3D
var _target_point: Vector3 = Vector3.ZERO  ## ターゲット地点（ゼロでない場合ターゲットモード）
var _target_line_mesh: MeshInstance3D = null  ## ターゲット線用メッシュ


func _ready() -> void:
	_setup_mesh()


func _setup_mesh() -> void:
	_array_mesh = ArrayMesh.new()
	mesh = _array_mesh

	# 円のマテリアル
	_circle_material = StandardMaterial3D.new()
	_circle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_circle_material.albedo_color = circle_color
	_circle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_circle_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_circle_material.render_priority = 10  # フォグより上にレンダリング

	# 矢印のマテリアル
	_arrow_material = StandardMaterial3D.new()
	_arrow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arrow_material.albedo_color = arrow_color
	_arrow_material.emission_enabled = true
	_arrow_material.emission = arrow_color
	_arrow_material.emission_energy_multiplier = 1.2
	_arrow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_arrow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_arrow_material.render_priority = 11  # 円より上にレンダリング

	# ターゲット線のマテリアル
	_target_line_material = StandardMaterial3D.new()
	_target_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_target_line_material.albedo_color = target_line_color
	_target_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_target_line_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_target_line_material.render_priority = 9  # 円より下にレンダリング

	_build_mesh()


func _build_mesh() -> void:
	_array_mesh.clear_surfaces()

	# 塗りつぶし円を生成
	_build_filled_circle()

	# 矢印を生成（上向き = +Z方向、後で回転で調整）
	_build_arrow()


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


## 矢印を構築（+Z方向を向く）
func _build_arrow() -> void:
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()

	var arrow_length = circle_radius * 1.4  # 矢印の長さ
	var shaft_length = arrow_length * 0.6  # シャフト部分
	var head_width = circle_radius * 0.4  # 矢印頭の幅
	var head_length = arrow_length * 0.4  # 矢印頭の長さ
	var half_thickness = arrow_thickness / 2.0
	var y_offset = 0.02  # 円より上（Z-fighting防止）

	# シャフト（縦棒）- 中央から上に伸びる
	var shaft_start = -circle_radius * 0.5
	var shaft_end = shaft_start + shaft_length

	# シャフトの4頂点
	vertices.append(Vector3(-half_thickness, y_offset, shaft_start))  # 0: 左下
	vertices.append(Vector3(half_thickness, y_offset, shaft_start))   # 1: 右下
	vertices.append(Vector3(half_thickness, y_offset, shaft_end))     # 2: 右上
	vertices.append(Vector3(-half_thickness, y_offset, shaft_end))    # 3: 左上

	# シャフトの三角形
	indices.append(0)
	indices.append(1)
	indices.append(2)
	indices.append(0)
	indices.append(2)
	indices.append(3)

	# 矢印頭（三角形）
	var head_base = shaft_end - arrow_thickness  # 少し重ねる
	var head_tip = shaft_end + head_length - arrow_thickness

	vertices.append(Vector3(-head_width, y_offset, head_base))  # 4: 左
	vertices.append(Vector3(head_width, y_offset, head_base))   # 5: 右
	vertices.append(Vector3(0, y_offset, head_tip))             # 6: 先端

	# 矢印頭の三角形
	indices.append(4)
	indices.append(5)
	indices.append(6)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_array_mesh.surface_set_material(1, _arrow_material)


## マーカーを配置して方向を設定
## @param anchor: パス上のアンカー位置
## @param direction: 視線方向（正規化済み）
func set_position_and_direction(anchor: Vector3, direction: Vector3) -> void:
	# 位置を設定
	global_position = Vector3(anchor.x, height_offset, anchor.z)

	# 方向を設定（Y軸回転）
	if direction.length_squared() > 0.001:
		var dir_xz = Vector3(direction.x, 0, direction.z).normalized()
		# +Z方向が矢印の向きなので、方向に合わせて回転
		rotation.y = atan2(dir_xz.x, dir_xz.z)


## 色を変更
func set_colors(bg_color: Color, fg_color: Color) -> void:
	circle_color = bg_color
	arrow_color = fg_color
	if _circle_material:
		_circle_material.albedo_color = bg_color
	if _arrow_material:
		_arrow_material.albedo_color = fg_color
		_arrow_material.emission = fg_color


## マーカーを配置してターゲット地点を設定（ターゲットポイントモード）
## @param anchor: パス上のアンカー位置
## @param target: ターゲット地点（キャラクターがここを見続ける）
func set_position_and_target(anchor: Vector3, target: Vector3) -> void:
	_target_point = target

	# 位置を設定
	global_position = Vector3(anchor.x, height_offset, anchor.z)

	# 方向を計算してマーカーを回転
	var direction = (target - anchor)
	direction.y = 0
	if direction.length_squared() > 0.001:
		var dir_xz = direction.normalized()
		rotation.y = atan2(dir_xz.x, dir_xz.z)

	# ターゲットへの線を構築
	_build_line_to_target()


## ターゲット地点を取得
func get_target_point() -> Vector3:
	return _target_point


## ターゲットポイントモードかどうか
func has_target_point() -> bool:
	return _target_point.length_squared() > 0.001


## ターゲットへの線を構築
func _build_line_to_target() -> void:
	# 既存の線メッシュを削除
	if _target_line_mesh:
		_target_line_mesh.queue_free()
		_target_line_mesh = null

	if _target_point.length_squared() < 0.001:
		return

	# ターゲット線用のメッシュを作成
	_target_line_mesh = MeshInstance3D.new()
	add_child(_target_line_mesh)

	var line_mesh = ArrayMesh.new()
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()

	# アンカーからターゲットへの線を作成
	var anchor_local = Vector3.ZERO  # ローカル座標での原点
	var target_local = _target_point - global_position
	target_local.y = height_offset * 0.5  # 少し高めに

	var direction = target_local.normalized()
	var distance = target_local.length()

	# 線を幅のある四角形として描画
	var perpendicular = Vector3(-direction.z, 0, direction.x).normalized() * target_line_width

	# 開始点（円の端から）
	var start_offset = circle_radius + 0.05
	var start_pos = direction * start_offset

	# 終点（ターゲット少し手前）
	var end_pos = target_local - direction * 0.1

	# 4頂点
	vertices.append(start_pos - perpendicular)  # 0: 左下
	vertices.append(start_pos + perpendicular)  # 1: 右下
	vertices.append(end_pos + perpendicular)    # 2: 右上
	vertices.append(end_pos - perpendicular)    # 3: 左上

	# 2つの三角形
	indices.append(0)
	indices.append(1)
	indices.append(2)
	indices.append(0)
	indices.append(2)
	indices.append(3)

	# ターゲット地点にダイヤモンド形のマーカーを追加
	var diamond_size = 0.15
	var diamond_center = target_local
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

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	line_mesh.surface_set_material(0, _target_line_material)

	_target_line_mesh.mesh = line_mesh
	# ローカル座標でのオフセットは不要（親の位置基準）
	_target_line_mesh.position = Vector3.ZERO
	# 回転を打ち消す（親が回転しているため）
	_target_line_mesh.rotation.y = -rotation.y


## ターゲット線の色を設定
func set_target_line_color(color: Color) -> void:
	target_line_color = color
	if _target_line_material:
		_target_line_material.albedo_color = color
