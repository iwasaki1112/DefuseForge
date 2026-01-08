class_name CharacterBase
extends CharacterBody3D

## キャラクター基底クラス
## 移動、アニメーション、地形追従の共通機能を提供

# CharacterSetup はグローバルクラス名として登録されているため、直接参照可能

signal path_completed
signal waypoint_reached(index: int)
signal died(killer: Node3D)
signal damaged(amount: int, attacker: Node3D, is_headshot: bool)
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
var anim_tree: AnimationTree = null
var anim_blend_tree: AnimationNodeBlendTree = null  # BlendTreeへの参照
var current_move_state: int = -1  # -1: uninitialized, 0: idle, 1: walk, 2: run
var current_weapon_type: int = CharacterSetup.WeaponType.NONE
var current_weapon_id: int = CharacterSetup.WeaponId.NONE
const ANIM_BLEND_TIME: float = 0.3

# 射撃状態（上半身ブレンド用）
var is_shooting: bool = false
var _shooting_blend: float = 0.0
const SHOOTING_BLEND_SPEED: float = 10.0

# 歩行シーケンス状態
enum WalkSequenceState { NONE, START, LOOP, END }
var walk_sequence_state: WalkSequenceState = WalkSequenceState.NONE
var walk_sequence_base_name: String = ""  # "walk" or "sprint" など
var _pending_walk_stop: bool = false  # 停止リクエストがあるか

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
		# マテリアルとテクスチャを設定
		CharacterSetup.setup_materials(model, name)

		# Skeletonを取得（武器装着用・Yオフセット計算用）
		skeleton = CharacterSetup.find_skeleton(model)
		if skeleton:
			# スキンバインディングを修正（FBXインポート時のbone_idx=-1問題を解決）
			# これによりアニメーションが正しく適用されるようになる
			CharacterSetup.fix_skin_bindings(model, skeleton, name)

			# Skeletonのレストポーズからfeet-to-hips距離を計算してYオフセットを適用
			# キャラクターごとの体格差を吸収する
			var model_scale: float = model.scale.y
			var y_offset = CharacterSetup.calculate_y_offset_from_skeleton(skeleton, model_scale, name)
			if y_offset > 0:
				model.position.y = y_offset

		# AnimationPlayerを取得してアニメーションをロード
		anim_player = CharacterSetup.find_animation_player(model)
		if anim_player:
			CharacterSetup.load_animations(anim_player, model, name)
			# 歩行シーケンス用のシグナル接続
			if not anim_player.animation_finished.is_connected(_on_animation_finished):
				anim_player.animation_finished.connect(_on_animation_finished)
			# AnimationTreeをセットアップ（上半身ブレンド用）
			# 初期アニメーションはAnimationTree内で設定される
			_setup_animation_tree(model)


