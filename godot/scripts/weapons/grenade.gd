class_name Grenade
extends Node3D
## 投擲グレネード（キネマティック方式）
## 放物線軌道で飛び、壁・床に跳ね返り、一定時間後に爆発
## 物理エンジンを使わず、運動方程式で決定論的に軌道を計算

signal exploded(position: Vector3)

## 爆発設定
@export var fuse_time: float = 3.0  ## 導火線時間（秒）
@export var explosion_radius: float = 5.0  ## 爆発範囲
@export var explosion_damage: float = 100.0  ## 最大ダメージ

## 投擲設定
@export var default_arc_height: float = 2.0  ## デフォルトの放物線高さ

## 物理設定
@export var throw_gravity: float = 9.8  ## 重力
@export var bounce_factor: float = 0.4  ## 跳ね返り係数（複数回の小バウンド用）
@export var friction: float = 0.8  ## 摩擦係数（着地後の減速用）
@export var min_bounce_velocity: float = 0.3  ## バウンス判定の最小速度（小さいほど細かいバウンドが出る）
@export var collision_radius: float = 0.08  ## 衝突判定の半径

## 内部状態
var _has_exploded: bool = false
var _thrower: Node3D = null  ## 投げたキャラクター（自傷判定用）
var initial_velocity: Vector3 = Vector3.ZERO  ## 初速度（ネットワーク同期用）
var network_grenade_id: int = 0  ## ネットワーク同期用ID
var is_remote: bool = false  ## リモートから生成されたグレネードか
var _fow_system = null  ## FogOfWarSystem参照（リモートグレネードのFoW可視性用）

## キネマティック状態
var _velocity: Vector3 = Vector3.ZERO
var _is_active: bool = false  ## 飛行中かどうか
var _is_grounded: bool = false  ## 地面に着地しているか
var _ground_normal: Vector3 = Vector3.UP  ## 地面の法線

## 回転演出
var _spin_axis: Vector3 = Vector3.ZERO  ## 回転軸（投擲方向に直交）
var _spin_speed: float = 0.0  ## 現在の回転速度（rad/s）
const SPIN_SPEED_BASE: float = 12.0  ## 基本回転速度（rad/s）
var _model_node: Node3D = null  ## Modelノード参照キャッシュ

## タイマー
var _fuse_timer: Timer = null


func _ready() -> void:
	_setup_fuse_timer()
	# 武器モデルの視認性向上スケールを適用
	_model_node = get_node_or_null("Model") as Node3D
	if _model_node:
		_model_node.scale = Vector3.ONE * GameConstants.WEAPON_VISIBILITY_SCALE


## FogOfWarSystemを設定（リモートグレネードのFoW可視性チェック用）
func set_fow_system(fow) -> void:
	_fow_system = fow


func _physics_process(delta: float) -> void:
	if not _is_active or _has_exploded:
		return

	_update_kinematic(delta)
	_update_spin(delta)
	_update_fow_visibility()


## モデルの回転演出を更新
func _update_spin(delta: float) -> void:
	if not _model_node or _spin_speed < 0.1:
		return
	_model_node.rotate(_spin_axis, _spin_speed * delta)
	# 着地後は摩擦で回転を減衰
	if _is_grounded:
		_spin_speed = move_toward(_spin_speed, 0.0, SPIN_SPEED_BASE * 2.0 * delta)


## ランダムな回転軸と速度を初期化
func _init_spin() -> void:
	# ランダムな方向の回転軸を生成（単位球面上の一様分布）
	_spin_axis = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	).normalized()
	# 軸がゼロベクトルになった場合のフォールバック
	if _spin_axis.length_squared() < 0.01:
		_spin_axis = Vector3.RIGHT
	_spin_speed = SPIN_SPEED_BASE * randf_range(0.8, 1.2)


## 導火線タイマーをセットアップ
func _setup_fuse_timer() -> void:
	_fuse_timer = Timer.new()
	_fuse_timer.name = "FuseTimer"
	_fuse_timer.wait_time = fuse_time
	_fuse_timer.one_shot = true
	_fuse_timer.timeout.connect(_on_fuse_timeout)
	add_child(_fuse_timer)


## キネマティック更新（毎フレーム）
func _update_kinematic(delta: float) -> void:
	if _is_grounded:
		# 地面上での転がり/滑り
		_update_grounded_movement(delta)
	else:
		# 空中での放物線運動
		_update_airborne_movement(delta)


## 空中での放物線運動
func _update_airborne_movement(delta: float) -> void:
	# 重力を適用
	_velocity.y -= throw_gravity * delta

	# 次の位置を計算
	var next_pos := global_position + _velocity * delta

	# 衝突判定
	var collision := _check_collision(global_position, next_pos)
	if collision.hit:
		_handle_collision(collision)
	else:
		global_position = next_pos


