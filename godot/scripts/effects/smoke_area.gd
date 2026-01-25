class_name SmokeArea
extends Node3D
## スモークエリア効果
## 時間経過による半径変化と視線ブロック機能を提供
## GPUParticles3Dによる煙エフェクトを含む

signal smoke_started
signal smoke_ended

## スモーク設定
@export var max_radius: float = GameConstants.SMOKE_RADIUS
@export var duration: float = GameConstants.SMOKE_DURATION
@export var expand_time: float = GameConstants.SMOKE_EXPAND_TIME
@export var fade_time: float = GameConstants.SMOKE_FADE_TIME

## 現在の有効半径
var _current_radius: float = 0.0
## 経過時間
var _elapsed_time: float = 0.0
## アクティブフラグ
var _is_active: bool = false

## 参照
var _particles: GPUParticles3D = null
var _smoke_manager: SmokeAreaManager = null


func _ready() -> void:
	_particles = $GPUParticles3D if has_node("GPUParticles3D") else null


## スモークを開始
## @param manager: SmokeAreaManagerへの参照（自動登録用）
func start(manager: SmokeAreaManager = null) -> void:
	_smoke_manager = manager
	_is_active = true
	_elapsed_time = 0.0
	_current_radius = 0.0

	if _smoke_manager:
		_smoke_manager.register_area(self)

	if _particles:
		_particles.emitting = true

	smoke_started.emit()


func _physics_process(delta: float) -> void:
	if not _is_active:
		return

	_elapsed_time += delta
	_update_radius()
	_update_particles()

	# 持続時間終了
	if _elapsed_time >= duration:
		_stop()


## 半径を更新
func _update_radius() -> void:
	var fade_start := duration - fade_time

	if _elapsed_time < expand_time:
		# 展開フェーズ: 0 → max_radius（イーズアウト）
		var t := _elapsed_time / expand_time
		# イーズアウト: 急速に立ち上がり、終盤で減速
		t = 1.0 - pow(1.0 - t, 2.0)
		_current_radius = max_radius * t
	elif _elapsed_time < fade_start:
		# 維持フェーズ
		_current_radius = max_radius
	else:
		# 消滅フェーズ: max_radius → 0（線形）
		var t := (_elapsed_time - fade_start) / fade_time
		_current_radius = max_radius * (1.0 - t)


## パーティクルの更新（半径に応じてスケール調整）
func _update_particles() -> void:
	if not _particles:
		return

	# パーティクルエミッターのスケールを半径に合わせる
	var scale_factor := _current_radius / max_radius if max_radius > 0 else 0.0
	_particles.scale = Vector3.ONE * scale_factor

	# 消滅フェーズではエミッションを停止（既存パーティクルはフェードアウト）
	var fade_start := duration - fade_time
	if _elapsed_time >= fade_start and _particles.emitting:
		_particles.emitting = false


## スモークを停止
func _stop() -> void:
	_is_active = false
	_current_radius = 0.0

	if _smoke_manager:
		_smoke_manager.unregister_area(self)

	smoke_ended.emit()

	# パーティクルが完全に消えるまで待ってから削除
	if _particles and _particles.lifetime > 0:
		await get_tree().create_timer(_particles.lifetime).timeout

	queue_free()


## 視線がこのスモークエリアと交差するか判定
## XZ平面上での線分と円の交差判定
## @param from: 線分の始点
## @param to: 線分の終点
## @return: 交差している場合true
func intersects_line_segment(from: Vector3, to: Vector3) -> bool:
	if _current_radius <= 0:
		return false

	# XZ平面に投影
	var center := Vector2(global_position.x, global_position.z)
	var p1 := Vector2(from.x, from.z)
	var p2 := Vector2(to.x, to.z)

	# 線分と円の交差判定
	# D = P2 - P1, F = P1 - C
	# a = D・D, b = 2F・D, c = F・F - R²
	# 判別式 = b² - 4ac

	var d := p2 - p1
	var f := p1 - center

	var a := d.dot(d)
	var b := 2.0 * f.dot(d)
	var c := f.dot(f) - _current_radius * _current_radius

	# 線分の長さが0の場合
	if a < 0.0001:
		return c <= 0

	var discriminant := b * b - 4.0 * a * c

	if discriminant < 0:
		return false

	# 交点のパラメータtを計算
	var sqrt_disc := sqrt(discriminant)
	var t1 := (-b - sqrt_disc) / (2.0 * a)
	var t2 := (-b + sqrt_disc) / (2.0 * a)

	# t ∈ [0, 1] に交点があるかチェック
	if (t1 >= 0 and t1 <= 1) or (t2 >= 0 and t2 <= 1):
		return true

	# 線分が完全に円の内部にある場合
	if t1 < 0 and t2 > 1:
		return true

	return false


## 指定位置がこのスモークエリア内にあるか判定
## @param pos: 判定位置
## @return: エリア内にある場合true
func is_position_inside(pos: Vector3) -> bool:
	if _current_radius <= 0:
		return false

	# XZ平面上での距離判定
	var dx := pos.x - global_position.x
	var dz := pos.z - global_position.z
	var dist_sq := dx * dx + dz * dz

	return dist_sq <= _current_radius * _current_radius


## 現在の有効半径を取得
func get_current_radius() -> float:
	return _current_radius


## アクティブ状態を取得
func is_active() -> bool:
	return _is_active


## 経過時間を取得
func get_elapsed_time() -> float:
	return _elapsed_time


## 残り時間を取得
func get_remaining_time() -> float:
	return max(0.0, duration - _elapsed_time)