## AnimationTreeをセットアップ（上半身/下半身ブレンド用）
## 構造:
##   locomotion (idle/walk/run) -> blend2 (upper body filter) -> output
##                 shoot --------^
## 下半身: locomotionアニメーションのまま
## 上半身: 射撃中はshootアニメーション、それ以外はlocomotion
func _setup_animation_tree(model: Node3D) -> void:
	if not anim_player or not skeleton:
		return

	# AnimationTreeを作成
	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	model.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)

	# BlendTreeを作成
	anim_blend_tree = AnimationNodeBlendTree.new()
	anim_tree.tree_root = anim_blend_tree

	# locomotionアニメーション（idle/walk/run - 全身）
	var locomotion_anim = AnimationNodeAnimation.new()
	anim_blend_tree.add_node("locomotion", locomotion_anim, Vector2(0, 0))

	# shootアニメーション（上半身用）
	var shoot_anim = AnimationNodeAnimation.new()
	anim_blend_tree.add_node("shoot", shoot_anim, Vector2(0, 200))

	# Blend2ノード（上半身のみブレンド）
	var blend2 = AnimationNodeBlend2.new()
	anim_blend_tree.add_node("upper_blend", blend2, Vector2(300, 100))

	# 接続
	anim_blend_tree.connect_node("upper_blend", 0, "locomotion")  # blend=0でlocomotion
	anim_blend_tree.connect_node("upper_blend", 1, "shoot")       # blend=1でshoot

	# 出力に接続
	anim_blend_tree.connect_node("output", 0, "upper_blend")

	# 上半身ボーンのフィルターを設定
	_setup_upper_body_filter(blend2)

	# 初期アニメーションを設定
	var idle_anim = CharacterSetup.get_animation_name("idle", current_weapon_type)
	if not anim_player.has_animation(idle_anim):
		idle_anim = CharacterSetup.get_animation_name("idle", CharacterSetup.WeaponType.NONE)

	# 射撃アニメーション優先順位: idle_aiming > shoot > walking > idle
	var shoot_anim_name = CharacterSetup.get_animation_name("idle_aiming", current_weapon_type)
	if not anim_player.has_animation(shoot_anim_name):
		shoot_anim_name = CharacterSetup.get_animation_name("shoot", current_weapon_type)
		if not anim_player.has_animation(shoot_anim_name):
			shoot_anim_name = CharacterSetup.get_animation_name("walking", current_weapon_type)
			if not anim_player.has_animation(shoot_anim_name):
				shoot_anim_name = idle_anim

	# AnimationNodeにアニメーション名を設定
	var locomotion_node = anim_blend_tree.get_node("locomotion") as AnimationNodeAnimation
	var shoot_node = anim_blend_tree.get_node("shoot") as AnimationNodeAnimation
	if locomotion_node:
		locomotion_node.animation = idle_anim
	if shoot_node:
		shoot_node.animation = shoot_anim_name

	# AnimationTreeを有効化
	anim_tree.active = true

	print("[%s] AnimationTree setup complete (locomotion: %s, shoot: %s)" % [name, idle_anim, shoot_anim_name])


## 上半身ボーンのフィルターを設定
func _setup_upper_body_filter(blend_node: AnimationNodeBlend2) -> void:
	blend_node.filter_enabled = true

	# Mixamoスケルトンの上半身ボーン
	var upper_body_bones = [
		"mixamorig_Spine",
		"mixamorig_Spine1",
		"mixamorig_Spine2",
		"mixamorig_Neck",
		"mixamorig_Head",
		"mixamorig_HeadTop_End",
		"mixamorig_LeftShoulder",
		"mixamorig_LeftArm",
		"mixamorig_LeftForeArm",
		"mixamorig_LeftHand",
		"mixamorig_RightShoulder",
		"mixamorig_RightArm",
		"mixamorig_RightForeArm",
		"mixamorig_RightHand",
	]

	# 指のボーンも追加
	for side in ["Left", "Right"]:
		for finger in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			for i in range(1, 5):
				upper_body_bones.append("mixamorig_%s%s%d" % [side + "Hand", finger, i])

	# Armatureプレフィックスを考慮したパスを構築
	var armature_path = ""
	var armature = skeleton.get_parent()
	if armature and armature.name == "Armature":
		armature_path = "Armature/"

	# フィルターを設定
	for bone_name in upper_body_bones:
		var bone_idx = skeleton.find_bone(bone_name)
		if bone_idx >= 0:
			# Skeleton3D:bone_name 形式でパスを設定
			var bone_path = "%sSkeleton3D:%s" % [armature_path, bone_name]
			blend_node.set_filter_path(NodePath(bone_path), true)


func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	# 射撃ブレンドを更新
	_update_shooting_blend(delta)

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


