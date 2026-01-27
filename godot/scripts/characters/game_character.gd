extends CharacterBody3D
class_name GameCharacter
## Character management class
## Provides HP, death state, and team management
## Works with CharacterAnimationController for animations

const MUZZLE_FLASH_TEXTURE = preload("res://assets/effects/muzzle_flash_sprite_sheet.jpg")
const MUZZLE_FLASH_BASE_SIZE: float = 0.25
const MUZZLE_FLASH_SCALE_MULTIPLIER: float = 200.0
const MUZZLE_FLASH_DURATION: float = 0.09  # 3フレーム × 0.03秒/フレーム
const MUZZLE_FLASH_FRAME_COUNT: int = 3
const MUZZLE_FLASH_FRAME_TIME: float = 0.03  # 各フレームの表示時間

# Bullet Trail (Shader-based)
const BULLET_TRAIL_SHADER = preload("res://shaders/bullet_trail.gdshader")
const BULLET_TRAIL_DURATION: float = 0.15
const BULLET_TRAIL_WIDTH: float = 0.01  # トレイルの幅
const BULLET_TRAIL_MAX_DISTANCE: float = 50.0

# ============================================
# Team Definition
# ============================================
enum Team { NONE = 0, COUNTER_TERRORIST = 1, TERRORIST = 2 }

# ============================================
# Signals
# ============================================
signal died(character: GameCharacter)
signal state_changed(character: GameCharacter)  ## マルチプレイヤー用：状態変更通知

# ============================================
# Export Settings
# ============================================
@export_group("HP Settings")
@export var max_health: float = 100.0

@export_group("Team Settings")
@export var team: Team = Team.NONE

@export_group("UI Settings")
## キャラクターマーカー名（alpha, bravo, ares, brim）
@export var marker_name: String = ""

# ============================================
# Network Identity (Multiplayer)
# ============================================

## ネットワーク上のグローバルID（0はローカル専用）
var network_id: int = 0

## 所有者のpeer_id（0はローカル/未割当）
var owner_peer_id: int = 0

# ============================================
# State
# ============================================
var current_health: float = 100.0
var is_alive: bool = true

# ============================================
# Remote Interpolation (リモートキャラクター用補間)
# ============================================
var _remote_target_position: Vector3 = Vector3.ZERO
var _remote_target_rotation: float = 0.0
var _remote_target_velocity: Vector3 = Vector3.ZERO
var _remote_interpolation_active: bool = false
const REMOTE_INTERPOLATION_SPEED: float = 15.0  # 補間速度

# ============================================
# Facing Direction (一元管理)
# ============================================
## キャラクターの向き（正規化済みXZ平面ベクトル）
## すべてのコンポーネント（Animation, Vision）はこれを参照する
var _facing_direction: Vector3 = Vector3.FORWARD

# ============================================
# References
# ============================================
var anim_ctrl: CharacterAnimationController = null  # CharacterAnimationController
var vision: VisionComponent = null  # VisionComponent for FoW
var combat_awareness: CombatAwarenessComponent = null  # CombatAwarenessComponent for enemy tracking
var current_weapon: WeaponPreset = null  # WeaponPreset
var _weapon_attachment: BoneAttachment3D = null  # 武器アタッチメントノード
var _weapon_socket: Node3D = null  # 武器調整用ソケットノード
var _weapon_model: Node3D = null  # 現在の武器モデル
var _muzzle_flash: Node3D = null
var _muzzle_flash_mat: StandardMaterial3D = null  # マテリアル参照用
var _muzzle_flash_light: OmniLight3D = null  # マズルフラッシュ光源
var _muzzle_flash_tween: Tween = null
var _muzzle_flash_preview_enabled: bool = false
var _muzzle_flash_quad1: MeshInstance3D = null  # Quad1参照用
var _muzzle_flash_quad1_x_offset: float = 0.032  # Quad1のX位置オフセット
var _muzzle_flash_quad1_z_offset: float = 0.026  # Quad1のZ位置オフセット
var _bullet_trail: Node3D = null
var _bullet_trail_mat: ShaderMaterial = null
var _bullet_trail_tween: Tween = null
var _bullet_trail_quad1: MeshInstance3D = null
var _bullet_trail_quad2: MeshInstance3D = null

# ============================================
# Lifecycle
# ============================================

func _ready() -> void:
	current_health = max_health
	is_alive = true
	add_to_group(GameConstants.GROUP_CHARACTERS)

# ============================================
# HP API
# ============================================

## Take damage
func take_damage(amount: float, attacker: Node3D = null, is_headshot: bool = false) -> void:
	if not is_alive:
		return

	current_health = max(0.0, current_health - amount)

	if current_health <= 0.0:
		_die(attacker, is_headshot)

## Heal
func heal(amount: float) -> void:
	if not is_alive:
		return
	current_health = min(max_health, current_health + amount)

## Get health ratio (0.0 - 1.0)
func get_health_ratio() -> float:
	return current_health / max_health if max_health > 0 else 0.0

## Reset health
func reset_health() -> void:
	current_health = max_health
	is_alive = true
	# Re-enable vision on respawn
	if vision:
		vision.enable()

