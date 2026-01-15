class_name AnimationComponent
extends Node

## アニメーション管理コンポーネント
## AnimationTree、上半身/下半身ブレンド、上半身エイミングを担当

signal animation_finished(anim_name: String)
signal death_animation_finished

## 移動状態
enum LocomotionState { IDLE, WALK, RUN }

## 武器タイプ別アニメーション名マッピング
const WEAPON_TYPE_NAMES := {
	0: "none",   # NONE
	1: "rifle",  # RIFLE
	2: "pistol"  # PISTOL
}

## 上半身エイミング設定
@export var aim_rotation_speed: float = 10.0
@export_range(0, 180, 1) var aim_max_angle_deg: float = 90.0
@export_range(-90, 90, 1) var aim_max_pitch_deg: float = 30.0

## アニメーション速度設定
## アニメーションが想定している移動速度（m/s）
@export var anim_base_walk_speed: float = 1.5  ## 歩行アニメーションの基準速度
@export var anim_base_run_speed: float = 4.0   ## 走行アニメーションの基準速度

## 内部参照
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var _blend_tree: AnimationNodeBlendTree
var skeleton: Skeleton3D
var _upper_body_modifier: Node  # UpperBodyRotationModifier

const UpperBodyRotationModifierClass = preload("res://scripts/utils/upper_body_rotation_modifier.gd")
const AnimationFallback = preload("res://scripts/utils/animation_fallback.gd")
const BoneNameRegistry = preload("res://scripts/utils/bone_name_registry.gd")

## 状態
var locomotion_state: LocomotionState = LocomotionState.IDLE
var weapon_type: int = 2  # WeaponRegistry.WeaponType (default: PISTOL)
var is_shooting: bool = false
var _shooting_blend: float = 0.0

## ストレイフ（8方向移動）
var _strafe_blend_x: float = 0.0  # -1 = 左, 0 = 前後, +1 = 右
var _strafe_blend_y: float = 1.0  # -1 = 後退, 0 = 停止, +1 = 前進
var _strafe_enabled: bool = false

## 上半身リコイル
var _upper_body_recoil: float = 0.0
const RECOIL_KICK_ANGLE: float = 0.08  # ~4.5度
const UPPER_BODY_RECOIL_RECOVERY_SPEED: float = 12.0

## 上半身エイミング（ヨー・ピッチ）
var _current_aim_rotation: float = 0.0
var _target_aim_rotation: float = 0.0
var _current_pitch_rotation: float = 0.0
var _target_pitch_rotation: float = 0.0

const SHOOTING_BLEND_SPEED: float = 10.0
const ANIM_BLEND_TIME: float = 0.3
const LOCOMOTION_XFADE_TIME: float = 0.2  # 移動アニメーション遷移のクロスフェード時間


func _ready() -> void:
	pass


## 初期化
## @param model: キャラクターモデル
## @param skel: Skeleton3D
func setup(model: Node3D, skel: Skeleton3D) -> void:
	skeleton = skel

	# AnimationPlayerを取得
	anim_player = model.get_node_or_null("AnimationPlayer")
	if anim_player == null:
		push_error("[AnimationComponent] AnimationPlayer not found in model: %s" % model.name)
		return

	# アニメーション終了シグナルを接続
	if not anim_player.animation_finished.is_connected(_on_animation_finished):
		anim_player.animation_finished.connect(_on_animation_finished)

	# 上半身回転モディファイアを作成（SkeletonModifier3Dベース）
	_setup_upper_body_modifier()

	# 移動系アニメーションをループに設定
	_setup_animation_loops()

	# AnimationTreeを設定
	_setup_animation_tree(model)


## 移動状態を設定
## @param state: 0=IDLE, 1=WALK, 2=RUN
func set_locomotion(state: int) -> void:
	var new_state := state as LocomotionState
	if locomotion_state == new_state:
		return

	locomotion_state = new_state

	# AnimationTreeを有効化（play_animationでループアニメーション再生中の場合に必要）
	if anim_tree and not anim_tree.active:
		anim_tree.active = true

	_update_locomotion_animation()


