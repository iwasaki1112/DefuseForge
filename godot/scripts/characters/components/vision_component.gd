class_name VisionComponent
extends Node

## 視野コンポーネント（グリッドベース版）
## キャラクターの視野を管理し、GridManagerを使用して可視セルを計算

signal visibility_changed(visible_cells: Array)

@export_group("視野設定")
@export var fov_angle: float = 120.0  # 視野角（度）
@export var view_distance: float = 15.0  # 視野距離（ワールド単位）

@export_group("更新設定")
@export var update_interval: float = 0.0  # 視野更新間隔（秒）- 0で毎フレーム更新

# 親キャラクター参照
var character: CharacterBody3D = null

# 可視セルのリスト（グリッド座標）
var visible_cells: Array[Vector2i] = []

# 視野の原点セル
var origin_cell: Vector2i = Vector2i.ZERO

# 視野の原点（ワールド座標）- 後方互換性のため維持
var vision_origin: Vector3 = Vector3.ZERO

# GridManager参照
var _grid_manager: Node = null

# 更新タイマー
var _update_timer: float = 0.0


func _ready() -> void:
	character = get_parent() as CharacterBody3D
	if not character:
		push_error("[VisionComponent] Parent must be CharacterBody3D")
		return

	# 敵チームの場合は即座に処理を無効化
	if not _should_register_with_fog():
		set_process(false)
		print("[VisionComponent] Disabled for enemy team: %s" % character.name)
		return

	# FogOfWarManagerへの登録を遅延実行
	_deferred_register.call_deferred()


## 遅延登録
func _deferred_register() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not _should_register_with_fog():
		set_process(false)
		return

	# GridManagerへの参照を取得
	_grid_manager = _get_grid_manager()
	if not _grid_manager:
		push_warning("[VisionComponent] GridManager not found for: %s" % character.name)

	var fow = _get_fog_of_war_manager()
	if fow:
		fow.register_vision_component(self)
		print("[VisionComponent] Registered to FogOfWarManager: %s" % character.name)
	else:
		push_warning("[VisionComponent] FogOfWarManager not found for: %s" % character.name)

	# 初回計算
	_calculate_visibility()


func _exit_tree() -> void:
	var fow = _get_fog_of_war_manager()
	if fow:
		fow.unregister_vision_component(self)


func _get_fog_of_war_manager() -> Node:
	return GameManager.fog_of_war_manager if GameManager else null


func _get_grid_manager() -> Node:
	return GameManager.grid_manager if GameManager else null


func _should_register_with_fog() -> bool:
	if character and character.has_method("is_player") and not character.is_player():
		return false
	if character and character.is_in_group("enemies"):
		return false
	return true


func _process(delta: float) -> void:
	if not character:
		return

	_update_timer += delta
	if _update_timer >= update_interval:
		_update_timer = 0.0
		_calculate_visibility()


## 視界を計算（グリッドベース）
func _calculate_visibility() -> void:
	if not character or not character.is_inside_tree():
		visible_cells.clear()
		return

	if not _grid_manager:
		_grid_manager = _get_grid_manager()
		if not _grid_manager:
			return

	var char_pos := character.global_position
	vision_origin = char_pos

	# キャラクターの位置をセル座標に変換
	origin_cell = _grid_manager.world_to_cell(char_pos)

	# キャラクターの向きを取得（XZ平面上）
	var forward := character.global_transform.basis.z  # +Z方向
	var forward_2d := Vector2(forward.x, forward.z).normalized()

	# 視野距離をセル数に変換
	var cell_size: float = _grid_manager.cell_size
	var view_distance_cells := int(ceil(view_distance / cell_size))

	# GridManagerを使用して可視セルを取得
	visible_cells = _grid_manager.get_visible_cells_in_fov(
		origin_cell,
		forward_2d,
		fov_angle,
		view_distance_cells
	)

	visibility_changed.emit(visible_cells)


## 指定した位置が視野内かどうかを判定（グリッドベース）
func is_position_visible(target_pos: Vector3) -> bool:
	if not character or not _grid_manager:
		return false

	# ターゲット位置をセル座標に変換
	var target_cell: Vector2i = _grid_manager.world_to_cell(target_pos)

	# 可視セルリストに含まれているかチェック
	return target_cell in visible_cells


## 指定したキャラクターが視野内かどうかを判定
func is_character_visible(target: CharacterBody3D) -> bool:
	if not target:
		return false
	return is_position_visible(target.global_position)


## 指定したセルが視野内かどうかを判定
func is_cell_visible(cell: Vector2i) -> bool:
	return cell in visible_cells


## 視野距離をセル数で取得
func get_view_distance_cells() -> int:
	if not _grid_manager:
		return 0
	return int(ceil(view_distance / _grid_manager.cell_size))


## デバッグ用：可視セル数を取得
func get_visible_cell_count() -> int:
	return visible_cells.size()


## ========================================
## 拡張視界API
## ========================================

## レイキャストで遮蔽物を考慮した視線チェック
## @param target_pos: チェック対象位置
## @param collision_mask: 遮蔽物判定用のコリジョンマスク（デフォルト: 壁レイヤー = 6）
## @return: 視線が通っているか
func has_line_of_sight(target_pos: Vector3, collision_mask: int = 6) -> bool:
	if not character or not character.is_inside_tree():
		return false

	var space_state = character.get_world_3d().direct_space_state
	if not space_state:
		return false

	# 視点位置（キャラクターの頭の高さ）
	var eye_pos = character.global_position + Vector3(0, 1.6, 0)
	var target_eye_pos = target_pos + Vector3(0, 1.6, 0)

	var query = PhysicsRayQueryParameters3D.create(eye_pos, target_eye_pos)
	query.collision_mask = collision_mask
	query.exclude = [character]

	var result = space_state.intersect_ray(query)
	return result.is_empty()


## 視野内かつ視線が通っているか判定（遮蔽物考慮）
## @param target_pos: チェック対象位置
## @param check_occlusion: 遮蔽物チェックを行うか
func is_position_truly_visible(target_pos: Vector3, check_occlusion: bool = true) -> bool:
	# まずグリッドベースの視野チェック
	if not is_position_visible(target_pos):
		return false

	# 遮蔽物チェックが有効な場合、レイキャストで確認
	if check_occlusion:
		return has_line_of_sight(target_pos)

	return true


## キャラクターが視野内かつ視線が通っているか判定
func is_character_truly_visible(target: CharacterBody3D, check_occlusion: bool = true) -> bool:
	if not target:
		return false
	return is_position_truly_visible(target.global_position, check_occlusion)


## 視野角を動的に変更
## @param new_fov: 新しい視野角（度）
func set_fov_angle(new_fov: float) -> void:
	fov_angle = clamp(new_fov, 10.0, 360.0)
	_calculate_visibility()


## 視野距離を動的に変更
## @param new_distance: 新しい視野距離（ワールド単位）
func set_view_distance_value(new_distance: float) -> void:
	view_distance = max(1.0, new_distance)
	_calculate_visibility()


## 視界情報を辞書形式で取得
func get_vision_info() -> Dictionary:
	return {
		"fov_angle": fov_angle,
		"view_distance": view_distance,
		"origin_cell": origin_cell,
		"visible_cell_count": visible_cells.size(),
		"vision_origin": vision_origin
	}


## 視野を強制更新
func force_update() -> void:
	_calculate_visibility()
