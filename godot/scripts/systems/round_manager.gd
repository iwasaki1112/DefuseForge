extends Node
class_name RoundManager
## ラウンド管理システム
##
## ラウンドの状態管理、タイマー制御、生存者数追跡、勝敗判定を行う。

# ============================================
# Enums
# ============================================

enum RoundPhase { NONE, ACTIVE, ENDED }
enum EndReason { TIME_UP, CT_ELIMINATED, T_ELIMINATED }

# ============================================
# Signals
# ============================================

signal round_started()
signal round_ended(winner: int, reason: int)  # winner: GameCharacter.Team, reason: EndReason
signal timer_updated(remaining_seconds: float)
signal survivor_count_changed(ct_count: int, t_count: int)

# ============================================
# Properties
# ============================================

var current_phase: RoundPhase = RoundPhase.NONE
var remaining_time: float = 0.0
var ct_alive_count: int = 0
var t_alive_count: int = 0
var winner_team: int = 0  # GameCharacter.Team.NONE

var _game_manager: GameManager = null
var _registered_characters: Array[GameCharacter] = []
var _last_timer_second: int = -1  # タイマー更新の最適化用

# ============================================
# Public Methods
# ============================================

## 初期化
func setup(game_manager: GameManager) -> void:
	_game_manager = game_manager


## ラウンド開始
func start_round() -> void:
	if current_phase == RoundPhase.ACTIVE:
		return

	current_phase = RoundPhase.ACTIVE
	remaining_time = GameConstants.ROUND_TIME_LIMIT
	winner_team = GameCharacter.Team.NONE
	_last_timer_second = -1

	# 生存者数を初期カウント
	_update_survivor_counts()

	round_started.emit()
	timer_updated.emit(remaining_time)


## ラウンド終了
func end_round(winner: int, reason: EndReason) -> void:
	if current_phase == RoundPhase.ENDED:
		return

	current_phase = RoundPhase.ENDED
	winner_team = winner
	round_ended.emit(winner, reason)


## 毎フレーム処理（タイマー更新・勝敗判定）
func process(delta: float) -> void:
	if current_phase != RoundPhase.ACTIVE:
		return

	# タイマー更新
	remaining_time -= delta
	if remaining_time <= 0.0:
		remaining_time = 0.0
		_on_time_up()
		return

	# 秒が変わった時のみシグナル発火（最適化）
	var current_second := int(remaining_time)
	if current_second != _last_timer_second:
		_last_timer_second = current_second
		timer_updated.emit(remaining_time)


## キャラクターを追跡登録
func register_character(character: GameCharacter) -> void:
	if _registered_characters.has(character):
		return

	_registered_characters.append(character)

	# 死亡シグナルを接続
	if not character.died.is_connected(_on_character_died):
		character.died.connect(_on_character_died)

	# 生存者数を更新
	if current_phase == RoundPhase.ACTIVE:
		_update_survivor_counts()


## キャラクターを登録解除
func unregister_character(character: GameCharacter) -> void:
	if not _registered_characters.has(character):
		return

	_registered_characters.erase(character)

	# 死亡シグナルを切断
	if character.died.is_connected(_on_character_died):
		character.died.disconnect(_on_character_died)

# ============================================
# Private Methods
# ============================================

## 生存者数を更新
func _update_survivor_counts() -> void:
	var prev_ct := ct_alive_count
	var prev_t := t_alive_count

	ct_alive_count = 0
	t_alive_count = 0

	for character in _registered_characters:
		if not is_instance_valid(character):
			continue
		if not character.is_alive:
			continue

		match character.team:
			GameCharacter.Team.COUNTER_TERRORIST:
				ct_alive_count += 1
			GameCharacter.Team.TERRORIST:
				t_alive_count += 1

	# 変更があればシグナル発火
	if ct_alive_count != prev_ct or t_alive_count != prev_t:
		survivor_count_changed.emit(ct_alive_count, t_alive_count)


## タイムアップ時の処理
func _on_time_up() -> void:
	# ドロー（winner_team = NONE）
	end_round(GameCharacter.Team.NONE, EndReason.TIME_UP)


## キャラクター死亡時の処理
func _on_character_died(_character: GameCharacter) -> void:
	if current_phase != RoundPhase.ACTIVE:
		return

	# 生存者数を更新
	_update_survivor_counts()

	# 全滅判定
	if ct_alive_count == 0 and t_alive_count > 0:
		# CT全滅 → T勝利
		end_round(GameCharacter.Team.TERRORIST, EndReason.CT_ELIMINATED)
	elif t_alive_count == 0 and ct_alive_count > 0:
		# T全滅 → CT勝利
		end_round(GameCharacter.Team.COUNTER_TERRORIST, EndReason.T_ELIMINATED)
	elif ct_alive_count == 0 and t_alive_count == 0:
		# 両チーム全滅 → ドロー
		end_round(GameCharacter.Team.NONE, EndReason.CT_ELIMINATED)
