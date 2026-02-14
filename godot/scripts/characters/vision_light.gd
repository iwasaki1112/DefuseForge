class_name VisionLight
extends Node
## キャラクター視界用のPointLight2D管理クラス
## 3D位置・回転を2D SubViewport内のライトに同期
## Light2D + LightOccluder2Dで壁の影を自動計算（GPU最適化）

## メインFOVライト（扇形）
var _light: PointLight2D = null

## 周辺視界ライト（小さな円形、360度）
var _peripheral_light: PointLight2D = null

## キャラクター参照
var _character: Node3D = null

## 座標変換パラメータ
var _map_size: Vector2 = Vector2(40, 40)
var _map_center: Vector2 = Vector2.ZERO
var _texture_resolution: int = 256

## 視界設定
var fov_degrees: float = 75.0
var view_distance: float = 7.0

## 周辺視界設定（至近距離の360度視界）
var peripheral_distance: float = 0.5

## 回転補間用
var _current_rotation: float = 0.0  ## 現在の補間された回転角度
var _rotation_initialized: bool = false  ## 初回は即座に設定
const ROTATION_SMOOTHING: float = 12.0  ## 回転補間速度（大きいほど速く追従）

## 位置補間用
var _current_position: Vector2 = Vector2.ZERO  ## 現在の補間されたビューポート位置
var _position_initialized: bool = false  ## 初回は即座に設定
const POSITION_SMOOTHING: float = 15.0  ## 位置補間速度（大きいほど速く追従）

## FOVテクスチャ
var _fov_texture: ImageTexture = null
## 周辺視界テクスチャ
var _peripheral_texture: ImageTexture = null

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
	if _peripheral_light:
		_peripheral_light.queue_free()

	# メインFOVライトを作成（扇形）
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

	# 周辺視界ライトを作成（小さな円形、360度）
	_peripheral_light = PointLight2D.new()
	_peripheral_light.name = "PeripheralLight_%s" % character.name if character else "PeripheralLight"
	_peripheral_light.enabled = true
	_peripheral_light.visible = true
	_peripheral_light.color = LIGHT_COLOR
	_peripheral_light.energy = LIGHT_ENERGY
	_peripheral_light.blend_mode = Light2D.BLEND_MODE_ADD
	_peripheral_light.range_item_cull_mask = 1
	_peripheral_light.range_z_min = -1024
	_peripheral_light.range_z_max = 1024

	# シャドウ設定（壁の影を自動計算）
	_peripheral_light.shadow_enabled = SHADOW_ENABLED
	_peripheral_light.shadow_filter = SHADOW_FILTER
	_peripheral_light.shadow_filter_smooth = SHADOW_FILTER_SMOOTH
	_peripheral_light.shadow_color = Color(0, 0, 0, 1)
	_peripheral_light.shadow_item_cull_mask = 1

	# ビューポートに追加
	viewport.add_child(_peripheral_light)

	# テクスチャを設定
	_update_fov_texture()
	_update_peripheral_texture()
	_update_light_scale()

	# 初期位置を設定
	sync_transform()

	var char_name := str(character.name) if character else "unknown"
	if Debug.enabled: print("[FOW] VisionLight setup: ", char_name,
		", fov: ", fov_degrees, ", scale: ", _light.texture_scale,
		", peripheral: ", peripheral_distance)


