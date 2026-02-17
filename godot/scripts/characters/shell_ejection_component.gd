class_name ShellEjectionComponent
extends RefCounted

## 薬莢排出コンポーネント
## 射撃時に薬莢が銃の右側から排出され、放物線を描いて地面に落下
## 数秒後にフェードアウトして消える
## GameCharacterの射撃イベント(_on_anim_fired)から呼び出される

# ============================================
# Constants
# ============================================

const MAX_CASINGS: int = 20  ## 同時表示最大数（オブジェクトプール）
const CASING_LIFETIME: float = 3.0  ## 地面到達後の表示時間（秒）
const CASING_FADE_DURATION: float = 0.5  ## フェードアウト時間（秒）
const GRAVITY: float = 9.8  ## 重力加速度
const EJECT_SPEED_RIGHT: float = 1.5  ## 横方向射出速度（m/s）
const EJECT_SPEED_UP: float = 2.0  ## 上方向射出速度（m/s）
const EJECT_SPEED_FORWARD: float = 0.3  ## 前後方向射出速度（m/s）
const SPIN_SPEED: float = 720.0  ## 回転速度（度/秒）
const CASING_SCALE: float = 3.0  ## ゲーム用誇張（実寸の3倍）

# ============================================
# References
# ============================================

var _character: Node3D = null
var _weapon_socket: Node3D = null
var _casing_scene: PackedScene = null  ## GLBリソース参照保持
var _casing_mesh: Mesh = null
var _casing_base_scale: Vector3 = Vector3.ONE  ## GLB内のMeshInstance3Dスケール

# ============================================
# Object Pool
# ============================================

var _pool: Array[MeshInstance3D] = []
var _pool_tweens: Array = []  ## 並列配列: 各casingのTween（nullまたはTween）
var _pool_cursor: int = 0

# ============================================
# Setup
# ============================================

func _init() -> void:
	_load_casing_mesh()


func _load_casing_mesh() -> void:
	_casing_scene = load("res://assets/effects/bullet_casing.glb")
	if not _casing_scene:
		push_warning("ShellEjectionComponent: bullet_casing.glb not found")
		return

	var instance := _casing_scene.instantiate()
	var mesh_inst := _find_mesh_instance(instance)
	if mesh_inst:
		_casing_mesh = mesh_inst.mesh
		_casing_base_scale = mesh_inst.scale
	instance.free()


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var result := _find_mesh_instance(child)
		if result:
			return result
	return null


## セットアップ
func setup(character: Node3D, weapon_socket: Node3D) -> void:
	_character = character
	_weapon_socket = weapon_socket
	if _character and not _character.tree_exited.is_connected(_on_character_tree_exited):
		_character.tree_exited.connect(_on_character_tree_exited)


## 武器ソケットを更新
func set_weapon_socket(socket: Node3D) -> void:
	_weapon_socket = socket


## ウォームアップ（現在は不要だが、他コンポーネントとのインターフェース一貫性のため）
func warm_up() -> void:
	pass


func _on_character_tree_exited() -> void:
	cleanup()


## クリーンアップ: 全プール解放
func cleanup() -> void:
	for i in range(_pool_tweens.size()):
		var tween: Tween = _pool_tweens[i]
		if tween and tween.is_running():
			tween.kill()
	_pool_tweens.clear()
	for mesh_inst in _pool:
		if mesh_inst and is_instance_valid(mesh_inst):
			mesh_inst.queue_free()
	_pool.clear()
	_pool_cursor = 0

# ============================================
# Public API
# ============================================

## 薬莢を排出（射撃時に呼び出し）
func play(_current_weapon: Resource, _weapon_model: Node3D) -> void:
	if not _character or not _weapon_socket or not _casing_mesh:
		return
	if not _character.is_inside_tree():
		return
	_eject_casing()

# ============================================
# Internal
# ============================================

