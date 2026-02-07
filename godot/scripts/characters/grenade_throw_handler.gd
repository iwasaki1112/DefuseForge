class_name GrenadeThrowHandler
extends RefCounted
## グレネード投擲ハンドラ
## PathFollowingControllerからグレネード投擲ロジックを分離
## DoorInteractionHandlerと同じパターンで投擲シーケンスを管理

## 投擲リリースシグナル（GrenadeServiceへの委譲用）
signal grenade_released(character: CharacterBody3D, target_pos: Vector3)

## 投擲状態
var is_throwing: bool = false

## 参照
var _controller: Node = null  # PathFollowingController
var _character: CharacterBody3D = null


## セットアップ
func setup(controller: Node, character: CharacterBody3D) -> void:
	_controller = controller
	_character = character


## 状態リセット
func reset() -> void:
	is_throwing = false


## 投擲を開始
## @param point_data: { path_ratio, anchor, target_pos }
func start_throw(point_data: Dictionary) -> void:
	if is_throwing or not _character:
		return

	is_throwing = true
	var target_pos: Vector3 = point_data.get("target_pos", Vector3.ZERO)

	# キャラクターを停止
	_character.velocity = Vector3.ZERO

	# ターゲットに向く
	_character.face_towards(target_pos)

	# 投擲アニメーション開始
	var anim_controller = _character.get_anim_controller()
	if not anim_controller:
		is_throwing = false
		return

	# シグナル接続（ワンショット）
	anim_controller.throw_release.connect(_on_throw_release.bind(target_pos), CONNECT_ONE_SHOT)
	anim_controller.throw_finished.connect(_on_throw_finished, CONNECT_ONE_SHOT)

	anim_controller.play_throw()


## 投擲リリースタイミング（グレネード発射）
func _on_throw_release(target_pos: Vector3) -> void:
	grenade_released.emit(_character, target_pos)


## 投擲アニメーション完了（パス移動再開）
func _on_throw_finished() -> void:
	is_throwing = false
