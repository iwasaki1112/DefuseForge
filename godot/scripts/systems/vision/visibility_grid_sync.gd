class_name VisibilityGridSync
extends RefCounted

## 可視性グリッド同期クラス（GridManager連携版）
## ネットワーク同期用にグリッドデータを圧縮・差分送信する
## GridManagerと連携して座標変換を行う
##
## 機能:
## - グリッドをビットマップに変換
## - 前フレームとの差分をXOR計算
## - RLE圧縮で差分データを軽量化
## - 敵位置の可視性フィルタリング

# グリッド解像度（GridManagerと同期）
var grid_resolution: Vector2i = Vector2i(32, 32)

# GridManager参照
var _grid_manager = null

# 現在と前フレームのビットマップ
var _current_bitmap: PackedByteArray = PackedByteArray()
var _previous_bitmap: PackedByteArray = PackedByteArray()

# 統計情報（デバッグ用）
var last_full_size: int = 0
var last_compressed_size: int = 0
var compression_ratio: float = 0.0


func _init(resolution: Vector2i = Vector2i(32, 32), grid_manager = null) -> void:
	grid_resolution = resolution
	_grid_manager = grid_manager
	_initialize_bitmaps()


## ビットマップを初期化
func _initialize_bitmaps() -> void:
	# ビット数 / 8 = バイト数
	var byte_count := (grid_resolution.x * grid_resolution.y + 7) / 8
	_current_bitmap.resize(byte_count)
	_previous_bitmap.resize(byte_count)
	_current_bitmap.fill(0)
	_previous_bitmap.fill(0)


## ImageからビットマップにLを変換
## VisibilityTextureWriterの_current_imageから呼び出す
func update_from_image(image: Image) -> void:
	# 前フレームを保存
	_previous_bitmap = _current_bitmap.duplicate()

	# 現在フレームをクリア
	_current_bitmap.fill(0)

	# Image（R8フォーマット）からビットマップに変換
	for y in range(grid_resolution.y):
		for x in range(grid_resolution.x):
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.5:  # 可視セル
				_set_bit(x, y, true)


## 指定位置のビットを設定
func _set_bit(x: int, y: int, value: bool) -> void:
	var index := y * grid_resolution.x + x
	var byte_index := index / 8
	var bit_index := index % 8

	if byte_index >= _current_bitmap.size():
		return

	if value:
		_current_bitmap[byte_index] |= (1 << bit_index)
	else:
		_current_bitmap[byte_index] &= ~(1 << bit_index)


## 指定位置のビットを取得
func _get_bit(bitmap: PackedByteArray, x: int, y: int) -> bool:
	var index := y * grid_resolution.x + x
	var byte_index := index / 8
	var bit_index := index % 8

	if byte_index >= bitmap.size():
		return false

	return (bitmap[byte_index] & (1 << bit_index)) != 0


## 現在のビットマップで指定位置が可視かどうか
func is_cell_visible(x: int, y: int) -> bool:
	return _get_bit(_current_bitmap, x, y)


## ワールド座標が可視かどうか（GridManager使用）
func is_position_visible(world_pos: Vector3) -> bool:
	if not _grid_manager:
		return false

	var cell: Vector2i = _grid_manager.world_to_cell(world_pos)

	if cell.x < 0 or cell.x >= grid_resolution.x:
		return false
	if cell.y < 0 or cell.y >= grid_resolution.y:
		return false

	return is_cell_visible(cell.x, cell.y)


# =============================================================================
# ネットワーク同期用メソッド
# =============================================================================

## 差分データを取得（XOR + RLE圧縮）
## 戻り値: 圧縮された差分バイト配列
func get_diff_data() -> PackedByteArray:
	# XOR差分を計算
	var diff := PackedByteArray()
	diff.resize(_current_bitmap.size())

	for i in range(_current_bitmap.size()):
		diff[i] = _current_bitmap[i] ^ _previous_bitmap[i]

	# RLE圧縮
	var compressed := _rle_compress(diff)

	# 統計情報を更新
	last_full_size = diff.size()
	last_compressed_size = compressed.size()
	compression_ratio = float(last_compressed_size) / float(last_full_size) if last_full_size > 0 else 0.0

	return compressed


