class_name FogOfWarRenderer
extends Node3D

## Fog of Warレンダラー（テクスチャベース方式）
## グリッドベースの可視性テクスチャを使用し、シェーダーでテンポラル補間
## Unreal Engine記事を参考: https://minmax.itch.io/operators/devlog/222177/rendering-grid-based-fog-of-war-in-unreal-engine-4-part-1

const VisibilityTextureWriterClass = preload("res://scripts/systems/vision/visibility_texture_writer.gd")

@export_group("表示設定")
@export var fog_color: Color = Color(0.1, 0.15, 0.25, 0.9)  # 青みがかった暗い色
@export var fog_height: float = 0.1  # 地面からの高さ

@export_group("マップ設定")
@export var map_size: Vector2 = Vector2(100, 100)  # マップサイズ
@export var map_center: Vector3 = Vector3.ZERO  # マップ中心

@export_group("テクスチャ設定")
@export var grid_resolution: Vector2i = Vector2i(128, 128)  # グリッド解像度
@export var temporal_blend: float = 0.4  # テンポラル補間係数（0-1）
@export var edge_sharpness: float = 0.5  # エッジのシャープさ（0=ソフト、1=ハード）
@export var update_interval: float = 0.05  # 更新間隔（秒）- 0.05 = 20fps

var _update_timer: float = 0.0

# フォグメッシュ
var fog_mesh_instance: MeshInstance3D = null
var fog_shader_material: ShaderMaterial = null

# 可視性テクスチャライター
var visibility_writer = null  # VisibilityTextureWriter


func _ready() -> void:
	# 可視性テクスチャライターを初期化
	visibility_writer = VisibilityTextureWriterClass.new(grid_resolution)
	_update_map_bounds()

	# シェーダーをロード
	var shader := load("res://shaders/fog_of_war.gdshader") as Shader
	if not shader:
		push_error("[FogOfWarRenderer] Failed to load fog_of_war.gdshader")
		return

	# シェーダーマテリアルを作成
	fog_shader_material = ShaderMaterial.new()
	fog_shader_material.shader = shader
	fog_shader_material.set_shader_parameter("fog_color", fog_color)
	fog_shader_material.set_shader_parameter("temporal_blend", temporal_blend)
	fog_shader_material.set_shader_parameter("edge_sharpness", edge_sharpness)
	_update_shader_map_bounds()

	# フォグメッシュを作成
	fog_mesh_instance = MeshInstance3D.new()
	fog_mesh_instance.name = "FogMesh"
	fog_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fog_mesh_instance)

	# メッシュを構築
	_build_fog_mesh()

	# FogOfWarManagerに登録
	var fow = _get_fog_of_war_manager()
	if fow:
		fow.set_fog_renderer(self)
		fow.fog_updated.connect(_on_fog_updated)


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= update_interval:
		_update_timer = 0.0
		# 可視性テクスチャを更新
		if visibility_writer:
			visibility_writer.update_visibility()
			_update_shader_textures()


func _exit_tree() -> void:
	var fow = _get_fog_of_war_manager()
	if fow and fow.fog_updated.is_connected(_on_fog_updated):
		fow.fog_updated.disconnect(_on_fog_updated)


## FogOfWarManagerへの参照を取得
func _get_fog_of_war_manager() -> Node:
	return GameManager.fog_of_war_manager if GameManager else null


## シェーダーのテクスチャを更新
func _update_shader_textures() -> void:
	if fog_shader_material and visibility_writer:
		fog_shader_material.set_shader_parameter("visibility_texture", visibility_writer.current_texture)
		fog_shader_material.set_shader_parameter("prev_visibility_texture", visibility_writer.previous_texture)


## シェーダーのマップ範囲を更新
func _update_shader_map_bounds() -> void:
	if fog_shader_material:
		var half_size := map_size / 2.0
		var map_min := Vector2(map_center.x - half_size.x, map_center.z - half_size.y)
		var map_max := Vector2(map_center.x + half_size.x, map_center.z + half_size.y)
		fog_shader_material.set_shader_parameter("map_min", map_min)
		fog_shader_material.set_shader_parameter("map_max", map_max)


## 可視性ライターのマップ範囲を更新
func _update_map_bounds() -> void:
	if visibility_writer:
		var half_size := map_size / 2.0
		var map_min := Vector2(map_center.x - half_size.x, map_center.z - half_size.y)
		var map_max := Vector2(map_center.x + half_size.x, map_center.z + half_size.y)
		visibility_writer.set_map_bounds(map_min, map_max)


## フォグメッシュを構築（マップ全体を覆う平面）
func _build_fog_mesh() -> void:
	var half_x := map_size.x / 2.0
	var half_z := map_size.y / 2.0
	var y := fog_height

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(fog_shader_material)

	# 四角形を2つの三角形で構築
	var v0 := Vector3(map_center.x - half_x, y, map_center.z - half_z)
	var v1 := Vector3(map_center.x + half_x, y, map_center.z - half_z)
	var v2 := Vector3(map_center.x + half_x, y, map_center.z + half_z)
	var v3 := Vector3(map_center.x - half_x, y, map_center.z + half_z)

	# UV座標も追加（シェーダーでワールド座標から計算するので不要だが念のため）
	st.set_uv(Vector2(0, 0))
	st.add_vertex(v0)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(v1)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(v2)

	st.set_uv(Vector2(0, 0))
	st.add_vertex(v0)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(v2)
	st.set_uv(Vector2(0, 1))
	st.add_vertex(v3)

	fog_mesh_instance.mesh = st.commit()


## フォグが更新されたときのコールバック
func _on_fog_updated() -> void:
	# テクスチャ更新は_processで行う
	pass


## VisionComponentを登録
func register_vision_component(component: Node) -> void:
	if visibility_writer:
		visibility_writer.register_vision_component(component)


## VisionComponentを解除
func unregister_vision_component(component: Node) -> void:
	if visibility_writer:
		visibility_writer.unregister_vision_component(component)


## マップ設定を更新
func set_map_bounds(center: Vector3, size: Vector2) -> void:
	map_center = center
	map_size = size
	_update_map_bounds()
	_update_shader_map_bounds()
	_build_fog_mesh()


## テンポラル補間係数を設定
func set_temporal_blend(blend: float) -> void:
	temporal_blend = clampf(blend, 0.0, 1.0)
	if fog_shader_material:
		fog_shader_material.set_shader_parameter("temporal_blend", temporal_blend)


## フォグの色を設定
func set_fog_color(color: Color) -> void:
	fog_color = color
	if fog_shader_material:
		fog_shader_material.set_shader_parameter("fog_color", fog_color)


## エッジのシャープさを設定
func set_edge_sharpness(sharpness: float) -> void:
	edge_sharpness = clampf(sharpness, 0.0, 1.0)
	if fog_shader_material:
		fog_shader_material.set_shader_parameter("edge_sharpness", edge_sharpness)