# ============================================
# Team API
# ============================================

## Check if target is enemy team
func is_enemy_of(other: GameCharacter) -> bool:
	if other == null:
		return false
	if team == Team.NONE or other.team == Team.NONE:
		return false
	return team != other.team

# ============================================
# Animation Controller API
# ============================================

## Set CharacterAnimationController
func set_anim_controller(controller: CharacterAnimationController) -> void:
	if anim_ctrl and anim_ctrl.fired.is_connected(_on_anim_fired):
		anim_ctrl.fired.disconnect(_on_anim_fired)
	anim_ctrl = controller
	if anim_ctrl and not anim_ctrl.fired.is_connected(_on_anim_fired):
		anim_ctrl.fired.connect(_on_anim_fired)

## Get CharacterAnimationController
func get_anim_controller() -> CharacterAnimationController:
	return anim_ctrl

# ============================================
# Facing Direction API (一元管理)
# ============================================

## キャラクターの向きを設定（ベクトル）
## Animation、Visionすべてがこの向きを参照する
func set_facing_direction_vec(direction: Vector3) -> void:
	direction.y = 0
	if direction.length_squared() < 0.001:
		return
	_facing_direction = direction.normalized()
	# AnimationControllerのモデル向きを更新
	if anim_ctrl:
		anim_ctrl.set_model_direction(_facing_direction)


## キャラクターの向きを設定（Y軸回転、ラジアン）
func set_facing_direction(y_rotation: float) -> void:
	# y_rotation=0 → +Z方向（Mixamoモデルの前方向）
	var direction := Vector3(sin(y_rotation), 0, cos(y_rotation))
	set_facing_direction_vec(direction)


## ターゲット位置の方向を向く
func face_towards(target_pos: Vector3) -> void:
	var dir := target_pos - global_position
	set_facing_direction_vec(dir)


## 現在の向きを取得（すべてのコンポーネントはこれを参照すべき）
func get_facing_direction() -> Vector3:
	return _facing_direction

# ============================================
# Stance API
# ============================================

## Check if character is crouching
func is_crouching() -> bool:
	if anim_ctrl:
		return anim_ctrl.get_stance() == CharacterAnimationController.Stance.CROUCH
	return false


## Toggle crouch state
func toggle_crouch() -> void:
	if not anim_ctrl:
		return

	var current = anim_ctrl.get_stance()
	# Stance.STAND = 0, Stance.CROUCH = 1
	anim_ctrl.set_stance(CharacterAnimationController.Stance.STAND if current == CharacterAnimationController.Stance.CROUCH else CharacterAnimationController.Stance.CROUCH)


# ============================================
# Vision Component API
# ============================================

## Set VisionComponent
func set_vision_component(component: VisionComponent) -> void:
	vision = component

## Get VisionComponent
func get_vision_component() -> VisionComponent:
	return vision

## Setup vision component (auto-create if not exists)
func setup_vision(fov: float = 90.0, view_dist: float = 15.0) -> VisionComponent:
	if vision == null:
		vision = VisionComponent.new()
		vision.name = GameConstants.NODE_VISION_COMPONENT
		add_child(vision)

	vision.set_fov(fov)
	vision.set_view_distance(view_dist)
	return vision

# ============================================
# Combat Awareness API
# ============================================

## Setup combat awareness component (auto-create if not exists)
func setup_combat_awareness() -> CombatAwarenessComponent:
	if combat_awareness == null:
		combat_awareness = CombatAwarenessComponent.new()
		combat_awareness.name = GameConstants.NODE_COMBAT_AWARENESS
		add_child(combat_awareness)
		combat_awareness.setup(self)
	return combat_awareness


## Get CombatAwarenessComponent
func get_combat_awareness() -> CombatAwarenessComponent:
	return combat_awareness

# ============================================
# Weapon API
# ============================================

