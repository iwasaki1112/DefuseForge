extends Node
class_name CombatAwarenessComponent
## Combat Awareness Component
## Handles individual character enemy detection and tracking
## Automatically detects enemies in vision cone and provides aim direction override

# ============================================
# Signals
# ============================================
signal enemy_spotted(enemy: Node)
signal enemy_lost(enemy: Node)
signal target_changed(new_target: Node, old_target: Node)
signal damage_dealt(attacker: Node, target: Node, damage: float, is_headshot: bool)  ## ダメージを与えた時（ネットワーク同期用）

# ============================================
# Configuration
# ============================================
const SCAN_INTERVAL: float = 0.05  ## Scan every 50ms (matches EnemyVisibilitySystem)
const TRACKING_TIMEOUT: float = 0.75  ## Time to track last known position after losing sight
const CHARACTERS_CACHE_INTERVAL: float = 0.2  ## キャラクターキャッシュ更新間隔（200ms）
const FIRE_INTERVAL: float = 0.5  ## 発砲間隔（500ms）
const MOVEMENT_THRESHOLD: float = 0.5  ## Velocity threshold to consider "moving"
const SPRINT_THRESHOLD: float = 4.0  ## Velocity threshold to consider "sprinting"
const FACING_ANGLE_THRESHOLD: float = 0.866  ## cos(30°) — 射撃許可の角度閾値

# ============================================
# State
# ============================================
var _character: Node = null  # GameCharacter
var _current_target: Node = null
var _last_known_position: Vector3 = Vector3.ZERO
var _time_since_lost: float = 0.0
var _is_tracking_last_known: bool = false
var _scan_timer: float = 0.0
var _ignored_enemies: Array[Node] = []  ## Enemies dismissed by user action (e.g., rotation)
var _ignored_enemies_timer: float = 0.0  ## 無視リスト時間制限タイマー
const IGNORE_TIMEOUT: float = 3.0  ## 無視リスト自動解除時間（秒）
var _firing_enabled: bool = false  ## Whether automatic firing is enabled
var _fire_timer: float = 0.0  ## 発砲タイマー

# キャラクターキャッシュ（GC負荷削減）
var _characters_cache: Array = []
var _characters_cache_timer: float = CHARACTERS_CACHE_INTERVAL  # 初回即時更新

# 命中判定結果（最後の射撃）
var _last_shot_hit: bool = true
var _last_shot_miss_offset: Vector3 = Vector3.ZERO

# バースト射撃状態（Auto Firing Mode用）
var _burst_shots_remaining: int = 0  ## 残りバースト射撃数
var _is_in_burst: bool = false  ## バースト中フラグ
var _burst_interval_timer: float = 0.0  ## バースト内射撃間隔タイマー
var _post_burst_pause_timer: float = 0.0  ## バースト後の待機タイマー
var _current_firing_mode: int = -1  ## 現在の射撃モード（WeaponPreset.FiringMode）
var _last_critical_hit: bool = false  ## 最後の射撃がクリティカルだったか
var _stationary_time: float = 0.0  ## 静止継続時間（Steady Aim用）
var _reaction_timer: float = 0.0  ## 初弾リアクションタイマー


# ============================================
# Setup
# ============================================

## Initialize the component with the owning character
func setup(character: Node) -> void:
	_character = character


# ============================================
# Public API
# ============================================

## Get override look direction (returns ZERO if not tracking enemy)
func get_override_look_direction() -> Vector3:
	if not _character:
		return Vector3.ZERO

	var target_pos: Vector3 = Vector3.ZERO

	if _current_target and is_instance_valid(_current_target):
		# Active target - look at their current position
		target_pos = _current_target.global_position
	elif _is_tracking_last_known:
		# Lost sight but still within timeout - look at last known position
		target_pos = _last_known_position
	else:
		return Vector3.ZERO

	var char_pos: Vector3 = _character.global_position
	var direction: Vector3 = target_pos - char_pos
	direction.y = 0

	if direction.length_squared() < 0.01:
		return Vector3.ZERO

	return direction.normalized()


## Check if currently tracking an enemy
func is_tracking_enemy() -> bool:
	if _current_target and is_instance_valid(_current_target):
		return true
	return _is_tracking_last_known


## Get current target (may be null)
func get_current_target() -> Node:
	return _current_target


