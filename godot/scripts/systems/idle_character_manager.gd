extends Node
class_name IdleCharacterManager
## アイドルキャラクター管理
## TPS操作対象以外のキャラクターの状態更新を担当
## wandering_enabled = true 時、CPUキャラクターが自動的にマップ内を歩き回る

## 管理対象キャラクターリスト
var characters: Array[Node] = []

## プライマリキャラクター取得用のコールバック
var get_primary_callback: Callable

## 徘徊モード有効化（トレーニングモードでON）
var wandering_enabled: bool = false

## 1キャラクターごとの徘徊状態
## key: GameCharacter, value: { state, target_pos, timer, stuck_pos, stuck_timer, ray_timer }
var _wander_data: Dictionary = {}

## 徘徊ステート
enum WanderState { IDLE, WALKING }

## 徘徊定数
const WANDER_RADIUS := 6.0
const IDLE_TIME_MIN := 1.5
const IDLE_TIME_MAX := 4.0
const ARRIVAL_THRESHOLD := 0.5
const STUCK_TIME := 2.0
const WALL_CHECK_DISTANCE := 1.5
const RAY_CHECK_INTERVAL := 0.15
const FAN_RAY_ANGLE := deg_to_rad(30.0)


## セットアップ
func setup(
	char_list: Array[Node],
	primary_getter: Callable
) -> void:
	characters = char_list
	get_primary_callback = primary_getter


## キャラクターを追加
func add_character(character: Node) -> void:
	if not characters.has(character):
		characters.append(character)


## キャラクターを削除
func remove_character(character: Node) -> void:
	characters.erase(character)
	_wander_data.erase(character)


## キャラクターリストを更新
func set_characters(char_list: Array[Node]) -> void:
	characters = char_list
	_wander_data.clear()


## アイドル中のキャラクターを更新（毎フレーム呼ぶ）
func process_idle_characters(delta: float) -> void:
	var primary = get_primary_callback.call() if get_primary_callback.is_valid() else null

	for character in characters:
		var game_char := character as GameCharacter
		if not game_char:
			continue

		# リモートキャラクターはスキップ（ネットワークから状態を受信するため）
		if not game_char.is_local():
			continue

		# プライマリキャラクターはスキップ（TPSPlayerControllerが制御）
		if character == primary:
			continue
		# 死亡中はスキップ
		if not game_char.is_alive:
			continue

		_update_idle_character(character, delta)


## 単一キャラクターのアイドル状態を更新
func _update_idle_character(character: Node, delta: float) -> void:
	# フェーズ1: 敵検知（ターゲット特定のみ）
	if character.combat_awareness and character.combat_awareness.has_method("process"):
		character.combat_awareness.process(delta)

	var anim_ctrl = character.get_anim_controller()
	if not anim_ctrl:
		return

	var is_tracking := false
	var look_dir := Vector3.ZERO

	# 敵追跡チェック（手動回転中はスキップ）
	var is_manual_rotating: bool = false
	if character.has_method("is_manual_rotating"):
		is_manual_rotating = character.is_manual_rotating()
	if not is_manual_rotating and character.combat_awareness and character.combat_awareness.has_method("is_tracking_enemy"):
		if character.combat_awareness.is_tracking_enemy():
			is_tracking = true
			look_dir = character.combat_awareness.get_override_look_direction()

	if look_dir.length_squared() < 0.1:
		look_dir = anim_ctrl.get_look_direction()

	# フェーズ2: 徘徊処理
	var move_dir := Vector3.ZERO
	if wandering_enabled and not is_tracking:
		move_dir = _process_wandering(character, delta)

	# facing_direction を明示更新（視界判定・同期用）
	if is_tracking and look_dir.length_squared() > 0.01:
		character.set_facing_direction_vec(look_dir)
	elif move_dir.length_squared() > 0.01:
		character.set_facing_direction_vec(move_dir)

	# フェーズ3: アニメーション更新
	anim_ctrl.update_animation(move_dir, look_dir, false, delta)

	# フェーズ4: 物理移動（wandering ON/OFF 共通）
	if move_dir.length_squared() > 0.01:
		character.velocity = move_dir * CharacterAnimationController.WALK_SPEED
	else:
		character.velocity.x = 0
		character.velocity.z = 0
	if not character.is_on_floor():
		character.velocity.y -= 9.8 * delta
	character.move_and_slide()

	# フェーズ5: 射撃判定
	if character.combat_awareness and character.combat_awareness.has_method("process_firing"):
		character.combat_awareness.process_firing(delta)


