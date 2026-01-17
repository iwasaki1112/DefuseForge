class_name FogOfWarSystem
extends Node3D

## Fog of War システム（SubViewportテクスチャ方式）
## 可視領域を小さなテクスチャに描画し、それをサンプリングして可視性を決定
## 安定性とパフォーマンスのバランスが良い

## 品質設定
enum Quality { LOW, MEDIUM, HIGH }
const QUALITY_SETTINGS := {
	Quality.LOW: { "resolution": 512, "msaa": SubViewport.MSAA_DISABLED },    # モバイル向け
	Quality.MEDIUM: { "resolution": 1024, "msaa": SubViewport.MSAA_2X },       # バランス
	Quality.HIGH: { "resolution": 2048, "msaa": SubViewport.MSAA_4X },         # PC向け
}

## 設定
@export_group("Map Settings")
@export var map_size: Vector2 = Vector2(40, 40)
@export var fog_height: float = 0.02

@export_group("Visual Settings")
@export var fog_color: Color = Color(0.1, 0.15, 0.25, 0.85)
@export var quality: Quality = Quality.LOW  # モバイル最適化: メモリ94%削減

## 内部（品質設定から自動設定）
var texture_resolution: int = 2048

## 内部
var _fog_mesh: MeshInstance3D
var _fog_material: ShaderMaterial
var _visibility_viewport: SubViewport
var _visibility_polygons: Array[Polygon2D] = []  # 複数視界用ポリゴン配列

## 視界データ
var _vision_components: Array = []
var _needs_update: bool = false  # dirty flag: 視界が変更されたときのみtrue


func _ready() -> void:
	_apply_quality_settings()
	_setup_visibility_viewport()
	_setup_fog_mesh()


## 品質設定を適用
func _apply_quality_settings() -> void:
	var settings: Dictionary = QUALITY_SETTINGS[quality]
	texture_resolution = settings["resolution"]


func _setup_visibility_viewport() -> void:
	var settings: Dictionary = QUALITY_SETTINGS[quality]

	# SubViewport作成（可視性テクスチャ用）
	_visibility_viewport = SubViewport.new()
	_visibility_viewport.name = "VisibilityViewport"
	_visibility_viewport.size = Vector2i(texture_resolution, texture_resolution)
	_visibility_viewport.transparent_bg = true
	_visibility_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE  # 手動更新（シグナル駆動）
	_visibility_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_visibility_viewport.msaa_2d = settings["msaa"]  # 品質に応じたアンチエイリアス
	add_child(_visibility_viewport)

	# 背景（不可視領域 = 黒）
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.size = Vector2(texture_resolution, texture_resolution)
	_visibility_viewport.add_child(bg)
	# 可視領域ポリゴンは動的に作成（_sync_polygon_count で管理）


func _setup_fog_mesh() -> void:
	_fog_mesh = MeshInstance3D.new()
	_fog_mesh.name = "FogMesh"

	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = map_size
	_fog_mesh.mesh = plane_mesh
	_fog_mesh.position.y = fog_height

	# テクスチャサンプリングシェーダー（Gaussian blur付き）
	var shader_code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 fog_color : source_color = vec4(0.1, 0.15, 0.25, 0.85);
uniform sampler2D visibility_texture : filter_linear, hint_default_black;
uniform vec2 map_min;
uniform vec2 map_max;
uniform float texture_size = 2048.0;  // テクスチャ解像度

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 world_xz = world_pos.xz;

	// ワールド座標をUV座標に変換
	vec2 uv = (world_xz - map_min) / (map_max - map_min);

	// 3x3 Gaussian blur でエッジを滑らかに
	vec2 texel = 1.0 / vec2(texture_size);
	float weights[9] = float[](
		0.077847, 0.123317, 0.077847,
		0.123317, 0.195346, 0.123317,
		0.077847, 0.123317, 0.077847
	);

	float blurred = 0.0;
	int idx = 0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			blurred += texture(visibility_texture, uv + vec2(float(x), float(y)) * texel).r * weights[idx];
			idx++;
		}
	}

	// smoothstep で自然なグラデーション (0.45〜0.55)
	float visibility = smoothstep(0.45, 0.55, blurred);

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
	_fog_material.set_shader_parameter("texture_size", float(texture_resolution))

	_fog_mesh.material_override = _fog_material
	add_child(_fog_mesh)