func _eject_casing() -> void:
	var spawn_pos := _weapon_socket.global_position

	# キャラクターの向き方向から右方向を算出
	var facing: Vector3
	if _character.has_method("get_facing_direction"):
		facing = _character.get_facing_direction()
	else:
		facing = -_character.global_transform.basis.z
	facing.y = 0
	facing = facing.normalized()
	var right := facing.cross(Vector3.UP).normalized()

	# 排出口オフセット（銃の右側）
	spawn_pos += right * 0.05

	var casing := _acquire_casing()
	if not casing:
		return

	casing.global_position = spawn_pos
	casing.visible = true
	casing.transparency = 0.0

	# ランダム初期回転
	var rand_rot := Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	casing.rotation = rand_rot

	# 射出速度（ランダム化）
	var velocity := right * EJECT_SPEED_RIGHT * randf_range(0.8, 1.2)
	velocity.y = EJECT_SPEED_UP * randf_range(0.7, 1.3)
	velocity += facing * EJECT_SPEED_FORWARD * randf_range(-1.0, 1.0)

	var spin_axis := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var spin_rate := SPIN_SPEED * randf_range(0.6, 1.4)
	var initial_basis := Basis.from_euler(rand_rot)

	_animate_flight(casing, spawn_pos, velocity, spin_axis, spin_rate, initial_basis)


## プールから利用可能な薬莢を取得、なければ新規作成
func _acquire_casing() -> MeshInstance3D:
	# 非表示（利用可能）な薬莢を探す
	for i in range(_pool.size()):
		var idx := (_pool_cursor + i) % _pool.size()
		var c := _pool[idx]
		if c and is_instance_valid(c) and not c.visible:
			_pool_cursor = (idx + 1) % _pool.size()
			return c

	# プール上限未満なら新規作成
	if _pool.size() < MAX_CASINGS:
		var c := _create_casing_node()
		if c:
			_pool.append(c)
			_pool_tweens.append(null)
			return c
		return null

	# 上限到達 → 最古を強制再利用（Tweenキル）
	var reuse_idx := _pool_cursor
	_pool_cursor = (_pool_cursor + 1) % MAX_CASINGS
	var tween: Tween = _pool_tweens[reuse_idx]
	if tween and tween.is_running():
		tween.kill()
	return _pool[reuse_idx]


func _create_casing_node() -> MeshInstance3D:
	if not _character or not _character.is_inside_tree():
		return null
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = _casing_mesh
	mesh_inst.scale = _casing_base_scale * CASING_SCALE
	mesh_inst.visible = false
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_character.get_tree().root.add_child(mesh_inst)
	return mesh_inst


func _animate_flight(casing: MeshInstance3D, start_pos: Vector3, velocity: Vector3, spin_axis: Vector3, spin_rate: float, initial_basis: Basis) -> void:
	# プールインデックスを特定してTweenを管理
	var pool_idx := _pool.find(casing)
	if pool_idx < 0:
		return

	# 既存Tweenをキル
	if pool_idx < _pool_tweens.size():
		var old_tween: Tween = _pool_tweens[pool_idx]
		if old_tween and old_tween.is_running():
			old_tween.kill()

	# 地面到達時間を計算（放物線: y = h + vy*t - 0.5*g*t²、y=0で解く）
	var vy := velocity.y
	var h := start_pos.y
	var disc := vy * vy + 2.0 * GRAVITY * h
	var flight_time := clampf((vy + sqrt(maxf(disc, 0.0))) / GRAVITY, 0.2, 1.5)

	var casing_scale := _casing_base_scale * CASING_SCALE
	var tween := casing.create_tween()
	_pool_tweens[pool_idx] = tween

	# Phase 1: 放物線飛行
	tween.tween_method(func(t: float) -> void:
		if not is_instance_valid(casing):
			return
		casing.global_position = Vector3(
			start_pos.x + velocity.x * t,
			maxf(start_pos.y + velocity.y * t - 0.5 * GRAVITY * t * t, 0.01),
			start_pos.z + velocity.z * t
		)
		# 回転を設定後、スケールを再適用（basisが回転+スケールを含むため）
		var rot_basis := Basis(spin_axis, deg_to_rad(spin_rate * t)) * initial_basis
		casing.basis = rot_basis.scaled(casing_scale)
	, 0.0, flight_time, flight_time)

	# Phase 2: 地面で静止
	tween.tween_interval(CASING_LIFETIME)

	# Phase 3: フェードアウト
	tween.tween_property(casing, "transparency", 1.0, CASING_FADE_DURATION)

	# Phase 4: 非表示（プール再利用可能に）
	tween.tween_callback(func() -> void:
		if is_instance_valid(casing):
			casing.visible = false
			casing.transparency = 0.0
	)