## 射撃ブレンドを更新
func _update_shooting_blend(delta: float) -> void:
	if not anim_tree or not anim_tree.active:
		return

	# 射撃中かつ走行中でない場合のみ上半身ブレンドを適用
	# （走行中は射撃不可のため）
	var target_blend = 1.0 if (is_shooting and not is_running) else 0.0
	_shooting_blend = move_toward(_shooting_blend, target_blend, SHOOTING_BLEND_SPEED * delta)

	# AnimationTreeのブレンド値を設定（upper_blend/blend_amount）
	anim_tree.set("parameters/upper_blend/blend_amount", _shooting_blend)


## 射撃状態を設定（CombatComponentから呼ばれる）
func set_shooting(shooting: bool) -> void:
	if is_shooting == shooting:
		return
	is_shooting = shooting
	# 武器位置を更新（射撃状態に応じて位置が変わる場合があるため）
	_update_weapon_position()


## パス追従移動
func _handle_path_movement(delta: float) -> void:
	# パスがあるが移動していない場合、移動を開始
	if not is_moving and waypoints.size() > 0 and current_waypoint_index < waypoints.size():
		is_moving = true

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


## パスを設定（移動は実行フェーズで開始）
func set_path(new_waypoints: Array) -> void:
	waypoints = new_waypoints
	current_waypoint_index = 0
	is_running = false
	# 注: is_movingはここでは設定しない（実行フェーズで開始）


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
	visible = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	_snap_to_ground()
	visible = true


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
	else:
		push_warning("[%s] snap_to_ground: no ground found at %s" % [name, global_position])


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

	if anim_player.has_animation(anim_name):
		# AnimationTreeが有効な場合は、locomotionノードのアニメーションを更新
		if anim_tree and anim_tree.active and anim_blend_tree:
			var locomotion_node = anim_blend_tree.get_node("locomotion") as AnimationNodeAnimation
			if locomotion_node:
				locomotion_node.animation = anim_name
		else:
			# AnimationTreeが無効な場合はAnimationPlayerを直接使用
			anim_player.play(anim_name, ANIM_BLEND_TIME)
		print("[%s] Playing animation: %s" % [name, anim_name])

	# 武器位置を更新
	_update_weapon_position()


## 武器の位置をアニメーション状態に応じて更新
func _update_weapon_position() -> void:
	if weapon_attachment == null or current_weapon_id == CharacterSetup.WeaponId.NONE:
		return

	var anim_state := CharacterSetup.get_anim_state_from_move_state(current_move_state, is_shooting)
	CharacterSetup.update_weapon_position(weapon_attachment, current_weapon_id, anim_state, name)


## ダメージを受ける
## @param amount: ダメージ量
## @param attacker: 攻撃者（オプション）
## @param is_headshot: ヘッドショットか（オプション）
func take_damage(amount: float, attacker: Node3D = null, is_headshot: bool = false) -> void:
	if not is_alive:
		return

	var original_amount = amount

	# アーマー計算（ヘッドショットはアーマー貫通）
	if armor > 0 and not is_headshot:
		var armor_damage := amount * 0.5
		if armor_damage <= armor:
			armor -= armor_damage
			amount -= armor_damage
		else:
			amount -= armor
			armor = 0

	health -= amount
	damaged.emit(int(amount), attacker, is_headshot)

	var hs_text = " (HEADSHOT)" if is_headshot else ""
	print("[%s] Took %d damage%s from %s (HP: %.0f)" % [
		name,
		int(amount),
		hs_text,
		attacker.name if attacker else "unknown",
		health
	])

	if health <= 0:
		health = 0
		_die(attacker)


## 死亡処理
func _die(killer: Node3D = null) -> void:
	is_alive = false
	is_moving = false

	# CombatComponentを無効化
	var combat = get_node_or_null("CombatComponent")
	if combat:
		combat.disable_combat()

	play_dying_animation()
	died.emit(killer)

	# GameEventsに通知
	if killer and has_node("/root/GameEvents"):
		var weapon_id = 0
		if killer.has_method("get_current_weapon_id"):
			weapon_id = killer.get_current_weapon_id()
		get_node("/root/GameEvents").unit_killed.emit(killer, self, weapon_id)


