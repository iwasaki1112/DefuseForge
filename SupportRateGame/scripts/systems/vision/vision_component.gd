class_name VisionComponent
extends Node

## 視野コンポーネント
## キャラクターの視野を管理し、視界内のポイントを計算

signal visibility_changed(visible_points: Array)

@export_group("視野設定")
@export var fov_angle: float = 120.0  # 視野角（度）
@export var view_distance: float = 15.0  # 視野距離
@export var ray_count: int = 60  # 視野を構成するレイの数
@export var height_offset: float = 1.5  # レイキャストの高さオフセット

@export_group("更新設定")
@export var update_interval: float = 0.0  # 視野更新間隔（秒）- 0で毎フレーム更新

# 親キャラクター参照
var character: CharacterBody3D = null

# 視野ポリゴンを構成する点のリスト
var visible_points: Array = []  # Array of Vector3

# 壁検出用コリジョンマスク
var collision_mask: int = 2  # デフォルトは地形レイヤー

# 更新タイマー
var _update_timer: float = 0.0


func _ready() -> void:
	character = get_parent() as CharacterBody3D
	if not character:
		push_error("[VisionComponent] Parent must be CharacterBody3D")
		return

	# FogOfWarManagerに登録
	if FogOfWarManager:
		FogOfWarManager.register_vision_component(self)

	# 初回計算
	_calculate_visibility()


func _exit_tree() -> void:
	if FogOfWarManager:
		FogOfWarManager.unregister_vision_component(self)


func _process(delta: float) -> void:
	if not character:
		return

	_update_timer += delta
	if _update_timer >= update_interval:
		_update_timer = 0.0
		_calculate_visibility()


## 視界を計算
func _calculate_visibility() -> void:
	visible_points.clear()

	if not character or not character.is_inside_tree():
		return

	# ray_countが2未満の場合は計算をスキップ（ゼロ除算防止）
	if ray_count < 2:
		push_warning("[VisionComponent] ray_count must be at least 2")
		return

	var space_state := character.get_world_3d().direct_space_state
	var origin := character.global_position + Vector3(0, height_offset, 0)
	var forward := character.global_transform.basis.z  # キャラクターの前方向（+Z方向、このプロジェクトの設定）

	# 視野の開始角度と終了角度
	var half_fov := deg_to_rad(fov_angle / 2.0)
	var angle_step := deg_to_rad(fov_angle) / float(ray_count - 1)

	# 中心点を追加
	visible_points.append(character.global_position)

	# 各レイをキャスト
	for i in range(ray_count):
		var current_angle := -half_fov + angle_step * i

		# 前方向を基準に回転
		var ray_direction := forward.rotated(Vector3.UP, current_angle)
		ray_direction = ray_direction.normalized()

		var end_point := origin + ray_direction * view_distance

		# レイキャスト
		var query := PhysicsRayQueryParameters3D.create(origin, end_point)
		query.collision_mask = collision_mask
		query.exclude = [character]

		var result := space_state.intersect_ray(query)

		if result:
			# 壁にヒット
			visible_points.append(result.position)
		else:
			# 視野の端まで見える
			visible_points.append(end_point)

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
