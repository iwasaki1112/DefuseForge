class_name CharacterBase
extends CharacterBody3D

## キャラクター基底クラス
## 移動、アニメーション、地形追従の共通機能を提供

# CharacterSetup はグローバルクラス名として登録されているため、直接参照可能
const ActionState = preload("res://scripts/resources/action_state.gd")
const CharacterRegistry = preload("res://scripts/registries/character_registry.gd")
const WeaponRegistry = preload("res://scripts/registries/weapon_registry.gd")

signal path_completed
signal waypoint_reached(index: int)
signal died(killer: Node3D)
signal damaged(amount: int, attacker: Node3D, is_headshot: bool)
signal weapon_type_changed(weapon_type: int)
signal weapon_changed(weapon_id: int)
signal locomotion_changed(new_state: int)
signal action_started(action_type: int)
signal action_completed(action_type: int)

@export_group("移動設定")
@export var base_walk_speed: float = 3.0
@export var base_run_speed: float = 6.0
@export var rotation_speed: float = 10.0

# 武器による速度倍率適用後の実効速度
var walk_speed: float = 3.0
var run_speed: float = 6.0

@export_group("物理設定")
@export var gravity_value: float = -20.0

@export_group("上半身エイミング")
@export var upper_body_aim_enabled: bool = true  ## 上半身エイミングを有効にするか
@export var aim_rotation_speed: float = 10.0  ## エイミング回転補間速度
@export_range(0, 180, 1) var aim_max_angle_deg: float = 90.0  ## 最大回転角度（度）

# 物理状態
var vertical_velocity: float = 0.0

# パス追従用
var waypoints: Array = []  # Array of {position: Vector3, run: bool}
var current_waypoint_index: int = 0
var is_moving: bool = false
var is_running: bool = false

# アクション状態管理
var locomotion_state: int = ActionState.LocomotionState.IDLE
var current_action: int = ActionState.ActionType.NONE
var _action_timer: float = 0.0

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

# 左手IK（武器のLeftHandGripに手を追従させる）
var left_hand_ik: SkeletonIK3D = null
var left_hand_ik_target: Marker3D = null
var _left_hand_grip_source: Node3D = null
var _left_hand_ik_offset: Vector3 = Vector3.ZERO
var _left_hand_ik_rotation: Vector3 = Vector3.ZERO
var _weapon_resource: Resource = null  # WeaponResource
var _ik_interpolation_tween: Tween = null  # IK補間用Tween

# 上半身エイミング（内部状態）
var _aim_spine_bone_idx: int = -1  # mixamorig_Spine1 のインデックス
var _current_aim_rotation: float = 0.0  # 現在のエイミング角度（ラジアン）
var _target_aim_rotation: float = 0.0  # 目標エイミング角度（ラジアン）

# キャラクターリソース（武器オフセット等）
var _character_resource: Resource = null  # CharacterResource
var _weapon_position_offset: Vector3 = Vector3.ZERO  # キャラクター固有の武器位置オフセット
var _weapon_rotation_offset: Vector3 = Vector3.ZERO  # キャラクター固有の武器回転オフセット

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
		# キャラクターリソースを読み込み（武器オフセット等）
		_load_character_resource()

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

			# エイミング用スパインボーンを検索
			_find_aim_spine_bone()

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

	# アクション状態を更新（タイマーベースの自動終了）
	_update_action_state(delta)

	# 射撃ブレンドを更新
	_update_shooting_blend(delta)

	# 上半身エイミングを更新
	_update_upper_body_aim(delta)

	# 左手IKターゲットを更新
	_update_left_hand_ik_target()

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


# ========================================
# アクション状態管理
# ========================================

## 射撃可能かどうかを判定
func can_shoot() -> bool:
	# 移動状態をチェック
	if not ActionState.can_shoot_in_locomotion(locomotion_state):
		return false
	# 一時アクションをチェック
	if not ActionState.can_shoot_in_action(current_action):
		return false
	return true


## 移動状態を設定
func set_locomotion_state(state: int) -> void:
	if locomotion_state == state:
		return
	locomotion_state = state
	locomotion_changed.emit(state)