## 武器タイプを設定
## @param type: WeaponRegistry.WeaponType
func set_weapon_type(type: int) -> void:
	if weapon_type == type:
		return

	weapon_type = type
	_rebuild_walk_blend_space()
	_update_locomotion_animation()
	_update_shoot_animation()


## BlendSpace2D（歩行ストレイフ）を再構築
func _rebuild_walk_blend_space() -> void:
	if _blend_tree == null:
		return

	var walk_node = _blend_tree.get_node("locomotion_walk") as AnimationNodeBlendSpace2D
	if walk_node == null:
		return

	# BlendSpace2Dをクリアして再設定
	while walk_node.get_blend_point_count() > 0:
		walk_node.remove_blend_point(0)
	_setup_walk_blend_space(walk_node)


## 射撃状態を設定
## @param shooting: 射撃中かどうか
func set_shooting(shooting: bool) -> void:
	is_shooting = shooting


## 上半身リコイルを適用
## @param intensity: リコイル強度（0.0 - 1.0）
func apply_upper_body_recoil(intensity: float) -> void:
	_upper_body_recoil = RECOIL_KICK_ANGLE * intensity


## ストレイフブレンドを設定（8方向移動用）
## @param x: 左右成分（-1 = 左, 0 = 前後, +1 = 右）
## @param y: 前後成分（-1 = 後退, 0 = 停止, +1 = 前進）
func set_strafe_blend(x: float, y: float) -> void:
	_strafe_blend_x = clamp(x, -1.0, 1.0)
	_strafe_blend_y = clamp(y, -1.0, 1.0)
	_strafe_enabled = true


## ストレイフを無効化（通常の前進歩行に戻す）
func disable_strafe() -> void:
	_strafe_enabled = false
	_strafe_blend_x = 0.0
	_strafe_blend_y = 1.0


## ストレイフが有効かどうか
func is_strafe_enabled() -> bool:
	return _strafe_enabled


## 移動速度に基づいてアニメーション速度を設定
## @param current_speed: 現在の移動速度（m/s）
## @param is_running: 走っているかどうか
func set_animation_speed(current_speed: float, is_running: bool) -> void:
	if anim_tree == null or not anim_tree.active:
		return

	var base_speed = anim_base_run_speed if is_running else anim_base_walk_speed
	var time_scale = 1.0

	if base_speed > 0.01 and current_speed > 0.01:
		time_scale = current_speed / base_speed
		# 極端な値を制限
		time_scale = clampf(time_scale, 0.5, 2.0)

	anim_tree.set("parameters/time_scale/scale", time_scale)


## 上半身エイミング角度を設定（ヨー + ピッチ）
## @param yaw_degrees: 水平角度（度）
## @param pitch_degrees: 垂直角度（度）- デフォルト0.0で後方互換
func apply_spine_rotation(yaw_degrees: float, pitch_degrees: float = 0.0) -> void:
	_target_aim_rotation = deg_to_rad(clamp(yaw_degrees, -aim_max_angle_deg, aim_max_angle_deg))
	_target_pitch_rotation = deg_to_rad(clamp(pitch_degrees, -aim_max_pitch_deg, aim_max_pitch_deg))


## 現在の上半身回転角度を取得（ラジアン）
## @return: Vector2(yaw, pitch) - 現在の補間後の回転角度
func get_current_aim_rotation() -> Vector2:
	return Vector2(_current_aim_rotation, _current_pitch_rotation)


## アニメーションを直接再生（主にテスト用）
## @param anim_name: アニメーション名
## @param blend_time: ブレンド時間
func play_animation(anim_name: String, blend_time: float = ANIM_BLEND_TIME) -> void:
	if anim_player == null:
		push_warning("[AnimationComponent] anim_player is null!")
		return

	if not anim_player.has_animation(anim_name):
		push_warning("[AnimationComponent] Animation not found: %s (available: %s)" % [anim_name, anim_player.get_animation_list()])
		return
	# AnimationTree使用時は一時停止してAnimationPlayerで再生
	if anim_tree and anim_tree.active:
		anim_tree.active = false
		anim_player.play(anim_name, blend_time)
		# アニメーション終了後にAnimationTreeを再有効化
		await anim_player.animation_finished
		if anim_tree:
			anim_tree.active = true
	else:
		anim_player.play(anim_name, blend_time)


