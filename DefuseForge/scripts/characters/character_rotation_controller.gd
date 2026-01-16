extends Node
## CharacterRotationController
## キャラクターの回転モードを管理するコントローラークラス
## 視線方向をスムーズに変更し、確定/キャンセルをサポート

## 回転イージング速度
@export var rotation_easing_speed: float = 15.0

## シグナル
signal rotation_started(original_direction: Vector3)
signal rotation_confirmed(final_direction: Vector3)
signal rotation_cancelled()

## 内部状態
var _character: CharacterBody3D = null
var _camera: Camera3D = null
var _is_active: bool = false
var _original_direction: Vector3 = Vector3.ZERO
var _target_direction: Vector3 = Vector3.ZERO
var _ground_plane: Plane = Plane(Vector3.UP, 0)


## セットアップ
func setup(character: CharacterBody3D, camera: Camera3D) -> void:
	_character = character
	_camera = camera


## 回転モード開始
func start_rotation() -> void:
	if not _character:
		push_warning("[CharacterRotationController] No character set")
		return

	_is_active = true

	# 現在の向きを保存
	var anim_ctrl = _character.get_anim_controller()
	if anim_ctrl:
		_original_direction = anim_ctrl.get_look_direction()
		_target_direction = _original_direction

	rotation_started.emit(_original_direction)


## 回転を確定
func confirm() -> void:
	if not _is_active:
		return

	if _character and _target_direction.length_squared() > 0.001:
		var anim_ctrl = _character.get_anim_controller()
		if anim_ctrl:
			anim_ctrl.set_look_direction(_target_direction)

	var final_dir = _target_direction
	_finish()
	rotation_confirmed.emit(final_dir)


## 回転をキャンセル（元の向きに戻す）
func cancel() -> void:
	if not _is_active:
		return

	if _character and _original_direction.length_squared() > 0.1:
		var anim_ctrl = _character.get_anim_controller()
		if anim_ctrl:
			anim_ctrl.update_animation(Vector3.ZERO, _original_direction, false, 0.0)

	_finish()
	rotation_cancelled.emit()


## 回転モードがアクティブか確認
func is_rotation_active() -> bool:
	return _is_active


## 回転対象キャラクターを取得
func get_character() -> CharacterBody3D:
	return _character


## 入力処理（スクリーン座標からワールド座標を計算して回転方向を設定）
func handle_input(screen_pos: Vector2) -> void:
	if not _is_active or not _character or not _camera:
		return

	var ground_pos = _get_ground_position(screen_pos)
	if ground_pos == null:
		return

	var char_pos = _character.global_position
	var direction = ground_pos - char_pos
	direction.y = 0

	if direction.length_squared() < 0.01:
		return

	_target_direction = direction.normalized()


## 毎フレームの処理（_physics_processから呼び出す）
func process(delta: float) -> void:
	if not _is_active or not _character:
		return

	var anim_ctrl = _character.get_anim_controller()
	if anim_ctrl and _target_direction.length_squared() > 0.001:
		anim_ctrl.update_animation(Vector3.ZERO, _target_direction, false, delta)


## グラウンド座標を取得
func _get_ground_position(screen_pos: Vector2) -> Variant:
	var ray_origin = _camera.project_ray_origin(screen_pos)
	var ray_direction = _camera.project_ray_normal(screen_pos)

	var intersection = _ground_plane.intersects_ray(ray_origin, ray_direction)
	if intersection:
		return intersection as Vector3
	return null


## 回転モード終了（内部用）
func _finish() -> void:
	_is_active = false
	_original_direction = Vector3.ZERO
	_target_direction = Vector3.ZERO