## 一時アクションを開始
## @param action_type: ActionType enum値
## @param duration: アクション持続時間（秒）、0なら手動終了
func start_action(action_type: int, duration: float = 0.0) -> bool:
	# 既にアクション中なら開始不可
	if current_action != ActionState.ActionType.NONE:
		return false
	current_action = action_type
	_action_timer = duration
	action_started.emit(action_type)

	# アクションに応じたアニメーションを再生
	_play_action_animation(action_type)
	return true


## 一時アクションを終了
func end_action() -> void:
	if current_action == ActionState.ActionType.NONE:
		return
	var completed_action = current_action
	current_action = ActionState.ActionType.NONE
	_action_timer = 0.0
	action_completed.emit(completed_action)

	# アクション終了後、通常アニメーションに戻る
	_play_current_animation()


## アクションに応じたアニメーションを再生
func _play_action_animation(action_type: int) -> void:
	if anim_player == null:
		return

	var anim_name: String = ""

	match action_type:
		ActionState.ActionType.RELOAD:
			anim_name = CharacterSetup.get_animation_name("reload", current_weapon_type)
		ActionState.ActionType.OPEN_DOOR:
			anim_name = "open_door"
		_:
			return  # アニメーションなし

	# フォールバック
	if not anim_player.has_animation(anim_name):
		anim_name = CharacterSetup.get_animation_name("reload", CharacterSetup.WeaponType.RIFLE)

	if anim_player.has_animation(anim_name):
		# AnimationTreeを一時的に無効化してアクションアニメーションを直接再生
		if anim_tree and anim_tree.active:
			anim_tree.active = false
		anim_player.play(anim_name, ANIM_BLEND_TIME)
		# IK状態を更新（リロード中はIKを無効にする等）
		_update_left_hand_ik_enabled(anim_name)
		print("[CharacterBase] Playing action animation: %s" % anim_name)


## アクション状態の更新（タイマーベースの自動終了）
func _update_action_state(delta: float) -> void:
	if _action_timer > 0:
		_action_timer -= delta
		if _action_timer <= 0:
			end_action()


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


## エイミング用スパインボーンを検索
## mixamorig_Spine1 を使用（胸レベル、上半身回転に最適）
func _find_aim_spine_bone() -> void:
	if not skeleton:
		return

	var spine_names := ["mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Spine",
						"Spine1", "Spine2", "Spine"]

	for bone_name in spine_names:
		var idx := skeleton.find_bone(bone_name)
		if idx >= 0:
			_aim_spine_bone_idx = idx
			print("[CharacterBase] Found aim spine bone: %s (index: %d)" % [bone_name, idx])
			return

	push_warning("[CharacterBase] Aim spine bone not found")


## 上半身エイミングの目標角度を計算
func _update_upper_body_aim(delta: float) -> void:
	# エイミング無効 or 射撃中でない or 走行中 → エイミング解除
	if not upper_body_aim_enabled or not is_shooting or is_running:
		_target_aim_rotation = 0.0
		_current_aim_rotation = move_toward(_current_aim_rotation, 0.0, aim_rotation_speed * delta)
		return

	# CombatComponentからターゲットを取得
	var combat = get_node_or_null("CombatComponent")
	if not combat or not combat.has_method("get_current_target"):
		_target_aim_rotation = 0.0
		_current_aim_rotation = move_toward(_current_aim_rotation, 0.0, aim_rotation_speed * delta)
		return

	var target: Node3D = combat.get_current_target()
	if not is_instance_valid(target):
		_target_aim_rotation = 0.0
		_current_aim_rotation = move_toward(_current_aim_rotation, 0.0, aim_rotation_speed * delta)
		return

	# ターゲット方向を計算（XZ平面上）
	var to_target := target.global_position - global_position
	to_target.y = 0

	if to_target.length_squared() < 0.01:
		_target_aim_rotation = 0.0
		_current_aim_rotation = move_toward(_current_aim_rotation, 0.0, aim_rotation_speed * delta)
		return

	to_target = to_target.normalized()

	# キャラクターの前方向（-Z軸、rotation.yを考慮）
	var forward := Vector3(sin(rotation.y), 0, cos(rotation.y))

	# 前方向とターゲット方向の角度差を計算（符号付き）
	# cross product の Y 成分で符号を決定
	var cross := forward.cross(to_target)
	var dot := forward.dot(to_target)
	var angle := atan2(cross.y, dot)

	# 角度を制限
	var max_angle_rad := deg_to_rad(aim_max_angle_deg)
	_target_aim_rotation = clampf(angle, -max_angle_rad, max_angle_rad)

	# 現在の角度を目標に向かって補間
	_current_aim_rotation = lerp_angle(_current_aim_rotation, _target_aim_rotation, aim_rotation_speed * delta)


