extends "res://scripts/characters/character_base.gd"

## 敵クラス
## AI操作の敵キャラクター

signal enemy_died

# チーム
var team: GameManager.Team = GameManager.Team.TERRORIST

# AI状態
enum AIState { IDLE, PATROL, CHASE, ATTACK, COVER }
var ai_state: AIState = AIState.IDLE

# AI設定
@export_group("AI設定")
@export var detection_range: float = 15.0
@export var attack_range: float = 10.0
@export var patrol_points: Array[Vector3] = []

# ターゲット
var target: CharacterBase = null
var current_patrol_index: int = 0

# プレイヤー操作フラグ（オンラインマッチで人間が操作する場合true）
var is_player_controlled: bool = false


func _ready() -> void:
	super._ready()

	# 敵グループに追加（グループベース管理）
	add_to_group("enemies")

	# 死亡シグナルを接続
	died.connect(_on_enemy_died)

	# シーン離脱時にグループから自動削除されるが、明示的に処理
	tree_exiting.connect(_on_tree_exiting)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	if not is_alive:
		return

	# プレイヤー操作中はAIを無効化
	if is_player_controlled:
		return

	# 実行フェーズでのみAIを動かす（作戦フェーズでは動かない）
	if not GameManager.is_execution_phase():
		return

	# AI更新
	_update_ai(delta)


## AI状態更新
func _update_ai(_delta: float) -> void:
	match ai_state:
		AIState.IDLE:
			_ai_idle()
		AIState.PATROL:
			_ai_patrol()
		AIState.CHASE:
			_ai_chase()
		AIState.ATTACK:
			_ai_attack()
		AIState.COVER:
			_ai_cover()


## IDLE状態
func _ai_idle() -> void:
	# プレイヤーを検出
	if _detect_player():
		ai_state = AIState.CHASE
		return

	# パトロールポイントがあればパトロール開始
	if patrol_points.size() > 0:
		ai_state = AIState.PATROL


## パトロール状態
func _ai_patrol() -> void:
	# プレイヤーを検出
	if _detect_player():
		ai_state = AIState.CHASE
		return

	# パトロールポイントがない場合
	if patrol_points.size() == 0:
		ai_state = AIState.IDLE
		return

	# 移動中でなければ次のポイントへ
	if not is_moving:
		var next_point := patrol_points[current_patrol_index]
		move_to(next_point, false)
		current_patrol_index = (current_patrol_index + 1) % patrol_points.size()


## 追跡状態
func _ai_chase() -> void:
	if target == null or not target.is_character_alive():
		target = null
		ai_state = AIState.IDLE
		return

	var distance := global_position.distance_to(target.global_position)

	# 攻撃範囲内
	if distance <= attack_range:
		stop()
		ai_state = AIState.ATTACK
		return

	# 検出範囲外
	if distance > detection_range * 1.5:
		stop()
		target = null
		ai_state = AIState.IDLE
		return

	# ターゲットへ移動
	if not is_moving:
		move_to(target.global_position, true)


## 攻撃状態
func _ai_attack() -> void:
	if target == null or not target.is_character_alive():
		target = null
		ai_state = AIState.IDLE
		return

	var distance := global_position.distance_to(target.global_position)

	# 攻撃範囲外
	if distance > attack_range:
		ai_state = AIState.CHASE
		return

	# ターゲット方向を向く
	var direction := (target.global_position - global_position).normalized()
	direction.y = 0
	if direction.length() > 0.1:
		var target_rotation := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * get_physics_process_delta_time())

	# 攻撃処理（TODO: 射撃実装）
	# _fire_at_target()


## カバー状態
func _ai_cover() -> void:
	# TODO: カバー位置検索と移動
	pass


## プレイヤー検出
func _detect_player() -> bool:
	if GameManager.player == null:
		return false

	var player := GameManager.player as CharacterBase
	if player == null or not player.is_character_alive():
		return false

	var distance := global_position.distance_to(player.global_position)
	if distance <= detection_range:
		# TODO: 視線チェック（障害物判定）
		target = player
		return true

	return false


## 敵死亡時の処理
func _on_enemy_died(killer: Node3D) -> void:
	enemy_died.emit()
	# 注: killerが渡された場合、CharacterBaseの_die()で既にunit_killedが発火されている


## シーン離脱時の処理
func _on_tree_exiting() -> void:
	# グループからは自動削除されるので特別な処理は不要
	pass


## チームを設定
func set_team(new_team: GameManager.Team) -> void:
	team = new_team


## チームを取得
func get_team() -> GameManager.Team:
	return team


## プレイヤーかどうか
func is_player() -> bool:
	return false


## パトロールポイントを設定
func set_patrol_points(points: Array[Vector3]) -> void:
	patrol_points = points
	if patrol_points.size() > 0:
		ai_state = AIState.PATROL