## Find Skeleton3D recursively in node tree
func _find_skeleton_in_node(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton_in_node(child)
		if result:
			return result
	return null


## Create or get BoneAttachment3D for weapon
func _ensure_weapon_attachment() -> BoneAttachment3D:
	if _weapon_attachment:
		return _weapon_attachment

	var model = get_node_or_null(GameConstants.NODE_CHARACTER_MODEL)
	if not model:
		push_warning("GameCharacter: CharacterModel not found")
		return null

	var skeleton = _find_skeleton_in_node(model)
	if not skeleton:
		push_warning("GameCharacter: Skeleton not found")
		return null

	var bone_idx = skeleton.find_bone(GameConstants.BONE_RIGHT_HAND)
	if bone_idx < 0:
		push_warning("GameCharacter: mixamorig_RightHand bone not found")
		return null

	_weapon_attachment = BoneAttachment3D.new()
	_weapon_attachment.name = GameConstants.NODE_WEAPON_ATTACHMENT
	_weapon_attachment.bone_name = GameConstants.BONE_RIGHT_HAND
	skeleton.add_child(_weapon_attachment)

	return _weapon_attachment


## Create or get WeaponSocket under BoneAttachment3D
func _ensure_weapon_socket(attachment: BoneAttachment3D) -> Node3D:
	if _weapon_socket and _weapon_socket.is_inside_tree():
		return _weapon_socket

	_weapon_socket = Node3D.new()
	_weapon_socket.name = GameConstants.NODE_WEAPON_SOCKET
	attachment.add_child(_weapon_socket)
	return _weapon_socket


## Attach weapon model to right hand
func _attach_weapon_model(weapon: WeaponPreset) -> void:
	# Remove old weapon model
	if _weapon_model:
		_weapon_model.queue_free()
		_weapon_model = null

	if not weapon or not weapon.model_scene:
		push_warning("GameCharacter: No model_scene for weapon")
		return

	var attachment = _ensure_weapon_attachment()
	if not attachment:
		return

	var socket = _ensure_weapon_socket(attachment)
	if not socket:
		return

	_weapon_model = weapon.model_scene.instantiate()
	_weapon_model.name = GameConstants.NODE_WEAPON_MODEL
	socket.add_child(_weapon_model)

	# Mixamo skeleton is 0.01 scale, so weapon needs 100x scale
	_weapon_model.scale = Vector3.ONE * 100.0
	_weapon_model.position = Vector3.ZERO
	_weapon_model.rotation_degrees = Vector3.ZERO

	# Apply offset from WeaponPreset (use defaults for Mixamo if not set)
	if weapon.attach_offset != Vector3.ZERO:
		socket.position = weapon.attach_offset
	else:
		# Default offset for Mixamo right hand
		socket.position = Vector3(1, 7, 2)

	if weapon.attach_rotation != Vector3.ZERO:
		socket.rotation_degrees = weapon.attach_rotation
	else:
		# Default rotation for Mixamo right hand
		socket.rotation_degrees = Vector3(-79, -66, -28)



## Equip a weapon from WeaponPreset
## Applies weapon type and recoil settings to CharacterAnimationController
## Also attaches weapon model to right hand bone
func equip_weapon(weapon: WeaponPreset) -> void:
	current_weapon = weapon

	# Attach weapon model to right hand
	_attach_weapon_model(weapon)

	if not anim_ctrl:
		return

	# Convert WeaponCategory to CharacterAnimationController.Weapon
	# WeaponCategory: RIFLE=0, PISTOL=1, SMG=2, SHOTGUN=3, SNIPER=4
	# Weapon: NONE=0, RIFLE=1, PISTOL=2
	var weapon_type: CharacterAnimationController.Weapon = CharacterAnimationController.Weapon.RIFLE
	if weapon.category == WeaponPreset.WeaponCategory.PISTOL:
		weapon_type = CharacterAnimationController.Weapon.PISTOL

	anim_ctrl.set_weapon(weapon_type)

	# Apply recoil settings directly to controller
	if "rifle_recoil_strength" in anim_ctrl:
		# Apply weapon's recoil to both rifle/pistol slots based on category
		if weapon.category == WeaponPreset.WeaponCategory.PISTOL:
			anim_ctrl.pistol_recoil_strength = weapon.recoil_strength
		else:
			anim_ctrl.rifle_recoil_strength = weapon.recoil_strength

	if "recoil_recovery" in anim_ctrl:
		anim_ctrl.recoil_recovery = weapon.recoil_recovery

## Get current weapon
func get_current_weapon() -> WeaponPreset:
	return current_weapon

## Get weapon socket node (for adjustment/tools)
func get_weapon_socket() -> Node3D:
	return _weapon_socket

# ============================================
# Muzzle Flash
# ============================================

func _on_anim_fired() -> void:
	_play_muzzle_flash()
	_play_bullet_trail()

func set_muzzle_flash_preview(enabled: bool) -> void:
	_muzzle_flash_preview_enabled = enabled
	if not enabled:
		if _muzzle_flash:
			_muzzle_flash.visible = false
		if _muzzle_flash_tween and _muzzle_flash_tween.is_running():
			_muzzle_flash_tween.kill()
		return
	_ensure_muzzle_flash_visible()


func update_muzzle_flash_preview() -> void:
	if not _muzzle_flash_preview_enabled:
		return
	_ensure_muzzle_flash_visible()


func _play_muzzle_flash() -> void:
	if _muzzle_flash_preview_enabled:
		_ensure_muzzle_flash_visible()
		return
	if not _weapon_socket:
		return
	if not _muzzle_flash or not is_instance_valid(_muzzle_flash):
		_create_muzzle_flash()
	if not _muzzle_flash:
		return

	_muzzle_flash.position = _get_muzzle_flash_offset()
	_muzzle_flash.rotation_degrees = _get_muzzle_flash_rotation()

	var base_scale = _get_muzzle_flash_scale()
	_muzzle_flash.scale = Vector3.ONE * base_scale
	_muzzle_flash.visible = true

	if _muzzle_flash_tween and _muzzle_flash_tween.is_running():
		_muzzle_flash_tween.kill()

	if _muzzle_flash_mat:
		_muzzle_flash_mat.albedo_color = Color(1, 1, 1, 1)
		# フレーム0（左上）から開始
		_muzzle_flash_mat.uv1_offset = Vector3(0.0, 0.0, 0.0)
	if _muzzle_flash_light:
		_muzzle_flash_light.light_energy = 3.0

	_muzzle_flash_tween = create_tween()

	# スプライトシートアニメーション（上の行3フレーム）
	if _muzzle_flash_mat:
		# フレーム0→フレーム1（中央上）
		_muzzle_flash_tween.tween_callback(func():
			_muzzle_flash_mat.uv1_offset = Vector3(1.0 / 3.0, 0.0, 0.0)
		).set_delay(MUZZLE_FLASH_FRAME_TIME)
		# フレーム1→フレーム2（右上）
		_muzzle_flash_tween.tween_callback(func():
			_muzzle_flash_mat.uv1_offset = Vector3(2.0 / 3.0, 0.0, 0.0)
		).set_delay(MUZZLE_FLASH_FRAME_TIME)

	# スケールアニメーション
	_muzzle_flash_tween.parallel().tween_property(
		_muzzle_flash,
		"scale",
		Vector3.ONE * base_scale * 1.2,
		MUZZLE_FLASH_DURATION
	)
	# フェードアウト
	if _muzzle_flash_mat:
		_muzzle_flash_tween.parallel().tween_property(
			_muzzle_flash_mat,
			"albedo_color",
			Color(1, 1, 1, 0),
			MUZZLE_FLASH_DURATION
		)
	if _muzzle_flash_light:
		_muzzle_flash_tween.parallel().tween_property(
			_muzzle_flash_light,
			"light_energy",
			0.0,
			MUZZLE_FLASH_DURATION
		)
	_muzzle_flash_tween.tween_callback(func(): _muzzle_flash.visible = false)


func _ensure_muzzle_flash_visible() -> void:
	if not _weapon_socket:
		return
	if not _muzzle_flash or not is_instance_valid(_muzzle_flash):
		_create_muzzle_flash()
	if not _muzzle_flash:
		return

	_muzzle_flash.position = _get_muzzle_flash_offset()
	_muzzle_flash.rotation_degrees = _get_muzzle_flash_rotation()
	_muzzle_flash.scale = Vector3.ONE * _get_muzzle_flash_scale()
	if _muzzle_flash_mat:
		_muzzle_flash_mat.albedo_color = Color(1, 1, 1, 1)
		# プレビュー時は最初のフレーム（左上）を表示
		_muzzle_flash_mat.uv1_offset = Vector3(0.0, 0.0, 0.0)
	if _muzzle_flash_light:
		_muzzle_flash_light.light_energy = 3.0
	_muzzle_flash.visible = true


func _create_muzzle_flash() -> void:
	if not _weapon_socket or not is_instance_valid(_weapon_socket):
		return

	# 親ノードを作成
	_muzzle_flash = Node3D.new()
	_muzzle_flash.name = "MuzzleFlash"

	# 共通マテリアル作成（スプライトシート用）
	_muzzle_flash_mat = StandardMaterial3D.new()
	_muzzle_flash_mat.albedo_texture = MUZZLE_FLASH_TEXTURE
	_muzzle_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_muzzle_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_muzzle_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_muzzle_flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_muzzle_flash_mat.emission_enabled = true
	_muzzle_flash_mat.emission_texture = MUZZLE_FLASH_TEXTURE
	_muzzle_flash_mat.emission_energy_multiplier = 1.2
	# スプライトシート用UV設定（3×3グリッドの1コマ分）
	_muzzle_flash_mat.uv1_scale = Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0)
	_muzzle_flash_mat.uv1_offset = Vector3(0.0, 0.0, 0.0)  # 左上から開始

	# Quad 1 (XY平面 - 正面向き、Z軸で-90度回転してテクスチャ向き補正)
	_muzzle_flash_quad1 = MeshInstance3D.new()
	var mesh1 = QuadMesh.new()
	mesh1.size = Vector2(MUZZLE_FLASH_BASE_SIZE, MUZZLE_FLASH_BASE_SIZE)
	_muzzle_flash_quad1.mesh = mesh1
	_muzzle_flash_quad1.position = Vector3(_muzzle_flash_quad1_x_offset, 0, _muzzle_flash_quad1_z_offset)
	_muzzle_flash_quad1.rotation_degrees.z = -90  # テクスチャが横向きなので補正
	_muzzle_flash_quad1.material_override = _muzzle_flash_mat
	_muzzle_flash.add_child(_muzzle_flash_quad1)

	# Quad 2 (Quad1と同じ + Y軸90度で十字配置)
	var quad2 = MeshInstance3D.new()
	var mesh2 = QuadMesh.new()
	mesh2.size = Vector2(MUZZLE_FLASH_BASE_SIZE, MUZZLE_FLASH_BASE_SIZE)
	quad2.mesh = mesh2
	quad2.position = Vector3.ZERO
	quad2.rotation_degrees = Vector3(0, 90, -90)  # Y軸90度 + Z軸-90度
	quad2.material_override = _muzzle_flash_mat
	_muzzle_flash.add_child(quad2)

	# オレンジ光源
	_muzzle_flash_light = OmniLight3D.new()
	_muzzle_flash_light.light_color = Color(1.0, 0.6, 0.2)  # オレンジ
	_muzzle_flash_light.light_energy = 3.0
	_muzzle_flash_light.omni_range = 2.0
	_muzzle_flash_light.omni_attenuation = 2.0
	_muzzle_flash.add_child(_muzzle_flash_light)

	_muzzle_flash.visible = false
	_weapon_socket.add_child(_muzzle_flash)


