class_name CollisionAvoidanceController
extends RefCounted
## 衝突回避コントローラー
## PathFollowingControllerから味方判定ロジックを分離

## 参照
var _controller: Node = null  # PathFollowingController
var _character: CharacterBody3D = null


## セットアップ
func setup(controller: Node, character: CharacterBody3D) -> void:
	_controller = controller
	_character = character


## 状態リセット
func reset() -> void:
	pass


## 味方判定
func is_ally(other: Node) -> bool:
	if not _character or not other:
		return false
	if _character is GameCharacter and other is GameCharacter:
		return _character.team == other.team
	if _controller:
		var player_state = _controller.get_node_or_null("/root/PlayerState")
		if player_state and player_state.has_method("is_friendly"):
			return player_state.is_friendly(_character) == player_state.is_friendly(other)
	return false