## Clear current target (useful when target dies, etc.)
func clear_target() -> void:
	if _current_target:
		var old_target := _current_target
		_current_target = null
		_is_tracking_last_known = false
		_time_since_lost = 0.0
		enemy_lost.emit(old_target)
		target_changed.emit(null, old_target)


## Dismiss current target due to user action (adds to ignore list)
## The enemy will be ignored for IGNORE_TIMEOUT seconds or until it becomes invisible
func dismiss_current_target() -> void:
	if _current_target and is_instance_valid(_current_target):
		_ignored_enemies.append(_current_target)
		_ignored_enemies_timer = 0.0  # Reset timeout
	clear_target()


## Enable automatic firing when enemy is in sight
func enable_firing() -> void:
	_firing_enabled = true


## Disable automatic firing
func disable_firing() -> void:
	_firing_enabled = false


## Check if automatic firing is enabled
func is_firing_enabled() -> bool:
	return _firing_enabled


## Get last shot result (hit status, miss offset, and critical hit)
func get_last_shot_result() -> Dictionary:
	return {
		"hit": _last_shot_hit,
		"miss_offset": _last_shot_miss_offset,
		"critical": _last_critical_hit
	}


## 検知・追跡フェーズ（エイム更新前に呼ぶ）
## 射撃ロジックは process_firing() に分離されている
func process(delta: float) -> void:
	if not _character:
		return

	# キャラクターキャッシュ更新（200ms間隔）
	_characters_cache_timer += delta
	if _characters_cache_timer >= CHARACTERS_CACHE_INTERVAL:
		_characters_cache_timer = 0.0
		_characters_cache = get_tree().get_nodes_in_group("characters")

	# Steady Aim: 静止時間の更新
	if _character is CharacterBody3D and _character.velocity.length() <= MOVEMENT_THRESHOLD:
		_stationary_time += delta
	else:
		_stationary_time = 0.0

	# Update tracking timeout
	if _is_tracking_last_known:
		_time_since_lost += delta
		if _time_since_lost >= TRACKING_TIMEOUT:
			_is_tracking_last_known = false
			_time_since_lost = 0.0

	# Update ignored enemies timer (real delta for accuracy)
	_update_ignored_list(delta)

	# Periodic enemy scan
	_scan_timer += delta
	if _scan_timer >= SCAN_INTERVAL:
		_scan_timer = 0.0
		_scan_for_enemies()


## 射撃フェーズ（エイム更新後に呼ぶ）
## process() で検知 → 呼び出し側でエイム更新 → この関数で射撃判定
func process_firing(delta: float) -> void:
	if not _character:
		return
	if _firing_enabled and _current_target and is_instance_valid(_current_target):
		# リアクションタイム消化中は射撃しない
		if _reaction_timer > 0.0:
			_reaction_timer -= delta
			return
		_process_firing(delta)
	else:
		_reset_firing_state()


# ============================================
# Internal Methods
# ============================================

## Update ignored enemies list - remove enemies by timeout or invisibility
func _update_ignored_list(delta: float) -> void:
	if _ignored_enemies.is_empty():
		return

	# 時間経過で自動解除（チーム共有視界では不可視にならないケースがあるため）
	_ignored_enemies_timer += delta
	if _ignored_enemies_timer >= IGNORE_TIMEOUT:
		_ignored_enemies.clear()
		_ignored_enemies_timer = 0.0
		return

	var to_remove: Array[Node] = []
	for enemy in _ignored_enemies:
		if not is_instance_valid(enemy):
			to_remove.append(enemy)
			continue
		# Remove from ignore list when enemy becomes invisible (EnemyVisibilitySystem)
		if enemy is Node3D and not enemy.visible:
			to_remove.append(enemy)

	for enemy in to_remove:
		_ignored_enemies.erase(enemy)


