class_name CombatComponent
extends Node

## 戦闘コンポーネント
## キャラクターの攻撃ロジックを管理
## - 視界内の敵を自動攻撃
## - 確率ベースの命中判定（部位判定あり）
## - 武器ごとの発砲レート制御

signal target_acquired(target: Node3D)
signal target_lost()
signal fired(target: Node3D, hit: bool, damage: int)
signal killed(target: Node3D)

## 部位判定の結果
enum HitZone { MISS, BODY, HEAD }

@export_group("戦闘設定")
@export var auto_attack: bool = true  # 自動攻撃を有効にするか
@export var headshot_chance: float = 0.15  # ヘッドショット確率（命中時）
@export var walking_accuracy_modifier: float = 0.7  # 歩行中の命中率倍率

# 親キャラクター参照
var character: CharacterBody3D = null

# 現在のターゲット
var current_target: Node3D = null

# 武器データ（CharacterSetupから取得）
var weapon_data: Dictionary = {}

# 発砲クールダウン
var _fire_cooldown: float = 0.0

# 戦闘可能フラグ（死亡時などにfalse）
var _can_fight: bool = true

# 視界内の敵リスト
var _visible_enemies: Array[Node3D] = []

# 射撃状態タイマー（発砲後しばらく射撃ポーズを維持）
var _shooting_state_timer: float = 0.0
const SHOOTING_STATE_DURATION: float = 0.5


func _ready() -> void:
	character = get_parent() as CharacterBody3D
	if not character:
		push_error("[CombatComponent] Parent must be CharacterBody3D")
		return

	# 武器データの初期化
	_update_weapon_data()
	print("[CombatComponent] %s initialized, weapon_damage=%d" % [character.name, weapon_data.get("damage", 0)])


func _process(delta: float) -> void:
	# 射撃状態タイマーを更新
	_update_shooting_state(delta)

	if not _can_fight or not auto_attack:
		return

	# 実行フェーズのみ攻撃可能
	if not _can_attack_now():
		return

	# クールダウン更新
	if _fire_cooldown > 0:
		_fire_cooldown -= delta

	# 視界内の敵を検出
	_detect_visible_enemies()

	# ターゲット更新
	_update_target()

	# スプリント中は射撃不可
	if character.is_running:
		return

	# 攻撃実行
	if current_target and _fire_cooldown <= 0:
		_execute_attack()


## 射撃状態を更新
func _update_shooting_state(delta: float) -> void:
	if _shooting_state_timer > 0:
		_shooting_state_timer -= delta
		if _shooting_state_timer <= 0:
			# タイマー終了、射撃状態を解除
			if character.has_method("set_shooting"):
				character.set_shooting(false)


## 現在攻撃可能かどうか
func _can_attack_now() -> bool:
	if GameManager and GameManager.match_manager:
		return GameManager.match_manager.can_execute_movement()
	return true


## 視界内の敵を検出
func _detect_visible_enemies() -> void:
	_visible_enemies.clear()

	# 敵グループを取得
	var enemy_group = _get_enemy_group()
	if enemy_group.is_empty():
		return

	var enemies = character.get_tree().get_nodes_in_group(enemy_group)

	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy == character:
			continue
		if not _is_alive(enemy):
			continue

		# 射程内かチェック
		var distance = character.global_position.distance_to(enemy.global_position)
		var weapon_range = weapon_data.get("range", 10.0)
		if distance > weapon_range * 1.5:  # 射程の1.5倍まで検出
			continue

		# 視線が通っているかチェック
		if _has_line_of_sight(enemy):
			_visible_enemies.append(enemy)

	# デバッグ: 敵検出状況を出力（1秒ごと）
	if Engine.get_process_frames() % 60 == 0 and not _visible_enemies.is_empty():
		print("[CombatComponent] %s detected %d enemies" % [character.name, _visible_enemies.size()])


## 敵グループ名を取得
func _get_enemy_group() -> String:
	# プレイヤーなら敵は"enemies"、敵ならプレイヤーは"player"
	if character.is_in_group("player"):
		return "enemies"
	elif character.is_in_group("enemies"):
		return "player"
	return ""


## 視線が通っているかチェック
func _has_line_of_sight(target: Node3D) -> bool:
	var space_state = character.get_world_3d().direct_space_state

	# 頭の位置から射撃
	var from = character.global_position + Vector3(0, 1.5, 0)
	var to = target.global_position + Vector3(0, 1.0, 0)

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 6  # 壁レイヤー
	query.exclude = [character, target]

	var result = space_state.intersect_ray(query)

	# 何にも当たらなければ視線が通っている
	return result.is_empty()


## 武器データを更新
func _update_weapon_data() -> void:
	if character and character.has_method("get_current_weapon_id"):
		var weapon_id = character.get_current_weapon_id()
		weapon_data = CharacterSetup.get_weapon_data(weapon_id)
	else:
		weapon_data = CharacterSetup.get_weapon_data(CharacterSetup.WeaponId.NONE)


## 武器変更時に呼び出す
func on_weapon_changed(weapon_id: int) -> void:
	weapon_data = CharacterSetup.get_weapon_data(weapon_id)


## 視界内の敵リストを更新（外部から呼び出される）
func set_visible_enemies(enemies: Array[Node3D]) -> void:
	_visible_enemies = enemies

	# ターゲットが視界外になった場合
	if current_target and current_target not in _visible_enemies:
		current_target = null
		target_lost.emit()


