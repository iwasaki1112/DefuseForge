class_name SmokeArea
extends Node3D
## スモークエリア効果
## 時間経過による半径変化と視線ブロック機能を提供
## GPUパーティクル + 壁クリップシェーダーで壁を越えない煙演出

signal smoke_started
signal smoke_ended
signal radius_changed

## スモーク設定
@export var max_radius: float = GameConstants.SMOKE_RADIUS
@export var duration: float = GameConstants.SMOKE_DURATION
@export var expand_time: float = GameConstants.SMOKE_EXPAND_TIME
@export var fade_time: float = GameConstants.SMOKE_FADE_TIME

## 壁コリジョンマスク（レイヤー2）
const WALL_COLLISION_MASK: int = 2
## 壁距離マップの方向分割数
const NUM_DIRECTIONS: int = 64

## 現在の有効半径
var _current_radius: float = 0.0
## 経過時間
var _elapsed_time: float = 0.0
## アクティブフラグ
var _is_active: bool = false

## 参照
var _particles: GPUParticles3D = null
var _smoke_manager: SmokeAreaManager = null
## 壁距離マップテクスチャ（1D: R=正規化壁距離）
var _radius_map_texture: ImageTexture = null
## パーティクルクリップ用シェーダーマテリアル
var _particle_clip_mat: ShaderMaterial = null
## FogOfWarSystem参照（FoW可視性チェック用）
var _fow_system = null


func _ready() -> void:
	_particles = $GPUParticles3D if has_node("GPUParticles3D") else null


## FogOfWarSystemを設定（FoW可視性チェック用）
func set_fow_system(fow) -> void:
	_fow_system = fow


## スモークを開始
## @param manager: SmokeAreaManagerへの参照（自動登録用）
func start(manager: SmokeAreaManager = null) -> void:
	_smoke_manager = manager
	_is_active = true
	_elapsed_time = 0.0
	_current_radius = 0.0

	if _smoke_manager:
		_smoke_manager.register_area(self)

	# 壁クリップシェーダーを構築・適用（位置確定後に実行）
	_setup_particle_wall_clip()

	# FoW可視性をシェーダーに適用（パーティクル単位でFoWクリッピング）
	_apply_fow_to_shader()

	# パーティクル開始
	if _particles:
		_particles.visible = true
		_particles.emitting = true

	smoke_started.emit()


func _physics_process(delta: float) -> void:
	if not _is_active:
		return

	_elapsed_time += delta
	var prev_radius := _current_radius
	_update_radius()
	if not is_equal_approx(prev_radius, _current_radius):
		radius_changed.emit()
	_update_visuals()

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
		# フェード半ばでスモーク管理から解除（演出が消える前にキャラクターを表示）
		if _smoke_manager and t >= 0.5:
			_smoke_manager.unregister_area(self)
			_smoke_manager = null


## ビジュアルの更新（クリップシェーダーのパラメータ更新）
func _update_visuals() -> void:
	if _particle_clip_mat:
		_particle_clip_mat.set_shader_parameter("current_radius", _current_radius)
		var scale_factor := _current_radius / max_radius if max_radius > 0 else 0.0
		_particle_clip_mat.set_shader_parameter("smoke_alpha_multiplier", scale_factor)


## FoW可視性テクスチャをパーティクルシェーダーに適用（1回のみ呼出し）
## ViewportTextureはライブ参照のため毎フレーム更新不要
func _apply_fow_to_shader() -> void:
	if not _fow_system or not _particle_clip_mat:
		return

	var vis_tex = _fow_system.get_visibility_texture()
	if not vis_tex:
		return

	var half_map: Vector2 = _fow_system.map_size / 2.0
	_particle_clip_mat.set_shader_parameter("fow_visibility_texture", vis_tex)
	_particle_clip_mat.set_shader_parameter("fow_map_min", Vector2(-half_map.x, -half_map.y))
	_particle_clip_mat.set_shader_parameter("fow_map_max", Vector2(half_map.x, half_map.y))
	_particle_clip_mat.set_shader_parameter("fow_enabled", 1.0)


## スモークを停止
func _stop() -> void:
	_is_active = false
	_current_radius = 0.0

	if _smoke_manager:
		_smoke_manager.unregister_area(self)

	smoke_ended.emit()

	if _particles:
		_particles.emitting = false
		_particles.visible = false

	queue_free()


