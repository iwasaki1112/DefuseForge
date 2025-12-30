class_name CharacterBase
extends CharacterBody3D

## キャラクター基底クラス
## 移動、アニメーション、地形追従の共通機能を提供

# CharacterSetup はグローバルクラス名として登録されているため、直接参照可能

signal path_completed
signal waypoint_reached(index: int)
signal died
signal weapon_type_changed(weapon_type: int)
signal weapon_changed(weapon_id: int)

@export_group("移動設定")
@export var base_walk_speed: float = 3.0
@export var base_run_speed: float = 6.0
@export var rotation_speed: float = 10.0

# 武器による速度倍率適用後の実効速度
var walk_speed: float = 3.0
var run_speed: float = 6.0

@export_group("物理設定")
@export var gravity_value: float = -20.0

# 物理状態
var vertical_velocity: float = 0.0

# パス追従用
var waypoints: Array = []  # Array of {position: Vector3, run: bool}
var current_waypoint_index: int = 0
var is_moving: bool = false
var is_running: bool = false

# アニメーション
var anim_player: AnimationPlayer = null
var current_move_state: int = -1  # -1: uninitialized, 0: idle, 1: walk, 2: run
var current_weapon_type: int = CharacterSetup.WeaponType.NONE
var current_weapon_id: int = CharacterSetup.WeaponId.NONE
const ANIM_BLEND_TIME: float = 0.3

# 武器
var weapon_attachment: Node3D = null
var skeleton: Skeleton3D = null

# ステータス
var health: float = 100.0
var armor: float = 0.0
var is_alive: bool = true


func _ready() -> void:
	floor_snap_length = 1.0
	_update_speed_from_weapon()  # 初期速度を設定
	_setup_character()
	_initial_placement.call_deferred()


## キャラクターのセットアップ（オーバーライド可能）
func _setup_character() -> void:
	var model = get_node_or_null("CharacterModel")
	if model:
		print("[%s] CharacterModel found" % name)

		# マテリアルとテクスチャを設定
		CharacterSetup.setup_materials(model, name)

		# Yオフセットを適用
		var meshes = CharacterSetup.find_meshes(model)
		for mesh in meshes:
			var y_offset = CharacterSetup.get_y_offset(mesh.name)
			if y_offset != 0.0:
				model.position.y = y_offset
				print("[%s] Applied Y offset %.3f (from mesh '%s')" % [name, y_offset, mesh.name])
				break

		# Skeletonを取得（武器装着用）
		skeleton = CharacterSetup.find_skeleton(model)
		if skeleton:
			print("[%s] Skeleton found: %s" % [name, skeleton.name])

		# AnimationPlayerを取得
		anim_player = CharacterSetup.find_animation_player(model)
		if anim_player:
			print("[%s] AnimationPlayer found" % name)
			CharacterSetup.load_animations(anim_player, model, name)
			# 初期アニメーションを再生
			var idle_anim = CharacterSetup.get_animation_name("idle", current_weapon_type)
			if anim_player.has_animation(idle_anim):
				anim_player.play(idle_anim)
		else:
			print("[%s] NO AnimationPlayer!" % name)
	else:
		print("[%s] NO CharacterModel!" % name)


func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	# アニメーションは常に更新（PLAYING以外でもidleを再生）
	_update_animation()

	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	# 移動は実行フェーズのみ
	if _can_execute_movement():
		_handle_path_movement(delta)

	_handle_terrain_follow(delta)
	move_and_slide()


## 移動実行が可能かどうか
func _can_execute_movement() -> bool:
	if GameManager and GameManager.match_manager:
		return GameManager.match_manager.can_execute_movement()
	return true  # MatchManagerがなければ許可


