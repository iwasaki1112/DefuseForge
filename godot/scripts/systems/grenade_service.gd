extends Node
class_name GrenadeService

## グレネード管理サービス
## グレネードの生成・投擲・ネットワーク同期を一元管理
## GameManagerから抽出されたコンポーネント

## グレネード投擲シグナル
signal grenade_thrown(grenade: Node3D, character: Node)
## スモークグレネード投擲シグナル
signal smoke_grenade_thrown(smoke_grenade: Node3D, character: Node)
## ハンドグレネード投擲シグナル
signal hand_grenade_thrown(hand_grenade: Node3D, character: Node)
## ネットワークイベント（グレネード投擲）
signal grenade_network_event(start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int)
## ネットワークイベント（グレネード爆発/スモーク展開）
signal grenade_explode_network_event(grenade_id: int, position: Vector3, is_smoke: bool)

## シーン参照（iOSビルドでのpreload問題を回避）
var GrenadeScene: PackedScene = null
var SmokeGrenadeScene: PackedScene = null
var HandGrenadeScene: PackedScene = null
var SmokeAreaScene: PackedScene = null
var ExplosionEffectScene: PackedScene = null

## プリロード済みシェーダー・テクスチャ（初回投擲ラグ回避）
var smoke_clip_shader: Shader = null
var smoke_puff_texture: Texture2D = null

## グレネード追跡（爆発位置同期用）
var _active_grenades: Dictionary[int, Node3D] = {}  ## grenade_id -> Grenade/SmokeGrenade
var _exploded_grenades: Array[Node3D] = []  ## 爆発済みグレネード（ラウンド終了時に削除）
var _next_grenade_id: int = 1

## 外部参照
var _mesh_parent: Node3D = null
var _smoke_area_manager: SmokeAreaManager = null
var _fow_system = null  ## FogOfWarSystem参照（リモートグレネードのFoW可視性用）


func _init() -> void:
	GrenadeScene = load("res://scenes/weapons/grenade.tscn")
	SmokeGrenadeScene = load("res://scenes/weapons/smoke_grenade.tscn")
	HandGrenadeScene = load(GameConstants.SCENE_HAND_GRENADE)
	SmokeAreaScene = load(GameConstants.SCENE_SMOKE_AREA)
	ExplosionEffectScene = load(GameConstants.SCENE_EXPLOSION_EFFECT)
	smoke_clip_shader = load("res://shaders/smoke_particle_clip.gdshader") as Shader
	smoke_puff_texture = load("res://assets/effects/smoke_puff.png") as Texture2D


## セットアップ
func setup(mesh_parent: Node3D, smoke_area_manager: SmokeAreaManager = null) -> void:
	_mesh_parent = mesh_parent
	_smoke_area_manager = smoke_area_manager


## スモークエリアマネージャーを設定
func set_smoke_area_manager(manager: SmokeAreaManager) -> void:
	_smoke_area_manager = manager


## FogOfWarSystemを設定（リモートグレネードのFoW可視性チェック用）
func set_fow_system(fow) -> void:
	_fow_system = fow


## グレネードを生成して投擲
## 戻り値: [grenade, velocity, grenade_id] のトリプル
func spawn_and_throw_grenade(start_pos: Vector3, target_pos: Vector3, thrower: Node3D = null) -> Array:
	if not _mesh_parent:
		push_error("[GrenadeService] mesh_parent not set")
		return [null, Vector3.ZERO, 0]

	var grenade = GrenadeScene.instantiate() as Grenade
	if not grenade:
		return [null, Vector3.ZERO, 0]

	_mesh_parent.add_child(grenade)

	# グレネードIDを割り当てて追跡
	var grenade_id: int = _next_grenade_id
	_next_grenade_id += 1
	grenade.network_grenade_id = grenade_id
	_active_grenades[grenade_id] = grenade

	# 爆発シグナルを接続
	grenade.exploded.connect(_on_grenade_exploded.bind(grenade_id, false))

	# ターゲット位置に直接投擲
	grenade.throw(start_pos, target_pos, thrower)

	grenade_thrown.emit(grenade, thrower)

	return [grenade, grenade.initial_velocity, grenade_id]


