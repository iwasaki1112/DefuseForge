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
@export var bounce_factor: float = 0.5  ## 跳ね返り係数
@export var friction: float = 0.3  ## 摩擦係数
@export var min_bounce_velocity: float = 0.5  ## バウンス判定の最小速度
@export var collision_radius: float = 0.08  ## 衝突判定の半径

## 内部状態
var _has_exploded: bool = false
var _thrower: Node3D = null  ## 投げたキャラクター（自傷判定用）
var initial_velocity: Vector3 = Vector3.ZERO  ## 初速度（ネットワーク同期用）
var network_grenade_id: int = 0  ## ネットワーク同期用ID
var is_remote: bool = false  ## リモートから生成されたグレネードか

## キネマティック状態
var _velocity: Vector3 = Vector3.ZERO
var _is_active: bool = false  ## 飛行中かどうか
var _is_grounded: bool = false  ## 地面に着地しているか
var _ground_normal: Vector3 = Vector3.UP  ## 地面の法線

## タイマー
var _fuse_timer: Timer = null


func _ready() -> void:
	_setup_fuse_timer()


func _physics_process(delta: float) -> void:
	if not _is_active or _has_exploded:
		return

	_update_kinematic(delta)


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
			# バウンスせず着地
			_is_grounded = true
			_ground_normal = normal
			_velocity.y = 0
			# 水平速度を維持
		else:
			# バウンス
			_velocity = _velocity.bounce(normal) * bounce_factor
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
	_fuse_timer.start()


## 放物線軌道の初速度を計算
## 近距離は直線的に転がす、遠距離のみ放物線
func _calculate_throw_velocity(start: Vector3, target: Vector3, _arc_height: float) -> Vector3:
	var displacement: Vector3 = target - start
	var horizontal := Vector3(displacement.x, 0, displacement.z)
	var horizontal_distance: float = horizontal.length()
	var delta_y: float = displacement.y  # 高さの差（負 = 下向き）

	# 投擲速度（距離に応じて調整、ゆっくり転がす）
	var throw_speed: float = clamp(horizontal_distance * 0.5, 2.0, 5.0)

	# ターゲットへの3D方向（将来の使用のため保持）
	var _direction: Vector3 = displacement.normalized()

	# 近〜中距離（8m以下）: ほぼ直線的に投げる
	if horizontal_distance < 8.0:
		# 落下を補正するため、わずかに上向きに調整
		# 飛行時間 ≈ 距離 / 速度
		var flight_time: float = horizontal_distance / throw_speed
		# 落下量 = 0.5 * g * t^2
		var drop: float = 0.5 * throw_gravity * flight_time * flight_time
		# 落下を補正する上向き成分
		var up_compensation: float = (drop - delta_y) / flight_time

		# 最小限の上向き成分（転がし感を出す）
		up_compensation = max(up_compensation, 0.5)
		# 上向き成分を制限（山なりにならないよう）
		up_compensation = min(up_compensation, 3.0)

		return horizontal.normalized() * throw_speed + Vector3.UP * up_compensation
	else:
		# 遠距離（8m以上）: 放物線
		# 低めの弧（最大1.5m）
		var peak_height: float = min(1.5, horizontal_distance * 0.15)
		peak_height = max(peak_height, -delta_y + 0.2)

		var vy: float = sqrt(2.0 * throw_gravity * peak_height)
		var time_up: float = vy / throw_gravity
		var fall_height: float = peak_height - delta_y
		if fall_height < 0.1:
			fall_height = 0.1
		var time_down: float = sqrt(2.0 * fall_height / throw_gravity)
		var total_time: float = time_up + time_down
		var horizontal_speed: float = horizontal_distance / total_time

		return horizontal.normalized() * horizontal_speed + Vector3.UP * vy


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

	# オブジェクト削除
	queue_free()


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


## バウンス投擲（くの字投げ）
## バウンスポイントを経由してターゲットに向かう軌道で投擲
## start_pos: 投擲開始位置
## bounce_pos: バウンスポイント（壁/エッジ位置）
## bounce_normal: バウンス面の法線
## target_pos: 最終目標位置
## thrower: 投げたキャラクター（オプション）
func throw_with_bounce(start_pos: Vector3, bounce_pos: Vector3, bounce_normal: Vector3, target_pos: Vector3, thrower: Node3D = null) -> void:
	_thrower = thrower
	global_position = start_pos

	# 初速度を計算（反射の法則を使用）
	var velocity: Vector3 = _calculate_bounce_throw_velocity(start_pos, bounce_pos, target_pos, bounce_normal)
	initial_velocity = velocity  # 保存（ネットワーク同期用）
	_velocity = velocity
	_is_active = true
	_is_grounded = false

	# 導火線タイマー開始
	_fuse_timer.start()


