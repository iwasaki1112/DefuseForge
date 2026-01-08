class_name VisibilityTextureWriter
extends RefCounted

## 可視性テクスチャライター（グリッドベース版）
## VisionComponentのvisible_cells（グリッド座標）を直接テクスチャに書き込む
## GridManagerと連携してグリッド単位で可視性を管理

const VisibilityGridSyncClass = preload("res://scripts/systems/vision/visibility_grid_sync.gd")

# テクスチャ解像度（グリッド解像度と同じ）
var grid_resolution: Vector2i = Vector2i(32, 32)

# GridManager参照
var _grid_manager = null

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


func _init(resolution: Vector2i = Vector2i(32, 32), grid_manager = null) -> void:
	grid_resolution = resolution
	_grid_manager = grid_manager
	_initialize_textures()
	# ネットワーク同期用グリッドを初期化
	grid_sync = VisibilityGridSyncClass.new(resolution, grid_manager)


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


## 毎フレーム呼び出し：可視性テクスチャを更新
func update_visibility() -> void:
	# 前フレームのテクスチャを保存
	_swap_textures()

	# 現在フレームをクリア（完全に不可視）
	_current_image.fill(Color(0, 0, 0, 1))

	# 各視野コンポーネントの可視セルを書き込み
	for component in _vision_components:
		if component and is_instance_valid(component):
			_write_visible_cells_to_texture(component)

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


## 可視セルをテクスチャに書き込み（グリッドベース）
func _write_visible_cells_to_texture(component: Node) -> void:
	# visible_cellsプロパティをチェック
	if not "visible_cells" in component:
		return

	var visible_cells: Array = component.visible_cells

	if visible_cells.is_empty():
		return

	# 各可視セルをテクスチャに書き込み
	for cell in visible_cells:
		var cell_pos: Vector2i = cell as Vector2i
		# グリッド範囲内かチェック
		if cell_pos.x >= 0 and cell_pos.x < grid_resolution.x and \
		   cell_pos.y >= 0 and cell_pos.y < grid_resolution.y:
			_current_image.set_pixel(cell_pos.x, cell_pos.y, Color(1, 0, 0, 1))  # 可視 = 1.0