## 上半身エイミング回転をボーンに適用
## AnimationTree更新後に呼ばれる必要があるため、_process()で実行
func _apply_upper_body_aim_rotation() -> void:
	if not skeleton or _aim_spine_bone_idx < 0:
		return

	# 以前のオーバーライドをクリア
	skeleton.clear_bones_global_pose_override()

	# 回転が小さい場合はスキップ
	if abs(_current_aim_rotation) < 0.01:
		return

	# 現在のボーングローバルトランスフォームを取得（アニメーションから）
	var bone_global_transform := skeleton.get_bone_global_pose(_aim_spine_bone_idx)

	# Y軸周りの回転を作成（水平方向のエイミング）
	var aim_rotation := Quaternion(Vector3.UP, _current_aim_rotation)
	var aim_basis := Basis(aim_rotation)

	# ボーンの現在のbasisに回転を合成
	var new_transform := Transform3D(bone_global_transform.basis * aim_basis, bone_global_transform.origin)

	# ボーンのグローバルポーズをオーバーライド（amount=1.0で完全オーバーライド）
	skeleton.set_bone_global_pose_override(_aim_spine_bone_idx, new_transform, 1.0, true)


func _process(_delta: float) -> void:
	_apply_upper_body_aim_rotation()


# ========================================
# 上半身エイミング 公開API
# ========================================

## 現在のエイミング角度を取得（ラジアン）
func get_aim_rotation() -> float:
	return _current_aim_rotation


## 現在のエイミング角度を取得（度）
func get_aim_rotation_degrees() -> float:
	return rad_to_deg(_current_aim_rotation)


## 目標エイミング角度を取得（ラジアン）
func get_target_aim_rotation() -> float:
	return _target_aim_rotation


## 目標エイミング角度を取得（度）
func get_target_aim_rotation_degrees() -> float:
	return rad_to_deg(_target_aim_rotation)


## 上半身エイミングの有効/無効を設定
func set_upper_body_aim_enabled(enabled: bool) -> void:
	upper_body_aim_enabled = enabled
	if not enabled:
		# 無効化時は即座にリセット
		_current_aim_rotation = 0.0
		_target_aim_rotation = 0.0
		if skeleton and _aim_spine_bone_idx >= 0:
			skeleton.clear_bones_global_pose_override()


## 上半身エイミングが有効かどうかを取得
func is_upper_body_aim_enabled() -> bool:
	return upper_body_aim_enabled


## パス追従移動
func _handle_path_movement(delta: float) -> void:
	# パスがあるが移動していない場合、移動を開始
	if not is_moving and waypoints.size() > 0 and current_waypoint_index < waypoints.size():
		is_moving = true

	if is_moving and waypoints.size() > 0 and current_waypoint_index < waypoints.size():
		var waypoint: Dictionary = waypoints[current_waypoint_index]
		var target: Vector3 = waypoint.position
		is_running = waypoint.run
		# locomotion_state を同期
		if is_running:
			set_locomotion_state(ActionState.LocomotionState.SPRINT)
		else:
			set_locomotion_state(ActionState.LocomotionState.WALK)

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
	is_running = false
	waypoints.clear()
	current_waypoint_index = 0
	set_locomotion_state(ActionState.LocomotionState.IDLE)


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
		# AnimationTreeを再有効化（アクション後に無効化されている場合）
		if anim_tree and not anim_tree.active and anim_blend_tree:
			anim_tree.active = true

		# AnimationTreeが有効な場合は、locomotionノードのアニメーションを更新
		if anim_tree and anim_tree.active and anim_blend_tree:
			var locomotion_node = anim_blend_tree.get_node("locomotion") as AnimationNodeAnimation
			if locomotion_node:
				locomotion_node.animation = anim_name
		else:
			# AnimationTreeが無効な場合はAnimationPlayerを直接使用
			anim_player.play(anim_name, ANIM_BLEND_TIME)

		# IK状態を更新（移動アニメーションではIKを再有効化）
		_update_left_hand_ik_enabled(anim_name)

	# 武器位置を更新
	_update_weapon_position()


