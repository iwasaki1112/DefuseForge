class_name CharacterBase
extends CharacterBody3D

## キャラクター基底クラス
## コンポーネントを統合し、シンプルなAPIを提供

## チーム定義
enum Team { NONE = 0, PLAYER = 1, ENEMY = 2 }

const CharacterActionState = preload("res://scripts/resources/action_state.gd")
const MovementComponentScript = preload("res://scripts/characters/components/movement_component.gd")
const AnimationComponentScript = preload("res://scripts/characters/components/animation_component.gd")
const WeaponComponentScript = preload("res://scripts/characters/components/weapon_component.gd")
const HealthComponentScript = preload("res://scripts/characters/components/health_component.gd")
const VisionComponentScript = preload("res://scripts/characters/components/vision_component.gd")
const OutlineComponentScript = preload("res://scripts/characters/components/outline_component.gd")

## シグナル
signal path_completed
signal waypoint_reached(index: int)
signal died(killer: Node3D)
signal damaged(amount: float, attacker: Node3D, is_headshot: bool)
signal weapon_changed(weapon_id: int)
signal locomotion_changed(state: int)
signal action_started(action_type: int)
signal action_completed(action_type: int)

## エクスポート設定
@export_group("移動設定")
@export var base_walk_speed: float = 3.0
@export var base_run_speed: float = 6.0

@export_group("HP設定")
@export var max_health: float = 100.0

@export_group("チーム設定")
@export var team: Team = Team.NONE

@export_group("自動照準設定")
@export var auto_aim_enabled: bool = true

## コンポーネント参照
var movement: Node  # MovementComponent
var animation: Node  # AnimationComponent
var weapon: Node     # WeaponComponent
var health: Node     # HealthComponent
var vision: Node     # VisionComponent
var outline: Node    # OutlineComponent

## 内部参照
var skeleton: Skeleton3D
var model: Node3D

## アクション状態
var current_action: int = CharacterActionState.ActionType.NONE
var _action_timer: float = 0.0

## 生存状態
var is_alive: bool = true

## 自動照準ターゲット
var _current_target: CharacterBase = null


func _ready() -> void:
	add_to_group("characters")
	_find_model_and_skeleton()
	_setup_components()
	_connect_signals()


func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	# アクションタイマー更新
	_update_action_timer(delta)

	# コンポーネント更新
	if movement:
		velocity = movement.update(delta)
	if animation:
		animation.update(delta)
	if weapon:
		weapon.update()
		weapon.update_ik()
	if vision:
		vision.update(delta)

	# 自動照準更新
	_update_auto_aim()

	# 敵の可視性を更新（プレイヤーの視界内にいるときのみ表示）
	update_enemy_visibility()

	move_and_slide()


## モデルとスケルトンを検索
func _find_model_and_skeleton() -> void:
	# CharacterModelを検索
	model = get_node_or_null("CharacterModel")
	if model == null:
		# 子ノードから検索
		for child in get_children():
			if child is Node3D and child.name.contains("Model"):
				model = child
				break

	if model == null:
		push_warning("[CharacterBase] %s: CharacterModel not found" % name)
		return

	# スケルトンを検索
	skeleton = model.get_node_or_null("Armature/Skeleton3D")
	if skeleton == null:
		skeleton = _find_skeleton_recursive(model)

	if skeleton == null:
		push_warning("[CharacterBase] %s: Skeleton3D not found" % name)


## スケルトンを再帰検索
func _find_skeleton_recursive(node: Node) -> Skeleton3D:
	for child in node.get_children():
		if child is Skeleton3D:
			return child
		var found = _find_skeleton_recursive(child)
		if found:
			return found
	return null


