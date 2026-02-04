class_name FogOfWarSystem
extends Node3D

## Fog of War System (Light2D + LightOccluder2D)
## GPU最適化されたFoW。レイキャスト不要で、ドア開閉時の即時更新をサポート
## SubViewport内でLight2Dの影計算を利用して視界を描画

## Quality presets（モバイル60FPS最適化）
enum Quality { LOW, MEDIUM, HIGH }
const QUALITY_SETTINGS := {
	Quality.LOW: {
		"resolution": 512,
		"shadow_filter": Light2D.SHADOW_FILTER_PCF13,
		"shadow_smooth": 1.0,
		"update_hz": 30
	},
	Quality.MEDIUM: {
		"resolution": 512,
		"shadow_filter": Light2D.SHADOW_FILTER_PCF13,
		"shadow_smooth": 1.5,
		"update_hz": 30
	},
	Quality.HIGH: {
		"resolution": 1024,
		"shadow_filter": Light2D.SHADOW_FILTER_PCF13,
		"shadow_smooth": 2.0,
		"update_hz": 60
	},
}

## Export settings
@export_group("Map Settings")
@export var map_size: Vector2 = Vector2(40, 40)
@export var fog_height: float = 0.02

@export_group("Visual Settings")
@export var fog_color: Color = Color(0.1, 0.15, 0.25, 0.3)
@export var quality: Quality = Quality.LOW

## Internal settings (auto-configured from quality)
var texture_resolution: int = 128
var _update_interval: float = 0.033  # 30Hz default

## Internal nodes
var _fog_mesh: MeshInstance3D
var _fog_material: ShaderMaterial
var _visibility_viewport: SubViewport


## OccluderManager
var _occluder_manager: OccluderManager = null

## VisionLight管理
var _vision_lights: Dictionary = {}  # character -> VisionLight
var _registered_characters: Array = []

## 更新フラグ
var _needs_update: bool = false
var _time_since_update: float = 0.0

## Shader reference
const FOW_SHADER_PATH := "res://shaders/fow.gdshader"


func _ready() -> void:
	if Debug.enabled: print("[FOW] FogOfWarSystem._ready() - map_size: ", map_size)
	# テクスチャキャッシュをクリア（テクスチャ形式変更時の対策）
	FovTextureGenerator.clear_cache()
	_apply_quality_settings()
	_setup_visibility_viewport()
	_setup_fog_mesh()
	_setup_occluder_manager()


## Apply quality preset settings
func _apply_quality_settings() -> void:
	var settings: Dictionary = QUALITY_SETTINGS[quality]
	texture_resolution = settings["resolution"]
	_update_interval = 1.0 / float(settings["update_hz"])


func _setup_visibility_viewport() -> void:
	# Create SubViewport for 2D lighting
	_visibility_viewport = SubViewport.new()
	_visibility_viewport.name = "VisibilityViewport"
	_visibility_viewport.size = Vector2i(texture_resolution, texture_resolution)
	_visibility_viewport.transparent_bg = false
	_visibility_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_visibility_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	# 2Dライティング用に設定
	_visibility_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	_visibility_viewport.disable_3d = true  # 2D専用
	# NOTE: SubViewportは必ずシーンツリーに追加（add_child）してから使う
	add_child(_visibility_viewport)

	# CanvasModulateを追加（2Dライティングの基盤）
	# これにより、Light2Dがない部分は暗くなる
	var canvas_modulate := CanvasModulate.new()
	canvas_modulate.name = "CanvasModulate"
	canvas_modulate.color = Color(0, 0, 0, 1)  # 暗い環境
	_visibility_viewport.add_child(canvas_modulate)

	# 白い背景（CanvasModulateで暗くされ、Light2Dで照らされる）
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(1, 1, 1, 1)  # 白（Light2Dで照らされると明るくなる）
	bg.size = Vector2(texture_resolution, texture_resolution)
	bg.z_index = -100
	# ライトの影響を受けるように明示的に設定
	bg.light_mask = 1
	_visibility_viewport.add_child(bg)

	if Debug.enabled: print("[FOW] Viewport setup - size: ", _visibility_viewport.size)


