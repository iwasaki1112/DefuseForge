class_name VisionComponent
extends Node

## 視野コンポーネント
## キャラクターの視野を管理し、視界内のポイントを計算

signal visibility_changed(visible_points: Array)

@export_group("視野設定")
@export var fov_angle: float = 120.0  # 視野角（度）
@export var view_distance: float = 15.0  # 視野距離
@export var ray_count: int = 40  # 視野を構成するレイの数
@export var height_offset: float = 1.5  # レイキャストの高さオフセット

@export_group("更新設定")
@export var update_interval: float = 0.0  # 視野更新間隔（秒）- 0で毎フレーム更新

# 親キャラクター参照
var character: CharacterBody3D = null

# 視野ポリゴンを構成する点のリスト（事前確保してresize、メモリ割り当て削減）
var visible_points: Array = []  # Array of Vector3
var _visible_points_size: int = 0  # 実際に使用されているサイズ

# 壁検出用コリジョンマスク
var collision_mask: int = 2  # デフォルトは地形レイヤー

# 更新タイマー
var _update_timer: float = 0.0

# キャッシュされたレイ方向（ローカル空間、+Z前方基準）
var _cached_ray_directions: Array = []  # Array of Vector3
var _cached_fov_angle: float = 0.0
var _cached_ray_count: int = 0


func _ready() -> void:
	character = get_parent() as CharacterBody3D
	if not character:
		push_error("[VisionComponent] Parent must be CharacterBody3D")
		return

	# 敵チームの場合は即座に処理を無効化（遅延を待たずに）
	# これにより、モバイルでの初期化タイミング問題を回避
	if not _should_register_with_fog():
		set_process(false)
		print("[VisionComponent] Disabled for enemy team: %s" % character.name)
		return

	# FogOfWarManagerへの登録を遅延実行（game_sceneの初期化完了を待つ）
	_deferred_register.call_deferred()


## 遅延登録（FogOfWarManagerの初期化完了後に実行）
func _deferred_register() -> void:
	# 数フレーム待ってFogOfWarManagerが登録されるのを待つ
	await get_tree().process_frame
	await get_tree().process_frame

	if not _should_register_with_fog():
		set_process(false)
		return

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


## FogOfWarManagerへの参照を取得
func _get_fog_of_war_manager() -> Node:
	return GameManager.fog_of_war_manager if GameManager else null


## 敵チームの視界はFogOfWarに登録しない
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


## レイ方向キャッシュを更新（fov_angleやray_countが変更された場合）
func _update_ray_direction_cache() -> void:
	if _cached_fov_angle == fov_angle and _cached_ray_count == ray_count:
		return  # キャッシュは有効

	_cached_ray_directions.clear()
	_cached_fov_angle = fov_angle
	_cached_ray_count = ray_count

	if ray_count < 2:
		return

	var half_fov := deg_to_rad(fov_angle / 2.0)
	var angle_step := deg_to_rad(fov_angle) / float(ray_count - 1)

	# ローカル空間でのレイ方向を事前計算（+Z前方基準）
	for i in range(ray_count):
		var current_angle := -half_fov + angle_step * i
		# Vector3.BACK (0, 0, 1) = +Z方向（このプロジェクトの前方向）を基準に回転
		var local_direction := Vector3.BACK.rotated(Vector3.UP, current_angle)
		_cached_ray_directions.append(local_direction)


## 視界を計算
func _calculate_visibility() -> void:
	if not character or not character.is_inside_tree():
		_visible_points_size = 0
		return

	# ray_countが2未満の場合は計算をスキップ（ゼロ除算防止）
	if ray_count < 2:
		push_warning("[VisionComponent] ray_count must be at least 2")
		_visible_points_size = 0
		return

	# レイ方向キャッシュを更新（必要な場合のみ）
	_update_ray_direction_cache()

	# 配列サイズを調整（メモリ割り当て削減、かつ古いデータが残らないように）
	var required_size := ray_count + 1  # 中心点 + レイ数
	if visible_points.size() != required_size:
		visible_points.resize(required_size)

	var space_state := character.get_world_3d().direct_space_state
	var origin := character.global_position + Vector3(0, height_offset, 0)
	var basis := character.global_transform.basis

	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = collision_mask
	query.exclude = [character]
	query.collide_with_bodies = true
	query.collide_with_areas = false

	# 中心点を設定
	visible_points[0] = character.global_position
	var idx := 1

	# 各レイをキャスト（キャッシュされた方向を使用）
	for local_dir in _cached_ray_directions:
		# ローカル方向をワールド方向に変換
		var ray_direction: Vector3 = basis * local_dir
		var end_point := origin + ray_direction * view_distance

		# レイキャスト
		query.from = origin
		query.to = end_point

		var result := space_state.intersect_ray(query)

		if result:
			# 壁にヒット
			visible_points[idx] = result.position
		else:
			# 視野の端まで見える
			visible_points[idx] = end_point
		idx += 1

	_visible_points_size = idx
	visibility_changed.emit(visible_points)


## 指定した位置が視野内かどうかを判定
func is_position_visible(target_pos: Vector3) -> bool:
	if not character:
		return false

	var origin := character.global_position + Vector3(0, height_offset, 0)
	var to_target := target_pos - origin
	to_target.y = 0  # 水平方向のみ

	# 距離チェック
	if to_target.length() > view_distance:
		return false

	# 角度チェック
	var forward := character.global_transform.basis.z  # +Z方向（このプロジェクトの設定）
	forward.y = 0
	forward = forward.normalized()
	to_target = to_target.normalized()

	var angle := forward.angle_to(to_target)
	if angle > deg_to_rad(fov_angle / 2.0):
		return false

	# 視線が遮られていないかチェック
	var space_state := character.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, target_pos + Vector3(0, height_offset, 0))
	query.collision_mask = collision_mask
	query.exclude = [character]

	var result := space_state.intersect_ray(query)

	# ヒットしなければ見える
	return result.is_empty()


## 指定したキャラクターが視野内かどうかを判定
func is_character_visible(target: CharacterBody3D) -> bool:
	if not target:
		return false
	return is_position_visible(target.global_position)


## デバッグ用：視野を描画
func get_visibility_polygon_2d(camera: Camera3D) -> PackedVector2Array:
	var points := PackedVector2Array()

	if not camera:
		return points

	for point in visible_points:
		if camera.is_position_behind(point):
			continue
		points.append(camera.unproject_position(point))

	return points