## コンポーネントをセットアップ
func _setup_components() -> void:
	# MovementComponent
	movement = get_node_or_null("MovementComponent")
	if movement == null:
		movement = Node.new()
		movement.set_script(MovementComponentScript)
		movement.name = "MovementComponent"
		add_child(movement)

	movement.walk_speed = base_walk_speed
	movement.run_speed = base_run_speed

	# HealthComponent
	health = get_node_or_null("HealthComponent")
	if health == null:
		health = Node.new()
		health.set_script(HealthComponentScript)
		health.name = "HealthComponent"
		add_child(health)

	health.max_health = max_health

	# AnimationComponent
	animation = get_node_or_null("AnimationComponent")
	if animation == null:
		animation = Node.new()
		animation.set_script(AnimationComponentScript)
		animation.name = "AnimationComponent"
		add_child(animation)

	if skeleton and model:
		animation.setup(model, skeleton)

	# WeaponComponent
	weapon = get_node_or_null("WeaponComponent")
	if weapon == null:
		weapon = Node.new()
		weapon.set_script(WeaponComponentScript)
		weapon.name = "WeaponComponent"
		add_child(weapon)

	if skeleton:
		weapon.setup(skeleton, self)

	# スケルトン更新シグナルを接続
	if skeleton:
		skeleton.skeleton_updated.connect(_on_skeleton_updated)

	# VisionComponent
	vision = get_node_or_null("VisionComponent")
	if vision == null:
		vision = Node.new()
		vision.set_script(VisionComponentScript)
		vision.name = "VisionComponent"
		add_child(vision)

	# OutlineComponent
	outline = get_node_or_null("OutlineComponent")
	if outline == null:
		outline = Node.new()
		outline.set_script(OutlineComponentScript)
		outline.name = "OutlineComponent"
		add_child(outline)
	# Note: outline.setup() is called separately via setup_outline_camera()


## シグナルを接続
func _connect_signals() -> void:
	if movement:
		movement.path_completed.connect(func(): path_completed.emit())
		movement.waypoint_reached.connect(func(idx): waypoint_reached.emit(idx))
		movement.locomotion_changed.connect(_on_locomotion_changed)

	if health:
		health.died.connect(_on_died)
		health.damaged.connect(_on_damaged)

	if weapon:
		weapon.weapon_changed.connect(func(id): weapon_changed.emit(id))


## ========================================
## モデル管理 API
## ========================================

## モデルをリロードし、全コンポーネントを再初期化
## CharacterModelノードを入れ替えた後に呼び出す
func reload_model(new_model: Node3D = null) -> void:
	# 既存のシグナル接続を切断
	if skeleton and skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
		skeleton.skeleton_updated.disconnect(_on_skeleton_updated)

	# モデル参照を更新
	if new_model:
		model = new_model

	# 再初期化
	_find_model_and_skeleton()
	_setup_components()
	_connect_signals()


## ========================================
## 移動 API
## ========================================

## パスを設定して移動開始
func set_path(points: Array[Vector3], run: bool = false) -> void:
	if movement:
		movement.set_path(points, run)


## 単一の目標地点に移動
func move_to(target: Vector3, run: bool = false) -> void:
	if movement:
		movement.move_to(target, run)


## 移動を停止
func stop() -> void:
	if movement:
		movement.stop()


## 走る/歩くを切り替え
func set_running(running: bool) -> void:
	if movement:
		movement.set_running(running)


## 移動中かどうか
func is_moving() -> bool:
	return movement.is_moving if movement else false


## ========================================
## 武器 API
## ========================================

## 武器を設定
func set_weapon(weapon_id: int) -> void:
	if weapon:
		weapon.set_weapon(weapon_id)

	# アニメーションコンポーネントにも通知
	if animation and weapon and weapon.weapon_resource:
		animation.set_weapon_type(weapon.weapon_resource.weapon_type)


## 現在の武器IDを取得
func get_weapon_id() -> int:
	return weapon.get_weapon_id() if weapon else 0


## 現在の武器IDを取得（エイリアス）
func get_current_weapon_id() -> int:
	return get_weapon_id()


## 武器リソースを取得
func get_weapon_resource() -> WeaponResource:
	return weapon.get_weapon_resource() if weapon else null


## リコイルを適用
func apply_recoil(intensity: float = 1.0) -> void:
	if weapon:
		weapon.apply_recoil(intensity)
	if animation:
		animation.apply_upper_body_recoil(intensity)


## ========================================
## アニメーション API
## ========================================

## アニメーションを再生
func play_animation(anim_name: String, blend_time: float = 0.3) -> void:
	if animation:
		animation.play_animation(anim_name, blend_time)
	else:
		push_warning("[CharacterBase] animation component is null!")


## 射撃状態を設定
func set_shooting(shooting: bool) -> void:
	if animation:
		animation.set_shooting(shooting)


## 上半身回転を設定
func set_upper_body_rotation(degrees: float) -> void:
	if animation:
		animation.apply_spine_rotation(degrees)


