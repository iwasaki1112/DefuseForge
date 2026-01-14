class_name OutlineComponent
extends Node

## 選択アウトラインエフェクトコンポーネント
## SubViewportマスク + エッジ検出でシルエットのみ表示

signal outline_toggled(enabled: bool)

## アウトライン設定
@export var outline_color: Color = Color(0.0, 0.8, 1.0, 1.0)
@export var line_width: float = 2.0
@export var emission_energy: float = 1.0

## 内部変数
var _is_selected: bool = false
var _character: Node3D
var _main_camera: Camera3D

## SubViewport関連
var _mask_viewport: SubViewport
var _mask_camera: Camera3D
var _mask_material: ShaderMaterial
var _edge_canvas_layer: CanvasLayer
var _edge_rect: ColorRect
var _edge_material: ShaderMaterial

## メッシュ複製用
var _mask_meshes: Array[MeshInstance3D] = []

const MASK_SHADER_PATH := "res://shaders/silhouette_mask.gdshader"
const EDGE_SHADER_PATH := "res://shaders/silhouette_edge_detect.gdshader"
const MASK_LAYER := 20  # 専用レイヤー


func _ready() -> void:
	_create_mask_material()
	_create_edge_material()


func _process(_delta: float) -> void:
	if _is_selected and _main_camera and _mask_camera:
		_sync_camera()


## メインカメラとキャラクターでセットアップ
func setup(character: Node3D, main_camera: Camera3D) -> void:
	_character = character
	_main_camera = main_camera

	# メインカメラからマスクレイヤーを除外
	if _main_camera:
		_main_camera.cull_mask &= ~(1 << (MASK_LAYER - 1))

	_setup_mask_viewport()
	_setup_edge_overlay()


func _create_mask_material() -> void:
	var shader = load(MASK_SHADER_PATH)
	if shader == null:
		push_warning("[OutlineComponent] Mask shader not found: %s" % MASK_SHADER_PATH)
		return

	_mask_material = ShaderMaterial.new()
	_mask_material.shader = shader


func _create_edge_material() -> void:
	var shader = load(EDGE_SHADER_PATH)
	if shader == null:
		push_warning("[OutlineComponent] Edge shader not found: %s" % EDGE_SHADER_PATH)
		return

	_edge_material = ShaderMaterial.new()
	_edge_material.shader = shader
	_edge_material.set_shader_parameter("outline_color", outline_color)
	_edge_material.set_shader_parameter("line_width", line_width)
	_edge_material.set_shader_parameter("emission_energy", emission_energy)


func _setup_mask_viewport() -> void:
	if _mask_viewport:
		return

	# SubViewport作成
	_mask_viewport = SubViewport.new()
	_mask_viewport.name = "OutlineMaskViewport"
	_mask_viewport.size = Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1920),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1080)
	)
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_mask_viewport.transparent_bg = true
	_mask_viewport.world_3d = _character.get_world_3d()  # 同じワールドを共有
	add_child(_mask_viewport)

	# マスク用カメラ作成
	_mask_camera = Camera3D.new()
	_mask_camera.name = "MaskCamera"
	_mask_camera.cull_mask = 1 << (MASK_LAYER - 1)  # マスクレイヤーのみ
	_mask_camera.current = true
	_mask_viewport.add_child(_mask_camera)


func _setup_edge_overlay() -> void:
	if _edge_canvas_layer:
		return

	# CanvasLayer作成（最前面に表示）
	_edge_canvas_layer = CanvasLayer.new()
	_edge_canvas_layer.name = "OutlineCanvasLayer"
	_edge_canvas_layer.layer = 100
	_edge_canvas_layer.visible = false
	add_child(_edge_canvas_layer)

	# 全画面ColorRect作成
	_edge_rect = ColorRect.new()
	_edge_rect.name = "OutlineRect"
	_edge_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_canvas_layer.add_child(_edge_rect)


func _sync_camera() -> void:
	if _main_camera and _mask_camera:
		_mask_camera.global_transform = _main_camera.global_transform
		_mask_camera.fov = _main_camera.fov
		_mask_camera.near = _main_camera.near
		_mask_camera.far = _main_camera.far

	# ビューポートサイズ同期
	if _mask_viewport:
		var main_viewport = _character.get_viewport()
		if main_viewport:
			_mask_viewport.size = main_viewport.size


## アウトライン表示切替
func set_selected(selected: bool) -> void:
	if _is_selected == selected:
		return

	_is_selected = selected

	if _is_selected:
		_apply_outline()
	else:
		_remove_outline()

	outline_toggled.emit(_is_selected)


func is_selected() -> bool:
	return _is_selected


func _apply_outline() -> void:
	if _mask_material == null or _edge_material == null:
		push_warning("[OutlineComponent] Materials not ready")
		return

	# カメラを同期してから表示（チラつき防止）
	_sync_camera()

	# キャラクターのメッシュをマスクレイヤーに複製
	_create_mask_meshes()

	# エッジシェーダーにマスクテクスチャを設定
	if _mask_viewport and _edge_material:
		_edge_material.set_shader_parameter("mask_texture", _mask_viewport.get_texture())

	# エッジオーバーレイを表示
	if _edge_rect:
		_edge_rect.material = _edge_material

	if _edge_canvas_layer:
		_edge_canvas_layer.visible = true


func _remove_outline() -> void:
	# マスクメッシュを削除
	_clear_mask_meshes()

	# エッジオーバーレイを非表示
	if _edge_canvas_layer:
		_edge_canvas_layer.visible = false


func _create_mask_meshes() -> void:
	_clear_mask_meshes()

	# キャラクターの全MeshInstance3Dを検索して複製
	var meshes: Array[MeshInstance3D] = []
	_find_mesh_instances_recursive(_character, meshes)

	for original_mesh in meshes:
		var mask_mesh = MeshInstance3D.new()
		mask_mesh.mesh = original_mesh.mesh
		mask_mesh.skin = original_mesh.skin
		mask_mesh.material_override = _mask_material
		mask_mesh.layers = 1 << (MASK_LAYER - 1)

		# 元メッシュと同じ親に追加（スケルトンパスを維持）
		var parent = original_mesh.get_parent()
		if parent:
			parent.add_child(mask_mesh)
			mask_mesh.global_transform = original_mesh.global_transform
			# スケルトンパスを元メッシュと同じに設定
			mask_mesh.skeleton = original_mesh.skeleton

		_mask_meshes.append(mask_mesh)


func _clear_mask_meshes() -> void:
	for mesh in _mask_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_mask_meshes.clear()


func _find_mesh_instances_recursive(node: Node, result: Array[MeshInstance3D]) -> void:
	# LaserPointerとその子は除外
	if node.name == "LaserPointer" or node.name.begins_with("Laser"):
		return
	# MuzzleFlashとその子は除外
	if node.name == "MuzzleFlash" or node.name.begins_with("Muzzle"):
		return

	if node is MeshInstance3D:
		result.append(node)

	for child in node.get_children():
		_find_mesh_instances_recursive(child, result)


func set_outline_color(color: Color) -> void:
	outline_color = color
	if _edge_material:
		_edge_material.set_shader_parameter("outline_color", color)


func set_outline_width(width: float) -> void:
	line_width = width
	if _edge_material:
		_edge_material.set_shader_parameter("line_width", width)


func set_emission_energy(energy: float) -> void:
	emission_energy = energy
	if _edge_material:
		_edge_material.set_shader_parameter("emission_energy", energy)