func _setup_fog_mesh() -> void:
	_fog_mesh = MeshInstance3D.new()
	_fog_mesh.name = "FogMesh"

	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = map_size
	_fog_mesh.mesh = plane_mesh
	_fog_mesh.position.y = fog_height

	# Load external shader
	var shader: Shader = load(FOW_SHADER_PATH)
	if not shader:
		push_error("FogOfWarSystem: Failed to load shader from " + FOW_SHADER_PATH)
		return

	_fog_material = ShaderMaterial.new()
	_fog_material.shader = shader
	_fog_material.set_shader_parameter("fog_color", fog_color)
	_fog_material.set_shader_parameter("map_min", Vector2(-map_size.x / 2, -map_size.y / 2))
	_fog_material.set_shader_parameter("map_max", Vector2(map_size.x / 2, map_size.y / 2))
	_fog_material.set_shader_parameter("texture_size", float(texture_resolution))
	# デバッグ: blur無効、edge_softnessを広げて可視化しやすく
	_fog_material.set_shader_parameter("blur_radius", 0.0)
	_fog_material.set_shader_parameter("edge_softness", 0.4)  # 0.1〜0.9が可視範囲

	_fog_mesh.material_override = _fog_material
	add_child(_fog_mesh)
	# グローバル位置は親がシーンツリーに追加された後でないと取得できない
	_fog_mesh.ready.connect(func():
		if Debug.enabled: print("[FOW] FogMesh global_position: ", _fog_mesh.global_position, ", FoWSystem global_position: ", global_position)
	)
	if Debug.enabled: print("[FOW] FogMesh local position: ", _fog_mesh.position, ", size: ", map_size)


func _setup_occluder_manager() -> void:
	_occluder_manager = OccluderManager.new()
	_occluder_manager.name = "OccluderManager"
	add_child(_occluder_manager)
	_occluder_manager.setup(_visibility_viewport, map_size, texture_resolution)


func _process(delta: float) -> void:
	# VisionLightの位置は毎フレーム同期（滑らかな追従のため）
	_sync_vision_lights()

	_time_since_update += delta

	# テクスチャ更新は一定間隔で行う（パフォーマンス維持）
	if _time_since_update >= _update_interval:
		_time_since_update = 0.0

		# シェーダーにテクスチャを設定
		if _visibility_viewport and _fog_material:
			var vis_tex := _visibility_viewport.get_texture()
			_fog_material.set_shader_parameter("visibility_texture", vis_tex)

		# 可視性キャッシュをダーティにマーク（次の判定で再取得）
		_mark_visibility_cache_dirty()


## VisionLightの位置・回転を同期
func _sync_vision_lights() -> void:
	for character in _registered_characters:
		if not is_instance_valid(character):
			continue
		if character in _vision_lights:
			var vision_light: VisionLight = _vision_lights[character]

			# 死亡キャラクターの視界を無効化
			var is_alive := true
			if "is_alive" in character:
				is_alive = character.is_alive

			vision_light.set_enabled(is_alive)

			if is_alive:
				# VisionComponentからパラメータを同期（動的変更対応）
				if character.has_method("get_vision_component"):
					var vision = character.get_vision_component()
					if vision:
						if vision_light.fov_degrees != vision.fov_degrees:
							vision_light.set_fov_degrees(vision.fov_degrees)
						if vision_light.view_distance != vision.view_distance:
							vision_light.set_view_distance(vision.view_distance)
						if vision_light.peripheral_distance != vision.peripheral_distance:
							vision_light.set_peripheral_distance(vision.peripheral_distance)

				vision_light.sync_transform()


# ============================================
# Public API - キャラクター登録
# ============================================

## キャラクターを登録（VisionLightを作成）
func register_character(character: Node3D) -> void:
	if character in _registered_characters:
		return

	_registered_characters.append(character)

	# VisionLightを作成
	var vision_light := VisionLight.new()
	vision_light.name = "VisionLight_%s" % character.name

	# キャラクターからFOV設定を取得（VisionComponentが唯一の設定元）
	var fov := 90.0
	var view_dist := 15.0
	var peripheral_dist := 0.8
	if character.has_method("get_vision_component"):
		var vision = character.get_vision_component()
		if vision:
			fov = vision.fov_degrees
			view_dist = vision.view_distance
			peripheral_dist = vision.peripheral_distance

	vision_light.fov_degrees = fov
	vision_light.view_distance = view_dist
	vision_light.peripheral_distance = peripheral_dist
	add_child(vision_light)

	# セットアップ
	vision_light.setup(_visibility_viewport, character, map_size, texture_resolution)

	# 品質設定を適用
	var settings: Dictionary = QUALITY_SETTINGS[quality]
	if vision_light._light:
		vision_light._light.shadow_filter = settings["shadow_filter"]
		vision_light._light.shadow_filter_smooth = settings["shadow_smooth"]

	_vision_lights[character] = vision_light
	_needs_update = true


## キャラクターを解除
func unregister_character(character: Node3D) -> void:
	if character not in _registered_characters:
		return

	_registered_characters.erase(character)

	if character in _vision_lights:
		_vision_lights[character].cleanup()
		_vision_lights[character].queue_free()
		_vision_lights.erase(character)

	_needs_update = true


## 旧API互換: VisionComponentを登録（内部でキャラクターを登録）
func register_vision(vision) -> void:
	if vision and vision.has_method("get_parent"):
		var character: Node = vision.get_parent()
		if character is Node3D:
			register_character(character)