## 毎フレーム更新
## @param delta: フレーム時間
func update(delta: float) -> void:
	_update_shooting_blend(delta)
	_update_upper_body_aim(delta)
	_recover_upper_body_recoil(delta)
	_update_strafe_blend()


## AnimationPlayerの全アニメーションリストを取得
func get_animation_list() -> PackedStringArray:
	if anim_player == null:
		return PackedStringArray()
	return anim_player.get_animation_list()


## スケルトン更新時に呼ばれる（CharacterBaseから）
func on_skeleton_updated() -> void:
	# UpperBodyRotationModifier (SkeletonModifier3D) が回転を担当するため、
	# ここでは追加の回転処理は行わない
	pass


## アニメーション名を取得
## @param base_name: 基本名（idle, walking, sprint等）
## @return: 武器タイプ付きアニメーション名
func get_animation_name(base_name: String) -> String:
	var weapon_name = WEAPON_TYPE_NAMES.get(weapon_type, "none")
	return "%s_%s" % [weapon_name, base_name]


## AnimationTreeを設定
func _setup_animation_tree(model: Node3D) -> void:
	if anim_player == null or skeleton == null:
		return

	# 既存のAnimationTreeを削除
	var existing = model.get_node_or_null("AnimationTree")
	if existing:
		existing.queue_free()

	# AnimationTreeを作成
	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	model.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)

	# BlendTreeを作成
	_blend_tree = AnimationNodeBlendTree.new()
	anim_tree.tree_root = _blend_tree

	# locomotion用のノードを作成
	var locomotion_idle = AnimationNodeAnimation.new()
	var locomotion_run = AnimationNodeAnimation.new()
	_blend_tree.add_node("locomotion_idle", locomotion_idle, Vector2(-300, -100))
	_blend_tree.add_node("locomotion_run", locomotion_run, Vector2(-300, 100))

	# BlendSpace2D（ストレイフ用）を作成
	var walk_blend_space = AnimationNodeBlendSpace2D.new()
	walk_blend_space.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	walk_blend_space.set_min_space(Vector2(-1, -1))
	walk_blend_space.set_max_space(Vector2(1, 1))
	_blend_tree.add_node("locomotion_walk", walk_blend_space, Vector2(-300, 0))

	# BlendSpace2Dにアニメーションポイントを追加（4方向）
	_setup_walk_blend_space(walk_blend_space)

	# AnimationNodeTransitionを作成（クロスフェード付き遷移）
	var transition = AnimationNodeTransition.new()
	transition.xfade_time = LOCOMOTION_XFADE_TIME
	transition.add_input("idle")    # input 0
	transition.add_input("walk")    # input 1
	transition.add_input("run")     # input 2
	_blend_tree.add_node("locomotion_transition", transition, Vector2(0, 0))

	# locomotionノードをTransitionに接続
	_blend_tree.connect_node("locomotion_transition", 0, "locomotion_idle")
	_blend_tree.connect_node("locomotion_transition", 1, "locomotion_walk")
	_blend_tree.connect_node("locomotion_transition", 2, "locomotion_run")

	# TimeScaleノードを追加（アニメーション速度調整用）
	var time_scale = AnimationNodeTimeScale.new()
	_blend_tree.add_node("time_scale", time_scale, Vector2(150, 0))
	_blend_tree.connect_node("time_scale", 0, "locomotion_transition")
	_blend_tree.connect_node("output", 0, "time_scale")

	# 初期アニメーションを設定
	_update_locomotion_animation()
	# _update_shoot_animation()  # テスト中: upper_blendをバイパスしているため無効化

	# AnimationTreeを有効化
	anim_tree.active = true

	# デバッグ出力
	print("[AnimationComponent] Setup complete")
	print("[AnimationComponent] Available animations: %s" % str(anim_player.get_animation_list()))
	print("[AnimationComponent] AnimationTree active: %s" % anim_tree.active)
	print("[AnimationComponent] tree_root: %s" % anim_tree.tree_root)


