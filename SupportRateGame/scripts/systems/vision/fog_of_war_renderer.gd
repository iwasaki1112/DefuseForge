class_name FogOfWarRenderer
extends Node3D

## Fog of Warレンダラー（3Dワールド空間方式）
## 2つのメッシュを使用：フォグメッシュ + ビジョンメッシュ（減算）
## Door Kickers 2スタイルの実装

@export_group("表示設定")
@export var fog_color: Color = Color(0.1, 0.15, 0.25, 0.9)  # 青みがかった暗い色（90%不透明）
@export var fog_height: float = 0.1  # 地面からの高さ

@export_group("マップ設定")
@export var map_size: Vector2 = Vector2(100, 100)  # マップサイズ
@export var map_center: Vector3 = Vector3.ZERO  # マップ中心

# フォグメッシュ（全面を覆う）
var fog_mesh_instance: MeshInstance3D = null
var fog_material: StandardMaterial3D = null

# ビジョンメッシュ（視野エリアをくり抜く）
var vision_mesh_instance: MeshInstance3D = null
var vision_material: StandardMaterial3D = null

# dirtyフラグ
var _dirty: bool = true


func _ready() -> void:
	# ビジョンマテリアルを作成（透明だが深度に書き込む - 先に描画）
	vision_material = StandardMaterial3D.new()
	vision_material.albedo_color = Color(0, 0, 0, 0)  # 完全透明
	vision_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	vision_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vision_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	vision_material.render_priority = -1  # フォグより先に描画
	vision_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS

	# フォグマテリアルを作成（深度テストでビジョン部分を避ける）
	fog_material = StandardMaterial3D.new()
	fog_material.albedo_color = fog_color
	fog_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fog_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fog_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	fog_material.render_priority = 10

	# ビジョンメッシュインスタンスを作成（先に描画）
	vision_mesh_instance = MeshInstance3D.new()
	vision_mesh_instance.name = "VisionMesh"
	vision_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(vision_mesh_instance)

	# フォグメッシュインスタンスを作成（後に描画）
	fog_mesh_instance = MeshInstance3D.new()
	fog_mesh_instance.name = "FogMesh"
	fog_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fog_mesh_instance)

	# FogOfWarManagerに登録
	var fow = _get_fog_of_war_manager()
	if fow:
		fow.set_fog_renderer(self)
		fow.fog_updated.connect(_on_fog_updated)

	# 初期メッシュを構築
	_rebuild_meshes()


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_rebuild_meshes()


func _exit_tree() -> void:
	var fow = _get_fog_of_war_manager()
	if fow and fow.fog_updated.is_connected(_on_fog_updated):
		fow.fog_updated.disconnect(_on_fog_updated)


## FogOfWarManagerへの参照を取得
func _get_fog_of_war_manager() -> Node:
	return GameManager.fog_of_war_manager if GameManager else null


## メッシュを再構築
func _rebuild_meshes() -> void:
	# フォグメッシュは常に全面
	_build_fog_mesh()

	# ビジョンメッシュを構築
	var fow = _get_fog_of_war_manager()
	if not fow:
		vision_mesh_instance.mesh = null
		return

	# 視野ポリゴンを収集
	var vision_polygons: Array = []
	for component in fow.vision_components:
		if not component or component.visible_points.size() < 3:
			continue

		var polygon_2d := PackedVector2Array()
		for point_3d in component.visible_points:
			polygon_2d.append(Vector2(point_3d.x, point_3d.z))

		if polygon_2d.size() >= 3:
			vision_polygons.append(polygon_2d)

	if vision_polygons.is_empty():
		vision_mesh_instance.mesh = null
		return

	_build_vision_mesh(vision_polygons)


## フォグメッシュを構築（全面）
func _build_fog_mesh() -> void:
	var half_x := map_size.x / 2.0
	var half_z := map_size.y / 2.0
	var y := fog_height

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(fog_material)

	# 四角形を2つの三角形で構築
	var v0 := Vector3(map_center.x - half_x, y, map_center.z - half_z)
	var v1 := Vector3(map_center.x + half_x, y, map_center.z - half_z)
	var v2 := Vector3(map_center.x + half_x, y, map_center.z + half_z)
	var v3 := Vector3(map_center.x - half_x, y, map_center.z + half_z)

	# 三角形1
	st.add_vertex(v0)
	st.add_vertex(v1)
	st.add_vertex(v2)

	# 三角形2
	st.add_vertex(v0)
	st.add_vertex(v2)
	st.add_vertex(v3)

	fog_mesh_instance.mesh = st.commit()


## ビジョンメッシュを構築（視野エリア）
func _build_vision_mesh(vision_polygons: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(vision_material)

	var y := fog_height + 0.05  # フォグより上（深度テスト用）
	var vertex_count := 0

	for poly in vision_polygons:
		if poly.size() < 3:
			continue

		# ポリゴンを三角形分割
		var indices := Geometry2D.triangulate_polygon(poly)
		if indices.is_empty():
			continue

		for idx in indices:
			if idx < poly.size():
				var p2d: Vector2 = poly[idx]
				st.add_vertex(Vector3(p2d.x, y, p2d.y))
				vertex_count += 1

	if vertex_count >= 3:
		vision_mesh_instance.mesh = st.commit()
	else:
		vision_mesh_instance.mesh = null


## フォグが更新されたときのコールバック
func _on_fog_updated() -> void:
	_dirty = true


## マップ設定を更新
func set_map_bounds(center: Vector3, size: Vector2) -> void:
	map_center = center
	map_size = size
	_dirty = true
