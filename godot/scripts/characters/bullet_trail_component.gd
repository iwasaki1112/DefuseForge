class_name BulletTrailComponent
extends RefCounted

## 弾道表示コンポーネント
## 射撃時の弾道トレイルエフェクト表示を管理
## GameCharacterから抽出されたコンポーネント

# ============================================
# Constants
# ============================================

var BULLET_TRAIL_SHADER: Shader = null
const BULLET_TRAIL_DURATION: float = 0.15
const BULLET_TRAIL_WIDTH: float = 0.04
const BULLET_TRAIL_MAX_DISTANCE: float = 50.0

# ============================================
# References
# ============================================

var _character: Node3D = null
var _weapon_socket: Node3D = null
var _muzzle_flash_component: MuzzleFlashComponent = null
var _combat_awareness = null  # CombatAwarenessComponent

# ============================================
# State
# ============================================

var _bullet_trail: Node3D = null
var _bullet_trail_mat: ShaderMaterial = null
var _bullet_trail_tween: Tween = null
var _bullet_trail_quad1: MeshInstance3D = null
var _bullet_trail_quad2: MeshInstance3D = null

# ============================================
# Setup
# ============================================

func _init() -> void:
	BULLET_TRAIL_SHADER = load("res://shaders/bullet_trail.gdshader")


## セットアップ
func setup(character: Node3D, weapon_socket: Node3D, muzzle_flash: MuzzleFlashComponent, combat_awareness = null) -> void:
	_character = character
	_weapon_socket = weapon_socket
	_muzzle_flash_component = muzzle_flash
	_combat_awareness = combat_awareness

	# キャラクター破棄時にトレイルノードをクリーンアップ
	if _character and not _character.tree_exited.is_connected(_on_character_tree_exited):
		_character.tree_exited.connect(_on_character_tree_exited)


## キャラクターがシーンから削除された時のクリーンアップ
func _on_character_tree_exited() -> void:
	cleanup()


## トレイルノードをクリーンアップ
func cleanup() -> void:
	if _bullet_trail_tween and is_instance_valid(_bullet_trail_tween) and _bullet_trail_tween.is_running():
		_bullet_trail_tween.kill()
	_bullet_trail_tween = null
	if _bullet_trail and is_instance_valid(_bullet_trail):
		_bullet_trail.queue_free()
		_bullet_trail = null


## 武器ソケットを更新
func set_weapon_socket(socket: Node3D) -> void:
	_weapon_socket = socket


## CombatAwarenessを設定
func set_combat_awareness(awareness) -> void:
	_combat_awareness = awareness


## ウォームアップ: ノード生成とシェーダーコンパイルを事前に行う
func warm_up() -> void:
	_ensure_trail_nodes()

# ============================================
# Public API
# ============================================

## 弾道トレイルを再生
func play(current_weapon: Resource, weapon_model: Node3D) -> void:
	if not _weapon_socket:
		return

	var muzzle_world_pos = _get_muzzle_world_position(current_weapon, weapon_model)
	var target_pos = _get_bullet_target_position()

	if muzzle_world_pos == Vector3.ZERO or target_pos == Vector3.ZERO:
		return

	_create_trail(muzzle_world_pos, target_pos)

# ============================================
# Internal
# ============================================

func _get_muzzle_world_position(current_weapon: Resource, weapon_model: Node3D) -> Vector3:
	if not _weapon_socket or not is_instance_valid(_weapon_socket):
		return Vector3.ZERO

	# MuzzleFlashComponentから位置を取得
	if _muzzle_flash_component:
		var pos = _muzzle_flash_component.get_world_position()
		if pos != Vector3.ZERO:
			return pos

	# フォールバック: オフセットから計算
	var muzzle_offset = _get_muzzle_offset(current_weapon, weapon_model)
	return _weapon_socket.to_global(muzzle_offset)


func _get_muzzle_offset(current_weapon: Resource, _weapon_model: Node3D) -> Vector3:
	if current_weapon and current_weapon.has_method("get"):
		var offset = current_weapon.get("muzzle_flash_offset")
		if offset != null and offset != Vector3.ZERO:
			return offset
	# デフォルトオフセット
	return Vector3(0, 0, -0.25)