## BlendSpace2D（歩行ストレイフ）をセットアップ
func _setup_walk_blend_space(blend_space: AnimationNodeBlendSpace2D) -> void:
	if anim_player == null:
		return

	# 前進アニメーション（新形式 "forward" または旧形式 "pistol_walking" を探す）
	var forward_name = _find_animation(["forward", get_animation_name("walking"), "rifle_walking"])
	var has_forward = not forward_name.is_empty()
	if has_forward:
		var forward_anim = AnimationNodeAnimation.new()
		forward_anim.animation = forward_name
		blend_space.add_blend_point(forward_anim, Vector2(0, 1))
	else:
		push_warning("[AnimationComponent] Forward animation not found")

	# 後退アニメーション（新形式 "backward" または旧形式 "pistol_retreat"）
	var back_name = _find_animation(["backward", get_animation_name("retreat"), "rifle_retreat"])
	var has_back = not back_name.is_empty()
	if has_back:
		var back_anim = AnimationNodeAnimation.new()
		back_anim.animation = back_name
		blend_space.add_blend_point(back_anim, Vector2(0, -1))
	else:
		push_warning("[AnimationComponent] Backward animation not found")

	# 左ストレイフアニメーション（新形式 "left_strafe" または旧形式 "pistol_strafe_left"）
	# 座標系調整: 左右を入れ替え
	var left_name = _find_animation(["left_strafe", get_animation_name("strafe_left")])
	var has_left = not left_name.is_empty()
	if has_left:
		var left_anim = AnimationNodeAnimation.new()
		left_anim.animation = left_name
		blend_space.add_blend_point(left_anim, Vector2(1, 0))  # 左→+X

	# 右ストレイフ（新形式 "right_strafe" または旧形式 "pistol_strafe_right"）
	var right_name = _find_animation(["right_strafe", get_animation_name("strafe_right")])
	var has_right = not right_name.is_empty()
	if has_right:
		var right_anim = AnimationNodeAnimation.new()
		right_anim.animation = right_name
		blend_space.add_blend_point(right_anim, Vector2(-1, 0))  # 右→-X
	elif has_left:
		# 右ストレイフがない場合は左を代用
		var right_anim = AnimationNodeAnimation.new()
		right_anim.animation = left_name
		blend_space.add_blend_point(right_anim, Vector2(-1, 0))
		push_warning("[AnimationComponent] Missing right_strafe - using left as fallback")

	# 斜め方向のブレンドポイントを追加（左右入れ替え）
	# 前左斜め
	if has_forward and has_left:
		var fl_anim = AnimationNodeAnimation.new()
		fl_anim.animation = forward_name
		blend_space.add_blend_point(fl_anim, Vector2(0.7, 0.7))
	# 前右斜め
	if has_forward and (has_right or has_left):
		var fr_anim = AnimationNodeAnimation.new()
		fr_anim.animation = forward_name
		blend_space.add_blend_point(fr_anim, Vector2(-0.7, 0.7))
	# 後左斜め
	if has_back and has_left:
		var bl_anim = AnimationNodeAnimation.new()
		bl_anim.animation = back_name
		blend_space.add_blend_point(bl_anim, Vector2(0.7, -0.7))
	# 後右斜め
	if has_back and (has_right or has_left):
		var br_anim = AnimationNodeAnimation.new()
		br_anim.animation = back_name
		blend_space.add_blend_point(br_anim, Vector2(-0.7, -0.7))


## アニメーション名リストから最初に見つかったものを返す
func _find_animation(candidates: Array) -> String:
	for name in candidates:
		if anim_player.has_animation(name):
			return name
	return ""


## 上半身ボーンフィルターを設定
func _setup_upper_body_filter(blend_node: AnimationNodeBlend2) -> void:
	blend_node.filter_enabled = true

	# BoneNameRegistryを使用して上半身ボーンを取得
	var upper_body_bones := BoneNameRegistry.get_upper_body_bones(skeleton)

	# Armatureプレフィックスを考慮したパスを構築
	var armature_path = ""
	var armature = skeleton.get_parent()
	if armature and armature.name == "Armature":
		armature_path = "Armature/"

	# フィルターを設定
	for bone_name in upper_body_bones:
		var bone_idx = skeleton.find_bone(bone_name)
		if bone_idx >= 0:
			var bone_path = "%sSkeleton3D:%s" % [armature_path, bone_name]
			blend_node.set_filter_path(NodePath(bone_path), true)


