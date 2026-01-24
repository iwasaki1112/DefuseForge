class_name Grenade
extends RigidBody3D
## 投擲グレネード
## 放物線軌道で飛び、壁・床に跳ね返り、一定時間後に爆発

signal exploded(position: Vector3)

## 爆発設定
@export var fuse_time: float = 3.0  ## 導火線時間（秒）
@export var explosion_radius: float = 5.0  ## 爆発範囲
@export var explosion_damage: float = 100.0  ## 最大ダメージ

## 投擲設定
@export var default_arc_height: float = 2.0  ## デフォルトの放物線高さ

## 物理設定（PhysicsMaterialはシーンで設定）
@export var throw_gravity: float = 9.8  ## 投擲時の重力計算用

## 内部状態
var _has_exploded: bool = false
var _thrower: Node3D = null  ## 投げたキャラクター（自傷判定用）

## タイマー
var _fuse_timer: Timer = null


func _ready() -> void:
	_setup_fuse_timer()


## 導火線タイマーをセットアップ
func _setup_fuse_timer() -> void:
	_fuse_timer = Timer.new()
	_fuse_timer.name = "FuseTimer"
	_fuse_timer.wait_time = fuse_time
	_fuse_timer.one_shot = true
	_fuse_timer.timeout.connect(_on_fuse_timeout)
	add_child(_fuse_timer)


## グレネードを投擲
## start_pos: 投擲開始位置
## target_pos: 目標位置
## thrower: 投げたキャラクター（オプション）
## arc_height: 放物線の高さ（オプション）
func throw(start_pos: Vector3, target_pos: Vector3, thrower: Node3D = null, arc_height: float = -1.0) -> void:
	_thrower = thrower
	global_position = start_pos

	# 放物線高さを決定
	var height = arc_height if arc_height > 0 else default_arc_height

	# 初速度を計算して適用
	var velocity = _calculate_throw_velocity(start_pos, target_pos, height)
	linear_velocity = velocity

	# 導火線タイマー開始
	_fuse_timer.start()


## 放物線軌道の初速度を計算
## 近距離は直線的に転がす、遠距離のみ放物線
func _calculate_throw_velocity(start: Vector3, target: Vector3, _arc_height: float) -> Vector3:
	var displacement = target - start
	var horizontal = Vector3(displacement.x, 0, displacement.z)
	var horizontal_distance = horizontal.length()
	var delta_y = displacement.y  # 高さの差（負 = 下向き）

	# 投擲速度（距離に応じて調整、ゆっくり転がす）
	var throw_speed = clamp(horizontal_distance * 0.5, 2.0, 5.0)

	# ターゲットへの3D方向（将来の使用のため保持）
	var _direction = displacement.normalized()

	# 近〜中距離（8m以下）: ほぼ直線的に投げる
	if horizontal_distance < 8.0:
		# 落下を補正するため、わずかに上向きに調整
		# 飛行時間 ≈ 距離 / 速度
		var flight_time = horizontal_distance / throw_speed
		# 落下量 = 0.5 * g * t^2
		var drop = 0.5 * throw_gravity * flight_time * flight_time
		# 落下を補正する上向き成分
		var up_compensation = (drop - delta_y) / flight_time

		# 最小限の上向き成分（転がし感を出す）
		up_compensation = max(up_compensation, 0.5)
		# 上向き成分を制限（山なりにならないよう）
		up_compensation = min(up_compensation, 3.0)

		return horizontal.normalized() * throw_speed + Vector3.UP * up_compensation
	else:
		# 遠距離（8m以上）: 放物線
		# 低めの弧（最大1.5m）
		var peak_height = min(1.5, horizontal_distance * 0.15)
		peak_height = max(peak_height, -delta_y + 0.2)

		var vy = sqrt(2.0 * throw_gravity * peak_height)
		var time_up = vy / throw_gravity
		var fall_height = peak_height - delta_y
		if fall_height < 0.1:
			fall_height = 0.1
		var time_down = sqrt(2.0 * fall_height / throw_gravity)
		var total_time = time_up + time_down
		var horizontal_speed = horizontal_distance / total_time

		return horizontal.normalized() * horizontal_speed + Vector3.UP * vy


## 導火線タイムアウト時
func _on_fuse_timeout() -> void:
	_explode()


## 爆発処理
func _explode() -> void:
	if _has_exploded:
		return
	_has_exploded = true

	# 範囲内のキャラクターにダメージを与える
	var space_state = get_world_3d().direct_space_state
	if space_state:
		var shape = SphereShape3D.new()
		shape.radius = explosion_radius

		var query = PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis(), global_position)
		query.collision_mask = 1  # キャラクターレイヤー

		var results = space_state.intersect_shape(query)
		for result in results:
			var collider = result.collider
			# GameCharacterを探す（コライダーの親を辿る）
			var character = _find_game_character(collider)
			if character and character.is_alive:
				# 距離に応じたダメージ計算
				var dist = global_position.distance_to(character.global_position)
				var damage_ratio = 1.0 - (dist / explosion_radius)
				var damage = explosion_damage * max(0.0, damage_ratio)
				if damage > 0:
					character.take_damage(damage)

	# シグナル発火
	exploded.emit(global_position)

	# オブジェクト削除
	queue_free()


## コライダーからGameCharacterを探す
func _find_game_character(node: Node) -> GameCharacter:
	var current = node
	while current:
		if current is GameCharacter:
			return current
		current = current.get_parent()
	return null


