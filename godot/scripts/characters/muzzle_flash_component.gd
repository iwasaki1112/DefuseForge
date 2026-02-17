class_name MuzzleFlashComponent
extends RefCounted

## マズルフラッシュコンポーネント
## 射撃時のマズルフラッシュエフェクト表示を管理
## GameCharacterから抽出されたコンポーネント

# ============================================
# Constants
# ============================================

var MUZZLE_FLASH_TEXTURE: Texture2D = null
const MUZZLE_FLASH_BASE_SIZE: float = 0.25
const MUZZLE_FLASH_SCALE_MULTIPLIER: float = 2.0  ## ARP 1.0スケール用（旧Mixamo 0.01時代は200.0）
const MUZZLE_FLASH_DURATION: float = 0.09  # 3フレーム × 0.03秒/フレーム
const MUZZLE_FLASH_FRAME_TIME: float = 0.03  # 各フレームの表示時間

# ============================================
# References
# ============================================

var _character: Node3D = null
var _weapon_socket: Node3D = null

# ============================================
# State
# ============================================

var _muzzle_flash: Node3D = null
var _muzzle_flash_mat: StandardMaterial3D = null
var _muzzle_flash_light: OmniLight3D = null
var _muzzle_flash_tween: Tween = null
var _muzzle_flash_preview_enabled: bool = false
var _muzzle_flash_quad1: MeshInstance3D = null
var _muzzle_flash_quad1_x_offset: float = 0.032
var _muzzle_flash_quad1_z_offset: float = 0.026

# ============================================
# Setup
# ============================================

func _init() -> void:
	MUZZLE_FLASH_TEXTURE = load("res://assets/effects/muzzle_flash_sprite_sheet.jpg")


## セットアップ
func setup(character: Node3D, weapon_socket: Node3D) -> void:
	_character = character
	_weapon_socket = weapon_socket


## 武器ソケットを更新
func set_weapon_socket(socket: Node3D) -> void:
	_weapon_socket = socket


## ウォームアップ: ノード生成とマテリアル作成を事前に行う
func warm_up() -> void:
	if not _muzzle_flash or not is_instance_valid(_muzzle_flash):
		_create()

# ============================================
# Public API
# ============================================

## マズルフラッシュを再生
func play(current_weapon: Resource, weapon_model: Node3D) -> void:
	if _muzzle_flash_preview_enabled:
		_ensure_visible(current_weapon, weapon_model)
		return
	if not _weapon_socket:
		return
	if not _muzzle_flash or not is_instance_valid(_muzzle_flash):
		_create()
	if not _muzzle_flash:
		return

	_muzzle_flash.position = _get_offset(current_weapon, weapon_model)
	_muzzle_flash.rotation_degrees = _get_rotation(current_weapon)

	var base_scale = _get_scale(current_weapon)
	_muzzle_flash.scale = Vector3.ONE * base_scale
	_muzzle_flash.visible = true

	if _muzzle_flash_tween and _muzzle_flash_tween.is_running():
		_muzzle_flash_tween.kill()

	if _muzzle_flash_mat:
		_muzzle_flash_mat.albedo_color = Color(1, 1, 1, 1)
		_muzzle_flash_mat.uv1_offset = Vector3(0.0, 0.0, 0.0)
	if _muzzle_flash_light:
		_muzzle_flash_light.light_energy = 3.0

	_muzzle_flash_tween = _character.create_tween() if _character else null
	if not _muzzle_flash_tween:
		return

	# スプライトシートアニメーション
	if _muzzle_flash_mat:
		_muzzle_flash_tween.tween_callback(func():
			_muzzle_flash_mat.uv1_offset = Vector3(1.0 / 3.0, 0.0, 0.0)
		).set_delay(MUZZLE_FLASH_FRAME_TIME)
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