## スモークグレネードを生成して投擲
## 戻り値: [smoke_grenade, velocity, grenade_id] のトリプル
func spawn_and_throw_smoke_grenade(start_pos: Vector3, target_pos: Vector3, thrower: Node3D = null) -> Array:
	if not _mesh_parent:
		push_error("[GrenadeService] mesh_parent not set")
		return [null, Vector3.ZERO, 0]

	var smoke_grenade = SmokeGrenadeScene.instantiate() as SmokeGrenade
	if not smoke_grenade:
		return [null, Vector3.ZERO, 0]

	if _smoke_area_manager:
		smoke_grenade.set_smoke_manager(_smoke_area_manager)
	# FoWシステムを設定（視界外の煙を非表示にするため）
	if _fow_system:
		smoke_grenade.set_fow_system(_fow_system)
	# プリロード済みリソースを渡す（初回投擲ラグ回避）
	_apply_preloaded_resources(smoke_grenade)
	_mesh_parent.add_child(smoke_grenade)

	# グレネードIDを割り当てて追跡
	var grenade_id: int = _next_grenade_id
	_next_grenade_id += 1
	smoke_grenade.network_grenade_id = grenade_id
	_active_grenades[grenade_id] = smoke_grenade

	# 爆発シグナルを接続（スモークはis_smoke=true）
	smoke_grenade.exploded.connect(_on_grenade_exploded.bind(grenade_id, true))

	# ターゲット位置に直接投擲
	smoke_grenade.throw(start_pos, target_pos, thrower)

	smoke_grenade_thrown.emit(smoke_grenade, thrower)

	return [smoke_grenade, smoke_grenade.initial_velocity, grenade_id]


## ハンドグレネードを生成して投擲
## 戻り値: [hand_grenade, velocity, grenade_id] のトリプル
func spawn_and_throw_hand_grenade(start_pos: Vector3, target_pos: Vector3, thrower: Node3D = null) -> Array:
	if not _mesh_parent:
		push_error("[GrenadeService] mesh_parent not set")
		return [null, Vector3.ZERO, 0]

	var hand_grenade = HandGrenadeScene.instantiate() as HandGrenade
	if not hand_grenade:
		return [null, Vector3.ZERO, 0]

	# 爆発VFXシーンを注入
	if ExplosionEffectScene:
		hand_grenade.set_explosion_effect_scene(ExplosionEffectScene)
	# FoWシステムを設定
	if _fow_system:
		hand_grenade.set_fow_system(_fow_system)
	_mesh_parent.add_child(hand_grenade)

	# グレネードIDを割り当てて追跡
	var grenade_id: int = _next_grenade_id
	_next_grenade_id += 1
	hand_grenade.network_grenade_id = grenade_id
	_active_grenades[grenade_id] = hand_grenade

	# 爆発シグナルを接続（ハンドグレネードはis_smoke=false）
	hand_grenade.exploded.connect(_on_grenade_exploded.bind(grenade_id, false))

	# ターゲット位置に直接投擲
	hand_grenade.throw(start_pos, target_pos, thrower)

	hand_grenade_thrown.emit(hand_grenade, thrower)

	return [hand_grenade, hand_grenade.initial_velocity, grenade_id]


## ネットワークからハンドグレネードをスポーン（リモート用）
func spawn_hand_grenade_from_network(start_pos: Vector3, velocity: Vector3, grenade_id: int = 0, thrower_team: int = 0) -> void:
	if not _mesh_parent:
		push_error("[GrenadeService] mesh_parent not set")
		return

	if Debug.enabled: print("[HAND GRENADE SPAWN] start=", start_pos, " vel=", velocity, " id=", grenade_id)
	var hand_grenade = HandGrenadeScene.instantiate() as HandGrenade
	if not hand_grenade:
		return

	# 爆発VFXシーンを注入
	if ExplosionEffectScene:
		hand_grenade.set_explosion_effect_scene(ExplosionEffectScene)
	_mesh_parent.add_child(hand_grenade)

	# リモートグレネードとしてマーク
	hand_grenade.is_remote = true
	hand_grenade.network_grenade_id = grenade_id
	hand_grenade.thrower_team = thrower_team as GameCharacter.Team
	if _fow_system:
		hand_grenade.set_fow_system(_fow_system)

	# 追跡（爆発イベント受信用）
	if grenade_id > 0:
		_active_grenades[grenade_id] = hand_grenade

	hand_grenade.throw_with_velocity(start_pos, velocity)
	hand_grenade_thrown.emit(hand_grenade, null)


## ネットワークからグレネードをスポーン（リモート用）
## ハンドグレネードとして生成（is_smoke=falseのGRENADE_THROWイベント経由）
func spawn_grenade_from_network(start_pos: Vector3, velocity: Vector3, grenade_id: int = 0, thrower_team: int = 0) -> void:
	if not _mesh_parent:
		push_error("[GrenadeService] mesh_parent not set")
		return

	if Debug.enabled: print("[HAND GRENADE SPAWN FROM NET] start=", start_pos, " vel=", velocity, " id=", grenade_id)
	var hand_grenade = HandGrenadeScene.instantiate() as HandGrenade
	if not hand_grenade:
		return

	# 爆発VFXシーンを注入
	if ExplosionEffectScene:
		hand_grenade.set_explosion_effect_scene(ExplosionEffectScene)
	_mesh_parent.add_child(hand_grenade)

	# リモートグレネードとしてマーク
	hand_grenade.is_remote = true
	hand_grenade.network_grenade_id = grenade_id
	hand_grenade.thrower_team = thrower_team as GameCharacter.Team
	if _fow_system:
		hand_grenade.set_fow_system(_fow_system)

	# 追跡（爆発イベント受信用）
	if grenade_id > 0:
		_active_grenades[grenade_id] = hand_grenade

	hand_grenade.throw_with_velocity(start_pos, velocity)
	if Debug.enabled: print("[HAND GRENADE SPAWNED] vel=", velocity)
	hand_grenade_thrown.emit(hand_grenade, null)