## 手動で爆発させる（デバッグ用）
func force_explode() -> void:
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
	var velocity = _calculate_bounce_throw_velocity(start_pos, bounce_pos, target_pos, bounce_normal)
	linear_velocity = velocity

	# 導火線タイマー開始
	_fuse_timer.start()


## バウンス投擲用の初速度を計算
## 最低限の弧でバウンスポイントに到達する軌道（壁を乗り越えない）
func _calculate_bounce_throw_velocity(start: Vector3, bounce: Vector3, target: Vector3, bounce_normal: Vector3) -> Vector3:
	# 水平面での計算
	var start_h = Vector3(start.x, 0, start.z)
	var bounce_h = Vector3(bounce.x, 0, bounce.z)
	var target_h = Vector3(target.x, 0, target.z)

	# 法線が水平面でゼロになる場合（床へのバウンス）
	var normal_h = Vector3(bounce_normal.x, 0, bounce_normal.z)
	if normal_h.length_squared() < 0.01:
		return _calculate_throw_velocity(start, bounce, default_arc_height)
	normal_h = normal_h.normalized()

	# 水平距離
	var dist1 = start_h.distance_to(bounce_h)
	var dist2 = bounce_h.distance_to(target_h)

	if dist1 < 0.3:
		return _calculate_throw_velocity(start, target, default_arc_height)

	# 水平方向の決定（反射を考慮）
	var outgoing_dir_h = (target_h - bounce_h).normalized()
	if outgoing_dir_h.length_squared() < 0.01:
		outgoing_dir_h = -normal_h
	var required_incoming_h = outgoing_dir_h.reflect(normal_h)
	var actual_dir_h = (bounce_h - start_h).normalized()
	var dot_product = required_incoming_h.dot(actual_dir_h)
	var final_dir_h: Vector3
	if dot_product > 0.3:
		final_dir_h = (actual_dir_h * 0.6 + required_incoming_h * 0.4).normalized()
	else:
		final_dir_h = actual_dir_h

	# === 最低弧軌道の計算 ===
	# バウンスポイントで下降速度 = -descent_speed になるように計算
	# これにより頂点がバウンスポイント直前になり、最も低い弧で到達
	var delta_y = bounce.y - start.y
	var g = throw_gravity

	# 到達時の下降速度（小さいほど低い弧、大きいほど急角度で当たる）
	var descent_speed = 2.0  # 2 m/s で下降中に到達

	# vy_at_bounce = vy - g*T = -descent_speed
	# vy = g*T - descent_speed
	#
	# delta_y = vy*T - 0.5*g*T²
	# delta_y = (g*T - descent_speed)*T - 0.5*g*T²
	# delta_y = g*T² - descent_speed*T - 0.5*g*T²
	# delta_y = 0.5*g*T² - descent_speed*T
	# 0.5*g*T² - descent_speed*T - delta_y = 0
	#
	# 二次方程式: aT² + bT + c = 0
	# a = 0.5*g, b = -descent_speed, c = -delta_y
	# T = (descent_speed + sqrt(descent_speed² + 2*g*delta_y)) / g

	var discriminant = descent_speed * descent_speed + 2.0 * g * delta_y

	var flight_time: float
	var vy: float

	if discriminant >= 0:
		# 解が存在 → 最低弧軌道が可能
		flight_time = (descent_speed + sqrt(discriminant)) / g
		vy = g * flight_time - descent_speed
	else:
		# 解が存在しない（バウンスポイントが低すぎる）
		# フォールバック: 固定の飛行時間を使用
		flight_time = max(0.5, dist1 / 10.0)
		vy = (delta_y + 0.5 * g * flight_time * flight_time) / flight_time

	# 最低飛行時間を確保（近距離でも安定させる）
	if flight_time < 0.3:
		flight_time = 0.3
		vy = (delta_y + 0.5 * g * flight_time * flight_time) / flight_time

	# === 最大高さ制限 ===
	# 軌道の頂点が壁を超えないよう制限
	# 頂点高さ = start.y + vy²/(2g)
	# 最大頂点 = 地面から2.0m（壁の高さを想定）
	var max_peak_from_ground = 2.0
	var max_peak_above_start = max_peak_from_ground - start.y
	if max_peak_above_start < 0.1:
		max_peak_above_start = 0.1

	var current_peak_above_start = (vy * vy) / (2.0 * g)

	if current_peak_above_start > max_peak_above_start and vy > 0:
		# 頂点が高すぎる → vyを制限して再計算
		var max_vy = sqrt(2.0 * g * max_peak_above_start)
		vy = max_vy
		# 飛行時間を再計算（バウンスポイントに到達する時間）
		# delta_y = vy*T - 0.5*g*T²
		# 0.5*g*T² - vy*T + delta_y = 0
		var disc2 = vy * vy - 2.0 * g * delta_y
		if disc2 >= 0:
			flight_time = (vy + sqrt(disc2)) / g
		# flight_timeが短くなりすぎないよう確保
		flight_time = max(flight_time, 0.3)

	# 水平速度
	var horizontal_speed = dist1 / flight_time

	# バウンス後の減衰を補償（第2区間の距離に応じて）
	var bounce_compensation = 1.0 + (dist2 / max(dist1 + dist2, 1.0)) * 1.0
	horizontal_speed *= bounce_compensation

	# 最終速度ベクトル
	var velocity = final_dir_h * horizontal_speed + Vector3.UP * vy

	return velocity