## 旧API互換: VisionComponentを解除
func unregister_vision(vision) -> void:
	if vision and vision.has_method("get_parent"):
		var character: Node = vision.get_parent()
		if character is Node3D:
			unregister_character(character)


# ============================================
# Public API - Occluder管理
# ============================================

## マップからオクルーダーを抽出
func extract_occluders_from_map(map_node: Node3D) -> void:
	if _occluder_manager:
		_occluder_manager.extract_occluders_from_map(map_node)
	# 壁を常に明るく表示
	_make_walls_always_lit(map_node)


## 壁メッシュを常に明るく表示（ライティングの影響を受けない）
func _make_walls_always_lit(map_node: Node3D) -> void:
	_make_walls_always_lit_recursive(map_node)


## 再帰的に壁メッシュを探索してunshadedに設定
func _make_walls_always_lit_recursive(node: Node) -> void:
	var node_name_lower := node.name.to_lower()
	var parent: Node = node.get_parent()
	var parent_name_lower := parent.name.to_lower() if parent else ""

	# 壁/ドアの判定
	var is_wall := node_name_lower.begins_with("wall_") or parent_name_lower.begins_with("wall_")
	var is_door := node_name_lower.begins_with("door_") or parent_name_lower.begins_with("door_")

	if (is_wall or is_door) and node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		_set_mesh_unshaded(mesh_instance)

	# 子ノードを再帰的に処理
	for child in node.get_children():
		_make_walls_always_lit_recursive(child)


## メッシュをunshadedに設定（常に明るく表示）
func _set_mesh_unshaded(mesh_instance: MeshInstance3D) -> void:
	var mesh := mesh_instance.mesh
	if not mesh:
		return

	for i in range(mesh.get_surface_count()):
		var original_mat := mesh_instance.get_surface_override_material(i)
		if not original_mat:
			original_mat = mesh.surface_get_material(i)

		# StandardMaterial3Dの場合、unshadedモードに設定
		if original_mat is StandardMaterial3D:
			var new_mat := original_mat.duplicate() as StandardMaterial3D
			new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh_instance.set_surface_override_material(i, new_mat)


## ドアオクルーダーの有効/無効を切り替え
func set_door_occluder_enabled(door: Node3D, enabled: bool) -> void:
	if _occluder_manager:
		_occluder_manager.set_door_occluder_enabled(door, enabled)


## スモークオクルーダーを追加
func add_smoke_occluder(smoke_area: Node3D) -> void:
	if _occluder_manager:
		_occluder_manager.add_smoke_occluder(smoke_area)


## スモークオクルーダーを削除
func remove_smoke_occluder(smoke_area: Node3D) -> void:
	if _occluder_manager:
		_occluder_manager.remove_smoke_occluder(smoke_area)


## スモークオクルーダーの半径を更新
func update_smoke_radius(smoke_area: Node3D) -> void:
	if _occluder_manager:
		_occluder_manager.update_smoke_radius(smoke_area)


## OccluderManagerを取得
func get_occluder_manager() -> OccluderManager:
	return _occluder_manager


# ============================================
# Public API - 表示制御
# ============================================

## Set fog visibility
func set_fog_visible(fog_visible: bool) -> void:
	if _fog_mesh:
		_fog_mesh.visible = fog_visible


## Force visibility texture update
func force_update() -> void:
	_needs_update = true
	_time_since_update = _update_interval


## Set fog color
func set_fog_color(color: Color) -> void:
	fog_color = color
	if _fog_material:
		_fog_material.set_shader_parameter("fog_color", fog_color)


## Get visibility texture (for wall lighting, etc.)
func get_visibility_texture() -> ViewportTexture:
	if _visibility_viewport:
		return _visibility_viewport.get_texture()
	return null


## 可視性閾値（この明るさ以上で「見える」と判定）
const VISIBILITY_THRESHOLD: float = 0.15

## キャッシュされたテクスチャデータ（毎フレームGPU→CPU転送を避ける）
var _visibility_image: Image = null
var _visibility_image_dirty: bool = true


## ワールド位置がFoWテクスチャで可視かどうかを判定
## 視覚的なFoW表示と完全に同期した判定を行う
## @param world_pos: 判定するワールド座標
## @return: 可視ならtrue
func is_position_visible_in_fow(world_pos: Vector3) -> bool:
	if not _visibility_viewport:
		return false

	# ワールド座標をテクスチャUVに変換
	var uv := _world_to_texture_uv(world_pos)

	# UV範囲外は不可視
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return false

	# テクスチャから明るさを取得
	var brightness := _sample_visibility_at_uv(uv)

	return brightness >= VISIBILITY_THRESHOLD