## ネットワークからスモークグレネードをスポーン（リモート用）
func spawn_smoke_grenade_from_network(start_pos: Vector3, velocity: Vector3, grenade_id: int = 0, thrower_team: int = 0) -> void:
	if not _mesh_parent:
		push_error("[GrenadeService] mesh_parent not set")
		return

	if Debug.enabled: print("[SMOKE SPAWN] start=", start_pos, " vel=", velocity, " id=", grenade_id)
	var smoke_grenade = SmokeGrenadeScene.instantiate() as SmokeGrenade
	if not smoke_grenade:
		return

	if _smoke_area_manager:
		smoke_grenade.set_smoke_manager(_smoke_area_manager)
	# プリロード済みリソースを渡す（初回投擲ラグ回避）
	_apply_preloaded_resources(smoke_grenade)
	_mesh_parent.add_child(smoke_grenade)

	# リモートグレネードとしてマーク
	smoke_grenade.is_remote = true
	smoke_grenade.network_grenade_id = grenade_id
	smoke_grenade.thrower_team = thrower_team as GameCharacter.Team
	if _fow_system:
		smoke_grenade.set_fow_system(_fow_system)

	# 追跡（爆発イベント受信用）
	if grenade_id > 0:
		_active_grenades[grenade_id] = smoke_grenade

	smoke_grenade.throw_with_velocity(start_pos, velocity)
	smoke_grenade_thrown.emit(smoke_grenade, null)


## ネットワークからの爆発イベントを処理（リモートグレネード用）
func handle_grenade_explode_from_network(grenade_id: int, position: Vector3, _is_smoke: bool) -> void:
	if Debug.enabled: print("[GRENADE EXPLODE] id=", grenade_id, " pos=", position)
	if not _active_grenades.has(grenade_id):
		push_warning("[GrenadeService] Grenade not found for explosion: ", grenade_id)
		return

	var grenade: Grenade = _active_grenades[grenade_id] as Grenade
	_active_grenades.erase(grenade_id)

	if is_instance_valid(grenade):
		grenade.explode_at_position(position)
		_exploded_grenades.append(grenade)


## グレネード爆発時のコールバック（ネットワーク送信用）
func _on_grenade_exploded(position: Vector3, grenade_id: int, is_smoke: bool) -> void:
	# アクティブから爆発済みリストに移動
	if _active_grenades.has(grenade_id):
		var grenade: Node3D = _active_grenades[grenade_id]
		_active_grenades.erase(grenade_id)
		if is_instance_valid(grenade):
			_exploded_grenades.append(grenade)

	# ネットワークイベントを発火（リモート側で同じ位置で爆発させる）
	grenade_explode_network_event.emit(grenade_id, position, is_smoke)


## ネットワークイベントを発火（グレネード投擲）
func emit_grenade_network_event(start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int = 0) -> void:
	grenade_network_event.emit(start_pos, velocity, is_smoke, grenade_id)


## プリロード済みリソースをスモークグレネードに適用
func _apply_preloaded_resources(smoke_grenade: SmokeGrenade) -> void:
	if SmokeAreaScene:
		smoke_grenade.set_smoke_area_scene(SmokeAreaScene)
	smoke_grenade.smoke_clip_shader = smoke_clip_shader
	smoke_grenade.smoke_puff_texture = smoke_puff_texture


## シェーダーウォームアップ（ゲーム開始時に呼び出し、初回GPUコンパイルを事前完了）
func warmup_smoke_shader() -> void:
	if not smoke_clip_shader:
		return
	# 不可視メッシュでシェーダーを1フレーム描画してGPUコンパイルを強制
	var mat := ShaderMaterial.new()
	mat.shader = smoke_clip_shader
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = QuadMesh.new()
	mesh_inst.mesh.material = mat
	# 画面外に配置
	mesh_inst.position = Vector3(0, -1000, 0)
	mesh_inst.scale = Vector3(0.01, 0.01, 0.01)
	add_child(mesh_inst)
	# 次フレームで削除（1フレーム描画すればGPUコンパイル完了）
	mesh_inst.tree_entered.connect(func():
		get_tree().create_timer(0.1).timeout.connect(mesh_inst.queue_free)
	)


## アクティブなグレネード数を取得
func get_active_grenade_count() -> int:
	return _active_grenades.size()


## 全グレネードをクリア
func clear_all() -> void:
	for grenade in _active_grenades.values():
		if is_instance_valid(grenade):
			grenade.queue_free()
	_active_grenades.clear()
	for grenade in _exploded_grenades:
		if is_instance_valid(grenade):
			grenade.queue_free()
	_exploded_grenades.clear()
	_next_grenade_id = 1