## プレビュー有効/無効設定
func set_preview(enabled: bool, current_weapon: Resource, weapon_model: Node3D) -> void:
	_muzzle_flash_preview_enabled = enabled
	if not enabled:
		if _muzzle_flash:
			_muzzle_flash.visible = false
		if _muzzle_flash_tween and _muzzle_flash_tween.is_running():
			_muzzle_flash_tween.kill()
		return
	_ensure_visible(current_weapon, weapon_model)


## プレビュー更新
func update_preview(current_weapon: Resource, weapon_model: Node3D) -> void:
	if not _muzzle_flash_preview_enabled:
		return
	_ensure_visible(current_weapon, weapon_model)


## マズルフラッシュのワールド位置を取得
func get_world_position() -> Vector3:
	if not _weapon_socket or not is_instance_valid(_weapon_socket):
		return Vector3.ZERO
	if _muzzle_flash and is_instance_valid(_muzzle_flash):
		return _muzzle_flash.global_position
	return Vector3.ZERO


## Quad1 Xオフセット設定
func set_quad1_x(x_offset: float) -> void:
	_muzzle_flash_quad1_x_offset = x_offset
	if _muzzle_flash_quad1 and is_instance_valid(_muzzle_flash_quad1):
		_muzzle_flash_quad1.position.x = x_offset


## Quad1 Xオフセット取得
func get_quad1_x() -> float:
	return _muzzle_flash_quad1_x_offset


## Quad1 Zオフセット設定
func set_quad1_z(z_offset: float) -> void:
	_muzzle_flash_quad1_z_offset = z_offset
	if _muzzle_flash_quad1 and is_instance_valid(_muzzle_flash_quad1):
		_muzzle_flash_quad1.position.z = z_offset


## Quad1 Zオフセット取得
func get_quad1_z() -> float:
	return _muzzle_flash_quad1_z_offset

# ============================================
# Internal
# ============================================

func _ensure_visible(current_weapon: Resource, weapon_model: Node3D) -> void:
	if not _weapon_socket:
		return
	if not _muzzle_flash or not is_instance_valid(_muzzle_flash):
		_create()
	if not _muzzle_flash:
		return

	_muzzle_flash.position = _get_offset(current_weapon, weapon_model)
	_muzzle_flash.rotation_degrees = _get_rotation(current_weapon)
	_muzzle_flash.scale = Vector3.ONE * _get_scale(current_weapon)
	if _muzzle_flash_mat:
		_muzzle_flash_mat.albedo_color = Color(1, 1, 1, 1)
		_muzzle_flash_mat.uv1_offset = Vector3(0.0, 0.0, 0.0)
	if _muzzle_flash_light:
		_muzzle_flash_light.light_energy = 3.0
	_muzzle_flash.visible = true