## 複数のワールド位置の可視性を一括判定（バッチ処理で効率化）
## @param positions: 判定するワールド座標の配列
## @return: 各位置の可視性配列（true/false）
func are_positions_visible_in_fow(positions: Array[Vector3]) -> Array[bool]:
	var results: Array[bool] = []

	if not _visibility_viewport or positions.is_empty():
		results.resize(positions.size())
		results.fill(false)
		return results

	# テクスチャデータを1回だけ取得
	_update_visibility_image_cache()

	for pos in positions:
		var uv := _world_to_texture_uv(pos)
		if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
			results.append(false)
		else:
			var brightness := _sample_visibility_from_cache(uv)
			results.append(brightness >= VISIBILITY_THRESHOLD)

	return results


## ワールド座標をテクスチャUVに変換
func _world_to_texture_uv(world_pos: Vector3) -> Vector2:
	var half_map := map_size / 2.0
	var uv_x := (world_pos.x + half_map.x) / map_size.x
	var uv_y := (world_pos.z + half_map.y) / map_size.y
	return Vector2(uv_x, uv_y)


## テクスチャUV位置の明るさを取得
func _sample_visibility_at_uv(uv: Vector2) -> float:
	_update_visibility_image_cache()
	return _sample_visibility_from_cache(uv)


## キャッシュされたImageから明るさを取得
func _sample_visibility_from_cache(uv: Vector2) -> float:
	if not _visibility_image:
		return 0.0

	# UVをピクセル座標に変換
	var pixel_x := int(uv.x * _visibility_image.get_width())
	var pixel_y := int(uv.y * _visibility_image.get_height())

	# 範囲チェック
	pixel_x = clampi(pixel_x, 0, _visibility_image.get_width() - 1)
	pixel_y = clampi(pixel_y, 0, _visibility_image.get_height() - 1)

	var color := _visibility_image.get_pixel(pixel_x, pixel_y)
	# R成分を明るさとして使用（グレースケールの場合RGBは同じ）
	return color.r


## 可視性テクスチャキャッシュを更新
func _update_visibility_image_cache() -> void:
	if not _visibility_viewport:
		return

	# フレームごとに1回だけ更新（コスト削減）
	if _visibility_image_dirty:
		var viewport_texture := _visibility_viewport.get_texture()
		if viewport_texture:
			_visibility_image = viewport_texture.get_image()
		_visibility_image_dirty = false


## フレーム終了時にキャッシュをダーティにする（次フレームで再取得）
func _mark_visibility_cache_dirty() -> void:
	_visibility_image_dirty = true


## Dynamically change map size
func set_map_size(new_size: Vector2) -> void:
	if Debug.enabled: print("[FOW] set_map_size called: ", new_size, " (was: ", map_size, ")")
	map_size = new_size

	# Update fog mesh size
	if _fog_mesh and _fog_mesh.mesh is PlaneMesh:
		(_fog_mesh.mesh as PlaneMesh).size = map_size

	# Update shader parameters
	var map_min := Vector2(-map_size.x / 2, -map_size.y / 2)
	var map_max := Vector2(map_size.x / 2, map_size.y / 2)
	if _fog_material:
		_fog_material.set_shader_parameter("map_min", map_min)
		_fog_material.set_shader_parameter("map_max", map_max)
		if Debug.enabled: print("[FOW] Shader params updated - map_min: ", map_min, ", map_max: ", map_max)

	# Update occluder manager
	if _occluder_manager:
		_occluder_manager.set_map_size(new_size)

	# Update existing VisionLights with new map_size
	for vision_light in _vision_lights.values():
		if vision_light:
			vision_light._map_size = new_size
			vision_light.sync_transform()

	_needs_update = true


## Set quality preset at runtime
func set_quality(q: Quality) -> void:
	quality = q
	_apply_quality_settings()

	# Resize viewport
	if _visibility_viewport:
		_visibility_viewport.size = Vector2i(texture_resolution, texture_resolution)
		# Resize background
		for child in _visibility_viewport.get_children():
			if child is ColorRect:
				child.size = Vector2(texture_resolution, texture_resolution)
				break

	if _fog_material:
		_fog_material.set_shader_parameter("texture_size", float(texture_resolution))

	# Update occluder manager
	if _occluder_manager:
		_occluder_manager.set_texture_resolution(texture_resolution)

	# Update vision light shadow settings
	var settings: Dictionary = QUALITY_SETTINGS[quality]
	for vision_light in _vision_lights.values():
		if vision_light._light:
			vision_light._light.shadow_filter = settings["shadow_filter"]
			vision_light._light.shadow_filter_smooth = settings["shadow_smooth"]

	_needs_update = true


## Get quality settings for external synchronization
func get_quality_settings() -> Dictionary:
	return QUALITY_SETTINGS[quality]