## ターゲットを更新（最も近い敵を選択）
func _update_target() -> void:
	if _visible_enemies.is_empty():
		if current_target:
			current_target = null
			target_lost.emit()
		return

	# 生存している敵のみをフィルタ
	var alive_enemies: Array[Node3D] = []
	for enemy in _visible_enemies:
		if is_instance_valid(enemy) and _is_alive(enemy):
			alive_enemies.append(enemy)

	if alive_enemies.is_empty():
		if current_target:
			current_target = null
			target_lost.emit()
		return

	# 最も近い敵を選択
	var closest: Node3D = null
	var closest_dist: float = INF

	for enemy in alive_enemies:
		var dist = character.global_position.distance_to(enemy.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = enemy

	if closest != current_target:
		current_target = closest
		if current_target:
			target_acquired.emit(current_target)


## 敵が生存しているかチェック
func _is_alive(target: Node3D) -> bool:
	if target.has_method("is_alive"):
		return target.is_alive()
	if target.has_method("get_health"):
		return target.get_health() > 0
	# health変数を直接チェック
	if "health" in target:
		return target.health > 0
	return true


## 攻撃を実行
func _execute_attack() -> void:
	if not current_target or not is_instance_valid(current_target):
		return

	# 武器がない場合は攻撃しない
	if weapon_data.damage <= 0:
		return

	# 発砲クールダウン設定
	_fire_cooldown = weapon_data.fire_rate

	# 射撃状態を設定（上半身アニメーション用）
	_shooting_state_timer = SHOOTING_STATE_DURATION
	if character.has_method("set_shooting"):
		character.set_shooting(true)

	# マズルフラッシュを表示
	_show_muzzle_flash()

	# 命中判定
	var hit_result = _calculate_hit(current_target)

	if hit_result.zone == HitZone.MISS:
		fired.emit(current_target, false, 0)
		print("[CombatComponent] %s missed %s" % [character.name, current_target.name])
		return

	# ダメージ計算
	var damage = _calculate_damage(hit_result.zone)

	# ダメージ適用
	_apply_damage(current_target, damage, hit_result.zone)

	fired.emit(current_target, true, damage)

	var zone_name = "HEAD" if hit_result.zone == HitZone.HEAD else "BODY"
	print("[CombatComponent] %s hit %s (%s) for %d damage" % [
		character.name, current_target.name, zone_name, damage
	])


## 命中判定を計算
func _calculate_hit(target: Node3D) -> Dictionary:
	var result = { "zone": HitZone.MISS, "accuracy": 0.0 }

	# 距離に基づく命中率計算
	var distance = character.global_position.distance_to(target.global_position)
	var base_accuracy = weapon_data.get("accuracy", 0.5)
	var weapon_range = weapon_data.get("range", 10.0)

	# 距離による命中率減衰（rangeの距離で命中率が半減）
	var distance_modifier = 1.0
	if weapon_range > 0:
		distance_modifier = clampf(1.0 - (distance / weapon_range) * 0.5, 0.1, 1.0)

	# 移動中の命中率低下（歩行中のみ、スプリント中は射撃不可なのでここには来ない）
	var movement_modifier = 1.0
	if character.is_moving and not character.is_running:
		movement_modifier = walking_accuracy_modifier

	var final_accuracy = base_accuracy * distance_modifier * movement_modifier
	result.accuracy = final_accuracy

	# 命中判定
	if randf() > final_accuracy:
		result.zone = HitZone.MISS
		return result

	# 部位判定（命中時）
	if randf() < headshot_chance:
		result.zone = HitZone.HEAD
	else:
		result.zone = HitZone.BODY

	return result


## ダメージを計算
func _calculate_damage(zone: HitZone) -> int:
	var base_damage = weapon_data.get("damage", 0)

	match zone:
		HitZone.HEAD:
			var multiplier = weapon_data.get("headshot_multiplier", 4.0)
			return int(base_damage * multiplier)
		HitZone.BODY:
			var multiplier = weapon_data.get("bodyshot_multiplier", 1.0)
			return int(base_damage * multiplier)
		_:
			return 0


## ダメージを適用
func _apply_damage(target: Node3D, damage: int, zone: HitZone) -> void:
	if target.has_method("take_damage"):
		var is_headshot = (zone == HitZone.HEAD)
		target.take_damage(damage, character, is_headshot)
	elif "health" in target:
		target.health -= damage
		if target.health <= 0:
			_on_target_killed(target)


## ターゲットを倒した時
func _on_target_killed(target: Node3D) -> void:
	killed.emit(target)

	# GameEventsに通知
	if has_node("/root/GameEvents"):
		var weapon_id = 0
		if character.has_method("get_current_weapon_id"):
			weapon_id = character.get_current_weapon_id()
		get_node("/root/GameEvents").unit_killed.emit(character, target, weapon_id)

	print("[CombatComponent] %s killed %s" % [character.name, target.name])


## マズルフラッシュを表示
func _show_muzzle_flash() -> void:
	# 武器からMuzzleFlashノードを探す
	if not character.weapon_attachment:
		return

	# find_childで再帰的に探す（パス構造に依存しない）
	var muzzle_flash = character.weapon_attachment.find_child("MuzzleFlash", true, false)
	if muzzle_flash and muzzle_flash.has_method("flash"):
		muzzle_flash.flash()


## 戦闘を無効化（死亡時など）
func disable_combat() -> void:
	_can_fight = false
	current_target = null


## 戦闘を有効化
func enable_combat() -> void:
	_can_fight = true


## ラウンドリセット
func reset() -> void:
	_can_fight = true
	current_target = null
	_fire_cooldown = 0.0
	_visible_enemies.clear()
	_update_weapon_data()