## Scan for visible enemies and select closest target
## プレイヤーチーム: EnemyVisibilitySystem（FoWテクスチャ）の結果（enemy.visible）を使用
## 敵AI: VisionComponent（個別レイキャスト）を使用
## 射撃制限は_is_facing_target()で行う（向いていないと撃たない）
func _scan_for_enemies() -> void:
	if not _character:
		return

	# Clear target immediately if they died
	if _current_target and is_instance_valid(_current_target):
		if "is_alive" in _current_target and not _current_target.is_alive:
			clear_target()

	# Check if character is alive
	if _character.has_method("is_alive") or "is_alive" in _character:
		if not _character.is_alive:
			clear_target()
			return

	# Get all enemy characters (uses cache, updated every 200ms)
	var enemies := _get_enemy_characters()
	if enemies.is_empty():
		_handle_no_enemy_in_sight()
		return

	# プレイヤーチームか判定
	# プレイヤーチーム: enemy.visible（FoW）と同じ判定を使用（表示と検知を統一）
	# 敵AI: VisionComponent（個別レイキャスト）で可視判定
	var is_player_team := _character is GameCharacter and PlayerState.is_friendly(_character)
	var vision: VisionComponent = null
	if _character.has_method("get_vision_component"):
		vision = _character.get_vision_component()
	if not is_player_team and not vision:
		_handle_no_enemy_in_sight()
		return

	# Find closest visible enemy
	var closest_enemy: Node = null
	var closest_distance: float = INF

	var char_pos: Vector3 = _character.global_position
	# プレイヤーチーム用: 仲間の遠方視界への反応を防ぐための距離制限
	# FoWのLight2Dはソフトエッジでview_distanceより少し先まで照らすためマージンを追加
	var max_detect_distance: float = (vision.view_distance if vision else 7.0) + 1.0

	for enemy in enemies:
		# Skip ignored enemies (dismissed by user action)
		if enemy in _ignored_enemies:
			continue

		# Skip dead enemies
		if "is_alive" in enemy and not enemy.is_alive:
			continue

		# 可視性チェック
		if is_player_team:
			# FoW可視性チェック: チーム全体の共有視界で非表示なら確実にスキップ
			if enemy is Node3D and not enemy.visible:
				continue
			# 個別視界チェック: 自分自身のVisionComponentで見えているか判定
			# COOPで味方の視界に映っているだけの敵に反応しないようにする
			if vision:
				var enemy_pos: Vector3 = enemy.global_position + Vector3(0, 1.0, 0)
				if not vision.is_position_in_view(enemy_pos):
					continue
			else:
				# VisionComponentがない場合は距離制限でフォールバック
				var dist_xz := Vector2(
					enemy.global_position.x - char_pos.x,
					enemy.global_position.z - char_pos.z
				).length()
				if dist_xz > max_detect_distance:
					continue
		else:
			# 敵AI: VisionComponentの個別レイキャストで可視判定
			var enemy_pos: Vector3 = enemy.global_position + Vector3(0, 1.0, 0)
			if not vision.is_position_in_view(enemy_pos):
				continue

		var dist: float = char_pos.distance_to(enemy.global_position)

		if dist < closest_distance:
			closest_distance = dist
			closest_enemy = enemy

	if closest_enemy:
		_handle_enemy_in_sight(closest_enemy)
	else:
		_handle_no_enemy_in_sight()


## Handle enemy detection
func _handle_enemy_in_sight(enemy: Node) -> void:
	_is_tracking_last_known = false
	_time_since_lost = 0.0

	# Update last known position
	_last_known_position = enemy.global_position

	if enemy != _current_target:
		var old_target := _current_target
		_current_target = enemy

		# 初弾リアクションタイム: Steady Aim進行度に応じて短縮
		# 完全静止（steady_aim_time経過）→ 0秒、移動中 → reaction_time
		var weapon = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
		if weapon:
			var steady_t: float = clampf(_stationary_time / weapon.steady_aim_time, 0.0, 1.0)
			_reaction_timer = weapon.reaction_time * (1.0 - steady_t)
		else:
			_reaction_timer = 0.0

		if old_target == null:
			enemy_spotted.emit(enemy)

		target_changed.emit(enemy, old_target)


## Handle no enemy in sight
func _handle_no_enemy_in_sight() -> void:
	if _current_target:
		var old_target := _current_target
		_last_known_position = old_target.global_position
		_current_target = null
		_is_tracking_last_known = true
		_time_since_lost = 0.0
		enemy_lost.emit(old_target)
		target_changed.emit(null, old_target)