## 武器の位置をアニメーション状態に応じて更新
## キャラクターオフセット + アニメーションオフセットを組み合わせ
func _update_weapon_position() -> void:
	if weapon_attachment == null or current_weapon_id == CharacterSetup.WeaponId.NONE:
		return

	# 武器ノードを取得
	var weapon_node: Node3D = null
	for child in weapon_attachment.get_children():
		if child is Node3D:
			weapon_node = child as Node3D
			break

	if weapon_node == null:
		return

	# アニメーション状態に応じたオフセットを取得
	var anim_state := CharacterSetup.get_anim_state_from_move_state(current_move_state, is_shooting)
	var anim_offset_pos := Vector3.ZERO
	var anim_offset_rot := Vector3.ZERO

	if CharacterSetup.WEAPON_ANIMATION_OFFSETS.has(current_weapon_id):
		var weapon_offsets: Dictionary = CharacterSetup.WEAPON_ANIMATION_OFFSETS[current_weapon_id]
		if weapon_offsets.has(anim_state):
			var offset_data: Dictionary = weapon_offsets[anim_state]
			anim_offset_pos = offset_data.get("position", Vector3.ZERO)
			anim_offset_rot = offset_data.get("rotation", Vector3.ZERO)

	# キャラクターオフセット + アニメーションオフセットを組み合わせ
	weapon_node.position = _weapon_position_offset + anim_offset_pos
	weapon_node.rotation_degrees = _weapon_rotation_offset + anim_offset_rot


# ========================================
# 左手IK & キャラクターリソース
# ========================================

## キャラクターリソースを読み込み（武器オフセット等を取得）
## CharacterRegistryを使用して明示的なエラーメッセージを提供
func _load_character_resource() -> void:
	_character_resource = null
	_weapon_position_offset = Vector3.ZERO
	_weapon_rotation_offset = Vector3.ZERO

	# キャラクターIDを検出
	var character_id := _detect_character_id()
	if character_id.is_empty():
		push_warning("[CharacterBase] Could not detect character ID")
		return

	# CharacterRegistryからリソースを取得
	_character_resource = CharacterRegistry.get_character(character_id)
	if _character_resource:
		_weapon_position_offset = _character_resource.weapon_position_offset
		_weapon_rotation_offset = _character_resource.weapon_rotation_offset
		print("[CharacterBase] Weapon Pos Offset: %s, Rot Offset: %s" % [_weapon_position_offset, _weapon_rotation_offset])


## キャラクターIDを検出
## @return: キャラクターID、検出できない場合は空文字列
func _detect_character_id() -> String:
	# 1. CharacterModelのシーンパスからIDを取得（最も信頼性が高い）
	var model = get_node_or_null("CharacterModel")
	if model:
		var scene_path: String = model.scene_file_path
		if not scene_path.is_empty():
			var detected = CharacterRegistry.detect_character_id_from_scene_path(scene_path)
			if not detected.is_empty():
				print("[CharacterBase] Detected character from scene path: %s" % detected)
				return detected

	# 2. フォールバック: ノード名から推測
	if model:
		var model_name = model.name.to_lower()
		if model_name.ends_with("model"):
			return model_name.substr(0, model_name.length() - 5)
		return model_name

	return name.to_lower()


## 武器にキャラクター固有のオフセットを適用
## test_animation_viewer.gd の _apply_weapon_offset() と同等
func _apply_weapon_offset() -> void:
	if weapon_attachment == null:
		return

	# 武器ノードを取得（BoneAttachment3Dの子ノード）
	var weapon_node: Node3D = null
	for child in weapon_attachment.get_children():
		if child is Node3D:
			weapon_node = child as Node3D
			break

	if weapon_node:
		weapon_node.position = _weapon_position_offset
		weapon_node.rotation_degrees = _weapon_rotation_offset
		print("[CharacterBase] Applied weapon offset: pos=%s, rot=%s" % [_weapon_position_offset, _weapon_rotation_offset])


