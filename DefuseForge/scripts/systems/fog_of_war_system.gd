class_name FogOfWarSystem
extends Node3D

## Fog of War システム（SubViewportテクスチャ方式）
## 可視領域を小さなテクスチャに描画し、それをサンプリングして可視性を決定
## 安定性とパフォーマンスのバランスが良い

## 設定
@export_group("Map Settings")
@export var map_size: Vector2 = Vector2(40, 40)
@export var fog_height: float = 0.1

@export_group("Visual Settings")
@export var fog_color: Color = Color(0.1, 0.15, 0.25, 0.85)
@export var texture_resolution: int = 512  # 可視性テクスチャ解像度（高いほど滑らか）

## 内部
var _fog_mesh: MeshInstance3D
var _fog_material: ShaderMaterial
var _visibility_viewport: SubViewport
var _visibility_polygon: Polygon2D

## 視界データ
var _vision_components: Array = []


func _ready() -> void:
	_setup_visibility_viewport()
	_setup_fog_mesh()


func _setup_visibility_viewport() -> void:
	# SubViewport作成（可視性テクスチャ用）
	_visibility_viewport = SubViewport.new()
	_visibility_viewport.name = "VisibilityViewport"
	_visibility_viewport.size = Vector2i(texture_resolution, texture_resolution)
	_visibility_viewport.transparent_bg = true
	_visibility_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_visibility_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_visibility_viewport.msaa_2d = SubViewport.MSAA_4X  # アンチエイリアス
	add_child(_visibility_viewport)

	# 背景（不可視領域 = 黒）
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.size = Vector2(texture_resolution, texture_resolution)
	_visibility_viewport.add_child(bg)

	# 可視領域ポリゴン（白）
	_visibility_polygon = Polygon2D.new()
	_visibility_polygon.color = Color(1, 1, 1, 1)
	_visibility_polygon.antialiased = true  # アンチエイリアス
	_visibility_viewport.add_child(_visibility_polygon)


func _setup_fog_mesh() -> void:
	_fog_mesh = MeshInstance3D.new()
	_fog_mesh.name = "FogMesh"

	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = map_size
	_fog_mesh.mesh = plane_mesh
	_fog_mesh.position.y = fog_height

	# テクスチャサンプリングシェーダー
	var shader_code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 fog_color : source_color = vec4(0.1, 0.15, 0.25, 0.85);
uniform sampler2D visibility_texture : filter_linear, hint_default_black;
uniform vec2 map_min;
uniform vec2 map_max;
uniform float edge_smoothness = 0.1;  // エッジの滑らかさ

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 world_xz = world_pos.xz;

	// ワールド座標をUV座標に変換
	vec2 uv = (world_xz - map_min) / (map_max - map_min);

	// テクスチャから可視性を取得
	float raw_visibility = texture(visibility_texture, uv).r;

	// エッジをスムーズに
	float visibility = smoothstep(0.5 - edge_smoothness, 0.5 + edge_smoothness, raw_visibility);

	ALBEDO = fog_color.rgb;
	ALPHA = fog_color.a * (1.0 - visibility);
}
"""
	var shader = Shader.new()
	shader.code = shader_code

	_fog_material = ShaderMaterial.new()
	_fog_material.shader = shader
	_fog_material.set_shader_parameter("fog_color", fog_color)
	_fog_material.set_shader_parameter("map_min", Vector2(-map_size.x / 2, -map_size.y / 2))
	_fog_material.set_shader_parameter("map_max", Vector2(map_size.x / 2, map_size.y / 2))

	_fog_mesh.material_override = _fog_material
	add_child(_fog_mesh)


func _process(_delta: float) -> void:
	_update_visibility_texture()
	# テクスチャをシェーダーに渡す
	if _visibility_viewport:
		_fog_material.set_shader_parameter("visibility_texture", _visibility_viewport.get_texture())


func _update_visibility_texture() -> void:
	if _vision_components.is_empty():
		_visibility_polygon.polygon = PackedVector2Array()
		return

	# 最初のVisionComponentのポリゴンを使用
	var vision = _vision_components[0]
	if not is_instance_valid(vision):
		return

	var polygon_3d = vision.get_visible_polygon()
	if polygon_3d.size() < 3:
		_visibility_polygon.polygon = PackedVector2Array()
		return

	# 3Dポリゴンを2Dテクスチャ座標に変換
	var polygon_2d = PackedVector2Array()
	var half_map = map_size / 2

	for point in polygon_3d:
		# ワールドXZ → テクスチャUV → ピクセル座標
		var uv_x = (point.x + half_map.x) / map_size.x
		var uv_y = (point.z + half_map.y) / map_size.y
		polygon_2d.append(Vector2(uv_x * texture_resolution, uv_y * texture_resolution))

	_visibility_polygon.polygon = polygon_2d


## VisionComponentを登録
func register_vision(vision) -> void:
	if vision and vision not in _vision_components:
		_vision_components.append(vision)


## VisionComponentを解除
func unregister_vision(vision) -> void:
	_vision_components.erase(vision)


## フォグの表示/非表示
func set_fog_visible(fog_visible: bool) -> void:
	if _fog_mesh:
		_fog_mesh.visible = fog_visible


## フォグの色を設定
func set_fog_color(color: Color) -> void:
	fog_color = color
	if _fog_material:
		_fog_material.set_shader_parameter("fog_color", fog_color)


## 可視性テクスチャを取得（壁の照明などに使用）
func get_visibility_texture() -> ViewportTexture:
	if _visibility_viewport:
		return _visibility_viewport.get_texture()
	return null