## Get all enemy characters
func _get_enemy_characters() -> Array[Node]:
	var enemies: Array[Node] = []

	# キャッシュを使用（GC負荷削減）
	for character in _characters_cache:
		if character == _character:
			continue

		# Check if enemy using PlayerState or direct comparison
		var is_enemy := false

		if character is GameCharacter and _character is GameCharacter:
			is_enemy = _character.is_enemy_of(character)
		elif Engine.has_singleton("PlayerState") or has_node("/root/PlayerState"):
			var player_state = get_node_or_null("/root/PlayerState")
			if player_state and player_state.has_method("is_enemy"):
				# If our character is player team's ally, their enemies are our enemies
				if player_state.is_friendly(_character):
					is_enemy = player_state.is_enemy(character)
				else:
					# If our character is enemy team, player's allies are our enemies
					is_enemy = player_state.is_friendly(character)

		if is_enemy:
			enemies.append(character)

	return enemies




## キャラクターが現在のターゲット方向を向いているかチェック
## モデルの実際の回転状態（SLERP途中を含む）を使って判定する
func _is_facing_target() -> bool:
	if not _current_target or not is_instance_valid(_current_target):
		return false
	var to_target: Vector3 = _current_target.global_position - _character.global_position
	to_target.y = 0
	if to_target.length_squared() < 0.01:
		return true
	to_target = to_target.normalized()
	# モデルの実際の向きを取得（SLERP途中の状態を反映）
	var facing_dir := Vector3.ZERO
	var anim_ctrl = _character.get_anim_controller()
	if anim_ctrl:
		var model = anim_ctrl.get_model()
		if model:
			facing_dir = model.global_transform.basis.orthonormalized().z
			facing_dir.y = 0
	if facing_dir.length_squared() < 0.001:
		return false
	facing_dir = facing_dir.normalized()
	return facing_dir.dot(to_target) >= FACING_ANGLE_THRESHOLD


## Attempt to fire at current target
## Returns true if shot was taken, false if blocked (e.g. not facing target)
func _try_fire() -> bool:
	if not _character:
		return false
	# 投擲・ドア開放・gun_down中は射撃しない
	var anim_ctrl = _character.get_anim_controller() if _character.has_method("get_anim_controller") else null
	if anim_ctrl:
		if anim_ctrl.is_throwing() or anim_ctrl.is_opening_door() or anim_ctrl.is_gun_down():
			return false
	if not _is_facing_target():
		return false
	# ダメージ計算を先に行い、命中/外れ結果をセットしてからシグナルを発火
	# これによりBulletTrailComponentが正しい射撃結果を取得できる
	_apply_damage_to_target()
	if not anim_ctrl:
		anim_ctrl = _character.get_anim_controller() if _character.has_method("get_anim_controller") else null
	if anim_ctrl and anim_ctrl.has_method("fire"):
		anim_ctrl.fire()  # Trigger recoil animation + fired signal
	return true


## 距離カーブから基礎精度を取得
func _get_accuracy_from_curve(weapon: WeaponPreset, distance: float) -> float:
	if distance <= weapon.accuracy_range_min:
		# 0 〜 range_min: accuracy_close → accuracy_peak
		if weapon.accuracy_range_min <= 0.0:
			return weapon.accuracy_peak
		var t: float = distance / weapon.accuracy_range_min
		return lerpf(weapon.accuracy_close, weapon.accuracy_peak, t)
	elif distance <= weapon.accuracy_range_max:
		# range_min 〜 range_max: accuracy_peak 固定（スイートスポット）
		return weapon.accuracy_peak
	elif distance <= weapon.accuracy_max_distance:
		# range_max 〜 max_distance: accuracy_peak → accuracy_far
		var range_span: float = weapon.accuracy_max_distance - weapon.accuracy_range_max
		if range_span <= 0.0:
			return weapon.accuracy_far
		var t: float = (distance - weapon.accuracy_range_max) / range_span
		return lerpf(weapon.accuracy_peak, weapon.accuracy_far, t)
	else:
		# max_distance以降: accuracy_far 固定
		return weapon.accuracy_far