## 移動アニメーションを更新
func _update_locomotion_animation() -> void:
	if _blend_tree == null or anim_tree == null:
		print("[AnimationComponent] _update_locomotion_animation: blend_tree or anim_tree is null")
		return

	# 各状態のアニメーション名を取得
	var idle_name = _get_locomotion_anim_name(LocomotionState.IDLE)
	var run_name = _get_locomotion_anim_name(LocomotionState.RUN)
	print("[AnimationComponent] idle_name: %s, run_name: %s" % [idle_name, run_name])

	# idle と run ノードにアニメーションを設定
	var idle_node = _blend_tree.get_node("locomotion_idle") as AnimationNodeAnimation
	var run_node = _blend_tree.get_node("locomotion_run") as AnimationNodeAnimation
	if idle_node:
		idle_node.animation = idle_name
		print("[AnimationComponent] Set idle_node.animation = %s" % idle_name)
	if run_node:
		run_node.animation = run_name
		print("[AnimationComponent] Set run_node.animation = %s" % run_name)

	# locomotion_walk は BlendSpace2D なので _setup_walk_blend_space() で設定済み
	# 武器タイプ変更時は _rebuild_walk_blend_space() を呼ぶ

	# Transitionの状態を切り替え（クロスフェード付き）
	var transition_name: String
	match locomotion_state:
		LocomotionState.IDLE:
			transition_name = "idle"
		LocomotionState.WALK:
			transition_name = "walk"
		LocomotionState.RUN:
			transition_name = "run"

	print("[AnimationComponent] Setting transition to: %s" % transition_name)
	anim_tree.set("parameters/locomotion_transition/transition_request", transition_name)


## 移動状態に応じたアニメーション名を取得（フォールバック付き）
func _get_locomotion_anim_name(state: LocomotionState) -> String:
	var candidates: Array
	match state:
		LocomotionState.IDLE:
			# 新形式 "idle" を優先
			candidates = [
				"idle",  # 新形式
				get_animation_name("idle"),  # pistol_idle
				"forward",
			]
		LocomotionState.WALK:
			# 新形式 "forward" を優先
			candidates = [
				"forward",  # 新形式
				get_animation_name("walking"),  # pistol_walking
				"rifle_walking",
			]
		LocomotionState.RUN:
			# sprint → forward をフォールバック
			candidates = [
				"sprint",  # 新形式
				get_animation_name("sprint"),  # pistol_sprint
				"forward",
			]

	return _find_animation(candidates)


## ストレイフブレンド座標を更新
func _update_strafe_blend() -> void:
	if anim_tree == null or not anim_tree.active:
		return

	# WALK状態でストレイフが有効な場合のみ更新
	if locomotion_state == LocomotionState.WALK and _strafe_enabled:
		var blend_pos = Vector2(_strafe_blend_x, _strafe_blend_y)
		anim_tree.set("parameters/locomotion_walk/blend_position", blend_pos)
		# デバッグ出力（必要時のみ有効化）
		#if Engine.get_process_frames() % 60 == 0:
		#	print("[Anim] blend: (%.2f, %.2f)" % [blend_pos.x, blend_pos.y])


## 射撃アニメーションを更新
func _update_shoot_animation() -> void:
	if _blend_tree == null:
		return

	# 優先順位: idle_aiming > shoot > walking > idle
	var candidates = [
		get_animation_name("idle_aiming"),
		get_animation_name("shoot"),
		get_animation_name("walking"),
		get_animation_name("idle")
	]

	var shoot_anim_name = ""
	for candidate in candidates:
		if anim_player.has_animation(candidate):
			shoot_anim_name = candidate
			break

	if shoot_anim_name.is_empty():
		shoot_anim_name = "idle_none"

	var shoot_node = _blend_tree.get_node("shoot") as AnimationNodeAnimation
	if shoot_node:
		shoot_node.animation = shoot_anim_name