## 死亡アニメーションを再生
func play_dying_animation() -> void:
	# AnimationTreeを無効化（dyingアニメーションが正しく再生されるように）
	if anim_tree:
		anim_tree.active = false

	if anim_player and anim_player.has_animation("dying"):
		anim_player.play("dying")
		print("[%s] Playing dying animation" % name)


## 回復
func heal(amount: float) -> void:
	health = min(health + amount, 100.0)


## アーマー追加
func add_armor(amount: float) -> void:
	armor = min(armor + amount, 100.0)


## 生存確認
func is_character_alive() -> bool:
	return is_alive


## HP取得
func get_health() -> float:
	return health


## アーマー取得
func get_armor() -> float:
	return armor


## 武器タイプを設定
func set_weapon_type(weapon_type: int) -> void:
	if current_weapon_type == weapon_type:
		return

	current_weapon_type = weapon_type
	weapon_type_changed.emit(weapon_type)

	# 速度を更新
	_update_speed_from_weapon()

	# アニメーションを即座に更新
	# 注: 全アニメーションでHips Y位置が正規化されているため、Y位置調整は不要
	_play_current_animation()

	# 射撃アニメーションも更新
	_update_shoot_animation()

	var weapon_name = CharacterSetup.WEAPON_TYPE_NAMES.get(weapon_type, "unknown")
	print("[%s] Weapon type changed to: %s (speed: %.1f/%.1f)" % [name, weapon_name, walk_speed, run_speed])


## 射撃アニメーションを更新（武器タイプ変更時）
func _update_shoot_animation() -> void:
	if not anim_tree or not anim_tree.active or not anim_blend_tree:
		return

	# 射撃アニメーション優先順位: idle_aiming > shoot > walking > idle
	var shoot_anim_name = CharacterSetup.get_animation_name("idle_aiming", current_weapon_type)
	if not anim_player.has_animation(shoot_anim_name):
		shoot_anim_name = CharacterSetup.get_animation_name("shoot", current_weapon_type)
		if not anim_player.has_animation(shoot_anim_name):
			shoot_anim_name = CharacterSetup.get_animation_name("walking", current_weapon_type)
			if not anim_player.has_animation(shoot_anim_name):
				shoot_anim_name = CharacterSetup.get_animation_name("idle", current_weapon_type)
				if not anim_player.has_animation(shoot_anim_name):
					shoot_anim_name = CharacterSetup.get_animation_name("idle", CharacterSetup.WeaponType.NONE)

	var shoot_node = anim_blend_tree.get_node("shoot") as AnimationNodeAnimation
	if shoot_node:
		shoot_node.animation = shoot_anim_name
		print("[%s] Shoot animation updated to: %s" % [name, shoot_anim_name])


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
		# 武器位置を現在のアニメーション状態に合わせて更新
		_update_weapon_position()

	weapon_changed.emit(weapon_id)

	# CombatComponentに武器変更を通知
	var combat_component = get_node_or_null("CombatComponent")
	if combat_component:
		combat_component.on_weapon_changed(weapon_id)

	var weapon_data = CharacterSetup.get_weapon_data(weapon_id)
	print("[%s] Weapon changed to: %s" % [name, weapon_data.name])


## 現在の武器IDを取得
func get_weapon_id() -> int:
	return current_weapon_id


## 現在の武器IDを取得（CombatComponent用エイリアス）
func get_current_weapon_id() -> int:
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


## ========================================
## 歩行シーケンス API
## walk_start -> walk_loop -> walk_end
## ========================================