## アニメーションリストを取得
func get_animation_list() -> PackedStringArray:
	return animation.get_animation_list() if animation else PackedStringArray()


## ========================================
## HP API
## ========================================

## ダメージを受ける
func take_damage(amount: float, attacker: Node3D = null, is_headshot: bool = false) -> void:
	if health:
		health.take_damage(amount, attacker, is_headshot)


## 回復
func heal(amount: float) -> void:
	if health:
		health.heal(amount)


## HP割合を取得
func get_health_ratio() -> float:
	return health.get_health_ratio() if health else 0.0


## HPを取得
func get_health() -> float:
	return health.health if health else 0.0


## ========================================
## チーム API
## ========================================

## 対象が敵チームかどうか判定
## @param other: 判定対象のキャラクター
## @return: 敵チームならtrue
func is_enemy_of(other: CharacterBase) -> bool:
	if other == null:
		return false
	if team == Team.NONE or other.team == Team.NONE:
		return false
	return team != other.team


## ========================================
## アクション API
## ========================================

## アクションを開始
func start_action(action_type: int, duration: float) -> void:
	if current_action != CharacterActionState.ActionType.NONE:
		return

	current_action = action_type
	_action_timer = duration
	action_started.emit(action_type)


## アクションをキャンセル
func cancel_action() -> void:
	if current_action == CharacterActionState.ActionType.NONE:
		return

	current_action = CharacterActionState.ActionType.NONE
	_action_timer = 0.0


## アクション中かどうか
func is_in_action() -> bool:
	return current_action != CharacterActionState.ActionType.NONE


## アクションタイマーを更新
func _update_action_timer(delta: float) -> void:
	if current_action == CharacterActionState.ActionType.NONE:
		return

	_action_timer -= delta
	if _action_timer <= 0:
		var completed_action = current_action
		current_action = CharacterActionState.ActionType.NONE
		action_completed.emit(completed_action)


## ========================================
## 自動照準（内部処理）
## ========================================

## 自動照準の更新処理
func _update_auto_aim() -> void:
	if not auto_aim_enabled or not is_alive:
		return

	var enemy = _find_enemy_in_vision()
	_current_target = enemy

	if enemy:
		# 敵への方向ベクトル（XZ平面）
		var to_enemy = enemy.global_position - global_position
		to_enemy.y = 0

		# キャラクターの前方ベクトル（+Zが前方）
		var forward = global_transform.basis.z
		forward.y = 0

		# 前方ベクトルと敵方向の角度差を計算
		var angle_to_enemy = rad_to_deg(forward.signed_angle_to(to_enemy, Vector3.UP))

		# 上半身回転の範囲内にクランプして適用
		var clamped_angle = clamp(angle_to_enemy, -45.0, 45.0)
		set_upper_body_rotation(clamped_angle)
	else:
		# 敵がいない場合は上半身回転をリセット
		set_upper_body_rotation(0.0)


## 視界内の敵を検出（FOV + 距離 + レイキャスト方式）
func _find_enemy_in_vision() -> CharacterBase:
	if not vision:
		return null

	# "characters"グループから全キャラクターを取得
	var all_characters = get_tree().get_nodes_in_group("characters")
	var closest_enemy: CharacterBase = null
	var closest_distance: float = INF

	for node in all_characters:
		var character = node as CharacterBase
		if character == null or character == self:
			continue

		var is_enemy = is_enemy_of(character)
		if not is_enemy:
			continue
		if not character.is_alive:
			continue

		# 視界内かチェック
		var in_fov = _is_in_field_of_view(character)
		if in_fov:
			var dist = global_position.distance_to(character.global_position)
			if dist < closest_distance:
				closest_distance = dist
				closest_enemy = character

	return closest_enemy


