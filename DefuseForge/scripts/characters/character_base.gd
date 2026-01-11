class_name CharacterBase
extends CharacterBody3D

## キャラクター基底クラス
## コンポーネントを統合し、シンプルなAPIを提供

const CharacterActionState = preload("res://scripts/resources/action_state.gd")
const MovementComponentScript = preload("res://scripts/characters/components/movement_component.gd")
const AnimationComponentScript = preload("res://scripts/characters/components/animation_component.gd")
const WeaponComponentScript = preload("res://scripts/characters/components/weapon_component.gd")
const HealthComponentScript = preload("res://scripts/characters/components/health_component.gd")

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

## コンポーネント参照
var movement: Node  # MovementComponent
var animation: Node  # AnimationComponent
var weapon: Node     # WeaponComponent
var health: Node     # HealthComponent

## 内部参照
var skeleton: Skeleton3D
var model: Node3D

## アクション状態
var current_action: int = CharacterActionState.ActionType.NONE
var _action_timer: float = 0.0

## 生存状態
var is_alive: bool = true


func _ready() -> void:
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
		push_warning("[CharacterBase] CharacterModel not found")
		return

	# スケルトンを検索
	skeleton = model.get_node_or_null("Armature/Skeleton3D")
	if skeleton == null:
		skeleton = _find_skeleton_recursive(model)

	if skeleton == null:
		push_warning("[CharacterBase] Skeleton3D not found")


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
		weapon.setup(skeleton)

	# スケルトン更新シグナルを接続
	if skeleton:
		skeleton.skeleton_updated.connect(_on_skeleton_updated)


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


## ========================================
## アニメーション API
## ========================================

## アニメーションを再生
func play_animation(anim_name: String, blend_time: float = 0.3) -> void:
	print("[CharacterBase] play_animation: %s (animation=%s)" % [anim_name, animation])
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


func _on_damaged(amount: float, attacker: Node3D, is_headshot: bool) -> void:
	damaged.emit(amount, attacker, is_headshot)


func _on_skeleton_updated() -> void:
	if animation:
		animation.on_skeleton_updated()