## 射撃ブレンド値を更新
func _update_shooting_blend(delta: float) -> void:
	if anim_tree == null or not anim_tree.active:
		return

	var target = 1.0 if is_shooting else 0.0
	_shooting_blend = lerp(_shooting_blend, target, SHOOTING_BLEND_SPEED * delta)

	anim_tree.set("parameters/upper_blend/blend_amount", _shooting_blend)


## 上半身エイミング角度を更新（ヨー + ピッチ）
func _update_upper_body_aim(delta: float) -> void:
	# 目標角度に向けて補間（ヨー）
	_current_aim_rotation = lerp(_current_aim_rotation, _target_aim_rotation, aim_rotation_speed * delta)
	# 目標角度に向けて補間（ピッチ）
	_current_pitch_rotation = lerp(_current_pitch_rotation, _target_pitch_rotation, aim_rotation_speed * delta)

	# SkeletonModifier3Dに回転値を設定
	if _upper_body_modifier:
		_upper_body_modifier.rotation_angle = _current_aim_rotation
		_upper_body_modifier.pitch_angle = _current_pitch_rotation


## 上半身リコイルを回復
func _recover_upper_body_recoil(delta: float) -> void:
	if _upper_body_recoil > 0.001:
		_upper_body_recoil = lerpf(_upper_body_recoil, 0.0, UPPER_BODY_RECOIL_RECOVERY_SPEED * delta)
	else:
		_upper_body_recoil = 0.0

	# SkeletonModifier3Dにリコイル値を設定
	if _upper_body_modifier:
		_upper_body_modifier.recoil_angle = _upper_body_recoil


## アニメーション終了時
func _on_animation_finished(anim_name: StringName) -> void:
	animation_finished.emit(String(anim_name))


## 移動系アニメーションのループ設定
func _setup_animation_loops() -> void:
	if anim_player == null:
		return

	# ループにするアニメーションのパターン
	var loop_patterns = ["walk", "run", "idle", "sprint", "retreat", "strafe", "forward", "backward"]

	for anim_name in anim_player.get_animation_list():
		var anim = anim_player.get_animation(anim_name)
		if anim == null:
			continue

		var lower_name = anim_name.to_lower()
		for pattern in loop_patterns:
			if pattern in lower_name:
				anim.loop_mode = Animation.LOOP_LINEAR
				break


## 上半身回転モディファイアをセットアップ
func _setup_upper_body_modifier() -> void:
	if skeleton == null:
		return

	# 既存のモディファイアを削除
	var existing = skeleton.get_node_or_null("UpperBodyRotationModifier")
	if existing:
		existing.queue_free()

	# 新しいモディファイアを作成
	_upper_body_modifier = UpperBodyRotationModifierClass.new()
	_upper_body_modifier.name = "UpperBodyRotationModifier"
	_upper_body_modifier.influence = 1.0
	_upper_body_modifier.active = true

	# Skeleton3Dの子として追加
	skeleton.add_child(_upper_body_modifier)


## 死亡アニメーションを再生
## @param weapon_type_param: 武器タイプ（0=NONE, 1=RIFLE, 2=PISTOL）
func play_death_animation(weapon_type_param: int = 1) -> void:
	if anim_player == null:
		death_animation_finished.emit()
		return

	var weapon_name = WEAPON_TYPE_NAMES.get(weapon_type_param, "rifle")

	# AnimationFallback を使用してフォールバック検索
	var found_anim = AnimationFallback.get_death_animation(anim_player, weapon_name)

	if found_anim.is_empty():
		push_warning("[AnimationComponent] No death animation found")
		death_animation_finished.emit()
		return

	# AnimationTreeを無効化
	if anim_tree and anim_tree.active:
		anim_tree.active = false

	# 上半身回転モディファイアを無効化
	if _upper_body_modifier:
		_upper_body_modifier.active = false

	# ループモードを無効化
	var anim = anim_player.get_animation(found_anim)
	if anim:
		anim.loop_mode = Animation.LOOP_NONE

	# 再生
	anim_player.play(found_anim, 0.1)  # 短めのブレンド

	# 終了を待機
	await anim_player.animation_finished
	death_animation_finished.emit()