## WeaponResourceを読み込み
## WeaponRegistryを使用して明示的なエラーメッセージを提供
func _load_weapon_resource(weapon_id: int) -> void:
	_weapon_resource = null
	_left_hand_ik_offset = Vector3.ZERO
	_left_hand_ik_rotation = Vector3.ZERO

	# 武器なしの場合は何もしない
	if weapon_id == CharacterSetup.WeaponId.NONE:
		return

	# WeaponRegistryからリソースを取得
	_weapon_resource = WeaponRegistry.get_weapon(weapon_id)
	if _weapon_resource:
		_left_hand_ik_offset = _weapon_resource.left_hand_ik_position
		_left_hand_ik_rotation = _weapon_resource.left_hand_ik_rotation
		print("[CharacterBase] IK Offset: %s, Rotation: %s" % [_left_hand_ik_offset, _left_hand_ik_rotation])


## 左手IKを設定
func _setup_left_hand_ik() -> void:
	if not skeleton or not weapon_attachment:
		return

	# 武器ノードを取得
	var weapon_node: Node3D = null
	for child in weapon_attachment.get_children():
		if child is Node3D:
			weapon_node = child as Node3D
			break

	if not weapon_node:
		return

	# 左手ボーンを検索
	var left_hand_bone_names := ["mixamorig_LeftHand", "LeftHand", "left_hand", "mixamorig:LeftHand"]
	var left_hand_bone_idx: int = -1

	for bone_name in left_hand_bone_names:
		var idx := skeleton.find_bone(bone_name)
		if idx >= 0:
			left_hand_bone_idx = idx
			break

	if left_hand_bone_idx < 0:
		return

	# 武器モデル内のLeftHandGripを検索
	var model_node = weapon_node.get_node_or_null("Model")
	if not model_node:
		model_node = weapon_node

	# 武器ID名でLeftHandGripを検索（例: LeftHandGrip_AK47）
	# scene_pathからIDを導出 (例: "res://scenes/weapons/ak47.tscn" → "ak47" → "AK47")
	var scene_path: String = CharacterSetup.WEAPON_DATA.get(current_weapon_id, {}).get("scene_path", "")
	var weapon_id_name: String = ""
	if scene_path:
		weapon_id_name = scene_path.get_file().get_basename().to_upper()  # "ak47" → "AK47"
	var grip_name = "LeftHandGrip_%s" % weapon_id_name
	print("[CharacterBase] Searching for left hand grip: %s (in %s)" % [grip_name, model_node.get_path()])
	var left_hand_grip = _find_node_recursive(model_node, grip_name)
	if not left_hand_grip:
		# 汎用名でフォールバック
		left_hand_grip = _find_node_recursive(model_node, "LeftHandGrip")
		if left_hand_grip:
			print("[CharacterBase] Found generic LeftHandGrip")
		else:
			print("[CharacterBase] Left hand grip not found: %s" % grip_name)

	if not left_hand_grip:
		return

	# IKターゲット用Marker3Dを作成（スケルトンの子として）
	left_hand_ik_target = Marker3D.new()
	left_hand_ik_target.name = "LeftHandIKTarget"
	skeleton.add_child(left_hand_ik_target)

	# SkeletonIK3Dを作成
	left_hand_ik = SkeletonIK3D.new()
	left_hand_ik.name = "LeftHandIK"

	# チップボーン（左手）を設定
	var tip_bone_name := skeleton.get_bone_name(left_hand_bone_idx)
	left_hand_ik.set_tip_bone(tip_bone_name)

	# ルートボーン（左腕）を検索
	var root_bone_names := ["mixamorig_LeftArm", "LeftArm", "left_arm", "mixamorig:LeftArm",
						   "mixamorig_LeftShoulder", "LeftShoulder"]
	var root_bone_name := ""
	for bone_name in root_bone_names:
		if skeleton.find_bone(bone_name) >= 0:
			root_bone_name = bone_name
			break

	if root_bone_name.is_empty():
		left_hand_ik_target.queue_free()
		left_hand_ik_target = null
		left_hand_ik.queue_free()
		left_hand_ik = null
		return

	left_hand_ik.set_root_bone(root_bone_name)
	left_hand_ik.set_target_node(left_hand_ik_target.get_path())

	# IK設定
	left_hand_ik.interpolation = 1.0  # フルIK影響
	left_hand_ik.override_tip_basis = true  # 手の回転もターゲットに合わせる

	skeleton.add_child(left_hand_ik)

	# IK開始
	left_hand_ik.start()

	# グリップソースを保存（毎フレーム位置更新用）
	_left_hand_grip_source = left_hand_grip

	print("[CharacterBase] Left hand IK setup complete: grip=%s" % left_hand_grip.get_path())