func _get_muzzle_flash_scale() -> float:
	if current_weapon:
		return maxf(0.01, current_weapon.muzzle_flash_scale) * MUZZLE_FLASH_SCALE_MULTIPLIER
	return MUZZLE_FLASH_SCALE_MULTIPLIER


func _get_muzzle_flash_rotation() -> Vector3:
	if current_weapon:
		return current_weapon.muzzle_flash_rotation
	return Vector3.ZERO


## Set Quad1 X offset for muzzle flash adjustment
func set_muzzle_flash_quad1_x(x_offset: float) -> void:
	_muzzle_flash_quad1_x_offset = x_offset
	if _muzzle_flash_quad1 and is_instance_valid(_muzzle_flash_quad1):
		_muzzle_flash_quad1.position.x = x_offset


## Get Quad1 X offset
func get_muzzle_flash_quad1_x() -> float:
	return _muzzle_flash_quad1_x_offset


## Set Quad1 Z offset for muzzle flash adjustment
func set_muzzle_flash_quad1_z(z_offset: float) -> void:
	_muzzle_flash_quad1_z_offset = z_offset
	if _muzzle_flash_quad1 and is_instance_valid(_muzzle_flash_quad1):
		_muzzle_flash_quad1.position.z = z_offset


## Get Quad1 Z offset
func get_muzzle_flash_quad1_z() -> float:
	return _muzzle_flash_quad1_z_offset


