class_name FogOfWarRenderer
extends Node3D

## Fog of War レンダラー
## 視野範囲を3Dで描画し、未探索エリアを暗くする

@export_group("表示設定")
@export var fog_height: float = 5.0  # フォグを描画する高さ（カメラより下）
@export var fog_color_unexplored: Color = Color(0, 0, 0, 0.95)  # 未探索エリアの色
@export var fog_color_explored: Color = Color(0, 0, 0, 0.6)  # 探索済みエリアの色
@export var visible_color: Color = Color(0, 0, 0, 0.0)  # 視野内の色（透明）

@export_group("マップ設定")
@export var map_size: Vector2 = Vector2(100, 100)  # マップサイズ
@export var map_center: Vector3 = Vector3.ZERO  # マップ中心

# メッシュインスタンス
var fog_mesh_instance: MeshInstance3D = null
var visibility_mesh_instance: MeshInstance3D = null

# マテリアル
var fog_material: ShaderMaterial = null
var visibility_material: StandardMaterial3D = null

# 視野ポリゴンデータ
var current_visibility_polygons: Array = []  # Array of Array[Vector3]


func _ready() -> void:
	_setup_fog_layer()
	_setup_visibility_layer()

	# FogOfWarManagerに登録
	if FogOfWarManager:
		FogOfWarManager.set_fog_renderer(self)
		FogOfWarManager.fog_updated.connect(_on_fog_updated)


func _exit_tree() -> void:
	if FogOfWarManager and FogOfWarManager.fog_updated.is_connected(_on_fog_updated):
		FogOfWarManager.fog_updated.disconnect(_on_fog_updated)


## フォグレイヤーをセットアップ（未探索エリア用）
func _setup_fog_layer() -> void:
	fog_mesh_instance = MeshInstance3D.new()
	fog_mesh_instance.name = "FogMesh"
	add_child(fog_mesh_instance)

	# シェーダーマテリアルを作成
	fog_material = ShaderMaterial.new()
	fog_material.shader = _create_fog_shader()
	fog_material.set_shader_parameter("fog_color", fog_color_unexplored)
	fog_material.set_shader_parameter("explored_color", fog_color_explored)

	# 初期メッシュを生成
	_update_fog_mesh()


## 視野レイヤーをセットアップ（動的視野ポリゴン用）
func _setup_visibility_layer() -> void:
	visibility_mesh_instance = MeshInstance3D.new()
	visibility_mesh_instance.name = "VisibilityMesh"
	add_child(visibility_mesh_instance)

	# マテリアルを作成
	visibility_material = StandardMaterial3D.new()
	visibility_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visibility_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visibility_material.albedo_color = visible_color
	visibility_material.cull_mode = BaseMaterial3D.CULL_DISABLED


## フォグシェーダーを作成
func _create_fog_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_disabled;

uniform vec4 fog_color : source_color = vec4(0.0, 0.0, 0.0, 0.95);
uniform vec4 explored_color : source_color = vec4(0.0, 0.0, 0.0, 0.6);
uniform sampler2D explored_texture : hint_default_black;
uniform vec2 map_size = vec2(100.0, 100.0);
uniform vec3 map_center = vec3(0.0, 0.0, 0.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// テクスチャ座標を計算
	vec2 uv = (world_pos.xz - map_center.xz + map_size * 0.5) / map_size;
	uv = clamp(uv, vec2(0.0), vec2(1.0));

	// 探索済みかどうかをテクスチャから取得
	float explored = texture(explored_texture, uv).r;

	// 探索済みなら薄いフォグ、未探索なら濃いフォグ
	vec4 final_color = mix(fog_color, explored_color, explored);

	ALBEDO = final_color.rgb;
	ALPHA = final_color.a;
}
"""
	return shader


## フォグメッシュを更新
func _update_fog_mesh() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = map_size
	mesh.subdivide_width = 1
	mesh.subdivide_depth = 1

	fog_mesh_instance.mesh = mesh
	fog_mesh_instance.material_override = fog_material
	fog_mesh_instance.position = map_center + Vector3(0, fog_height, 0)
	fog_mesh_instance.rotation_degrees = Vector3(0, 0, 0)


## 視野メッシュを更新
func _update_visibility_mesh() -> void:
	if not FogOfWarManager:
		return

	var visible_points := FogOfWarManager.get_current_visible_points()
	if visible_points.size() < 3:
		visibility_mesh_instance.mesh = null
		return

	# 各視野コンポーネントごとにポリゴンを生成
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for component in FogOfWarManager.vision_components:
		if not component or component.visible_points.size() < 3:
			continue

		var points: Array = component.visible_points
		var center: Vector3 = points[0] as Vector3  # 最初のポイントは中心

		# 扇形をトライアングルファンで描画
		for i in range(1, points.size() - 1):
			var p1: Vector3 = points[i] as Vector3
			var p2: Vector3 = points[i + 1] as Vector3

			# 高さを調整
			var c := Vector3(center.x, fog_height + 0.01, center.z)
			var v1 := Vector3(p1.x, fog_height + 0.01, p1.z)
			var v2 := Vector3(p2.x, fog_height + 0.01, p2.z)

			st.add_vertex(c)
			st.add_vertex(v1)
			st.add_vertex(v2)

	st.generate_normals()
	visibility_mesh_instance.mesh = st.commit()
	visibility_mesh_instance.material_override = visibility_material


## フォグが更新されたときのコールバック
func _on_fog_updated() -> void:
	_update_visibility_mesh()
	_update_explored_texture()


## 探索済みテクスチャを更新
func _update_explored_texture() -> void:
	if not FogOfWarManager:
		return

	# テクスチャサイズ（グリッド解像度）
	var tex_size := Vector2i(int(map_size.x), int(map_size.y))

	# Image を作成
	var image := Image.create(tex_size.x, tex_size.y, false, Image.FORMAT_L8)
	image.fill(Color(0, 0, 0))

	# 探索済みセルを白で塗る
	for cell in FogOfWarManager.explored_cells.keys():
		var grid_pos: Vector2i = cell
		# グリッド座標をテクスチャ座標に変換
		var tex_x := int(float(grid_pos.x) - map_center.x / FogOfWarManager.grid_cell_size + float(tex_size.x) / 2.0)
		var tex_y := int(float(grid_pos.y) - map_center.z / FogOfWarManager.grid_cell_size + float(tex_size.y) / 2.0)

		if tex_x >= 0 and tex_x < tex_size.x and tex_y >= 0 and tex_y < tex_size.y:
			image.set_pixel(tex_x, tex_y, Color(1, 1, 1))

	# ImageTexture を作成してシェーダーに設定
	var texture := ImageTexture.create_from_image(image)
	fog_material.set_shader_parameter("explored_texture", texture)


## マップ設定を更新
func set_map_bounds(center: Vector3, size: Vector2) -> void:
	map_center = center
	map_size = size
	_update_fog_mesh()

	# シェーダーパラメータを更新
	fog_material.set_shader_parameter("map_size", map_size)
	fog_material.set_shader_parameter("map_center", map_center)


## デバッグ用：視野ポリゴンを描画
func debug_draw_visibility() -> void:
	# DebugDraw3Dなどがあれば使用
	pass