func _create() -> void:
	if not _weapon_socket or not is_instance_valid(_weapon_socket):
		return

	_muzzle_flash = Node3D.new()
	_muzzle_flash.name = "MuzzleFlash"

	# 共通マテリアル作成（alpha=0で初期化し、GPUシェーダーを事前コンパイルさせる）
	_muzzle_flash_mat = StandardMaterial3D.new()
	_muzzle_flash_mat.albedo_texture = MUZZLE_FLASH_TEXTURE
	_muzzle_flash_mat.albedo_color = Color(1, 1, 1, 0)
	_muzzle_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_muzzle_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_muzzle_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_muzzle_flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_muzzle_flash_mat.emission_enabled = true
	_muzzle_flash_mat.emission_texture = MUZZLE_FLASH_TEXTURE
	_muzzle_flash_mat.emission_energy_multiplier = 1.2
	_muzzle_flash_mat.uv1_scale = Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0)
	_muzzle_flash_mat.uv1_offset = Vector3(0.0, 0.0, 0.0)

	# Quad 1
	_muzzle_flash_quad1 = MeshInstance3D.new()
	var mesh1 = QuadMesh.new()
	mesh1.size = Vector2(MUZZLE_FLASH_BASE_SIZE, MUZZLE_FLASH_BASE_SIZE)
	_muzzle_flash_quad1.mesh = mesh1
	_muzzle_flash_quad1.position = Vector3(_muzzle_flash_quad1_x_offset, 0, _muzzle_flash_quad1_z_offset)
	_muzzle_flash_quad1.rotation_degrees.z = -90
	_muzzle_flash_quad1.material_override = _muzzle_flash_mat
	_muzzle_flash.add_child(_muzzle_flash_quad1)

	# Quad 2
	var quad2 = MeshInstance3D.new()
	var mesh2 = QuadMesh.new()
	mesh2.size = Vector2(MUZZLE_FLASH_BASE_SIZE, MUZZLE_FLASH_BASE_SIZE)
	quad2.mesh = mesh2
	quad2.position = Vector3.ZERO
	quad2.rotation_degrees = Vector3(0, 90, -90)
	quad2.material_override = _muzzle_flash_mat
	_muzzle_flash.add_child(quad2)

	# 光源（energy=0で初期化、play()で3.0に設定）
	_muzzle_flash_light = OmniLight3D.new()
	_muzzle_flash_light.light_color = Color(1.0, 0.6, 0.2)
	_muzzle_flash_light.light_energy = 0.0
	_muzzle_flash_light.omni_range = 2.0
	_muzzle_flash_light.omni_attenuation = 2.0
	_muzzle_flash.add_child(_muzzle_flash_light)

	# visible=trueのままalpha=0/energy=0で追加し、GPUシェーダーを事前コンパイルさせる
	_weapon_socket.add_child(_muzzle_flash)


func _get_scale(current_weapon: Resource) -> float:
	if current_weapon:
		var scale_val = current_weapon.get("muzzle_flash_scale")
		if scale_val != null:
			return maxf(0.01, scale_val) * MUZZLE_FLASH_SCALE_MULTIPLIER
	return MUZZLE_FLASH_SCALE_MULTIPLIER


func _get_rotation(current_weapon: Resource) -> Vector3:
	if current_weapon:
		var rotation_val = current_weapon.get("muzzle_flash_rotation")
		if rotation_val != null:
			return rotation_val
	return Vector3.ZERO


func _get_offset(current_weapon: Resource, weapon_model: Node3D) -> Vector3:
	if current_weapon and current_weapon.has_method("get"):
		var offset = current_weapon.get("muzzle_flash_offset")
		if offset != null and offset != Vector3.ZERO:
			return offset
	var auto_offset = _calculate_offset_from_model(weapon_model)
	if auto_offset != Vector3.ZERO:
		return auto_offset
	return Vector3(0, 0, -0.25)


func _calculate_offset_from_model(weapon_model: Node3D) -> Vector3:
	if not weapon_model or not weapon_model.is_inside_tree():
		return Vector3.ZERO

	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(weapon_model, meshes)
	if meshes.is_empty():
		return Vector3.ZERO

	# weapon_modelのグローバル逆変換を取得（ネスト対応）
	var model_inverse := weapon_model.global_transform.affine_inverse()

	var combined := AABB()
	var has_aabb := false
	for mesh in meshes:
		if not mesh.is_inside_tree():
			continue
		var local_aabb = mesh.get_aabb()
		# メッシュのグローバル変換をweapon_modelのローカル空間に変換
		var mesh_to_model := model_inverse * mesh.global_transform
		var transformed = _transform_aabb(local_aabb, mesh_to_model)
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
	return Vector3(center.x, center.y, muzzle_z)


func _collect_mesh_instances(node: Node, results: Array[MeshInstance3D]) -> void:
	# ノード自体がMeshInstance3Dの場合も追加（単体メッシュ武器対応）
	if node is MeshInstance3D:
		results.append(node as MeshInstance3D)
	# 子ノードを再帰的に処理
	for child in node.get_children():
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
