class_name AnimationComponent
extends Node

## アニメーション管理コンポーネント
## AnimationTree、上半身/下半身ブレンド、上半身エイミングを担当

signal animation_finished(anim_name: String)

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

## 内部参照
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var _blend_tree: AnimationNodeBlendTree
var skeleton: Skeleton3D

## 状態
var locomotion_state: LocomotionState = LocomotionState.IDLE
var weapon_type: int = 0  # WeaponRegistry.WeaponType
var is_shooting: bool = false
var _shooting_blend: float = 0.0

## 上半身エイミング
var _aim_spine_bone_idx: int = -1
var _current_aim_rotation: float = 0.0
var _target_aim_rotation: float = 0.0

const SHOOTING_BLEND_SPEED: float = 10.0
const ANIM_BLEND_TIME: float = 0.3


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
		push_error("[AnimationComponent] AnimationPlayer not found in model")
		return

	# アニメーション終了シグナルを接続
	if not anim_player.animation_finished.is_connected(_on_animation_finished):
		anim_player.animation_finished.connect(_on_animation_finished)

	# 移動系アニメーションをループに設定
	_setup_animation_loops()

	# 上半身ボーンを検索
	_find_aim_spine_bone()

	# AnimationTreeを設定
	_setup_animation_tree(model)


## 移動状態を設定
## @param state: LocomotionState
func set_locomotion(state: LocomotionState) -> void:
	if locomotion_state == state:
		return

	locomotion_state = state
	_update_locomotion_animation()


## 武器タイプを設定
## @param type: WeaponRegistry.WeaponType
func set_weapon_type(type: int) -> void:
	if weapon_type == type:
		return

	weapon_type = type
	_update_locomotion_animation()
	_update_shoot_animation()


## 射撃状態を設定
## @param shooting: 射撃中かどうか
func set_shooting(shooting: bool) -> void:
	is_shooting = shooting


## 上半身エイミング角度を設定
## @param degrees: エイミング角度（度）
func apply_spine_rotation(degrees: float) -> void:
	_target_aim_rotation = deg_to_rad(clamp(degrees, -aim_max_angle_deg, aim_max_angle_deg))


## アニメーションを直接再生（主にテスト用）
## @param anim_name: アニメーション名
## @param blend_time: ブレンド時間
func play_animation(anim_name: String, blend_time: float = ANIM_BLEND_TIME) -> void:
	print("[AnimationComponent] play_animation called: %s" % anim_name)
	if anim_player == null:
		push_warning("[AnimationComponent] anim_player is null!")
		return

	if not anim_player.has_animation(anim_name):
		push_warning("[AnimationComponent] Animation not found: %s (available: %s)" % [anim_name, anim_player.get_animation_list()])
		return

	print("[AnimationComponent] Playing animation: %s" % anim_name)
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


## AnimationPlayerの全アニメーションリストを取得
func get_animation_list() -> PackedStringArray:
	if anim_player == null:
		return PackedStringArray()
	return anim_player.get_animation_list()


## スケルトン更新時に呼ばれる（CharacterBaseから）
func on_skeleton_updated() -> void:
	if skeleton == null or _aim_spine_bone_idx < 0:
		return

	# 上半身回転を適用
	if abs(_current_aim_rotation) > 0.001:
		var current_pose = skeleton.get_bone_pose_rotation(_aim_spine_bone_idx)
		var twist = Quaternion(Vector3.UP, _current_aim_rotation)
		skeleton.set_bone_pose_rotation(_aim_spine_bone_idx, current_pose * twist)


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

	# locomotionアニメーション（全身用）
	var locomotion_anim = AnimationNodeAnimation.new()
	_blend_tree.add_node("locomotion", locomotion_anim, Vector2(0, 0))

	# shootアニメーション（上半身用）
	var shoot_anim = AnimationNodeAnimation.new()
	_blend_tree.add_node("shoot", shoot_anim, Vector2(0, 200))

	# Blend2ノード（上半身のみブレンド）
	var blend2 = AnimationNodeBlend2.new()
	_blend_tree.add_node("upper_blend", blend2, Vector2(300, 100))

	# 接続
	_blend_tree.connect_node("upper_blend", 0, "locomotion")
	_blend_tree.connect_node("upper_blend", 1, "shoot")
	_blend_tree.connect_node("output", 0, "upper_blend")

	# 上半身ボーンフィルターを設定
	_setup_upper_body_filter(blend2)

	# 初期アニメーションを設定
	_update_locomotion_animation()
	_update_shoot_animation()

	# 有効化
	anim_tree.active = true