## パス追従移動
func _handle_path_movement(delta: float) -> void:
	if is_moving and waypoints.size() > 0 and current_waypoint_index < waypoints.size():
		var waypoint: Dictionary = waypoints[current_waypoint_index]
		var target: Vector3 = waypoint.position
		is_running = waypoint.run

		var direction := (target - global_position)
		direction.y = 0
		var distance := direction.length()

		if distance < 0.3:  # ウェイポイント到達
			waypoint_reached.emit(current_waypoint_index)
			current_waypoint_index += 1
			if current_waypoint_index >= waypoints.size():
				_stop_moving()
				path_completed.emit()
			return

		# 移動方向に回転
		if direction.length() > 0.1:
			var target_rotation := atan2(direction.x, direction.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)

		# 移動
		var speed := run_speed if is_running else walk_speed
		var move_dir := direction.normalized()
		velocity.x = move_dir.x * speed
		velocity.z = move_dir.z * speed
	else:
		velocity.x = 0
		velocity.z = 0


## 地形追従処理
func _handle_terrain_follow(delta: float) -> void:
	if is_on_floor():
		vertical_velocity = -0.1
	else:
		vertical_velocity += gravity_value * delta
		vertical_velocity = max(vertical_velocity, -50.0)

	velocity.y = vertical_velocity


## パスを設定して移動開始
func set_path(new_waypoints: Array) -> void:
	waypoints = new_waypoints
	current_waypoint_index = 0
	is_running = false
	is_moving = waypoints.size() > 0


## 移動停止
func _stop_moving() -> void:
	is_moving = false
	waypoints.clear()
	current_waypoint_index = 0


## 移動を中断
func stop() -> void:
	_stop_moving()


## 単一地点への移動
func move_to(target: Vector3, run: bool = false) -> void:
	set_path([{"position": target, "run": run}])


## 初期配置
func _initial_placement() -> void:
	print("[%s] _initial_placement started, pos=%s" % [name, global_position])
	visible = false

	await get_tree().physics_frame
	await get_tree().physics_frame
	_snap_to_ground()
	print("[%s] after snap, pos=%s" % [name, global_position])

	visible = true
	print("[%s] visible=true, final pos=%s" % [name, global_position])