## 左手IKの有効/無効を更新
## 特定のアニメーション（リロード等）ではIKを無効にする
## パターンマッチングで自動判定し、設定の分散を防ぐ
## IK再有効化時はTweenで補間してスムーズな遷移を実現
const IK_BLEND_DURATION: float = 0.25  # IK補間時間（秒）

func _update_left_hand_ik_enabled(anim_name: String) -> void:
	if not left_hand_ik:
		return

	var should_disable := _should_disable_ik_for_animation(anim_name)

	if should_disable:
		# IKを無効化（即座に）
		_cancel_ik_tween()
		if left_hand_ik.is_running():
			left_hand_ik.interpolation = 0.0
			left_hand_ik.stop()
			print("[CharacterBase] Left hand IK disabled for: %s" % anim_name)
	else:
		# IKを有効化（スムーズに補間）
		if not left_hand_ik.is_running():
			left_hand_ik.interpolation = 0.0
			left_hand_ik.start()
			_blend_ik_interpolation(1.0, IK_BLEND_DURATION)
			print("[CharacterBase] Left hand IK enabled (blending) for: %s" % anim_name)


## IK補間Tweenをキャンセル
func _cancel_ik_tween() -> void:
	if _ik_interpolation_tween and _ik_interpolation_tween.is_valid():
		_ik_interpolation_tween.kill()
		_ik_interpolation_tween = null