## 射手の移動状態による精度乗数を取得
func _get_shooter_movement_multiplier(weapon: WeaponPreset) -> float:
	if not (_character is CharacterBody3D):
		return 1.0
	var speed: float = _character.velocity.length()
	if speed <= MOVEMENT_THRESHOLD:
		# Steady Aim: 静止継続時間に応じてボーナス
		var steady_t: float = clampf(_stationary_time / weapon.steady_aim_time, 0.0, 1.0)
		return lerpf(1.0, weapon.steady_aim_bonus, steady_t)
	elif speed >= SPRINT_THRESHOLD:
		return weapon.shooter_sprint_penalty
	else:
		# 歩行〜スプリント間を補間
		var t: float = (speed - MOVEMENT_THRESHOLD) / (SPRINT_THRESHOLD - MOVEMENT_THRESHOLD)
		return lerpf(1.0, weapon.shooter_walk_penalty, t)


## ターゲットの移動状態による精度乗数を取得
func _get_target_movement_multiplier(weapon: WeaponPreset) -> float:
	if not _current_target or not is_instance_valid(_current_target):
		return 1.0
	if not (_current_target is CharacterBody3D):
		return 1.0
	var target_speed: float = _current_target.velocity.length()
	var speed_ratio: float = clampf(target_speed / weapon.target_speed_reference, 0.0, 1.0)
	return 1.0 - speed_ratio * weapon.target_move_penalty


## ダメージ距離減衰倍率を取得
func _get_damage_multiplier(weapon: WeaponPreset, distance: float) -> float:
	if not weapon.damage_falloff_enabled:
		return 1.0
	if distance <= weapon.damage_falloff_start:
		return 1.0
	if distance >= weapon.damage_falloff_end:
		return weapon.damage_falloff_min
	var range_span: float = weapon.damage_falloff_end - weapon.damage_falloff_start
	if range_span <= 0.0:
		return weapon.damage_falloff_min
	var t: float = (distance - weapon.damage_falloff_start) / range_span
	return lerpf(1.0, weapon.damage_falloff_min, t)


## Calculate hit chance based on weapon accuracy curve, distance, and movement
func _calculate_hit_chance(weapon: WeaponPreset, distance: float) -> float:
	if not weapon:
		return 0.5  # Default 50% if no weapon

	# 距離カーブから基礎精度
	var base_accuracy: float = _get_accuracy_from_curve(weapon, distance)

	# Apply auto firing mode accuracy modifier if applicable
	if _supports_auto_firing_mode():
		base_accuracy *= _get_current_accuracy_modifier()

	# 射手の移動ペナルティ
	var shooter_mult: float = _get_shooter_movement_multiplier(weapon)

	# ターゲットの移動ペナルティ
	var target_mult: float = _get_target_movement_multiplier(weapon)

	# 精度が高いほどバラつきが小さい
	var spread: float = (1.0 - base_accuracy) * randf() * 0.3

	# 最終命中率
	var final_accuracy: float = (base_accuracy - spread) * shooter_mult * target_mult
	return clampf(final_accuracy, 0.05, 1.0)  # Minimum 5% hit chance


## Roll hit check and return true if hit
func _roll_hit_check(weapon: WeaponPreset, distance: float) -> bool:
	var hit_chance: float = _calculate_hit_chance(weapon, distance)
	return randf() < hit_chance


## Calculate miss offset vector (perpendicular to target direction)
## 距離が遠いほどミスの散らばりが大きくなる
func _calculate_miss_offset() -> Vector3:
	if not _current_target or not is_instance_valid(_current_target):
		return Vector3.ZERO

	# Direction from shooter to target
	var to_target: Vector3 = _current_target.global_position - _character.global_position
	to_target.y = 0
	if to_target.length_squared() < 0.01:
		return Vector3.ZERO

	# 距離スケーリング: 遠いほどミスの散らばり大
	var distance: float = to_target.length()
	var distance_scale: float = clampf(distance / 20.0, 0.5, 2.5)

	to_target = to_target.normalized()

	# Perpendicular vector to target direction (horizontal)
	var right: Vector3 = to_target.cross(Vector3.UP).normalized()

	# Horizontal offset: left or right with random distance (距離スケーリング適用)
	var horizontal_offset: float = (randf() * 2.0 - 1.0) * randf_range(0.3, 1.2) * distance_scale

	# Vertical offset (smaller range, 距離スケーリング適用)
	var vertical_offset: float = randf_range(-0.4, 0.4) * distance_scale

	return right * horizontal_offset + Vector3.UP * vertical_offset