var _pending_render_frames: int = 0

func _process(_delta: float) -> void:
	# 保留中のレンダリングフレームがある場合は再レンダリング
	if _pending_render_frames > 0:
		_pending_render_frames -= 1
		if _visibility_viewport:
			_visibility_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			_fog_material.set_shader_parameter("visibility_texture", _visibility_viewport.get_texture())
		return

	# dirty flagがtrueのときのみ更新（シグナル駆動）
	if not _needs_update:
		return

	_update_visibility_texture()
	_needs_update = false

	# SubViewportを手動で再レンダリング要求（2フレーム連続でレンダリング）
	if _visibility_viewport:
		_visibility_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_fog_material.set_shader_parameter("visibility_texture", _visibility_viewport.get_texture())
		_pending_render_frames = 2  # 追加で2フレームレンダリング


func _update_visibility_texture() -> void:
	_sync_polygon_count()

	if _vision_components.is_empty():
		return

	# 各VisionComponentのポリゴンを描画
	for i in range(_vision_components.size()):
		var vision = _vision_components[i]
		if not is_instance_valid(vision):
			_visibility_polygons[i].polygon = PackedVector2Array()
			continue

		var polygon_3d = vision.get_visible_polygon()
		_visibility_polygons[i].polygon = _convert_polygon_to_2d(polygon_3d)


## ポリゴン数をVisionComponent数に同期
func _sync_polygon_count() -> void:
	# 不足分を追加
	while _visibility_polygons.size() < _vision_components.size():
		var polygon = Polygon2D.new()
		polygon.color = Color(1, 1, 1, 1)
		polygon.antialiased = true
		_visibility_viewport.add_child(polygon)
		_visibility_polygons.append(polygon)

	# 余剰分はクリアして非表示にする（削除しない）
	for i in range(_vision_components.size(), _visibility_polygons.size()):
		_visibility_polygons[i].polygon = PackedVector2Array()


## 3Dポリゴンを2Dテクスチャ座標に変換
func _convert_polygon_to_2d(polygon_3d: PackedVector3Array) -> PackedVector2Array:
	if polygon_3d.size() < 3:
		return PackedVector2Array()

	var polygon_2d = PackedVector2Array()
	var half_map = map_size / 2

	for point in polygon_3d:
		# ワールドXZ → テクスチャUV → ピクセル座標
		var uv_x = (point.x + half_map.x) / map_size.x
		var uv_y = (point.z + half_map.y) / map_size.y
		polygon_2d.append(Vector2(uv_x * texture_resolution, uv_y * texture_resolution))

	return polygon_2d


## VisionComponentを登録
func register_vision(vision) -> void:
	if vision and vision not in _vision_components:
		_vision_components.append(vision)
		# シグナル接続（視界更新時に通知を受ける）
		if vision.has_signal("vision_updated"):
			if not vision.vision_updated.is_connected(_on_vision_updated):
				vision.vision_updated.connect(_on_vision_updated)
		_needs_update = true


## VisionComponentを解除
func unregister_vision(vision) -> void:
	if vision in _vision_components:
		# シグナル切断
		if vision.has_signal("vision_updated") and vision.vision_updated.is_connected(_on_vision_updated):
			vision.vision_updated.disconnect(_on_vision_updated)
		_vision_components.erase(vision)
		_needs_update = true


## VisionComponentからの更新通知ハンドラ
func _on_vision_updated(_visible_points: PackedVector3Array) -> void:
	_needs_update = true


## フォグの表示/非表示
func set_fog_visible(fog_visible: bool) -> void:
	if _fog_mesh:
		_fog_mesh.visible = fog_visible


## 強制的に可視性テクスチャを更新
func force_update() -> void:
	_needs_update = true


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