## IK interpolationをスムーズに変更
func _blend_ik_interpolation(target_value: float, duration: float) -> void:
	_cancel_ik_tween()
	if not left_hand_ik:
		return

	_ik_interpolation_tween = create_tween()
	_ik_interpolation_tween.tween_property(left_hand_ik, "interpolation", target_value, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## アニメーション名からIKを無効にすべきか判定
## Convention over Configuration: 命名規則に基づいて自動判定
func _should_disable_ik_for_animation(anim_name: String) -> bool:
	# 武器リソースがIK無効の場合は常に無効
	if _weapon_resource and not _weapon_resource.left_hand_ik_enabled:
		return true

	# パターンマッチングで判定（命名規則に基づく）
	# リロード系: reload_rifle, reload_pistol, etc.
	if anim_name.begins_with("reload"):
		return true

	# 死亡系: dying, dying_left, Rifle_Death_R, etc.
	if anim_name.begins_with("dying") or anim_name.contains("Death"):
		return true

	# ドア開け: open_door
	if anim_name == "open_door":
		return true

	return false


## 左手IKターゲットを更新
func _update_left_hand_ik_target() -> void:
	if not left_hand_ik_target or not _left_hand_grip_source:
		return

	if not left_hand_ik or not left_hand_ik.is_running():
		return

	# グリップのグローバル位置をオフセット付きでIKターゲットに反映
	# (test_animation_viewer.gd の実装に合わせる)
	var grip_transform := _left_hand_grip_source.global_transform

	# 位置オフセットを適用（ローカル座標系）
	var offset_global := grip_transform.basis * _left_hand_ik_offset
	grip_transform.origin += offset_global

	# 角度オフセットを適用（度数→ラジアン）
	var rotation_offset := Basis.from_euler(Vector3(
		deg_to_rad(_left_hand_ik_rotation.x),
		deg_to_rad(_left_hand_ik_rotation.y),
		deg_to_rad(_left_hand_ik_rotation.z)
	))
	grip_transform.basis = grip_transform.basis * rotation_offset

	left_hand_ik_target.global_transform = grip_transform


## 左手IKをクリーンアップ
func _cleanup_left_hand_ik() -> void:
	if left_hand_ik:
		left_hand_ik.stop()
		left_hand_ik.queue_free()
		left_hand_ik = null

	if left_hand_ik_target:
		left_hand_ik_target.queue_free()
		left_hand_ik_target = null

	_left_hand_grip_source = null


## ノードを再帰的に検索
func _find_node_recursive(parent: Node, target_name: String) -> Node:
	for child in parent.get_children():
		if child.name == target_name:
			return child
		var found = _find_node_recursive(child, target_name)
		if found:
			return found
	return null


## ダメージを受ける
## @param amount: ダメージ量
## @param attacker: 攻撃者（オプション）
## @param is_headshot: ヘッドショットか（オプション）
func take_damage(amount: float, attacker: Node3D = null, is_headshot: bool = false) -> void:
	if not is_alive:
		return

	health -= amount
	damaged.emit(int(amount), attacker, is_headshot)

	if health <= 0:
		health = 0
		_die(attacker, is_headshot)


## 死亡処理
func _die(killer: Node3D = null, was_headshot: bool = false) -> void:
	is_alive = false
	is_moving = false

	var killer_name = killer.name if killer else "unknown"
	var headshot_str = " (HEADSHOT)" if was_headshot else ""
	print("[CharacterBase] %s died! Killed by %s%s" % [name, killer_name, headshot_str])

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
		get_node("/root/GameEvents").unit_killed.emit(killer, self, weapon_id, was_headshot)


## 死亡アニメーションを再生
func play_dying_animation() -> void:
	# AnimationTreeを無効化（dyingアニメーションが正しく再生されるように）
	if anim_tree:
		anim_tree.active = false

	# 左手IKを無効化（死亡時は手が武器から離れる）
	if left_hand_ik and left_hand_ik.is_running():
		left_hand_ik.stop()
		print("[CharacterBase] Left hand IK disabled for death animation")

	if not anim_player:
		return

	# 死亡アニメーションを探す（複数の候補から選択）
	var dying_animations = ["dying", "dying_left", "dying_3", "Rifle_Death_R", "Rifle_Death_L", "Rifle_Death_3"]
	var selected_anim: String = ""

	for anim_name in dying_animations:
		if anim_player.has_animation(anim_name):
			selected_anim = anim_name
			break

	if selected_anim != "":
		anim_player.play(selected_anim, ANIM_BLEND_TIME)
		print("[CharacterBase] %s playing death animation: %s" % [name, selected_anim])
	else:
		push_warning("[CharacterBase] %s has no death animation available" % name)


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

	var _weapon_name = CharacterSetup.WEAPON_TYPE_NAMES.get(weapon_type, "unknown")


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

	# 既存の左手IKを削除
	_cleanup_left_hand_ik()

	current_weapon_id = weapon_id

	# 武器タイプを更新（アニメーション用）
	var weapon_type = CharacterSetup.get_weapon_type_from_id(weapon_id)
	set_weapon_type(weapon_type)

	# WeaponResourceを読み込み（IK設定等を取得）
	_load_weapon_resource(weapon_id)

	# 武器モデルを装着
	if skeleton:
		weapon_attachment = CharacterSetup.attach_weapon_to_character(self, skeleton, weapon_id, name)
		# キャラクター固有の武器オフセットを適用（test_animation_viewerと同様）
		_apply_weapon_offset()
		# 武器位置を現在のアニメーション状態に合わせて更新
		_update_weapon_position()
		# 左手IKを設定
		_setup_left_hand_ik()

	weapon_changed.emit(weapon_id)

	# CombatComponentに武器変更を通知
	var combat_component = get_node_or_null("CombatComponent")
	if combat_component:
		combat_component.on_weapon_changed(weapon_id)

	var _weapon_data = CharacterSetup.get_weapon_data(weapon_id)


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


## 歩行シーケンス終了処理
func _finish_walk_sequence() -> void:
	walk_sequence_state = WalkSequenceState.NONE
	walk_sequence_base_name = ""
	_pending_walk_stop = false
	# idle に戻す
	_play_current_animation()