## フルグリッドデータを取得（初期同期用）
## 戻り値: RLE圧縮されたビットマップ
func get_full_data() -> PackedByteArray:
	var compressed := _rle_compress(_current_bitmap)

	last_full_size = _current_bitmap.size()
	last_compressed_size = compressed.size()
	compression_ratio = float(last_compressed_size) / float(last_full_size) if last_full_size > 0 else 0.0

	return compressed


## 差分データを適用（クライアント側）
func apply_diff_data(compressed_diff: PackedByteArray) -> void:
	# RLE展開
	var diff := _rle_decompress(compressed_diff)

	if diff.size() != _current_bitmap.size():
		push_error("VisibilityGridSync: Diff size mismatch")
		return

	# 前フレームを保存
	_previous_bitmap = _current_bitmap.duplicate()

	# XOR適用
	for i in range(_current_bitmap.size()):
		_current_bitmap[i] = _previous_bitmap[i] ^ diff[i]


## フルデータを適用（初期同期用、クライアント側）
func apply_full_data(compressed_data: PackedByteArray) -> void:
	var data := _rle_decompress(compressed_data)

	if data.size() != _current_bitmap.size():
		push_error("VisibilityGridSync: Full data size mismatch")
		return

	_previous_bitmap = _current_bitmap.duplicate()
	_current_bitmap = data


## RLE圧縮
## フォーマット: [count, value, count, value, ...]
## count: 連続するバイト数（1-255）、0は終端
func _rle_compress(data: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()

	if data.is_empty():
		return result

	var i := 0
	while i < data.size():
		var value := data[i]
		var count := 1

		# 連続する同じ値をカウント（最大255）
		while i + count < data.size() and data[i + count] == value and count < 255:
			count += 1

		result.append(count)
		result.append(value)
		i += count

	return result


## RLE展開
func _rle_decompress(compressed: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()

	var i := 0
	while i + 1 < compressed.size():
		var count := compressed[i]
		var value := compressed[i + 1]

		for _j in range(count):
			result.append(value)

		i += 2

	return result


# =============================================================================
# 敵位置フィルタリング（チート対策）
# =============================================================================

## 敵の位置データをフィルタリング
## 視界内の敵のみ位置を返し、視界外の敵はnullを返す
## 戻り値: Dictionary { enemy_id: Vector3 or null }
func filter_enemy_positions(enemies: Dictionary) -> Dictionary:
	var filtered := {}

	for enemy_id in enemies:
		var position: Vector3 = enemies[enemy_id]
		if is_position_visible(position):
			filtered[enemy_id] = position
		else:
			filtered[enemy_id] = null  # 位置情報を隠す

	return filtered


## 可視な敵IDのリストを取得
func get_visible_enemy_ids(enemies: Dictionary) -> Array:
	var visible_ids := []

	for enemy_id in enemies:
		var position: Vector3 = enemies[enemy_id]
		if is_position_visible(position):
			visible_ids.append(enemy_id)

	return visible_ids


# =============================================================================
# デバッグ用
# =============================================================================

## 可視セル数を取得
func get_visible_cell_count() -> int:
	var count := 0
	for y in range(grid_resolution.y):
		for x in range(grid_resolution.x):
			if is_cell_visible(x, y):
				count += 1
	return count


## 変更セル数を取得（前フレームとの差分）
func get_changed_cell_count() -> int:
	var count := 0
	for i in range(_current_bitmap.size()):
		var diff := _current_bitmap[i] ^ _previous_bitmap[i]
		# ビットカウント（popcount）
		while diff != 0:
			count += diff & 1
			diff >>= 1
	return count


## 同期統計を取得
func get_sync_stats() -> Dictionary:
	return {
		"full_size": last_full_size,
		"compressed_size": last_compressed_size,
		"compression_ratio": compression_ratio,
		"visible_cells": get_visible_cell_count(),
		"changed_cells": get_changed_cell_count()
	}
