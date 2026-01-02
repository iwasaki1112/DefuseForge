class_name VisibilityTextureWriter
extends RefCounted

## 可視性テクスチャライター
## VisionComponentの視野データをテクスチャに書き込む
## グリッドベースのFog of War用

const VisibilityGridSyncClass = preload("res://scripts/systems/vision/visibility_grid_sync.gd")

# テクスチャ解像度（1ピクセル = 1グリッドセル）
var grid_resolution: Vector2i = Vector2i(128, 128)

# マップ範囲（ワールド座標）
var map_min: Vector2 = Vector2(-50, -50)
var map_max: Vector2 = Vector2(50, 50)

# 現在と前フレームの可視性テクスチャ
var current_texture: ImageTexture = null
var previous_texture: ImageTexture = null

# 内部用Image（毎フレーム書き換え）
var _current_image: Image = null
var _previous_image: Image = null

# 視野コンポーネントへの参照
var _vision_components: Array = []

# ネットワーク同期用グリッド
var grid_sync = null  # VisibilityGridSync


func _init(resolution: Vector2i = Vector2i(128, 128)) -> void:
	grid_resolution = resolution
	_initialize_textures()
	# ネットワーク同期用グリッドを初期化
	grid_sync = VisibilityGridSyncClass.new(resolution)


## テクスチャを初期化
func _initialize_textures() -> void:
	# 現在フレーム用Image（R8フォーマット = 1チャンネル8ビット）
	_current_image = Image.create(grid_resolution.x, grid_resolution.y, false, Image.FORMAT_R8)
	_current_image.fill(Color(0, 0, 0, 1))  # 初期状態は完全に不可視

	# 前フレーム用Image
	_previous_image = Image.create(grid_resolution.x, grid_resolution.y, false, Image.FORMAT_R8)
	_previous_image.fill(Color(0, 0, 0, 1))

	# ImageTexture作成
	current_texture = ImageTexture.create_from_image(_current_image)
	previous_texture = ImageTexture.create_from_image(_previous_image)


## 視野コンポーネントを登録
func register_vision_component(component: Node) -> void:
	if component and component not in _vision_components:
		_vision_components.append(component)


## 視野コンポーネントを解除
func unregister_vision_component(component: Node) -> void:
	_vision_components.erase(component)


## マップ範囲を設定
func set_map_bounds(min_pos: Vector2, max_pos: Vector2) -> void:
	map_min = min_pos
	map_max = max_pos
	# ネットワーク同期用グリッドにも設定
	if grid_sync:
		grid_sync.set_map_bounds(min_pos, max_pos)


## 毎フレーム呼び出し：可視性テクスチャを更新
func update_visibility() -> void:
	# 前フレームのテクスチャを保存
	_swap_textures()

	# 現在フレームをクリア（完全に不可視）
	_current_image.fill(Color(0, 0, 0, 1))

	# 各視野コンポーネントの可視領域を書き込み
	for component in _vision_components:
		if component and is_instance_valid(component):
			_write_vision_to_texture(component)

	# テクスチャを更新
	current_texture.update(_current_image)

	# ネットワーク同期用グリッドを更新
	if grid_sync:
		grid_sync.update_from_image(_current_image)


## 前フレームと現フレームのテクスチャをスワップ
func _swap_textures() -> void:
	# 現在のImageを前フレームにコピー
	_previous_image.copy_from(_current_image)
	previous_texture.update(_previous_image)


## 視野データをテクスチャに書き込み
func _write_vision_to_texture(component: Node) -> void:
	if not component.has_method("get") or not "visible_points" in component:
		return

	var visible_points: Array = component.visible_points
	var vision_origin: Vector3 = component.vision_origin if "vision_origin" in component else Vector3.ZERO

	if visible_points.size() < 3:
		return

	# 視野ポリゴンを三角形に分解して各グリッドセルをチェック
	# points[0] = 中心（相対座標0）、points[1..n] = エッジポイント
	var center_world := Vector2(vision_origin.x, vision_origin.z)

	for i in range(1, visible_points.size() - 1):
		var rel_p1: Vector3 = visible_points[i]
		var rel_p2: Vector3 = visible_points[i + 1]

		var p1_world := Vector2(vision_origin.x + rel_p1.x, vision_origin.z + rel_p1.z)
		var p2_world := Vector2(vision_origin.x + rel_p2.x, vision_origin.z + rel_p2.z)

		# 三角形内のグリッドセルを塗りつぶし
		_fill_triangle(center_world, p1_world, p2_world)


## 三角形内のグリッドセルを塗りつぶし
func _fill_triangle(v0: Vector2, v1: Vector2, v2: Vector2) -> void:
	# バウンディングボックスを計算
	var min_x := minf(minf(v0.x, v1.x), v2.x)
	var max_x := maxf(maxf(v0.x, v1.x), v2.x)
	var min_y := minf(minf(v0.y, v1.y), v2.y)
	var max_y := maxf(maxf(v0.y, v1.y), v2.y)

	# グリッド座標に変換
	var grid_min := _world_to_grid(Vector2(min_x, min_y))
	var grid_max := _world_to_grid(Vector2(max_x, max_y))

	# クランプ
	grid_min.x = clampi(grid_min.x, 0, grid_resolution.x - 1)
	grid_min.y = clampi(grid_min.y, 0, grid_resolution.y - 1)
	grid_max.x = clampi(grid_max.x, 0, grid_resolution.x - 1)
	grid_max.y = clampi(grid_max.y, 0, grid_resolution.y - 1)

	# バウンディングボックス内の各ピクセルをチェック
	for gx in range(grid_min.x, grid_max.x + 1):
		for gy in range(grid_min.y, grid_max.y + 1):
			var world_pos := _grid_to_world(Vector2i(gx, gy))
			if _point_in_triangle(world_pos, v0, v1, v2):
				_current_image.set_pixel(gx, gy, Color(1, 0, 0, 1))  # 可視 = 1.0


## ワールド座標をグリッド座標に変換
func _world_to_grid(world_pos: Vector2) -> Vector2i:
	var normalized := (world_pos - map_min) / (map_max - map_min)
	return Vector2i(
		int(normalized.x * float(grid_resolution.x)),
		int(normalized.y * float(grid_resolution.y))
	)


## グリッド座標をワールド座標（セル中心）に変換
func _grid_to_world(grid_pos: Vector2i) -> Vector2:
	var normalized := Vector2(
		(float(grid_pos.x) + 0.5) / float(grid_resolution.x),
		(float(grid_pos.y) + 0.5) / float(grid_resolution.y)
	)
	return map_min + normalized * (map_max - map_min)


## 点が三角形内にあるかチェック（重心座標法）
func _point_in_triangle(p: Vector2, v0: Vector2, v1: Vector2, v2: Vector2) -> bool:
	var d1 := _sign(p, v0, v1)
	var d2 := _sign(p, v1, v2)
	var d3 := _sign(p, v2, v0)

	var has_neg := (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos := (d1 > 0) or (d2 > 0) or (d3 > 0)

	return not (has_neg and has_pos)


func _sign(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