func _get_bullet_target_position() -> Vector3:
	if not _character:
		return Vector3.ZERO

	# 1. CombatAwarenessから現在のターゲットを取得
	if _combat_awareness:
		var target = _combat_awareness.get_current_target() if _combat_awareness.has_method("get_current_target") else null
		if target and is_instance_valid(target) and target is Node3D:
			var target_pos: Vector3 = target.global_position + Vector3(0, 1.2, 0)

			# 命中判定結果を取得
			if _combat_awareness.has_method("get_last_shot_result"):
				var shot_result: Dictionary = _combat_awareness.get_last_shot_result()
				if not shot_result.get("hit", true):
					var miss_offset: Vector3 = shot_result.get("miss_offset", Vector3.ZERO)
					target_pos += miss_offset

			return target_pos

	# 2. フォールバック: キャラクターの視線方向に延長
	# facing_directionを使用（リモートキャラではノード回転と一致しない場合がある）
	var forward: Vector3
	if _character.has_method("get_facing_direction"):
		forward = _character.get_facing_direction()
	else:
		forward = -_character.global_transform.basis.z
	return _character.global_position + Vector3(0, 1.5, 0) + forward * BULLET_TRAIL_MAX_DISTANCE


## トレイルノードとシェーダーマテリアルを事前生成
func _ensure_trail_nodes() -> void:
	if _bullet_trail and is_instance_valid(_bullet_trail):
		return
	if not _character or not _character.is_inside_tree():
		return

	_bullet_trail = Node3D.new()
	_bullet_trail.name = "BulletTrail"

	# シェーダーマテリアル作成
	_bullet_trail_mat = ShaderMaterial.new()
	_bullet_trail_mat.shader = BULLET_TRAIL_SHADER
	_bullet_trail_mat.set_shader_parameter("trail_color", Color(1.0, 0.95, 0.85, 1.0))
	_bullet_trail_mat.set_shader_parameter("edge_softness", 0.3)
	_bullet_trail_mat.set_shader_parameter("tip_roundness", 0.12)
	_bullet_trail_mat.set_shader_parameter("fade_start", 0.0)
	_bullet_trail_mat.set_shader_parameter("fade_end", 0.7)
	_bullet_trail_mat.set_shader_parameter("glow_intensity", 1.8)
	_bullet_trail_mat.set_shader_parameter("overall_alpha", 1.0)

	# Quad 1（水平面）
	_bullet_trail_quad1 = MeshInstance3D.new()
	var mesh1 = QuadMesh.new()
	mesh1.size = Vector2(BULLET_TRAIL_WIDTH, 1.0)
	_bullet_trail_quad1.mesh = mesh1
	_bullet_trail_quad1.rotation_degrees.x = 90
	_bullet_trail_quad1.material_override = _bullet_trail_mat
	_bullet_trail.add_child(_bullet_trail_quad1)

	# Quad 2（垂直面）
	_bullet_trail_quad2 = MeshInstance3D.new()
	var mesh2 = QuadMesh.new()
	mesh2.size = Vector2(BULLET_TRAIL_WIDTH, 1.0)
	_bullet_trail_quad2.mesh = mesh2
	_bullet_trail_quad2.rotation_degrees.x = 90
	_bullet_trail_quad2.rotate_object_local(Vector3.UP, deg_to_rad(90))
	_bullet_trail_quad2.material_override = _bullet_trail_mat
	_bullet_trail.add_child(_bullet_trail_quad2)

	# ワールド空間に追加
	_character.get_tree().root.add_child(_bullet_trail)
	_bullet_trail.visible = false


func _create_trail(start: Vector3, end: Vector3) -> void:
	if _bullet_trail_tween and _bullet_trail_tween.is_running():
		_bullet_trail_tween.kill()

	var length = start.distance_to(end)
	if length < 0.1:
		return

	_ensure_trail_nodes()
	if not _bullet_trail:
		return

	# Quadサイズを更新
	var quad1_mesh = _bullet_trail_quad1.mesh as QuadMesh
	var quad2_mesh = _bullet_trail_quad2.mesh as QuadMesh
	if quad1_mesh:
		quad1_mesh.size = Vector2(BULLET_TRAIL_WIDTH, length)
	if quad2_mesh:
		quad2_mesh.size = Vector2(BULLET_TRAIL_WIDTH, length)

	# 位置と向き
	_bullet_trail.global_position = (start + end) * 0.5
	_bullet_trail.look_at(end, Vector3.UP)

	# 表示・アルファリセット
	_bullet_trail.visible = true
	if _bullet_trail_mat:
		_bullet_trail_mat.set_shader_parameter("overall_alpha", 1.0)

	# Tweenでフェードアウト
	if _character:
		_bullet_trail_tween = _character.create_tween()
		_bullet_trail_tween.tween_method(
			func(alpha: float): _bullet_trail_mat.set_shader_parameter("overall_alpha", alpha),
			1.0,
			0.0,
			BULLET_TRAIL_DURATION
		)
		_bullet_trail_tween.tween_callback(func(): _bullet_trail.visible = false)
