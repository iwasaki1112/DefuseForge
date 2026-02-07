class_name PathPointActionHandler
extends RefCounted
## パスポイントアクションハンドラ
## PathFollowingControllerからポイント到達時アクションを分離
## Clear/Grenade/SmokeGrenade/Waitポイントのチェックと処理

## ポイントインデックス
var clear_index: int = 0
var grenade_index: int = 0
var smoke_grenade_index: int = 0

## Wait状態
var is_waiting_for_wait: bool = false
var is_sync_waiting: bool = false
var wait_timer: float = 0.0
var current_wait_duration: float = 0.0

## 参照
var _controller: Node = null  # PathFollowingController
var _character: CharacterBody3D = null


## セットアップ
func setup(controller: Node, character: CharacterBody3D) -> void:
	_controller = controller
	_character = character


## 状態リセット
func reset() -> void:
	clear_index = 0
	grenade_index = 0
	smoke_grenade_index = 0
	is_waiting_for_wait = false
	is_sync_waiting = false
	wait_timer = 0.0
	current_wait_duration = 0.0


## Clearポイントのチェックと処理
func check_clear_points(progress: float, clear_points: Array[Dictionary]) -> void:
	while clear_index < clear_points.size():
		var cp = clear_points[clear_index]
		if progress >= cp.path_ratio:
			if _controller:
				_controller._forced_look_direction = Vector3.ZERO
				_controller._active_target_point = Vector3.ZERO
			clear_index += 1
		else:
			break


## グレネードポイントのチェックと処理
func check_grenade_points(progress: float, grenade_points: Array[Dictionary]) -> void:
	while grenade_index < grenade_points.size():
		var gp = grenade_points[grenade_index]
		if progress >= gp.path_ratio:
			if _controller:
				_controller.grenade_point_reached.emit(grenade_index, gp)
			grenade_index += 1
		else:
			break


## スモークグレネードポイントのチェックと処理
## 投擲ハンドラが投擲中の場合は次のポイントをスキップ（1つずつ処理）
func check_smoke_grenade_points(progress: float, smoke_grenade_points: Array[Dictionary]) -> void:
	if _controller and _controller._grenade_throw_handler and _controller._grenade_throw_handler.is_throwing:
		return  # 投擲中は次のポイントを処理しない

	while smoke_grenade_index < smoke_grenade_points.size():
		var sgp = smoke_grenade_points[smoke_grenade_index]
		if progress >= sgp.path_ratio:
			if _controller:
				_controller.smoke_grenade_point_reached.emit(smoke_grenade_index, sgp)
				# 投擲ハンドラで投擲シーケンスを開始
				if _controller._grenade_throw_handler:
					_controller._grenade_throw_handler.start_throw(sgp)
			smoke_grenade_index += 1
			return  # 1つ投擲したら中断（投擲完了後に次のポイントを処理）
		else:
			break


## Waitポイントのチェックと処理
## @return: Waitポイントに到達してパスを停止した場合はtrue
func check_wait_points(_progress: float) -> bool:
	if not _controller:
		return false

	var char_distance: float = _controller._calculate_distance_traveled()

	var reached_index: int = _controller._wait_checker.get_current_index()
	var wp = _controller._wait_checker.check_reached(char_distance)
	if wp == null:
		return false

	var duration: float = wp.wait_duration if wp.has("wait_duration") else 1.0

	_controller.wait_point_reached.emit(reached_index, wp)

	if _character:
		_character.velocity = Vector3.ZERO

	if duration < 0:
		is_sync_waiting = true
		_controller.sync_wait_started.emit()
	else:
		is_waiting_for_wait = true
		wait_timer = 0.0
		current_wait_duration = duration

	_update_idle_animation_while_waiting()
	return true


## Wait時間更新処理（process内から呼ばれる）
## @return: まだ待機中ならtrue
func process_wait(delta: float) -> bool:
	if not is_waiting_for_wait:
		return false

	wait_timer += delta
	if wait_timer >= current_wait_duration:
		is_waiting_for_wait = false
		wait_timer = 0.0
		current_wait_duration = 0.0
		return false  # 待機完了
	else:
		_update_idle_animation_while_waiting()
		return true  # まだ待機中


## 同期待機解除
func release_sync_wait() -> void:
	if is_sync_waiting:
		is_sync_waiting = false
		if _controller:
			_controller.sync_wait_released.emit()


## 最終目的地付近に味方キャラクターがいるかチェック
func is_ally_at_destination(current_path: Array[Vector3], characters_cache: Array, ally_collision_radius: float) -> bool:
	if current_path.size() == 0:
		return false

	var final_destination = current_path[current_path.size() - 1]
	final_destination.y = 0

	for character in characters_cache:
		if character == _character:
			continue
		if "is_alive" in character and not character.is_alive:
			continue
		# 味方判定はコントローラーのcollision_avoidanceを使用
		if _controller and "_collision_avoidance" in _controller:
			if not _controller._collision_avoidance.is_ally(character):
				continue
		var char_pos = character.global_position
		char_pos.y = 0
		if char_pos.distance_to(final_destination) < ally_collision_radius:
			return true

	return false


## ========================================
## 内部ヘルパー
## ========================================

## アイドルアニメーション更新（待機中共通）
func _update_idle_animation_while_waiting() -> void:
	if not _character:
		return

	var anim_ctrl = _character.get_anim_controller()
	if not anim_ctrl:
		return

	var look_dir := Vector3.FORWARD
	if _controller:
		var forced = _controller._forced_look_direction
		var last_move = _controller._last_move_direction
		if forced.length_squared() > 0.1:
			look_dir = forced
		elif last_move.length_squared() > 0.1:
			look_dir = last_move

	anim_ctrl.update_animation(Vector3.ZERO, look_dir, false, 0.016)