## Apply damage to the current target (with hit check)
func _apply_damage_to_target() -> void:
	if not _current_target or not is_instance_valid(_current_target):
		return
	if not _current_target.has_method("take_damage"):
		return

	var damage: float = 10.0  # Default damage
	var weapon = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if weapon and "damage" in weapon:
		damage = weapon.damage

	# Calculate distance to target
	var distance: float = _character.global_position.distance_to(_current_target.global_position)

	# Perform hit check
	var is_hit: bool = _roll_hit_check(weapon, distance)

	# Store result for bullet trail
	_last_shot_hit = is_hit

	if is_hit:
		# Hit - apply damage (with critical hit check and distance falloff)
		_last_shot_miss_offset = Vector3.ZERO
		var final_damage: float = damage
		# ダメージ距離減衰
		if weapon:
			final_damage *= _get_damage_multiplier(weapon, distance)
		var critical_rate: float = _get_current_critical_rate()
		_last_critical_hit = randf() < critical_rate
		if _last_critical_hit:
			final_damage *= 2.0  # Critical hit: 2x damage
		_current_target.take_damage(final_damage, _character, _last_critical_hit)
		# ネットワーク同期用シグナル
		damage_dealt.emit(_character, _current_target, final_damage, _last_critical_hit)
	else:
		# Miss - calculate miss offset and emit signal
		_last_shot_miss_offset = _calculate_miss_offset()
		_last_critical_hit = false


# ============================================
# Auto Firing Mode System
# ============================================

## Check if weapon supports auto firing mode
func _supports_auto_firing_mode() -> bool:
	var weapon = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if not weapon:
		return false
	if not weapon.auto_firing_mode_enabled:
		return false
	# Only RIFLE and SMG support auto firing mode
	return weapon.category == WeaponPreset.WeaponCategory.RIFLE or weapon.category == WeaponPreset.WeaponCategory.SMG


## Get current range type based on distance (0=CQB, 1=Medium, 2=Long)
func _get_range_type(distance: float) -> int:
	var weapon = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if not weapon:
		return 2  # Default to long range
	if distance <= weapon.cqb_max_distance:
		return 0  # CQB
	elif distance <= weapon.medium_max_distance:
		return 1  # Medium
	else:
		return 2  # Long


## Get firing mode for current range
func _get_current_firing_mode() -> int:
	if not _current_target or not is_instance_valid(_current_target):
		return WeaponPreset.FiringMode.SINGLE
	var weapon = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if not weapon:
		return WeaponPreset.FiringMode.SINGLE
	var distance: float = _character.global_position.distance_to(_current_target.global_position)
	var range_type: int = _get_range_type(distance)
	match range_type:
		0: return weapon.cqb_firing_mode
		1: return weapon.medium_firing_mode
		_: return weapon.long_firing_mode


## Get shots per burst for current range
func _get_current_shots_per_burst() -> int:
	var weapon = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if not weapon or not _current_target:
		return 1
	var distance: float = _character.global_position.distance_to(_current_target.global_position)
	var range_type: int = _get_range_type(distance)
	match range_type:
		0: return weapon.cqb_shots_per_burst
		1: return weapon.medium_shots_per_burst
		_: return weapon.long_shots_per_burst


## Get burst interval for current range
func _get_current_burst_interval() -> float:
	var weapon = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if not weapon or not _current_target:
		return 0.1
	var distance: float = _character.global_position.distance_to(_current_target.global_position)
	var range_type: int = _get_range_type(distance)
	match range_type:
		0: return weapon.cqb_burst_interval
		1: return weapon.medium_burst_interval
		_: return weapon.long_burst_interval


## Get pause after burst for current range
func _get_current_pause_after_burst() -> float:
	var weapon = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if not weapon or not _current_target:
		return 0.5
	var distance: float = _character.global_position.distance_to(_current_target.global_position)
	var range_type: int = _get_range_type(distance)
	match range_type:
		0: return weapon.cqb_pause_after_burst
		1: return weapon.medium_pause_after_burst
		_: return weapon.long_pause_after_burst


## Get accuracy modifier for current range
func _get_current_accuracy_modifier() -> float:
	var weapon = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if not weapon or not _current_target:
		return 1.0
	var distance: float = _character.global_position.distance_to(_current_target.global_position)
	var range_type: int = _get_range_type(distance)
	match range_type:
		0: return weapon.cqb_accuracy_modifier
		1: return weapon.medium_accuracy_modifier
		_: return weapon.long_accuracy_modifier


