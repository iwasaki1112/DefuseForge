class_name SelectionOutlineEffect
extends CanvasLayer

## シルエットベースの選択アウトライン効果
## SubViewportでマスクを作成し、エッジ検出でアウトラインを描画

@export var line_width: float = 4.0
@export var outline_color: Color = Color(0.0, 1.0, 0.8, 1.0)
@export var emission_energy: float = 3.0

var _mask_viewport: SubViewport
var _mask_camera: Camera3D
var _outline_rect: ColorRect
var _outline_material: ShaderMaterial
var _mask_material: ShaderMaterial
var _selected_meshes: Array[MeshInstance3D] = []
var _original_materials: Dictionary = {}  # mesh -> array of materials
var _main_camera: Camera3D
var _is_active: bool = false

func _ready() -> void:
	layer = 100  # UIより上に表示
	_setup_mask_viewport()
	_setup_outline_rect()
	# 初期状態では非表示
	_outline_rect.visible = false


func _setup_mask_viewport() -> void:
	_mask_viewport = SubViewport.new()
	_mask_viewport.name = "MaskViewport"
	_mask_viewport.transparent_bg = true
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_mask_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	# 独自のワールドを使用（メインシーンと分離）
	_mask_viewport.own_world_3d = true
	_mask_viewport.world_3d = World3D.new()
	add_child(_mask_viewport)

	# マスク用カメラ
	_mask_camera = Camera3D.new()
	_mask_camera.name = "MaskCamera"
	_mask_camera.current = true
	_mask_viewport.add_child(_mask_camera)

	# 白色マスク用マテリアル
	var mask_shader = Shader.new()
	mask_shader.code = """
shader_type spatial;
render_mode unshaded;

void fragment() {
	ALBEDO = vec3(1.0);
}
"""
	_mask_material = ShaderMaterial.new()
	_mask_material.shader = mask_shader


func _setup_outline_rect() -> void:
	_outline_rect = ColorRect.new()
	_outline_rect.name = "OutlineRect"
	_outline_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_outline_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline_rect.visible = false
	add_child(_outline_rect)

	var shader = load("res://shaders/silhouette_edge_detect.gdshader")
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = shader
	_outline_material.set_shader_parameter("line_width", line_width)
	_outline_material.set_shader_parameter("outline_color", outline_color)
	_outline_material.set_shader_parameter("emission_energy", emission_energy)
	_outline_rect.material = _outline_material


func _process(_delta: float) -> void:
	if not _is_active:
		return
	_sync_camera()
	_sync_viewport_size()
	_update_outline_texture()


func _sync_camera() -> void:
	if not _main_camera or not is_instance_valid(_main_camera):
		_main_camera = get_viewport().get_camera_3d()

	if _main_camera and _mask_camera:
		_mask_camera.global_transform = _main_camera.global_transform
		_mask_camera.fov = _main_camera.fov
		_mask_camera.projection = _main_camera.projection
		_mask_camera.size = _main_camera.size
		_mask_camera.near = _main_camera.near
		_mask_camera.far = _main_camera.far


func _sync_viewport_size() -> void:
	var size = get_viewport().get_visible_rect().size
	if _mask_viewport.size != Vector2i(size):
		_mask_viewport.size = Vector2i(size)


func _update_outline_texture() -> void:
	if _mask_viewport:
		_outline_material.set_shader_parameter("mask_texture", _mask_viewport.get_texture())


## 選択アウトラインを表示
func show_outline(character: Node) -> void:
	clear_outline()

	if not character:
		return

	# メッシュを収集
	_collect_meshes(character)

	# 各メッシュをマスクビューポートに複製
	for mesh in _selected_meshes:
		_add_mesh_to_mask(mesh)

	_is_active = true
	_outline_rect.visible = true


## アウトラインをクリア
func clear_outline() -> void:
	# マスクビューポートのメッシュを削除（カメラ以外）
	for child in _mask_viewport.get_children():
		if child != _mask_camera:
			child.queue_free()

	_selected_meshes.clear()
	_original_materials.clear()
	_is_active = false
	_outline_rect.visible = false


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		_selected_meshes.append(node)
	for child in node.get_children():
		_collect_meshes(child)


func _add_mesh_to_mask(original_mesh: MeshInstance3D) -> void:
	# メッシュの複製を作成
	var mask_mesh = MeshInstance3D.new()
	mask_mesh.mesh = original_mesh.mesh
	mask_mesh.skeleton = NodePath()  # スケルトンパスをクリア
	mask_mesh.material_override = _mask_material

	# 元のメッシュにリンク（トランスフォーム同期用）
	mask_mesh.set_meta("source_mesh", original_mesh)

	_mask_viewport.add_child(mask_mesh)


func _physics_process(_delta: float) -> void:
	if not _is_active:
		return
	# マスクメッシュのトランスフォームを同期
	for child in _mask_viewport.get_children():
		if child is MeshInstance3D and child.has_meta("source_mesh"):
			var source: MeshInstance3D = child.get_meta("source_mesh")
			if is_instance_valid(source):
				child.global_transform = source.global_transform


## アウトラインの設定を更新
func set_line_width(width: float) -> void:
	line_width = width
	if _outline_material:
		_outline_material.set_shader_parameter("line_width", line_width)


func set_outline_color(color: Color) -> void:
	outline_color = color
	if _outline_material:
		_outline_material.set_shader_parameter("outline_color", outline_color)


func set_emission_energy(energy: float) -> void:
	emission_energy = energy
	if _outline_material:
		_outline_material.set_shader_parameter("emission_energy", emission_energy)
