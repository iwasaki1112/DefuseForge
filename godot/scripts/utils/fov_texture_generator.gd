class_name FovTextureGenerator
extends RefCounted
## FOV（視野角）コーンテクスチャを動的生成するユーティリティ
## Light2D用の扇形グラデーションテクスチャを作成

## デフォルトテクスチャサイズ（コーンエッジの滑らかさに影響）
## ビューポート解像度とは独立。キャッシュされるため1回限りのCPUコスト
const DEFAULT_SIZE: int = 1024

## テクスチャキャッシュ（FOV角度 -> ImageTexture）
static var _texture_cache: Dictionary[String, ImageTexture] = {}


## 扇形FOVテクスチャを生成
## @param fov_degrees: 視野角（度数）
## @param size: テクスチャサイズ（ピクセル）
## @param falloff: エッジのフェードアウト係数（0.0-1.0）
## @return: 生成されたImageTexture
static func generate_fov_texture(fov_degrees: float, size: int = DEFAULT_SIZE, falloff: float = 0.3) -> ImageTexture:
	# キャッシュキー
	var cache_key := "%d_%d_%.2f" % [int(fov_degrees), size, falloff]
	if Debug.enabled: print("[FOV_TEX] generate_fov_texture called: fov=", fov_degrees, ", size=", size, ", falloff=", falloff, ", cache_key=", cache_key)
	if _texture_cache.has(cache_key):
		if Debug.enabled: print("[FOV_TEX] Using cached texture for: ", cache_key)
		return _texture_cache[cache_key]
	if Debug.enabled: print("[FOV_TEX] Generating new texture for: ", cache_key)

	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var half_fov := deg_to_rad(fov_degrees / 2.0)
	var max_dist := size / 2.0

	for y in range(size):
		for x in range(size):
			var pos := Vector2(x, y) - center
			# 上向き（-Y）を0度として角度を計算
			# Light2Dのテクスチャは+Xが右、+Yが下
			var angle := atan2(pos.x, -pos.y)
			var dist := pos.length() / max_dist

			var intensity := 0.0

			# 扇形の範囲内かつ距離内
			if falloff >= 0.7:
				# シャープエッジモード: アンチエイリアス付き
				# ピクセル単位のアンチエイリアス幅（小さいほどシャープな縁）
				var aa_width := 2.0 / max_dist

				# 距離エッジのアンチエイリアス
				var dist_aa := 1.0 - smoothstep(1.0 - aa_width, 1.0, dist)

				# 角度エッジのアンチエイリアス
				var angle_aa := 1.0 - smoothstep(half_fov - aa_width, half_fov, absf(angle))

				intensity = dist_aa * angle_aa
			elif absf(angle) <= half_fov and dist <= 1.0:
				# 距離に応じたフェードアウト
				var distance_fade := 1.0 - pow(dist, 2.0 - falloff)

				# エッジに近いほどフェードアウト（角度）
				var angle_ratio := absf(angle) / half_fov
				var angle_fade := 1.0 - pow(angle_ratio, 3.0)

				intensity = distance_fade * angle_fade

			# Light2Dはテクスチャの明るさ（RGB値）をライト強度として使用
			# アルファ値はテクスチャのブレンドに使用される
			image.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))

	var texture := ImageTexture.create_from_image(image)
	_texture_cache[cache_key] = texture
	return texture


## 円形テクスチャを生成（360度視野用）
## @param size: テクスチャサイズ（ピクセル）
## @param falloff: エッジのフェードアウト係数
## @return: 生成されたImageTexture
static func generate_circular_texture(size: int = DEFAULT_SIZE, falloff: float = 0.3) -> ImageTexture:
	var cache_key := "circle_%d_%.2f" % [size, falloff]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]

	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var max_dist := size / 2.0

	for y in range(size):
		for x in range(size):
			var pos := Vector2(x, y) - center
			var dist := pos.length() / max_dist

			var intensity := 0.0
			if dist <= 1.0:
				intensity = 1.0 - pow(dist, 2.0 - falloff)

			# Light2Dはテクスチャの明るさ（RGB値）をライト強度として使用
			image.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))

	var texture := ImageTexture.create_from_image(image)
	_texture_cache[cache_key] = texture
	return texture


## 周辺視界用の均一な円形テクスチャを生成（フォールオフなし）
## 可視性判定で確実に検出されるよう、エッジまで均一な明るさ
## @param size: テクスチャサイズ（ピクセル）
## @return: 生成されたImageTexture
static func generate_peripheral_texture(size: int = DEFAULT_SIZE) -> ImageTexture:
	var cache_key := "peripheral_%d" % size
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]

	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var max_dist := size / 2.0

	for y in range(size):
		for x in range(size):
			var pos := Vector2(x, y) - center
			var dist := pos.length() / max_dist

			# 円内は均一な明るさ、エッジのみ少しソフト
			var intensity := 0.0
			if dist <= 0.9:
				intensity = 1.0  # 中心部は完全に明るい
			elif dist <= 1.0:
				# エッジ部分だけ少しソフトに（0.9-1.0の範囲でフェード）
				intensity = 1.0 - (dist - 0.9) / 0.1

			image.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))

	var texture := ImageTexture.create_from_image(image)
	_texture_cache[cache_key] = texture
	return texture


## キャッシュをクリア
static func clear_cache() -> void:
	_texture_cache.clear()


## 特定のFOV用のプリセットテクスチャを事前生成
## @param fov_list: 事前生成するFOV角度のリスト
## @param size: テクスチャサイズ
static func pregenerate_textures(fov_list: Array[float], size: int = DEFAULT_SIZE) -> void:
	for fov in fov_list:
		generate_fov_texture(fov, size)
