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
# Signals (reserved for future use)
# ============================================

# ============================================
# Export Settings
# ============================================
@export_group("HP Settings")
@export var max_health: float = 100.0

@export_group("Team Settings")
@export var team: Team = Team.NONE

# ============================================
# State
# ============================================
var current_health: float = 100.0
var is_alive: bool = true

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
			return target.global_position + Vector3(0, 1.2, 0)

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
	var mesh1 = _bullet_trail_quad1.mesh as QuadMesh
	var mesh2 = _bullet_trail_quad2.mesh as QuadMesh
	if mesh1:
		mesh1.size = Vector2(BULLET_TRAIL_WIDTH, length)
	if mesh2:
		mesh2.size = Vector2(BULLET_TRAIL_WIDTH, length)

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

func _die(killer: Node3D = null, is_headshot: bool = false) -> void:
	is_alive = false

	# Play death animation via CharacterAnimationController
	if anim_ctrl and anim_ctrl.has_method("play_death"):
		var hit_dir := _calculate_hit_direction(killer)
		anim_ctrl.play_death(hit_dir, is_headshot)

	# Disable vision on death
	if vision:
		vision.disable()

	# Clear combat awareness target on death
	if combat_awareness and combat_awareness.has_method("clear_target"):
		combat_awareness.clear_target()

	# Make corpse passable by other characters but keep ground collision
	_make_corpse_passable()

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

## Make corpse passable by other characters while keeping ground collision
func _make_corpse_passable() -> void:
	# Set collision_layer to 0 so other characters don't collide with this corpse
	# Keep collision_mask unchanged so corpse still detects ground
	collision_layer = 0