## 壁距離マップを構築（全方向レイキャスト → 1Dテクスチャ）
## ピクセルi = 角度 i*TAU/NUM_DIRECTIONS の方向の壁距離（正規化）
func _build_radius_map() -> void:
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return

	var center := global_position
	var from := Vector3(center.x, 1.0, center.z)

	var image := Image.create(NUM_DIRECTIONS, 1, false, Image.FORMAT_RF)

	for i in range(NUM_DIRECTIONS):
		var angle := float(i) * TAU / float(NUM_DIRECTIONS)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var to := from + dir * (max_radius + 0.5)

		var query := PhysicsRayQueryParameters3D.create(from, to, WALL_COLLISION_MASK)
		var result := space_state.intersect_ray(query)

		var dist := max_radius
		if not result.is_empty():
			var hit_pos: Vector3 = result.position
			var hit_dist := Vector2(hit_pos.x - center.x, hit_pos.z - center.z).length()
			dist = maxf(0.1, hit_dist - 0.15)

		# 正規化して格納（0.0〜1.0）
		image.set_pixel(i, 0, Color(dist / max_radius, 0.0, 0.0, 1.0))

	_radius_map_texture = ImageTexture.create_from_image(image)


## パーティクルに壁クリップシェーダーを適用
func _setup_particle_wall_clip() -> void:
	if not _particles:
		return

	var clip_shader: Shader = load("res://shaders/smoke_particle_clip.gdshader") as Shader
	if not clip_shader:
		push_warning("[SmokeArea] smoke_particle_clip.gdshader not found")
		return

	# 壁距離マップを構築
	_build_radius_map()
	if not _radius_map_texture:
		return

	# シェーダーマテリアルを作成
	_particle_clip_mat = ShaderMaterial.new()
	_particle_clip_mat.shader = clip_shader
	_particle_clip_mat.set_shader_parameter("radius_map", _radius_map_texture)
	_particle_clip_mat.set_shader_parameter("smoke_center", global_position)
	_particle_clip_mat.set_shader_parameter("max_radius", max_radius)
	_particle_clip_mat.set_shader_parameter("current_radius", 0.0)
	_particle_clip_mat.set_shader_parameter("smoke_alpha_multiplier", 0.0)

	# パーティクルのQuadMeshにクリップシェーダーを適用
	# 元のシーンデータを変更しないようメッシュを複製
	var quad := _particles.draw_pass_1 as QuadMesh
	if quad:
		var new_quad := quad.duplicate() as QuadMesh
		new_quad.material = _particle_clip_mat
		_particles.draw_pass_1 = new_quad


## 視線がこのスモークエリアと交差するか判定
## XZ平面上での線分と円の交差判定 + 壁越し判定
## @param from: 線分の始点
## @param to: 線分の終点
## @return: 交差している場合true（壁越しの場合はfalse）
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
		if c > 0:
			return false
		# 始点がスモーク内：壁チェック
		return not _is_wall_between(from, global_position)

	var discriminant := b * b - 4.0 * a * c

	if discriminant < 0:
		return false

	# 交点のパラメータtを計算
	var sqrt_disc := sqrt(discriminant)
	var t1 := (-b - sqrt_disc) / (2.0 * a)
	var t2 := (-b + sqrt_disc) / (2.0 * a)

	var intersects := false

	# t ∈ [0, 1] に交点があるかチェック
	if (t1 >= 0 and t1 <= 1) or (t2 >= 0 and t2 <= 1):
		intersects = true

	# 線分が完全に円の内部にある場合
	if not intersects and t1 < 0 and t2 > 1:
		intersects = true

	if not intersects:
		return false

	# 壁チェック: 視点からスモーク中心への経路に壁があればスモークは影響しない
	return not _is_wall_between(from, global_position)


## 指定位置がこのスモークエリア内にあるか判定
## 壁越しの場合はスモーク外と判定
## @param pos: 判定位置
## @return: エリア内にある場合true（壁越しの場合はfalse）
func is_position_inside(pos: Vector3) -> bool:
	if _current_radius <= 0:
		return false

	# XZ平面上での距離判定
	var dx := pos.x - global_position.x
	var dz := pos.z - global_position.z
	var dist_sq := dx * dx + dz * dz

	if dist_sq > _current_radius * _current_radius:
		return false

	# 壁チェック: 位置からスモーク中心への経路に壁があればスモーク外と判定
	return not _is_wall_between(pos, global_position)


## 2点間に壁があるかレイキャストで判定
## @param from_pos: 始点
## @param to_pos: 終点
## @return: 壁がある場合true
func _is_wall_between(from_pos: Vector3, to_pos: Vector3) -> bool:
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return false
	# 壁の中間高さでレイキャスト（地面すれすれだと検出漏れの可能性）
	var check_height := 1.0
	var from_adj := Vector3(from_pos.x, check_height, from_pos.z)
	var to_adj := Vector3(to_pos.x, check_height, to_pos.z)
	var query := PhysicsRayQueryParameters3D.create(from_adj, to_adj, WALL_COLLISION_MASK)
	var result := space_state.intersect_ray(query)
	return not result.is_empty()


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
