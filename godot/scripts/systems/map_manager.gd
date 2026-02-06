extends Node
class_name MapManager
## マップライフサイクル管理
## マップのロード・アンロード・状態追跡・クリーンアップを一元管理


# ============================================
# Signals
# ============================================

## マップロード前に発火
signal map_will_load(map_id: String)
## マップロード完了時に発火
signal map_loaded(map_id: String, map_instance: Node3D)
## マップアンロード前に発火
signal map_will_unload(map_id: String)
## マップアンロード完了時に発火
signal map_unloaded(map_id: String)

# ============================================
# Properties
# ============================================

## 現在のマップインスタンス
var current_map: Node3D = null
## 現在のマッププリセット
var current_preset: MapPreset = null
## 現在のマップID
var current_map_id: String = ""

# ============================================
# Internal
# ============================================

var _map_container: Node3D = null
var _game_manager = null  # GameManager（循環参照回避のためvariant型）

# ============================================
# Setup
# ============================================

## MapManagerをセットアップ
## map_container: マップを追加する親ノード
## game_manager: GameManager参照（クリーンアップ用）
func setup(map_container: Node3D, game_manager) -> void:
	_map_container = map_container
	_game_manager = game_manager


# ============================================
# Map Loading API
# ============================================

## マップをロード
## auto_cleanup: trueの場合、既存マップを自動アンロード
## Returns: マップインスタンス、失敗時はnull
func load_map(map_id: String, auto_cleanup: bool = true) -> Node3D:
	# プリセット取得
	var preset = MapRegistry.get_preset(map_id)
	if not preset:
		push_error("[MapManager] Map preset not found: %s" % map_id)
		return null

	# 自動クリーンアップ
	if auto_cleanup and has_map():
		unload_map(true)

	# ロード前シグナル
	map_will_load.emit(map_id)

	# マップをインスタンス化
	var map_instance = MapRegistry.instantiate_map(map_id)
	if not map_instance:
		push_error("[MapManager] Failed to instantiate map: %s" % map_id)
		return null

	# マップを配置
	if _map_container:
		_map_container.add_child(map_instance)

	# 状態を更新
	current_map = map_instance
	current_preset = preset
	current_map_id = map_id

	# FoWマップサイズ更新はMapBase._notify_fow_system()で自動計算される
	# GameManagerのfow_map_sizeフォールバック値は_on_map_loaded経由で設定される
	# （循環参照を避けるため、ここでは直接GameManagerを参照しない）

	# ロード完了シグナル（map_sizeも通知）
	map_loaded.emit(map_id, map_instance)

	return map_instance


## マップをアンロード
## cleanup_characters_on_unload: trueの場合、キャラクターとパスもクリーンアップ
func unload_map(cleanup_characters_on_unload: bool = true) -> void:
	if not has_map():
		return

	var old_map_id = current_map_id

	# アンロード前シグナル
	map_will_unload.emit(old_map_id)

	# クリーンアップ
	if cleanup_characters_on_unload:
		cleanup_paths()
		cleanup_characters()

	# マップを削除
	if current_map and is_instance_valid(current_map):
		current_map.queue_free()

	# 状態をリセット
	current_map = null
	current_preset = null
	current_map_id = ""

	# アンロード完了シグナル
	map_unloaded.emit(old_map_id)



## マップを切り替え（アンロード→ロードを一括実行）
## Returns: 新しいマップインスタンス、失敗時はnull
func switch_map(new_map_id: String) -> Node3D:
	return load_map(new_map_id, true)


# ============================================
# Cleanup API
# ============================================

## 登録済みキャラクターをすべて削除
func cleanup_characters() -> void:
	if not _game_manager:
		return

	var characters_to_remove = _game_manager.characters.duplicate()
	for character in characters_to_remove:
		if is_instance_valid(character):
			_game_manager.unregister_character(character)
			character.queue_free()



## パス関連の状態をすべてクリア
func cleanup_paths() -> void:
	if not _game_manager:
		return

	# パス追従停止
	_game_manager.cancel_all_path_following()

	# 保留パスクリア
	_game_manager.clear_all_pending_paths()

	# パスモードキャンセル
	if _game_manager.is_path_mode():
		_game_manager.cancel_path()

	# 選択解除
	if _game_manager.selection_manager:
		_game_manager.selection_manager.deselect_all()



# ============================================
# Query API
# ============================================

## マップがロードされているか
func has_map() -> bool:
	return current_map != null and is_instance_valid(current_map)


## マップサイズを取得
func get_map_size() -> Vector2:
	if current_preset:
		return current_preset.map_size
	return Vector2.ZERO


## スポーン位置を取得
func get_spawn_points(is_ct: bool) -> Array[Vector3]:
	if not current_preset:
		return []
	return current_preset.spawn_points_ct if is_ct else current_preset.spawn_points_t