## 毎フレームの位置・回転同期（_process または _physics_process から呼び出し）
func sync_transform() -> void:
	if not _character:
		return

	# 3D位置 → 2D位置
	var target_pos := _world_to_viewport(_character.global_position)

	# 位置を補間（滑らかな追従）
	var delta := get_process_delta_time()
	if not _position_initialized:
		# 初回は即座に設定
		_current_position = target_pos
		_position_initialized = true
	else:
		# lerpで滑らかに追従
		_current_position = _current_position.lerp(target_pos, POSITION_SMOOTHING * delta)

	# メインFOVライトの位置と回転を更新
	if _light:
		_light.position = _current_position
		# 3D Y軸回転 → 2D回転
		# モデルの前方向は+Z
		# ビューポート座標系: X=WorldX, Y=WorldZ
		# FOVテクスチャ: 上方向(-Y)が0度（rotation=0でビューポート上向き）
		# +Z（モデル前方）= ビューポート+Y（下）→ rotation=PI必要
		var facing := _get_facing_direction()
		# atan2(z, x)で3D角度を取得し、PI/2加算してビューポート座標に変換
		var target_angle := atan2(facing.z, facing.x) + PI / 2.0

		# 回転を補間（滑らかな追従）
		if not _rotation_initialized:
			# 初回は即座に設定
			_current_rotation = target_angle
			_rotation_initialized = true
		else:
			# lerp_angleで最短経路で補間
			_current_rotation = lerp_angle(_current_rotation, target_angle, ROTATION_SMOOTHING * delta)

		_light.rotation = _current_rotation

	# 周辺視界ライトの位置を更新（回転は不要、常に円形）
	if _peripheral_light:
		_peripheral_light.position = _current_position


## 視界距離を設定
func set_view_distance(distance: float) -> void:
	view_distance = distance
	_update_light_scale()


## FOV角度を設定
func set_fov_degrees(fov: float) -> void:
	fov_degrees = clamp(fov, 1.0, 360.0)
	_update_fov_texture()


## 周辺視界距離を設定
func set_peripheral_distance(distance: float) -> void:
	peripheral_distance = maxf(distance, 0.0)
	_update_light_scale()


## ライトの有効/無効
func set_enabled(enabled: bool) -> void:
	if _light:
		_light.visible = enabled
	if _peripheral_light:
		_peripheral_light.visible = enabled


## ライトが有効か確認
func is_enabled() -> bool:
	return (_light and _light.visible) or (_peripheral_light and _peripheral_light.visible)


## ライトを削除
func cleanup() -> void:
	if _light:
		_light.queue_free()
		_light = null
	if _peripheral_light:
		_peripheral_light.queue_free()
		_peripheral_light = null


# ============================================
# 内部メソッド
# ============================================

func _world_to_viewport(world_pos: Vector3) -> Vector2:
	var map_min := _map_center - _map_size / 2.0
	var uv_x := (world_pos.x - map_min.x) / _map_size.x
	var uv_y := (world_pos.z - map_min.y) / _map_size.y
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


## FOVテクスチャのエッジ鮮明度（0.0=ソフト, 1.0=シャープ）
const FOV_EDGE_FALLOFF := 0.8

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


func _update_peripheral_texture() -> void:
	if not _peripheral_light:
		return

	# 周辺視界は均一な明るさの円形テクスチャ（確実に検出されるため）
	_peripheral_texture = FovTextureGenerator.generate_peripheral_texture(_texture_resolution)
	_peripheral_light.texture = _peripheral_texture


func _update_light_scale() -> void:
	# アスペクト比補正のためのスケール計算
	# ビューポート座標系ではX/Zがmap_sizeで正規化されるため、
	# 非正方形マップでは円が楕円になる。これをノードのscaleで補正する。
	var aspect_scale := Vector2(1.0, 1.0)
	if _map_size.x > _map_size.y:
		# X方向がより広い -> Y方向のスケールを増やす
		aspect_scale.y = _map_size.x / _map_size.y
	elif _map_size.y > _map_size.x:
		# Y(Z)方向がより広い -> X方向のスケールを増やす
		aspect_scale.x = _map_size.y / _map_size.x

	var max_dimension := maxf(_map_size.x, _map_size.y)
	var scale_factor := float(_texture_resolution) / max_dimension
	var texture_size := float(_texture_resolution)

	# メインFOVライトのスケール
	if _light:
		var light_radius := view_distance * scale_factor * 2.0  # 直径
		var scale_value := light_radius / texture_size
		_light.texture_scale = scale_value
		_light.scale = aspect_scale

	# 周辺視界ライトのスケール
	if _peripheral_light:
		var peripheral_radius := peripheral_distance * scale_factor * 2.0  # 直径
		var peripheral_scale := peripheral_radius / texture_size
		_peripheral_light.texture_scale = peripheral_scale
		_peripheral_light.scale = aspect_scale