## 地面上での転がり/滑り
func _update_grounded_movement(delta: float) -> void:
	# 摩擦による減速
	var friction_decel := friction * throw_gravity * delta
	var speed := _velocity.length()

	if speed < friction_decel or speed < 0.1:
		# 停止
		_velocity = Vector3.ZERO
		return

	_velocity = _velocity.normalized() * (speed - friction_decel)

	# 次の位置を計算
	var next_pos := global_position + _velocity * delta

	# 地面との接地を維持（レイキャストで地面を追従）
	var ground_check := _raycast(next_pos + Vector3.UP * 0.1, Vector3.DOWN, 0.3)
	if ground_check.hit:
		next_pos.y = ground_check.position.y + collision_radius
		_ground_normal = ground_check.normal
	else:
		# 地面から離れた
		_is_grounded = false

	# 壁との衝突判定
	var wall_collision := _check_collision(global_position, next_pos)
	if wall_collision.hit and wall_collision.normal.y < 0.5:
		# 壁にバウンス
		_handle_collision(wall_collision)
	else:
		global_position = next_pos


## 衝突判定（球体スイープ）
func _check_collision(from: Vector3, to: Vector3) -> Dictionary:
	var direction := to - from
	var distance := direction.length()

	if distance < 0.001:
		return {"hit": false}

	var result := _raycast(from, direction.normalized(), distance + collision_radius)
	return result


## レイキャスト
func _raycast(from: Vector3, direction: Vector3, distance: float) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return {"hit": false}

	var query := PhysicsRayQueryParameters3D.create(
		from,
		from + direction * distance
	)
	query.collision_mask = 3  # 地形とオブジェクト
	query.exclude = []  # グレネード自身は除外不要（Node3Dなので）

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return {"hit": false}

	return {
		"hit": true,
		"position": result.position,
		"normal": result.normal,
		"collider": result.collider
	}


## 衝突処理（バウンス）
func _handle_collision(collision: Dictionary) -> void:
	var normal: Vector3 = collision.normal
	var hit_pos: Vector3 = collision.position

	# 位置を衝突点に移動（めり込み防止）
	global_position = hit_pos + normal * collision_radius

	# 地面判定（法線が上向き）
	if normal.y > 0.7:
		# 地面に着地
		var vertical_speed: float = absf(_velocity.y)

		if vertical_speed < min_bounce_velocity:
			# 十分遅いのでバウンスせず着地
			_is_grounded = true
			_ground_normal = normal
			_velocity.y = 0
			# 水平速度も減衰（着地の衝撃）
			_velocity.x *= 0.5
			_velocity.z *= 0.5
		else:
			# バウンス（垂直方向を反射＋減衰）
			_velocity = _velocity.bounce(normal) * bounce_factor
			# 水平速度も毎バウンスで減衰
			_velocity.x *= 0.7
			_velocity.z *= 0.7
	else:
		# 壁にバウンス
		_velocity = _velocity.bounce(normal) * bounce_factor


## グレネードを投擲
## start_pos: 投擲開始位置
## target_pos: 目標位置
## thrower: 投げたキャラクター（オプション）
## arc_height: 放物線の高さ（オプション）
func throw(start_pos: Vector3, target_pos: Vector3, thrower: Node3D = null, arc_height: float = -1.0) -> void:
	_thrower = thrower
	global_position = start_pos

	# 放物線高さを決定
	var height: float = arc_height if arc_height > 0 else default_arc_height

	# 初速度を計算して適用
	var velocity: Vector3 = _calculate_throw_velocity(start_pos, target_pos, height)
	initial_velocity = velocity  # 保存（ネットワーク同期用）
	_velocity = velocity
	_is_active = true
	_is_grounded = false
	_init_spin()

	# 導火線タイマー開始
	_fuse_timer.start()


## 計算済みの速度で直接投擲（ネットワーク同期用）
## start_pos: 投擲開始位置
## velocity: 初速度ベクトル
func throw_with_velocity(start_pos: Vector3, velocity: Vector3) -> void:
	global_position = start_pos
	global_rotation = Vector3.ZERO  # 回転をリセット
	initial_velocity = velocity
	_velocity = velocity
	_is_active = true
	_is_grounded = false
	_init_spin()
	_fuse_timer.start()