## 徘徊処理（ステートマシン）
func _process_wandering(character: CharacterBody3D, delta: float) -> Vector3:
	if not _wander_data.has(character):
		_wander_data[character] = {
			"state": WanderState.IDLE,
			"target_pos": Vector3.ZERO,
			"timer": randf_range(IDLE_TIME_MIN, IDLE_TIME_MAX),
			"stuck_pos": character.global_position,
			"stuck_timer": 0.0,
			"ray_timer": randf() * RAY_CHECK_INTERVAL,  # 位相をずらす
		}

	var data: Dictionary = _wander_data[character]
	var state: int = data["state"]

	if state == WanderState.IDLE:
		data["timer"] -= delta
		if data["timer"] <= 0.0:
			var target := _pick_random_target(character)
			data["target_pos"] = target
			data["state"] = WanderState.WALKING
			data["stuck_pos"] = character.global_position
			data["stuck_timer"] = 0.0
			data["ray_timer"] = 0.0
		return Vector3.ZERO

	# WALKING
	var target_pos: Vector3 = data["target_pos"]
	var char_pos := character.global_position
	var to_target := target_pos - char_pos
	to_target.y = 0.0
	var dist := to_target.length()

	# 到着判定
	if dist < ARRIVAL_THRESHOLD:
		data["state"] = WanderState.IDLE
		data["timer"] = randf_range(IDLE_TIME_MIN, IDLE_TIME_MAX)
		return Vector3.ZERO

	var move_dir := to_target.normalized()

	# スタック検知
	data["stuck_timer"] += delta
	if data["stuck_timer"] >= STUCK_TIME:
		var stuck_pos: Vector3 = data["stuck_pos"]
		var moved := Vector3(char_pos.x - stuck_pos.x, 0.0, char_pos.z - stuck_pos.z).length()
		if moved < 0.3:
			# スタック → 新しい目標を選択してIDLEに
			data["state"] = WanderState.IDLE
			data["timer"] = randf_range(0.5, 1.0)
			return Vector3.ZERO
		data["stuck_pos"] = char_pos
		data["stuck_timer"] = 0.0

	# レイキャスト間引き: 壁チェック
	data["ray_timer"] -= delta
	if data["ray_timer"] <= 0.0:
		data["ray_timer"] = RAY_CHECK_INTERVAL
		if _check_wall_ahead(character, move_dir):
			# 壁 → 新しい目標を選択
			var new_target := _pick_random_target(character)
			data["target_pos"] = new_target
			data["stuck_pos"] = char_pos
			data["stuck_timer"] = 0.0
			# 更新された方向を返す
			var new_dir := (new_target - char_pos)
			new_dir.y = 0.0
			if new_dir.length_squared() > 0.01:
				return new_dir.normalized()
			return Vector3.ZERO

	return move_dir


## 前方3方向ファンレイキャストで壁チェック
func _check_wall_ahead(character: CharacterBody3D, move_dir: Vector3) -> bool:
	var space_state := character.get_world_3d().direct_space_state
	if not space_state:
		return false

	var origin := character.global_position + Vector3.UP * 0.5
	var dirs: Array[Vector3] = [move_dir]

	# 左30°
	var left := move_dir.rotated(Vector3.UP, FAN_RAY_ANGLE)
	dirs.append(left)
	# 右30°
	var right := move_dir.rotated(Vector3.UP, -FAN_RAY_ANGLE)
	dirs.append(right)

	for dir in dirs:
		var query := PhysicsRayQueryParameters3D.create(
			origin, origin + dir * WALL_CHECK_DISTANCE
		)
		query.collision_mask = MapBase.WALL_COLLISION_LAYER
		if not space_state.intersect_ray(query).is_empty():
			return true

	return false


## ランダムな徘徊目標地点を選択
func _pick_random_target(character: CharacterBody3D) -> Vector3:
	var char_pos := character.global_position
	var space_state := character.get_world_3d().direct_space_state

	for _attempt in range(3):
		var angle := randf() * TAU
		var radius := randf_range(2.0, WANDER_RADIUS)
		var target := Vector3(
			char_pos.x + cos(angle) * radius,
			char_pos.y,
			char_pos.z + sin(angle) * radius
		)

		# 壁チェック（目標方向にレイキャスト）
		if space_state:
			var origin := char_pos + Vector3.UP * 0.5
			var target_h := target + Vector3.UP * 0.5
			var query := PhysicsRayQueryParameters3D.create(origin, target_h)
			query.collision_mask = MapBase.WALL_COLLISION_LAYER
			if not space_state.intersect_ray(query).is_empty():
				continue  # 壁がある → 別方向を試行

		return target

	# 全試行失敗 → 現在位置を返す（IDLEに戻る）
	return char_pos


## プライマリキャラクターのアイドル処理（手動操作無効時）
func process_primary_idle(character: Node, delta: float) -> void:
	if not character or not character.is_alive:
		return

	# リモートキャラクターはスキップ（ネットワークから状態を受信するため）
	var game_char := character as GameCharacter
	if game_char and not game_char.is_local():
		return

	# フェーズ1: 敵検知（ターゲット特定のみ）
	if character.combat_awareness and character.combat_awareness.has_method("process"):
		character.combat_awareness.process(delta)

	var anim_ctrl = character.get_anim_controller()
	if not anim_ctrl:
		return

	var look_dir: Vector3 = Vector3.ZERO

	# 敵視認チェック（最優先、ただし手動回転中はスキップ）
	var is_manual_rotating: bool = false
	if character.has_method("is_manual_rotating"):
		is_manual_rotating = character.is_manual_rotating()
	if not is_manual_rotating and character.combat_awareness and character.combat_awareness.has_method("is_tracking_enemy"):
		if character.combat_awareness.is_tracking_enemy():
			look_dir = character.combat_awareness.get_override_look_direction()

	# デフォルト: 現在の向きを維持
	if look_dir.length_squared() < 0.1:
		look_dir = anim_ctrl.get_look_direction()

	# フェーズ2: アニメーション更新（SLERP回転を進める）
	anim_ctrl.update_animation(Vector3.ZERO, look_dir, false, delta)

	# フェーズ3: 射撃判定（回転後に向き完了チェック）
	if character.combat_awareness and character.combat_awareness.has_method("process_firing"):
		character.combat_awareness.process_firing(delta)

	# 重力適用
	character.velocity.x = 0
	character.velocity.z = 0
	if not character.is_on_floor():
		character.velocity.y -= 9.8 * delta
	character.move_and_slide()
