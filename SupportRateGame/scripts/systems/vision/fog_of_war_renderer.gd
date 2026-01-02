class_name FogOfWarRenderer
extends Node3D

## Fog of Warレンダラー（グリッドベース版）
## GridManagerと連携し、グリッドセル単位で可視性を管理
## シェーダーでテンポラル補間を行いスムーズな表示を実現

const VisibilityTextureWriterClass = preload("res://scripts/systems/vision/visibility_texture_writer.gd")
const VisibilityGridSyncClass = preload("res://scripts/systems/vision/visibility_grid_sync.gd")

@export_group("表示設定")
@export var fog_color: Color = Color(0.1, 0.15, 0.25, 0.9)  # 青みがかった暗い色
@export var fog_height: float = 0.02  # 地面からの高さ（Z-fighting対策で低く設定）

@export_group("テクスチャ設定")
## テンポラル補間係数（0-1）
## 1.0 = 補間なし（グリッド単位で即座に反映）
## 0.5以下 = 滑らかな遷移（パフォーマンス優先時に使用）
@export var temporal_blend: float = 1.0
@export var update_interval: float = 0.05  # 更新間隔（秒）- 0.05 = 20fps

var _update_timer: float = 0.0

# GridManager参照
var _grid_manager: Node = null

# グリッド設定（GridManagerから取得）
var grid_resolution: Vector2i = Vector2i(32, 32)
var map_min: Vector2 = Vector2.ZERO
var map_max: Vector2 = Vector2(32, 32)
var map_center: Vector3 = Vector3.ZERO
var map_size: Vector2 = Vector2(32, 32)

# フォグメッシュ
var fog_mesh_instance: MeshInstance3D = null
var fog_shader_material: ShaderMaterial = null

# 可視性テクスチャライター
var visibility_writer = null  # VisibilityTextureWriter

# 初期化済みフラグ
var _initialized: bool = false


func _ready() -> void:
	# GridManagerの初期化を待つ
	_deferred_init.call_deferred()


func _deferred_init() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	# GridManagerへの参照を取得
	_grid_manager = _get_grid_manager()
	if not _grid_manager:
		push_error("[FogOfWarRenderer] GridManager not found")
		return

	# GridManagerから設定を取得
	_sync_with_grid_manager()

	# 可視性テクスチャライターを初期化
	visibility_writer = VisibilityTextureWriterClass.new(grid_resolution, _grid_manager)

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

	_initialized = true
	print("[FogOfWarRenderer] Initialized with grid %dx%d" % [grid_resolution.x, grid_resolution.y])


func _process(delta: float) -> void:
	if not _initialized:
		return

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


## GridManagerへの参照を取得
func _get_grid_manager() -> Node:
	return GameManager.grid_manager if GameManager else null


## FogOfWarManagerへの参照を取得
func _get_fog_of_war_manager() -> Node:
	return GameManager.fog_of_war_manager if GameManager else null


## GridManagerから設定を同期
func _sync_with_grid_manager() -> void:
	if not _grid_manager:
		return

	grid_resolution = Vector2i(_grid_manager.grid_width, _grid_manager.grid_height)
	var cell_size: float = _grid_manager.cell_size
	var origin: Vector3 = _grid_manager.grid_origin

	map_size = Vector2(
		float(_grid_manager.grid_width) * cell_size,
		float(_grid_manager.grid_height) * cell_size
	)

	map_center = Vector3(
		origin.x + map_size.x / 2.0,
		origin.y,
		origin.z + map_size.y / 2.0
	)

	map_min = Vector2(origin.x, origin.z)
	map_max = Vector2(origin.x + map_size.x, origin.z + map_size.y)


## シェーダーのテクスチャを更新
func _update_shader_textures() -> void:
	if fog_shader_material and visibility_writer:
		fog_shader_material.set_shader_parameter("visibility_texture", visibility_writer.current_texture)
		fog_shader_material.set_shader_parameter("prev_visibility_texture", visibility_writer.previous_texture)


## シェーダーのマップ範囲を更新
func _update_shader_map_bounds() -> void:
	if fog_shader_material:
		fog_shader_material.set_shader_parameter("map_min", map_min)
		fog_shader_material.set_shader_parameter("map_max", map_max)


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


# =============================================================================
# ネットワーク同期API
# =============================================================================

## VisibilityGridSyncを取得（直接アクセス用）
func get_grid_sync():  # -> VisibilityGridSync
	if visibility_writer:
		return visibility_writer.grid_sync
	return null


## 差分データを取得（サーバー→クライアント送信用）
## 戻り値: RLE圧縮された差分バイト配列
func get_visibility_diff() -> PackedByteArray:
	var grid_sync = get_grid_sync()
	if grid_sync:
		return grid_sync.get_diff_data()
	return PackedByteArray()


## フルデータを取得（初期同期用）
## 戻り値: RLE圧縮されたビットマップ
func get_visibility_full() -> PackedByteArray:
	var grid_sync = get_grid_sync()
	if grid_sync:
		return grid_sync.get_full_data()
	return PackedByteArray()


## 差分データを適用（クライアント側）
func apply_visibility_diff(compressed_diff: PackedByteArray) -> void:
	var grid_sync = get_grid_sync()
	if grid_sync:
		grid_sync.apply_diff_data(compressed_diff)


## フルデータを適用（初期同期用、クライアント側）
func apply_visibility_full(compressed_data: PackedByteArray) -> void:
	var grid_sync = get_grid_sync()
	if grid_sync:
		grid_sync.apply_full_data(compressed_data)


## 敵位置をフィルタリング（チート対策）
## 視界外の敵位置を隠す
## enemies: Dictionary { enemy_id: Vector3 }
## 戻り値: Dictionary { enemy_id: Vector3 or null }
func filter_enemy_positions(enemies: Dictionary) -> Dictionary:
	var grid_sync = get_grid_sync()
	if grid_sync:
		return grid_sync.filter_enemy_positions(enemies)
	return enemies


## 指定位置が可視かどうか（高速版）
## ビットマップを直接参照するため、ポリゴン判定より高速
func is_position_visible_fast(world_pos: Vector3) -> bool:
	var grid_sync = get_grid_sync()
	if grid_sync:
		return grid_sync.is_position_visible(world_pos)
	return false


## 同期統計を取得（デバッグ用）
func get_sync_stats() -> Dictionary:
	var grid_sync = get_grid_sync()
	if grid_sync:
		return grid_sync.get_sync_stats()
	return {}