## 歩行シーケンスを開始
## @param base_name: "walk" や "sprint" などのベース名
## @param blend_time: ブレンド時間
func start_walk_sequence(base_name: String = "walk", blend_time: float = 0.3) -> void:
	if not anim_player:
		return

	walk_sequence_base_name = base_name
	_pending_walk_stop = false

	# start アニメーションがあるかチェック
	var start_anim = _get_walk_sequence_anim("start")
	if anim_player.has_animation(start_anim):
		walk_sequence_state = WalkSequenceState.START
		_play_walk_sequence_anim("start", blend_time)
	else:
		# startがなければ直接loopへ
		walk_sequence_state = WalkSequenceState.LOOP
		_play_walk_sequence_anim("loop", blend_time)


## 歩行シーケンスを停止（end アニメーションを再生）
## @param blend_time: ブレンド時間
func stop_walk_sequence(blend_time: float = 0.3) -> void:
	if not anim_player or walk_sequence_state == WalkSequenceState.NONE:
		return

	# 現在START中なら、終了後にENDへ
	if walk_sequence_state == WalkSequenceState.START:
		_pending_walk_stop = true
		return

	# end アニメーションがあるかチェック
	var end_anim = _get_walk_sequence_anim("end")
	if anim_player.has_animation(end_anim):
		walk_sequence_state = WalkSequenceState.END
		_play_walk_sequence_anim("end", blend_time)
	else:
		# endがなければ直接シーケンス終了
		_finish_walk_sequence()


## 歩行シーケンスを強制終了（アニメーションなし）
func cancel_walk_sequence() -> void:
	walk_sequence_state = WalkSequenceState.NONE
	walk_sequence_base_name = ""
	_pending_walk_stop = false


## 歩行シーケンスがアクティブか
func is_walk_sequence_active() -> bool:
	return walk_sequence_state != WalkSequenceState.NONE


## アニメーション終了時のコールバック
func _on_animation_finished(anim_name: String) -> void:
	if walk_sequence_state == WalkSequenceState.NONE:
		return

	var expected_start = _get_walk_sequence_anim("start")
	var expected_loop = _get_walk_sequence_anim("loop")
	var expected_end = _get_walk_sequence_anim("end")

	match walk_sequence_state:
		WalkSequenceState.START:
			if anim_name == expected_start:
				if _pending_walk_stop:
					_pending_walk_stop = false
					stop_walk_sequence()
				else:
					walk_sequence_state = WalkSequenceState.LOOP
					_play_walk_sequence_anim("loop", 0.1)

		WalkSequenceState.END:
			if anim_name == expected_end:
				_finish_walk_sequence()


## 歩行シーケンス用アニメーション名を取得
func _get_walk_sequence_anim(phase: String) -> String:
	# 例: rifle_walk_start, rifle_walk, rifle_walk_end
	var weapon_prefix = CharacterSetup.get_weapon_prefix(current_weapon_type)

	if phase == "loop":
		# ループは武器プレフィックス + ベース名（例: rifle_walk）
		return weapon_prefix + walk_sequence_base_name
	else:
		# start/end は武器プレフィックス + ベース名 + _phase（例: rifle_walk_start）
		return weapon_prefix + walk_sequence_base_name + "_" + phase


## 歩行シーケンスアニメーションを再生
func _play_walk_sequence_anim(phase: String, blend_time: float) -> void:
	var anim_name = _get_walk_sequence_anim(phase)

	if not anim_player.has_animation(anim_name):
		push_warning("[%s] Walk sequence animation not found: %s" % [name, anim_name])
		return

	# AnimationTreeが有効な場合
	if anim_tree and anim_tree.active and anim_blend_tree:
		var locomotion_node = anim_blend_tree.get_node("locomotion") as AnimationNodeAnimation
		if locomotion_node:
			locomotion_node.animation = anim_name
	else:
		anim_player.play(anim_name, blend_time)

	print("[%s] Walk sequence: %s -> %s" % [name, phase, anim_name])


## 歩行シーケンス終了処理
func _finish_walk_sequence() -> void:
	walk_sequence_state = WalkSequenceState.NONE
	walk_sequence_base_name = ""
	_pending_walk_stop = false
	# idle に戻す
	_play_current_animation()