## 上半身ボーンフィルターを設定
func _setup_upper_body_filter(blend_node: AnimationNodeBlend2) -> void:
	blend_node.filter_enabled = true

	var upper_body_bones: Array[String] = []

	# スケルトンから上半身ボーンを動的に収集
	for i in range(skeleton.get_bone_count()):
		var bone_name = skeleton.get_bone_name(i)
		var lower_name = bone_name.to_lower()

		if "spine" in lower_name or "neck" in lower_name or "head" in lower_name \
			or "shoulder" in lower_name or "arm" in lower_name or "hand" in lower_name \
			or "thumb" in lower_name or "index" in lower_name or "middle" in lower_name \
			or "ring" in lower_name or "pinky" in lower_name:
			upper_body_bones.append(bone_name)

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
	if _blend_tree == null:
		return

	var anim_name: String
	match locomotion_state:
		LocomotionState.IDLE:
			anim_name = get_animation_name("idle")
		LocomotionState.WALK:
			anim_name = get_animation_name("walking")
		LocomotionState.RUN:
			anim_name = get_animation_name("sprint")

	# アニメーションが存在しない場合はフォールバック
	if not anim_player.has_animation(anim_name):
		# idle→walkingにフォールバック（idleアニメーションがない場合）
		anim_name = get_animation_name("walking")
		if not anim_player.has_animation(anim_name):
			anim_name = "rifle_walking"
			if not anim_player.has_animation(anim_name):
				anim_name = "idle_none"

	var locomotion_node = _blend_tree.get_node("locomotion") as AnimationNodeAnimation
	if locomotion_node:
		locomotion_node.animation = anim_name


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


## 上半身エイミング角度を更新
func _update_upper_body_aim(delta: float) -> void:
	if _aim_spine_bone_idx < 0:
		return

	# 目標角度に向けて補間
	_current_aim_rotation = lerp(_current_aim_rotation, _target_aim_rotation, aim_rotation_speed * delta)


## 上半身エイミング用のスパインボーンを検索
func _find_aim_spine_bone() -> void:
	if skeleton == null:
		return

	# 優先順位付きで検索
	var candidates = ["c_spine_02.x", "spine_02", "spine.002", "Spine2", "spine2"]
	for candidate in candidates:
		var idx = skeleton.find_bone(candidate)
		if idx >= 0:
			_aim_spine_bone_idx = idx
			return

	# 見つからなければ spine を含むボーンを検索
	for i in range(skeleton.get_bone_count()):
		var bone_name = skeleton.get_bone_name(i)
		if "spine" in bone_name.to_lower() and "02" in bone_name:
			_aim_spine_bone_idx = i
			return


## アニメーション終了時
func _on_animation_finished(anim_name: StringName) -> void:
	animation_finished.emit(String(anim_name))


## 移動系アニメーションのループ設定
func _setup_animation_loops() -> void:
	if anim_player == null:
		return

	# ループにするアニメーションのパターン
	var loop_patterns = ["walk", "run", "idle", "sprint"]

	for anim_name in anim_player.get_animation_list():
		var anim = anim_player.get_animation(anim_name)
		if anim == null:
			continue

		var lower_name = anim_name.to_lower()
		for pattern in loop_patterns:
			if pattern in lower_name:
				anim.loop_mode = Animation.LOOP_LINEAR
				print("[AnimationComponent] Set loop for: %s (loop_mode=%d)" % [anim_name, anim.loop_mode])
				break