## バウンス投擲用の初速度を計算
## バウンスポイントに到達した時点での速度方向が、反射後にターゲットへ向かうように計算
func _calculate_bounce_throw_velocity(start: Vector3, bounce: Vector3, target: Vector3, bounce_normal: Vector3) -> Vector3:
	# バウンスポイントが近すぎる場合は直接投擲
	var dist_to_bounce: float = start.distance_to(bounce)
	if dist_to_bounce < 0.5:
		return _calculate_throw_velocity(start, target, default_arc_height)

	# 法線を正規化
	var normal: Vector3 = bounce_normal.normalized()

	# 法線がほぼ上向き（床バウンス）の場合は直接投擲
	if absf(normal.y) > 0.9:
		return _calculate_throw_velocity(start, bounce, default_arc_height)

	# === Step 1: 必要な出射方向を計算 ===
	# バウンス後にターゲットへ向かう方向
	var outgoing_dir: Vector3 = (target - bounce).normalized()

	# === Step 2: 必要な入射方向を計算 ===
	# bounce() は反射の逆演算なので、outgoing.bounce(normal) = incoming
	var incoming_dir: Vector3 = outgoing_dir.bounce(normal).normalized()

	# === Step 3: 飛行時間を計算 ===
	# バウンスポイントに到達し、到達時の速度方向がincoming_dirになるように
	#
	# 運動方程式:
	# x(t) = x0 + vx*t
	# y(t) = y0 + vy*t - 0.5*g*t²
	# z(t) = z0 + vz*t
	#
	# 到達時の速度:
	# vel_x(t) = vx
	# vel_y(t) = vy - g*t
	# vel_z(t) = vz
	#
	# 条件:
	# 1. bounce = start + (vx*t, vy*t - 0.5*g*t², vz*t)
	# 2. 速度方向 ∝ incoming_dir

	var g: float = throw_gravity
	var d: Vector3 = bounce - start  # 変位

	# 水平方向の制約から飛行時間を計算
	# 水平速度 = d_h / t であり、これが incoming_dir の水平成分と平行である必要
	var d_h: Vector3 = Vector3(d.x, 0, d.z)
	var incoming_h: Vector3 = Vector3(incoming_dir.x, 0, incoming_dir.z)
	var d_h_len: float = d_h.length()
	var incoming_h_len: float = incoming_h.length()

	if d_h_len < 0.1 or incoming_h_len < 0.01:
		# 真上からのバウンス - 直接投擲にフォールバック
		return _calculate_throw_velocity(start, bounce, default_arc_height)

	# 水平方向の整合性チェック
	var d_h_dir: Vector3 = d_h.normalized()
	var incoming_h_dir: Vector3 = incoming_h.normalized()
	var horizontal_alignment: float = d_h_dir.dot(incoming_h_dir)

	# 水平方向が逆向きの場合（物理的に不可能）
	if horizontal_alignment < 0.1:
		# 直接バウンスポイントに投げる（反射は諦める）
		return _calculate_throw_velocity(start, bounce, default_arc_height)

	# === Step 4: 飛行時間 t を解く ===
	# 到達時の速度ベクトル vel(t) = (vx, vy - g*t, vz) が incoming_dir と平行
	#
	# vx = d.x / t
	# vz = d.z / t
	# vy = (d.y + 0.5*g*t²) / t
	#
	# vel(t) = (d.x/t, d.y/t + 0.5*g*t - g*t, d.z/t)
	#        = (d.x/t, d.y/t - 0.5*g*t, d.z/t)
	#
	# vel(t) ∝ incoming_dir より:
	# (d.x/t) / incoming.x = (d.y/t - 0.5*g*t) / incoming.y = (d.z/t) / incoming.z
	#
	# 水平成分から: d.x / incoming.x = d.z / incoming.z （整合性は上で確認済み）
	# 垂直と水平から: (d.x/t) / incoming.x = (d.y/t - 0.5*g*t) / incoming.y
	#
	# k = d.x / incoming.x とすると:
	# k = (d.y - 0.5*g*t²) / incoming.y
	# d.y - 0.5*g*t² = k * incoming.y
	# 0.5*g*t² = d.y - k * incoming.y
	# t² = 2*(d.y - k * incoming.y) / g
	#
	# k = d_h_len / incoming_h_len (水平方向のスケール)

	var k: float = d_h_len / incoming_h_len
	var t_squared: float = 2.0 * (d.y - k * incoming_dir.y) / g

	var t: float
	if t_squared > 0.01:
		t = sqrt(t_squared)
	else:
		# 解が存在しない場合 - 飛行時間を推定してフォールバック
		t = d_h_len / 8.0  # 8 m/s を基準
		t = clampf(t, 0.3, 2.0)

	# 飛行時間の制限
	t = clampf(t, 0.2, 3.0)

	# === Step 5: 初速度を計算 ===
	var vx: float = d.x / t
	var vz: float = d.z / t
	var vy: float = (d.y + 0.5 * g * t * t) / t

	# 速度の大きさ制限
	var velocity: Vector3 = Vector3(vx, vy, vz)
	var speed: float = velocity.length()
	if speed > 20.0:
		velocity = velocity.normalized() * 20.0
	elif speed < 2.0:
		velocity = velocity.normalized() * 2.0

	return velocity