func _get_muzzle_flash_offset() -> Vector3:
	if current_weapon and current_weapon.muzzle_flash_offset != Vector3.ZERO:
		return current_weapon.muzzle_flash_offset
	var auto_offset = _calculate_muzzle_offset_from_model()
	if auto_offset != Vector3.ZERO:
		return auto_offset
	# Fallback: weapon forward is usually -Z in Godot
	return Vector3(0, 0, -0.25)


func _calculate_muzzle_offset_from_model() -> Vector3:
	if not _weapon_model:
		return Vector3.ZERO

	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(_weapon_model, meshes)
	if meshes.is_empty():
		return Vector3.ZERO

	var combined := AABB()
	var has_aabb := false
	for mesh in meshes:
		var local_aabb = mesh.get_aabb()
		var transformed = _transform_aabb(local_aabb, mesh.transform)
		if not has_aabb:
			combined = transformed
			has_aabb = true
		else:
			combined = combined.merge(transformed)

	if not has_aabb:
		return Vector3.ZERO

	var center = combined.position + combined.size * 0.5
	var min_z = combined.position.z
	var max_z = combined.position.z + combined.size.z
	var muzzle_z = min_z if absf(min_z) >= absf(max_z) else max_z
	var muzzle_local = Vector3(center.x, center.y, muzzle_z)
	var model_scale = _weapon_model.scale
	return Vector3(muzzle_local.x * model_scale.x, muzzle_local.y * model_scale.y, muzzle_local.z * model_scale.z)


