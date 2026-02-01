class_name VisionLight
extends Node
## キャラクター視界用のPointLight2D管理クラス
## 3D位置・回転を2D SubViewport内のライトに同期
## Light2D + LightOccluder2Dで壁の影を自動計算（GPU最適化）

## PointLight2Dへの参照
var _light: PointLight2D = null

## キャラクター参照
var _character: Node3D = null

## 座標変換パラメータ
var _map_size: Vector2 = Vector2(40, 40)
var _texture_resolution: int = 256

## 視界設定
var fov_degrees: float = 90.0
var view_distance: float = 15.0

## FOVテクスチャ
var _fov_texture: ImageTexture = null

## ライトカラー（白=視界あり）
const LIGHT_COLOR := Color(1.0, 1.0, 1.0, 1.0)

## ライトエネルギー（CanvasModulateの暗さを相殺する値）
const LIGHT_ENERGY := 1.0

## シャドウ設定（壁の影を自動計算）
const SHADOW_ENABLED := true
## シャドウフィルター: NONE=シャープ, PCF5/PCF13=ソフト
const SHADOW_FILTER := Light2D.SHADOW_FILTER_NONE
const SHADOW_FILTER_SMOOTH := 0.0


## セットアップ
## @param viewport: 描画先のSubViewport
## @param character: 視界の持ち主キャラクター
## @param map_size: マップサイズ（ワールド座標）
## @param resolution: テクスチャ解像度
func setup(viewport: SubViewport, character: Node3D, map_size: Vector2, resolution: int) -> void:
	_character = character
	_map_size = map_size
	_texture_resolution = resolution

	# 既存のライトを削除
	if _light:
		_light.queue_free()

	# PointLight2Dを作成
	_light = PointLight2D.new()
	_light.name = "VisionLight_%s" % character.name if character else "VisionLight"
	_light.enabled = true
	_light.visible = true
	_light.color = LIGHT_COLOR
	_light.energy = LIGHT_ENERGY
	_light.blend_mode = Light2D.BLEND_MODE_ADD
	_light.range_item_cull_mask = 1
	_light.range_z_min = -1024
	_light.range_z_max = 1024

	# シャドウ設定（壁の影を自動計算）
	_light.shadow_enabled = SHADOW_ENABLED
	_light.shadow_filter = SHADOW_FILTER
	_light.shadow_filter_smooth = SHADOW_FILTER_SMOOTH
	_light.shadow_color = Color(0, 0, 0, 1)
	_light.shadow_item_cull_mask = 1

	# ビューポートに追加
	viewport.add_child(_light)

	# FOVテクスチャを設定
	_update_fov_texture()
	_update_light_scale()

	# 初期位置を設定
	sync_transform()

	print("[FOW] VisionLight setup: ", character.name if character else "unknown",
		", fov: ", fov_degrees, ", scale: ", _light.texture_scale)


## 毎フレームの位置・回転同期（_process または _physics_process から呼び出し）
func sync_transform() -> void:
	if not _light or not _character:
		return

	# 3D位置 → 2D位置
	_light.position = _world_to_viewport(_character.global_position)

	# 3D Y軸回転 → 2D回転
	# Mixamoモデルの前方向は+Z
	# ビューポート座標系: X=WorldX, Y=WorldZ
	# FOVテクスチャ: 上方向(-Y)が0度（rotation=0でビューポート上向き）
	# +Z（Mixamo前方）= ビューポート+Y（下）→ rotation=PI必要
	var facing := _get_facing_direction()
	# atan2(z, x)で3D角度を取得し、PI/2加算してビューポート座標に変換
	var angle_2d := atan2(facing.z, facing.x) + PI / 2.0
	_light.rotation = angle_2d


## 視界距離を設定
func set_view_distance(distance: float) -> void:
	view_distance = distance
	_update_light_scale()


## FOV角度を設定
func set_fov_degrees(fov: float) -> void:
	fov_degrees = clamp(fov, 1.0, 360.0)
	_update_fov_texture()


## ライトの有効/無効
func set_enabled(enabled: bool) -> void:
	if _light:
		_light.visible = enabled


## ライトが有効か確認
func is_enabled() -> bool:
	return _light and _light.visible


## ライトを削除
func cleanup() -> void:
	if _light:
		_light.queue_free()
		_light = null


# ============================================
# 内部メソッド
# ============================================

func _world_to_viewport(world_pos: Vector3) -> Vector2:
	var half_map := _map_size / 2.0
	var uv_x := (world_pos.x + half_map.x) / _map_size.x
	var uv_y := (world_pos.z + half_map.y) / _map_size.y
	return Vector2(uv_x * _texture_resolution, uv_y * _texture_resolution)


func _get_facing_direction() -> Vector3:
	if not _character:
		return Vector3.FORWARD

	# GameCharacterのfacing directionを使用
	if _character.has_method("get_facing_direction"):
		var dir: Vector3 = _character.get_facing_direction()
		if dir.length_squared() > 0.001:
			return dir.normalized()

	# フォールバック: キャラクターの前方向
	var forward := _character.global_transform.basis.z
	forward.y = 0
	if forward.length_squared() < 0.001:
		return Vector3.FORWARD
	return forward.normalized()


## FOVテクスチャのエッジ鮮明度（0.0=シャープ, 1.0=ソフト）
const FOV_EDGE_FALLOFF := 0.1

func _update_fov_texture() -> void:
	if not _light:
		return

	# FOVに応じたテクスチャを生成（falloffでエッジの鮮明度を調整）
	if fov_degrees >= 359.0:
		_fov_texture = FovTextureGenerator.generate_circular_texture(_texture_resolution, FOV_EDGE_FALLOFF)
	else:
		_fov_texture = FovTextureGenerator.generate_fov_texture(fov_degrees, _texture_resolution, FOV_EDGE_FALLOFF)

	_light.texture = _fov_texture
	_update_light_scale()


func _update_light_scale() -> void:
	if not _light:
		return

	# 視界距離に基づいてテクスチャスケールを計算
	var scale_factor := float(_texture_resolution) / maxf(_map_size.x, _map_size.y)
	var light_radius := view_distance * scale_factor * 2.0  # 直径

	# テクスチャサイズに対するスケール
	var texture_size := float(_texture_resolution)
	var scale_value := light_radius / texture_size

	_light.texture_scale = scale_value