## 対象が視界内にいるかチェック（FOV + 距離 + 遮蔽物）
func _is_in_field_of_view(target: CharacterBase) -> bool:
	if not vision:
		return false

	var view_distance = vision.view_distance
	var fov_degrees = vision.fov_degrees

	# 距離チェック
	var to_target = target.global_position - global_position
	var distance = to_target.length()
	if distance > view_distance:
		return false

	# FOVチェック（XZ平面）
	to_target.y = 0
	var forward = global_transform.basis.z  # +Zが前方
	forward.y = 0

	if to_target.length() < 0.01 or forward.length() < 0.01:
		return true  # ほぼ同じ位置

	var angle = rad_to_deg(forward.angle_to(to_target))
	if angle > fov_degrees / 2.0:
		return false

	# レイキャストで遮蔽物チェック
	var space_state = get_world_3d().direct_space_state
	var eye_pos = global_position + Vector3(0, vision.eye_height, 0)
	var target_pos = target.global_position + Vector3(0, 1.0, 0)  # 対象の胴体あたり

	var query = PhysicsRayQueryParameters3D.create(eye_pos, target_pos, vision.wall_collision_mask)
	query.exclude = [get_rid(), target.get_rid()]
	var result = space_state.intersect_ray(query)

	if not result.is_empty():
		return false

	# 壁に当たらなければ視界内
	return true


## ========================================
## コールバック
## ========================================

func _on_locomotion_changed(state: int) -> void:
	locomotion_changed.emit(state)

	# アニメーションを更新
	if animation:
		animation.set_locomotion(state)


func _on_died(killer: Node3D) -> void:
	is_alive = false
	died.emit(killer)

	# 移動停止
	if movement:
		movement.stop()

	# IKを無効化
	if weapon:
		weapon.disable_ik()

	# 視界（FoW）を無効化
	if vision:
		vision.disable()

	# コライダーを無効化
	_disable_collision()

	# 死亡アニメーション再生
	_play_death_animation()


## コライダーを無効化（死亡時）
func _disable_collision() -> void:
	var collision_shape = get_node_or_null("CollisionShape3D")
	if collision_shape:
		collision_shape.disabled = true


## 死亡アニメーションを再生
func _play_death_animation() -> void:
	if animation == null:
		return

	var current_weapon_type = 1  # デフォルト: RIFLE
	if weapon and weapon.weapon_resource:
		current_weapon_type = weapon.weapon_resource.weapon_type

	animation.play_death_animation(current_weapon_type)


func _on_damaged(amount: float, attacker: Node3D, is_headshot: bool) -> void:
	damaged.emit(amount, attacker, is_headshot)


func _on_skeleton_updated() -> void:
	if animation:
		animation.on_skeleton_updated()
	# Apply IK after animation is processed
	if weapon:
		weapon.apply_ik_after_animation()


## ========================================
## 視界 API
## ========================================

## 視野角を設定
func set_vision_fov(degrees: float) -> void:
	if vision:
		vision.set_fov(degrees)


## 視界距離を設定
func set_vision_distance(distance: float) -> void:
	if vision:
		vision.set_view_distance(distance)


## 視界ポリゴンを取得
func get_vision_polygon() -> PackedVector3Array:
	return vision.get_visible_polygon() if vision else PackedVector3Array()


## 壁ヒットポイントを取得
func get_wall_hit_points() -> PackedVector3Array:
	return vision.get_wall_hit_points() if vision else PackedVector3Array()


## ========================================
## 敵視認性 API
## ========================================

## 対象がプレイヤーチームの誰かの視界内にいるかチェック
## @param target: チェック対象のキャラクター
## @return: 誰かの視界内ならtrue
static func is_visible_to_player_team(target: CharacterBase) -> bool:
	if target == null or not target.is_alive:
		return false

	var all_characters = target.get_tree().get_nodes_in_group("characters")
	for node in all_characters:
		var character = node as CharacterBase
		if character == null or character == target:
			continue
		if character.team != Team.PLAYER or not character.is_alive:
			continue
		if character._is_in_field_of_view(target):
			return true
	return false


## 敵キャラクターの可視性を更新（敵のみ対象）
func update_enemy_visibility() -> void:
	if team != Team.ENEMY:
		return
	if model:
		model.visible = CharacterBase.is_visible_to_player_team(self)


## ========================================
## 選択 API
## ========================================

## アウトラインにカメラを設定（SubViewport方式に必要）
func setup_outline_camera(camera: Camera3D) -> void:
	if outline:
		outline.setup(self, camera)


## 選択状態を設定
func set_selected(selected: bool) -> void:
	if outline:
		outline.set_selected(selected)


## 選択状態を取得
func is_selected() -> bool:
	return outline.is_selected() if outline else false


## アウトライン色を設定
func set_outline_color(color: Color) -> void:
	if outline:
		outline.set_outline_color(color)


## アウトライン幅を設定
func set_outline_width(width: float) -> void:
	if outline:
		outline.set_outline_width(width)