func _collect_mesh_instances(node: Node, results: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			results.append(child)
		_collect_mesh_instances(child, results)


func _transform_aabb(aabb: AABB, xform: Transform3D) -> AABB:
	var corners = [
		Vector3(aabb.position.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.position.y + aabb.size.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.position.y, aabb.position.z + aabb.size.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y + aabb.size.y, aabb.position.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y, aabb.position.z + aabb.size.z),
		Vector3(aabb.position.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z)
	]

	var transformed := AABB()
	for i in corners.size():
		var p = xform * corners[i]
		if i == 0:
			transformed.position = p
			transformed.size = Vector3.ZERO
		else:
			transformed = transformed.expand(p)
	return transformed

# ============================================
# Bullet Trail
# ============================================

func _play_bullet_trail() -> void:
	if not _weapon_socket:
		return

	var muzzle_world_pos = _get_muzzle_world_position()
	var target_pos = _get_bullet_target_position()

	if muzzle_world_pos == Vector3.ZERO or target_pos == Vector3.ZERO:
		return

	_create_bullet_trail(muzzle_world_pos, target_pos)


func _get_muzzle_world_position() -> Vector3:
	if not _weapon_socket or not is_instance_valid(_weapon_socket):
		return Vector3.ZERO

	# マズルフラッシュが存在すればその位置を使用（最も正確）
	if _muzzle_flash and is_instance_valid(_muzzle_flash):
		return _muzzle_flash.global_position

	# フォールバック: オフセットから計算
	var muzzle_offset = _get_muzzle_flash_offset()
	return _weapon_socket.to_global(muzzle_offset)


func _get_bullet_target_position() -> Vector3:
	# 1. CombatAwarenessから現在のターゲットを取得
	if combat_awareness:
		var target = combat_awareness.get_current_target()
		if target and is_instance_valid(target) and target is Node3D:
			# ターゲットの中心（胸あたり）を狙う
			var target_pos: Vector3 = target.global_position + Vector3(0, 1.2, 0)

			# 命中判定結果を取得し、外れた場合はオフセットを適用
			var shot_result: Dictionary = combat_awareness.get_last_shot_result()
			if not shot_result.get("hit", true):
				var miss_offset: Vector3 = shot_result.get("miss_offset", Vector3.ZERO)
				target_pos += miss_offset

			return target_pos

	# 2. フォールバック: キャラクターの視線方向に延長
	var forward = global_transform.basis.z  # +Zが前方
	return global_position + Vector3(0, 1.5, 0) + forward * BULLET_TRAIL_MAX_DISTANCE


func _create_bullet_trail(start: Vector3, end: Vector3) -> void:
	# 既存のトレイルがあればTweenを止める
	if _bullet_trail_tween and _bullet_trail_tween.is_running():
		_bullet_trail_tween.kill()

	# トレイルの長さを計算
	var length = start.distance_to(end)
	if length < 0.1:
		return

	# 親ノードとメッシュが存在しなければ作成
	if not _bullet_trail or not is_instance_valid(_bullet_trail):
		_bullet_trail = Node3D.new()
		_bullet_trail.name = "BulletTrail"

		# シェーダーマテリアル作成
		_bullet_trail_mat = ShaderMaterial.new()
		_bullet_trail_mat.shader = BULLET_TRAIL_SHADER
		_bullet_trail_mat.set_shader_parameter("trail_color", Color(1.0, 0.95, 0.85, 1.0))
		_bullet_trail_mat.set_shader_parameter("edge_softness", 1.5)
		_bullet_trail_mat.set_shader_parameter("tip_roundness", 0.12)
		_bullet_trail_mat.set_shader_parameter("fade_start", 0.0)
		_bullet_trail_mat.set_shader_parameter("fade_end", 0.7)
		_bullet_trail_mat.set_shader_parameter("glow_intensity", 1.8)
		_bullet_trail_mat.set_shader_parameter("overall_alpha", 1.0)

		# Quad 1（水平面）- X軸90度回転でXZ平面に配置
		_bullet_trail_quad1 = MeshInstance3D.new()
		var mesh1 = QuadMesh.new()
		mesh1.size = Vector2(BULLET_TRAIL_WIDTH, 1.0)
		_bullet_trail_quad1.mesh = mesh1
		_bullet_trail_quad1.rotation_degrees.x = 90  # XY平面→XZ平面
		_bullet_trail_quad1.material_override = _bullet_trail_mat
		_bullet_trail.add_child(_bullet_trail_quad1)

		# Quad 2（垂直面）- Quad1と同じ回転 + ローカルY軸で90度回転
		_bullet_trail_quad2 = MeshInstance3D.new()
		var mesh2 = QuadMesh.new()
		mesh2.size = Vector2(BULLET_TRAIL_WIDTH, 1.0)
		_bullet_trail_quad2.mesh = mesh2
		_bullet_trail_quad2.rotation_degrees.x = 90  # Quad1と同じ
		_bullet_trail_quad2.rotate_object_local(Vector3.UP, deg_to_rad(90))  # ローカルY軸（弾道方向）周りに90度
		_bullet_trail_quad2.material_override = _bullet_trail_mat
		_bullet_trail.add_child(_bullet_trail_quad2)

		# ワールド空間に追加
		get_tree().root.add_child(_bullet_trail)

	# Quadサイズを長さに合わせて更新
	var quad1_mesh = _bullet_trail_quad1.mesh as QuadMesh
	var quad2_mesh = _bullet_trail_quad2.mesh as QuadMesh
	if quad1_mesh:
		quad1_mesh.size = Vector2(BULLET_TRAIL_WIDTH, length)
	if quad2_mesh:
		quad2_mesh.size = Vector2(BULLET_TRAIL_WIDTH, length)

	# トレイルの位置（中点）と向き
	_bullet_trail.global_position = (start + end) * 0.5
	_bullet_trail.look_at(end, Vector3.UP)

	# 表示・アルファリセット
	_bullet_trail.visible = true
	if _bullet_trail_mat:
		_bullet_trail_mat.set_shader_parameter("overall_alpha", 1.0)

	# Tweenでフェードアウト
	_bullet_trail_tween = create_tween()
	_bullet_trail_tween.tween_method(
		func(alpha: float): _bullet_trail_mat.set_shader_parameter("overall_alpha", alpha),
		1.0,
		0.0,
		BULLET_TRAIL_DURATION
	)
	_bullet_trail_tween.tween_callback(func(): _bullet_trail.visible = false)


# ============================================
# Death Processing
# ============================================

## 壁検出用定数
const WALL_DETECT_DISTANCE := 1.2  # 壁検出レイキャスト距離
const WALL_COLLISION_MASK := 2  # 壁コリジョンマスク

## 4方向の壁を検出（死亡アニメーション選択用）
## @return Dictionary { HitDirection(int) -> bool } 壁があればtrue
func _detect_nearby_walls() -> Dictionary:
	# HitDirection: FRONT=0, BACK=1, LEFT=2, RIGHT=3
	var result := { 0: false, 1: false, 2: false, 3: false }

	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return result

	var origin := global_position + Vector3(0, 0.8, 0)  # 胴体高さ
	var forward := global_transform.basis.z.normalized()
	forward.y = 0
	var right := forward.cross(Vector3.UP).normalized()

	var directions := {
		0: forward,    # FRONT
		1: -forward,   # BACK
		2: -right,     # LEFT
		3: right,      # RIGHT
	}

	for dir_idx in directions:
		var direction: Vector3 = directions[dir_idx]
		var query := PhysicsRayQueryParameters3D.create(
			origin, origin + direction * WALL_DETECT_DISTANCE, WALL_COLLISION_MASK
		)
		query.exclude = [get_rid()]
		if space_state.intersect_ray(query):
			result[dir_idx] = true

	return result


## 壁を避けた最適な死亡方向を選択
## @param hit_direction 被弾方向（HitDirection）
## @param walls 壁検出結果（_detect_nearby_walls()の戻り値）
## @return 安全な被弾方向（HitDirection）
func _select_safe_death_direction(hit_direction: int, walls: Dictionary) -> int:
	# 被弾方向 → 倒れる方向のマッピング
	# FRONT(0)から撃たれた → BACK(1)方向に倒れる（death_forwardアニメ）
	# BACK(1)から撃たれた → FRONT(0)方向に倒れる（death_backwardアニメ）
	# LEFT(2)から撃たれた → RIGHT(3)方向に倒れる（death_leftがないので注意）
	# RIGHT(3)から撃たれた → LEFT(2)方向に倒れる（death_rightアニメ）
	var fall_map := { 0: 1, 1: 0, 2: 3, 3: 2 }
	var fall_dir: int = fall_map[hit_direction]

	# 第1候補: 被弾方向の反対側に倒れる（壁がなければOK）
	if not walls[fall_dir]:
		return hit_direction

	# 第2候補: 他の安全な方向を探す
	# 優先順位: 後ろ(1) > 前(0) > 右(3)
	# LEFT(2)への被弾はdeath_leftがないのでスキップ
	var priority := [1, 0, 3]  # BACK, FRONT, RIGHT
	for check_hit_dir in priority:
		if check_hit_dir == hit_direction:
			continue
		var check_fall_dir: int = fall_map[check_hit_dir]
		if not walls[check_fall_dir]:
			return check_hit_dir

	# 全方向に壁 → 元の方向をそのまま使用
	return hit_direction


func _die(killer: Node3D = null, is_headshot: bool = false) -> void:
	is_alive = false

	# Play death animation via CharacterAnimationController
	if anim_ctrl and anim_ctrl.has_method("play_death"):
		var hit_dir := _calculate_hit_direction(killer)
		# 壁を検出して安全な方向を選択
		var walls := _detect_nearby_walls()
		var safe_hit_dir := _select_safe_death_direction(hit_dir, walls)
		anim_ctrl.play_death(safe_hit_dir, is_headshot)

	# Disable vision on death
	if vision:
		vision.disable()

	# Clear combat awareness target on death
	if combat_awareness and combat_awareness.has_method("clear_target"):
		combat_awareness.clear_target()

	# Hide character label (A, B, etc.)
	_hide_character_label()

	# Make corpse passable by other characters but keep ground collision
	_make_corpse_passable()

	# Emit died signal for path cleanup
	died.emit(self)

## Calculate HitDirection from attacker position
func _calculate_hit_direction(attacker: Node3D) -> int:
	if attacker == null:
		return 0  # FRONT

	var to_attacker := (attacker.global_position - global_position).normalized()
	to_attacker.y = 0

	var forward := global_transform.basis.z  # +Z forward
	forward.y = 0
	forward = forward.normalized()

	var angle := rad_to_deg(forward.signed_angle_to(to_attacker, Vector3.UP))

	# CharacterAnimationController.HitDirection
	# FRONT = 0, BACK = 1, LEFT = 2, RIGHT = 3
	if abs(angle) < 45:
		return 0  # FRONT
	elif abs(angle) > 135:
		return 1  # BACK
	elif angle < 0:
		return 2  # LEFT
	else:
		return 3  # RIGHT

## Hide character label (A, B marker above head)
func _hide_character_label() -> void:
	for child in get_children():
		if child.name.begins_with("CharacterLabel_"):
			child.visible = false
			break


## Make corpse passable by other characters while keeping ground collision
func _make_corpse_passable() -> void:
	# Set collision_layer to 0 so other characters don't collide with this corpse
	# Keep collision_mask unchanged so corpse still detects ground
	collision_layer = 0


# ============================================
# Multiplayer API
# ============================================

## ローカルプレイヤーのキャラクターか判定
## シングルプレイヤー時は常にtrue
func is_local() -> bool:
	if owner_peer_id == 0:
		return true  # シングルプレイヤーモード
	return owner_peer_id == PlayerState.get_local_peer_id()


## ネットワークIDを設定
func set_network_id(id: int) -> void:
	network_id = id


## 所有者のpeer_idを設定
func set_owner_peer_id(peer_id: int) -> void:
	owner_peer_id = peer_id


## リモートからの状態更新を適用
## ローカルキャラクターには適用しない（自分の入力が優先）
func apply_remote_state(state: NetworkMessages.CharacterStateMessage) -> void:
	if is_local():
		return  # ローカルキャラクターは自分で状態を管理

	# 補間を有効化し、目標位置を設定
	_remote_interpolation_active = true
	_remote_target_position = state.position
	_remote_target_rotation = state.rotation
	_remote_target_velocity = state.velocity

	# 初回受信時は即座に位置を設定（テレポート防止）
	if global_position.distance_to(state.position) > 5.0:
		global_position = state.position
		set_facing_direction(state.rotation)

	# HPを更新（即座に反映）
	current_health = state.current_health

	# 生存状態を更新（即座に反映）
	if is_alive and not state.is_alive:
		# 死亡 - アニメーションを再生
		is_alive = false
		_remote_interpolation_active = false  # 死亡時は補間停止
		if anim_ctrl and anim_ctrl.has_method("play_death"):
			# リモート死亡の場合はデフォルト方向で再生
			anim_ctrl.play_death(CharacterAnimationController.HitDirection.FRONT, false)
		if vision:
			vision.disable()
		_hide_character_label()
		_make_corpse_passable()
		died.emit(self)
	elif not is_alive and state.is_alive:
		# 復活（通常は起こらないが念のため）
		reset_health()

	# しゃがみ状態を更新（即座に反映）
	if anim_ctrl and state.is_crouching != is_crouching():
		toggle_crouch()


## リモートキャラクターの補間更新（毎フレーム呼び出し）
func update_remote_interpolation(delta: float) -> void:
	if not _remote_interpolation_active or is_local() or not is_alive:
		return

	# 位置の補間
	global_position = global_position.lerp(_remote_target_position, REMOTE_INTERPOLATION_SPEED * delta)

	# 回転の補間
	var current_rot := atan2(_facing_direction.x, _facing_direction.z)
	var target_rot := _remote_target_rotation
	# 角度の差を正規化（-PI〜PI）
	var rot_diff := fmod(target_rot - current_rot + PI, TAU) - PI
	var new_rot := current_rot + rot_diff * REMOTE_INTERPOLATION_SPEED * delta
	set_facing_direction(new_rot)

	# アニメーション更新
	if anim_ctrl:
		var move_dir := _remote_target_velocity.normalized() if _remote_target_velocity.length_squared() > 0.01 else Vector3.ZERO
		var is_running := _remote_target_velocity.length() > 3.0
		anim_ctrl.update_animation(move_dir, _facing_direction, is_running, delta)


## 現在の状態をCharacterStateMessageに変換
func to_character_state() -> NetworkMessages.CharacterStateMessage:
	var state := NetworkMessages.CharacterStateMessage.new()
	state.character_id = network_id if network_id != 0 else get_instance_id()
	state.position = global_position
	state.rotation = atan2(_facing_direction.x, _facing_direction.z)
	state.current_health = int(current_health)
	state.is_alive = is_alive
	state.is_crouching = is_crouching()
	state.velocity = velocity
	state.timestamp = Time.get_ticks_msec()

	# アニメーション状態を取得
	if anim_ctrl and anim_ctrl.has_method("get_current_animation"):
		state.animation_state = anim_ctrl.get_current_animation()

	return state


## 現在の状態をCharacterSnapshotに変換（より詳細）
func to_character_snapshot() -> SyncState.CharacterSnapshot:
	var snapshot := SyncState.CharacterSnapshot.new()
	snapshot.character_id = network_id if network_id != 0 else get_instance_id()
	snapshot.owner_peer_id = owner_peer_id
	snapshot.position = global_position
	snapshot.rotation = atan2(_facing_direction.x, _facing_direction.z)
	snapshot.facing_direction = _facing_direction
	snapshot.velocity = velocity
	snapshot.current_health = current_health
	snapshot.max_health = max_health
	snapshot.is_alive = is_alive
	snapshot.is_crouching = is_crouching()
	snapshot.team = team
	snapshot.timestamp = Time.get_ticks_msec()

	# 武器ID
	if current_weapon:
		snapshot.weapon_id = current_weapon.id

	# アニメーション状態
	if anim_ctrl and anim_ctrl.has_method("get_current_animation"):
		snapshot.animation_state = anim_ctrl.get_current_animation()

	return snapshot


## CharacterSnapshotから状態を復元（リモートキャラクター用）
func apply_character_snapshot(snapshot: SyncState.CharacterSnapshot) -> void:
	if is_local():
		return  # ローカルキャラクターは自分で状態を管理

	global_position = snapshot.position
	set_facing_direction(snapshot.rotation)
	velocity = snapshot.velocity
	current_health = snapshot.current_health

	# 生存状態
	if is_alive and not snapshot.is_alive:
		is_alive = false
		if vision:
			vision.disable()
		_hide_character_label()
		_make_corpse_passable()
		died.emit(self)
	elif not is_alive and snapshot.is_alive:
		reset_health()

	# しゃがみ状態
	if anim_ctrl and snapshot.is_crouching != is_crouching():
		toggle_crouch()


## 状態変更を通知（ネットワーク同期用）
## HPや位置が大きく変わった時に呼ぶ
func notify_state_changed() -> void:
	state_changed.emit(self)