## 放物線軌道の初速度を計算
## ターゲット位置に正確に到達する軌道を計算
func _calculate_throw_velocity(start: Vector3, target: Vector3, arc_height: float) -> Vector3:
	var displacement: Vector3 = target - start
	var horizontal: Vector3 = Vector3(displacement.x, 0, displacement.z)
	var horizontal_distance: float = horizontal.length()
	var delta_y: float = displacement.y  # 高さの差（負 = 下向き）
	var g: float = throw_gravity

	# 非常に近い場合はシンプルに
	if horizontal_distance < 0.5:
		return Vector3(displacement.x, 1.0, displacement.z).normalized() * 3.0

	# 水平方向の単位ベクトル
	var horizontal_dir: Vector3 = horizontal.normalized()

	# === 放物線軌道の計算 ===
	# 運動方程式:
	# x(t) = vx * t → vx = horizontal_distance / T
	# y(t) = vy * t - 0.5 * g * t² → vy = (delta_y + 0.5 * g * T²) / T
	#
	# 弧の高さから飛行時間を決定:
	# 頂点高さ h = vy² / (2g)
	# vy = sqrt(2 * g * h)
	#
	# 飛行時間 T は delta_y = vy*T - 0.5*g*T² を解く

	# 弧の高さを決定（距離に応じて調整）
	var peak_height: float
	if arc_height > 0:
		peak_height = arc_height
	else:
		# デフォルト: 距離に応じた低い弧
		peak_height = clampf(horizontal_distance * 0.1, 0.3, 2.0)
		# 下向きに投げる場合は弧を高くする必要がある
		if delta_y < 0:
			peak_height = maxf(peak_height, absf(delta_y) * 0.3 + 0.3)

	# 垂直初速度: vy = sqrt(2 * g * h)
	var vy: float = sqrt(2.0 * g * peak_height)

	# 飛行時間を計算
	# delta_y = vy * T - 0.5 * g * T²
	# 0.5 * g * T² - vy * T + delta_y = 0
	# T = (vy + sqrt(vy² - 2 * g * delta_y)) / g
	var discriminant: float = vy * vy - 2.0 * g * delta_y

	var flight_time: float
	if discriminant >= 0:
		# 正の解を取る（着地時間）
		flight_time = (vy + sqrt(discriminant)) / g
	else:
		# 判別式が負 = 弧が低すぎる
		# 弧を高くして再計算
		peak_height = absf(delta_y) + 1.0
		vy = sqrt(2.0 * g * peak_height)
		discriminant = vy * vy - 2.0 * g * delta_y
		flight_time = (vy + sqrt(discriminant)) / g

	# 飛行時間の最小値を確保
	flight_time = maxf(flight_time, 0.2)

	# 水平速度: vx = horizontal_distance / T
	var horizontal_speed: float = horizontal_distance / flight_time

	# 速度制限（あまりに速すぎる/遅すぎる場合は調整）
	if horizontal_speed > 15.0:
		# 速度を制限して飛行時間を再計算
		horizontal_speed = 15.0
		flight_time = horizontal_distance / horizontal_speed
		# vyを再計算して正確にターゲットに到達
		vy = (delta_y + 0.5 * g * flight_time * flight_time) / flight_time
	elif horizontal_speed < 1.0 and horizontal_distance > 0.5:
		horizontal_speed = 1.0
		flight_time = horizontal_distance / horizontal_speed
		vy = (delta_y + 0.5 * g * flight_time * flight_time) / flight_time

	# 最終速度ベクトル
	var velocity: Vector3 = horizontal_dir * horizontal_speed + Vector3.UP * vy

	return velocity


## リモートグレネードのFoW可視性を更新
func _update_fow_visibility() -> void:
	if not is_remote or not _fow_system:
		return
	visible = _fow_system.is_position_visible_in_fow(global_position)


## 導火線タイムアウト時
func _on_fuse_timeout() -> void:
	# リモートグレネードはネットワークからの爆発イベントを待つ
	if is_remote:
		return
	_explode()


## 爆発処理
func _explode() -> void:
	if _has_exploded:
		return
	_has_exploded = true
	_is_active = false

	# 範囲内のキャラクターにダメージを与える
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state:
		var shape := SphereShape3D.new()
		shape.radius = explosion_radius

		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis(), global_position)
		query.collision_mask = 1  # キャラクターレイヤー

		var results: Array[Dictionary] = space_state.intersect_shape(query)
		for result: Dictionary in results:
			var collider: Object = result.collider
			# GameCharacterを探す（コライダーの親を辿る）
			var character: GameCharacter = _find_game_character(collider)
			if character and character.is_alive:
				# 距離に応じたダメージ計算
				var dist: float = global_position.distance_to(character.global_position)
				var damage_ratio: float = 1.0 - (dist / explosion_radius)
				var damage: float = explosion_damage * max(0.0, damage_ratio)
				if damage > 0:
					character.take_damage(damage)

	# シグナル発火
	exploded.emit(global_position)


## コライダーからGameCharacterを探す
func _find_game_character(node: Object) -> GameCharacter:
	var current: Node = node as Node
	while current:
		if current is GameCharacter:
			return current
		current = current.get_parent()
	return null


## 手動で爆発させる（デバッグ用）
func force_explode() -> void:
	_explode()


## 指定位置で爆発（ネットワーク同期用）
func explode_at_position(pos: Vector3) -> void:
	global_position = pos
	_explode()
