class_name FogOfWarRenderer
extends Node3D

## 視野範囲レンダラー（深度ベースポストプロセス方式）
## 深度バッファからワールド座標を復元し、視野テクスチャを参照

@export_group("マップ設定")
@export var map_center: Vector3 = Vector3.ZERO
@export var map_size: Vector2 = Vector2(80.0, 80.0)

@export_group("フォグ設定")
@export var fog_brightness: float = 0.3
@export var blur_radius: float = 2.0

# ポストプロセス用MeshInstance3D（フルスクリーンクワッド）
var post_process_mesh: MeshInstance3D = null
var fog_material: ShaderMaterial = null

# 視野テクスチャ用SubViewport（ワールド空間でレンダリング）
var visibility_viewport: SubViewport = null
var visibility_canvas: Node2D = null

# テクスチャ解像度
const VISIBILITY_TEXTURE_SIZE: int = 512


func _ready() -> void:
	_setup_visibility_viewport()
	_setup_post_process()

	# FogOfWarManagerに登録
	var fow := _get_fog_of_war_manager()
	if fow:
		fow.set_fog_renderer(self)


func _process(_delta: float) -> void:
	# 毎フレーム視野テクスチャを更新
	_update_visibility_texture()


func _get_fog_of_war_manager() -> Node:
	return GameManager.fog_of_war_manager if GameManager else null


## 視野テクスチャ用SubViewportをセットアップ（ワールド空間座標）
func _setup_visibility_viewport() -> void:
	var container := SubViewportContainer.new()
	container.name = "VisibilityViewportContainer"
	container.visible = false
	add_child(container)

	visibility_viewport = SubViewport.new()
	visibility_viewport.name = "VisibilityViewport"
	visibility_viewport.size = Vector2i(VISIBILITY_TEXTURE_SIZE, VISIBILITY_TEXTURE_SIZE)
	visibility_viewport.transparent_bg = true
	visibility_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	visibility_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	container.add_child(visibility_viewport)

	visibility_canvas = Node2D.new()
	visibility_canvas.name = "VisibilityCanvas"
	visibility_viewport.add_child(visibility_canvas)


## ポストプロセスをセットアップ（フルスクリーン空間シェーダー）
func _setup_post_process() -> void:
	post_process_mesh = MeshInstance3D.new()
	post_process_mesh.name = "FogPostProcess"

	# シンプルなクワッドメッシュを作成
	# vertex()で POSITION = vec4(VERTEX.xy, 1.0, 1.0) とするので座標は-1〜1
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	post_process_mesh.mesh = quad

	# シェーダーマテリアルを設定
	fog_material = ShaderMaterial.new()
	var shader := load("res://resources/shaders/fog_of_war_post.gdshader") as Shader
	if shader:
		fog_material.shader = shader
		_update_shader_parameters()
	else:
		push_error("FogOfWarRenderer: シェーダー読み込み失敗")
		return

	post_process_mesh.material_override = fog_material
	post_process_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# フラスタムカリングを無効化（カメラがどこにあっても常に表示）
	post_process_mesh.extra_cull_margin = 10000.0
	# カスタムAABBを設定して常に描画
	post_process_mesh.custom_aabb = AABB(Vector3(-10000, -10000, -10000), Vector3(20000, 20000, 20000))

	# レンダリング優先度を低く設定（他のオブジェクトより先に描画）
	fog_material.render_priority = -100

	# カメラの子にする必要はない - シェーダーがフルスクリーンにする
	add_child(post_process_mesh)


## シェーダーパラメータを更新
func _update_shader_parameters() -> void:
	if not fog_material:
		return

	var half_size := map_size / 2.0
	var map_min := Vector2(map_center.x - half_size.x, map_center.z - half_size.y)
	var map_max := Vector2(map_center.x + half_size.x, map_center.z + half_size.y)

	fog_material.set_shader_parameter("map_min", map_min)
	fog_material.set_shader_parameter("map_max", map_max)
	fog_material.set_shader_parameter("fog_brightness", fog_brightness)
	fog_material.set_shader_parameter("blur_radius", blur_radius)


## 視野テクスチャを更新（ワールド座標をテクスチャ座標に変換）
func _update_visibility_texture() -> void:
	if not visibility_canvas or not visibility_viewport:
		return

	var fow := _get_fog_of_war_manager()
	if not fow:
		return

	# 古いポリゴンを削除
	for child in visibility_canvas.get_children():
		child.queue_free()

	# マップ境界
	var half_size := map_size / 2.0
	var map_min := Vector2(map_center.x - half_size.x, map_center.z - half_size.y)
	var map_max := Vector2(map_center.x + half_size.x, map_center.z + half_size.y)

	# 各視野コンポーネントのポリゴンをテクスチャ座標で描画
	for component in fow.vision_components:
		if not component or component.visible_points.size() < 3:
			continue
		_draw_vision_polygon_world_space(component.visible_points, map_min, map_max)

	# テクスチャをシェーダーに設定
	if fog_material and visibility_viewport:
		fog_material.set_shader_parameter("visibility_mask", visibility_viewport.get_texture())


## 視野ポリゴンをワールド座標からテクスチャ座標に変換して描画
func _draw_vision_polygon_world_space(points: Array, map_min: Vector2, map_max: Vector2) -> void:
	var texture_points := PackedVector2Array()
	var map_range := map_max - map_min

	for point in points:
		var world_pos := point as Vector3

		# ワールドXZ座標をテクスチャUV（0-1）に変換
		var uv := Vector2(
			(world_pos.x - map_min.x) / map_range.x,
			(world_pos.z - map_min.y) / map_range.y
		)

		# UVをピクセル座標に変換
		var pixel_pos := uv * Vector2(VISIBILITY_TEXTURE_SIZE, VISIBILITY_TEXTURE_SIZE)
		texture_points.append(pixel_pos)

	if texture_points.size() >= 3:
		var polygon := Polygon2D.new()
		polygon.polygon = texture_points
		polygon.color = Color.WHITE
		visibility_canvas.add_child(polygon)


## マップ境界を設定
func set_map_bounds(center: Vector3, size: Vector2) -> void:
	map_center = center
	map_size = size
	_update_shader_parameters()