## 地面にスナップ
func _snap_to_ground() -> void:
	var space_state := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 10, 0)
	var to := global_position + Vector3(0, -100, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2  # 地形レイヤー
	query.exclude = [self]

	var result := space_state.intersect_ray(query)
	if result:
		global_position = result.position
		vertical_velocity = 0


## アニメーション更新
func _update_animation() -> void:
	if anim_player == null:
		return

	var new_state: int = 0
	if is_moving:
		new_state = 2 if is_running else 1
	else:
		new_state = 0

	if new_state != current_move_state:
		current_move_state = new_state
		_play_current_animation()


## 現在の状態に応じたアニメーションを再生
func _play_current_animation() -> void:
	if anim_player == null:
		return

	anim_player.speed_scale = 1.0
	var anim_name: String = ""

	match current_move_state:
		0:  # idle
			anim_name = CharacterSetup.get_animation_name("idle", current_weapon_type)
		1:  # walk
			anim_name = CharacterSetup.get_animation_name("walking", current_weapon_type)
		2:  # run
			anim_name = CharacterSetup.get_animation_name("running", current_weapon_type)

	# 武器タイプ別アニメーションがない場合はnoneにフォールバック
	if not anim_player.has_animation(anim_name):
		var fallback_type = CharacterSetup.WeaponType.NONE
		match current_move_state:
			0:
				anim_name = CharacterSetup.get_animation_name("idle", fallback_type)
			1:
				anim_name = CharacterSetup.get_animation_name("walking", fallback_type)
			2:
				anim_name = CharacterSetup.get_animation_name("running", fallback_type)
				if not anim_player.has_animation(anim_name):
					# runがない場合はwalkを速く再生
					anim_name = CharacterSetup.get_animation_name("walking", fallback_type)
					anim_player.speed_scale = 1.5

	if anim_player.has_animation(anim_name):
		anim_player.play(anim_name, ANIM_BLEND_TIME)


## ダメージを受ける
func take_damage(amount: float) -> void:
	if not is_alive:
		return

	# アーマー計算
	if armor > 0:
		var armor_damage := amount * 0.5
		if armor_damage <= armor:
			armor -= armor_damage
			amount -= armor_damage
		else:
			amount -= armor
			armor = 0

	health -= amount

	if health <= 0:
		health = 0
		_die()


## 死亡処理
func _die() -> void:
	is_alive = false
	is_moving = false
	died.emit()


## 回復
func heal(amount: float) -> void:
	health = min(health + amount, 100.0)


## アーマー追加
func add_armor(amount: float) -> void:
	armor = min(armor + amount, 100.0)


## 生存確認
func is_character_alive() -> bool:
	return is_alive


## 武器タイプを設定
func set_weapon_type(weapon_type: int) -> void:
	if current_weapon_type == weapon_type:
		return

	var prev_weapon_type = current_weapon_type
	current_weapon_type = weapon_type
	weapon_type_changed.emit(weapon_type)

	# 速度を更新
	_update_speed_from_weapon()

	# CharacterModelのY位置を調整（武器タイプによるアニメーション位置の差を補正）
	var model = get_node_or_null("CharacterModel")
	if model:
		var prev_offset = CharacterSetup.WEAPON_Y_OFFSET.get(prev_weapon_type, 0.0)
		var new_offset = CharacterSetup.WEAPON_Y_OFFSET.get(weapon_type, 0.0)
		print("[%s] CharacterModel Y before: %.3f" % [name, model.position.y])
		model.position.y += (new_offset - prev_offset)
		print("[%s] CharacterModel Y after: %.3f (offset change: %.3f)" % [name, model.position.y, new_offset - prev_offset])

	# アニメーションを即座に更新
	_play_current_animation()

	var weapon_name = CharacterSetup.WEAPON_TYPE_NAMES.get(weapon_type, "unknown")
	print("[%s] Weapon type changed to: %s (speed: %.1f/%.1f)" % [name, weapon_name, walk_speed, run_speed])


## 現在の武器タイプを取得
func get_weapon_type() -> int:
	return current_weapon_type


## 武器タイプ名を取得
func get_weapon_type_name() -> String:
	return CharacterSetup.WEAPON_TYPE_NAMES.get(current_weapon_type, "unknown")


## 武器を設定（武器IDベース）
func set_weapon(weapon_id: int) -> void:
	if current_weapon_id == weapon_id:
		return
	
	current_weapon_id = weapon_id
	
	# 武器タイプを更新（アニメーション用）
	var weapon_type = CharacterSetup.get_weapon_type_from_id(weapon_id)
	set_weapon_type(weapon_type)
	
	# 武器モデルを装着
	if skeleton:
		weapon_attachment = CharacterSetup.attach_weapon_to_character(self, skeleton, weapon_id, name)
	
	weapon_changed.emit(weapon_id)
	
	var weapon_data = CharacterSetup.get_weapon_data(weapon_id)
	print("[%s] Weapon changed to: %s" % [name, weapon_data.name])


## 現在の武器IDを取得
func get_weapon_id() -> int:
	return current_weapon_id


## 現在の武器データを取得
func get_weapon_data() -> Dictionary:
	return CharacterSetup.get_weapon_data(current_weapon_id)


## 武器タイプに応じた速度を更新
func _update_speed_from_weapon() -> void:
	var modifier = CharacterSetup.WEAPON_SPEED_MODIFIER.get(current_weapon_type, 1.0)
	walk_speed = base_walk_speed * modifier
	run_speed = base_run_speed * modifier


## 現在の速度倍率を取得
func get_speed_modifier() -> float:
	return CharacterSetup.WEAPON_SPEED_MODIFIER.get(current_weapon_type, 1.0)