## Get critical hit rate for current range
func _get_current_critical_rate() -> float:
	if not _supports_auto_firing_mode():
		return 0.0  # No critical hits for non-auto firing mode weapons
	var weapon = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	if not weapon or not _current_target:
		return 0.0
	var distance: float = _character.global_position.distance_to(_current_target.global_position)
	var range_type: int = _get_range_type(distance)
	match range_type:
		0: return weapon.cqb_critical_rate
		1: return weapon.medium_critical_rate
		_: return weapon.long_critical_rate


## Process firing state machine
func _process_firing(delta: float) -> void:
	# Use legacy firing for non-auto firing mode weapons
	if not _supports_auto_firing_mode():
		_process_legacy_firing(delta)
		return

	# Handle post-burst pause
	if _post_burst_pause_timer > 0.0:
		_post_burst_pause_timer -= delta
		if _post_burst_pause_timer <= 0.0:
			_post_burst_pause_timer = 0.0
			# Start new burst after pause
			_start_burst()
		return

	# Handle burst in progress
	if _is_in_burst:
		_burst_interval_timer -= delta
		if _burst_interval_timer <= 0.0:
			_fire_burst_shot()
		return

	# Not in burst and no pause - start new burst
	_start_burst()


## Legacy firing for pistols and other non-auto mode weapons
func _process_legacy_firing(delta: float) -> void:
	var weapon = _character.get_current_weapon() if _character.has_method("get_current_weapon") else null
	var interval: float = weapon.fire_rate if weapon and weapon.fire_rate > 0.0 else FIRE_INTERVAL
	_fire_timer += delta
	if _fire_timer >= interval:
		if _try_fire():
			_fire_timer = 0.0
		else:
			# 向き未完了：タイマーを維持し、次フレームで即リトライ
			_fire_timer = interval


## Start a new burst sequence
func _start_burst() -> void:
	_current_firing_mode = _get_current_firing_mode()
	var shots: int = _get_current_shots_per_burst()

	if _current_firing_mode == WeaponPreset.FiringMode.FULL_AUTO and shots == 0:
		# Continuous fire mode - fire immediately and continue
		_is_in_burst = true
		_burst_shots_remaining = 999999  # Effectively unlimited
		_fire_burst_shot()
	elif _current_firing_mode == WeaponPreset.FiringMode.SINGLE or shots == 1:
		# Single shot mode
		_is_in_burst = false
		if _try_fire():
			_post_burst_pause_timer = _get_current_pause_after_burst()
		# 発射失敗時はpauseを設定しない→次フレームで再度_start_burst()が呼ばれる
	else:
		# Burst mode
		_is_in_burst = true
		_burst_shots_remaining = shots
		_fire_burst_shot()


## Fire a single shot within a burst
func _fire_burst_shot() -> void:
	if not _current_target or not is_instance_valid(_current_target):
		_end_burst()
		return

	if _try_fire():
		_burst_shots_remaining -= 1
		if _burst_shots_remaining <= 0 or (_current_firing_mode != WeaponPreset.FiringMode.FULL_AUTO and _burst_shots_remaining <= 0):
			_end_burst()
		else:
			# Schedule next shot in burst
			_burst_interval_timer = _get_current_burst_interval()
	else:
		# 向き未完了：ショット数を消費せず次フレームで即リトライ
		_burst_interval_timer = 0.0


## End the current burst
func _end_burst() -> void:
	_is_in_burst = false
	_burst_shots_remaining = 0
	_burst_interval_timer = 0.0

	# Check if we should continue with full auto
	if _current_firing_mode == WeaponPreset.FiringMode.FULL_AUTO:
		var shots: int = _get_current_shots_per_burst()
		if shots == 0:
			# Continuous fire - very short pause
			_post_burst_pause_timer = _get_current_burst_interval()
		else:
			_post_burst_pause_timer = _get_current_pause_after_burst()
	else:
		_post_burst_pause_timer = _get_current_pause_after_burst()


## Reset all firing state
func _reset_firing_state() -> void:
	_fire_timer = 0.0
	_is_in_burst = false
	_burst_shots_remaining = 0
	_burst_interval_timer = 0.0
	_post_burst_pause_timer = 0.0
	_current_firing_mode = -1
	_reaction_timer = 0.0
