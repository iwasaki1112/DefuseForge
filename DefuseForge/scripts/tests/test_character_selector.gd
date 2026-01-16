extends Node3D
## Test scene for character selection
## Debug tool to test different characters from CharacterRegistry
## Features:
## - マウスクリックでキャラクター選択
## - 右クリックでコンテキストメニュー表示
## - ドロップダウンからキャラクター追加

const AnimCtrl = preload("res://scripts/animation/character_animation_controller.gd")
const FogOfWarSystemScript = preload("res://scripts/systems/fog_of_war_system.gd")
const ContextMenuScript = preload("res://scripts/ui/context_menu_component.gd")

@onready var camera: Camera3D = $Camera3D
@onready var character_dropdown: OptionButton = $UI/CharacterDropdown
@onready var info_label: Label = $UI/InfoLabel
@onready var ui_layer: CanvasLayer = $UI

var current_character: Node = null
var selected_character: Node = null  ## 現在選択中のキャラクター
var characters: Array[Node] = []  ## シーン内の全キャラクター
var aim_position := Vector3.ZERO
var ground_plane := Plane(Vector3.UP, 0)
var fog_of_war_system: Node3D = null
var context_menu: Control = null  ## コンテキストメニュー
var outlined_meshes: Array[MeshInstance3D] = []  ## アウトライン適用中のメッシュ
var original_materials: Dictionary = {}  ## 元のマテリアルを保存

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
	_setup_fog_of_war()
	_setup_outline_material()
	_setup_context_menu()
	_populate_dropdown()
	character_dropdown.item_selected.connect(_on_character_selected)

	# Spawn first character
	if character_dropdown.item_count > 0:
		_on_character_selected(0)


func _setup_outline_material() -> void:
	# ステンシルベースのアウトラインはマテリアルのプロパティで設定するため
	# 事前のマテリアル作成は不要
	pass


func _setup_context_menu() -> void:
	context_menu = Control.new()
	context_menu.set_script(ContextMenuScript)
	context_menu.name = "ContextMenu"
	ui_layer.add_child(context_menu)
	context_menu.setup_default_items()
	context_menu.item_selected.connect(_on_context_menu_item_selected)


func _setup_fog_of_war() -> void:
	fog_of_war_system = Node3D.new()
	fog_of_war_system.set_script(FogOfWarSystemScript)
	fog_of_war_system.name = "FogOfWarSystem"
	fog_of_war_system.map_size = Vector2(50, 50)  # Match floor size
	add_child(fog_of_war_system)

func _populate_dropdown() -> void:
	character_dropdown.clear()

	# Add CT characters
	var cts = CharacterRegistry.get_counter_terrorists()
	for preset in cts:
		character_dropdown.add_item("[CT] %s" % preset.display_name)
		character_dropdown.set_item_metadata(character_dropdown.item_count - 1, preset.id)

	# Add T characters
	var ts = CharacterRegistry.get_terrorists()
	for preset in ts:
		character_dropdown.add_item("[T] %s" % preset.display_name)
		character_dropdown.set_item_metadata(character_dropdown.item_count - 1, preset.id)

func _on_character_selected(index: int) -> void:
	var preset_id: String = character_dropdown.get_item_metadata(index)
	_spawn_character(preset_id)

func _spawn_character(preset_id: String) -> void:
	# Unregister old vision from FoW
	if current_character and current_character.vision and fog_of_war_system:
		fog_of_war_system.unregister_vision(current_character.vision)

	# Remove current character
	if current_character:
		characters.erase(current_character)
		current_character.queue_free()
		current_character = null

	# Create new character
	current_character = CharacterRegistry.create_character(preset_id, Vector3.ZERO)
	if current_character:
		add_child(current_character)
		characters.append(current_character)
		selected_character = null  # 生成時は未選択状態
		_setup_character_vision()
		_update_info_label(preset_id)
		_clear_outline()  # アウトラインをクリア


func _setup_character_vision() -> void:
	if not current_character:
		return

	# Setup vision component
	var vision = current_character.setup_vision(90.0, 15.0)

	# Register with FoW system
	if fog_of_war_system and vision:
		await get_tree().process_frame  # Wait for VisionComponent to initialize
		fog_of_war_system.register_vision(vision)

func _update_info_label(preset_id: String) -> void:
	var preset = CharacterRegistry.get_preset(preset_id)
	if preset:
		info_label.text = """Character: %s (%s)
Team: %s
HP: %.0f
FoW: Active (FOV: 90°, Range: 15m)

Controls:
Left Click: Select | Right Click: Menu
WASD: Move | Shift: Run | C: Crouch
F: Aim | Space+F: Fire
1/2: Weapon | K: Die | R: Respawn
Esc: Mouse mode""" % [
			preset.display_name,
			preset.id,
			"CT" if preset.team == 1 else "T",
			preset.max_health
		]

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CONFINED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)

	# マウスクリック処理
	if event is InputEventMouseButton and event.pressed:
		_handle_mouse_click(event)

	if not selected_character:
		return

	var anim_ctrl = selected_character.get_anim_controller()
	if not anim_ctrl:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				anim_ctrl.set_weapon(AnimCtrl.Weapon.RIFLE)
			KEY_2:
				anim_ctrl.set_weapon(AnimCtrl.Weapon.PISTOL)
			KEY_K:
				selected_character.take_damage(selected_character.max_health)
			KEY_R:
				# Respawn
				var index = character_dropdown.selected
				if index >= 0:
					_on_character_selected(index)


## マウスクリック処理
func _handle_mouse_click(event: InputEventMouseButton) -> void:
	# コンテキストメニューが開いている場合は閉じる処理に任せる
	if context_menu and context_menu.is_open():
		return

	var clicked_character = _raycast_character(event.position)

	match event.button_index:
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
			# クリック: キャラクター選択 + コンテキストメニュー表示
			if clicked_character:
				_select_character(clicked_character)
				_show_context_menu(event.position, clicked_character)


## レイキャストでキャラクターを検出
func _raycast_character(screen_pos: Vector2) -> Node:
	if not camera:
		return null

	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var ray_end := ray_origin + ray_dir * 100.0

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return null

	# キャラクターを探す（衝突したコライダーの親を辿る）
	var collider = result.collider
	for character in characters:
		if _is_child_of(collider, character):
			return character
	return null


## ノードが親の子孫かどうか
func _is_child_of(child: Node, parent: Node) -> bool:
	var node = child
	while node:
		if node == parent:
			return true
		node = node.get_parent()
	return false


## キャラクターを選択
func _select_character(character: Node) -> void:
	selected_character = character
	current_character = character
	var preset_id = _get_character_preset_id(character)
	if preset_id:
		_update_info_label(preset_id)
	# 選択アウトラインを表示
	_show_selection_outline(character)


## 選択アウトラインを表示
func _show_selection_outline(character: Node) -> void:
	# 既存のアウトラインを削除
	_clear_outline()
	# 選択キャラクターにアウトラインを適用
	if character:
		_apply_outline(character)


## アウトラインを適用（ステンシル方式）
func _apply_outline(character: Node) -> void:
	var meshes = _find_mesh_instances(character)
	print("[Outline] Found %d meshes in %s" % [meshes.size(), character.name])

	for mesh in meshes:
		var surface_count = mesh.mesh.get_surface_count() if mesh.mesh else 0
		print("[Outline] Mesh %s has %d surfaces" % [mesh.name, surface_count])
		for i in range(surface_count):
			var mat = mesh.get_active_material(i)
			print("[Outline] Surface %d material type: %s" % [i, mat.get_class() if mat else "null"])
			if mat and mat is StandardMaterial3D:
				# 元のマテリアルを保存
				var key = "%s_%d" % [mesh.get_instance_id(), i]
				original_materials[key] = mat

				# マテリアルを複製してステンシルアウトラインを設定
				var mat_copy: StandardMaterial3D = mat.duplicate()
				mat_copy.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE
				mat_copy.stencil_outline_thickness = 3.5
				mat_copy.stencil_color = Color(0.0, 0.8, 1.0, 1.0)
				mesh.set_surface_override_material(i, mat_copy)
				print("[Outline] Stencil mode set to: %d, thickness: %f" % [mat_copy.stencil_mode, mat_copy.stencil_outline_thickness])
			elif mat:
				print("[Outline] Material is not StandardMaterial3D, trying to convert...")
				# 新しいStandardMaterial3Dを作成
				var new_mat = StandardMaterial3D.new()
				new_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE
				new_mat.stencil_outline_thickness = 3.5
				new_mat.stencil_color = Color(0.0, 0.8, 1.0, 1.0)
				mesh.set_surface_override_material(i, new_mat)
				print("[Outline] Created new StandardMaterial3D with stencil outline")
		outlined_meshes.append(mesh)
		print("[Outline] Applied outline to: %s" % mesh.name)


## アウトラインを削除
func _clear_outline() -> void:
	for mesh in outlined_meshes:
		if is_instance_valid(mesh):
			# サーフェスオーバーライドをクリア（元のマテリアルに戻る）
			var surface_count = mesh.mesh.get_surface_count() if mesh.mesh else 0
			for i in range(surface_count):
				mesh.set_surface_override_material(i, null)
	outlined_meshes.clear()
	original_materials.clear()


## MeshInstance3Dを再帰的に探す
func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_mesh_instances(child))
	return result


## キャラクターのプリセットIDを取得
func _get_character_preset_id(character: Node) -> String:
	if character.has_method("get_preset_id"):
		return character.get_preset_id()
	# プリセットIDがない場合は名前から推測
	return character.name.to_snake_case()


## コンテキストメニューを表示
func _show_context_menu(screen_pos: Vector2, character: Node) -> void:
	if context_menu:
		context_menu.open(screen_pos, character)


## コンテキストメニューアイテム選択時
func _on_context_menu_item_selected(action_id: String, character: CharacterBody3D) -> void:
	match action_id:
		"move":
			_start_move_mode(character)
		"rotate":
			_start_rotate_mode(character)
		"control":
			_start_control_mode(character)


## 移動モード開始
func _start_move_mode(character: Node) -> void:
	print("[ContextMenu] Move mode for: ", character.name)
	# TODO: 移動モードの実装


## 回転モード開始
func _start_rotate_mode(character: Node) -> void:
	print("[ContextMenu] Rotate mode for: ", character.name)
	# TODO: 回転モードの実装


## 操作モード開始
func _start_control_mode(character: Node) -> void:
	print("[ContextMenu] Control mode for: ", character.name)
	selected_character = character
	current_character = character
	var preset_id = _get_character_preset_id(character)
	if preset_id:
		_update_info_label(preset_id)

func _physics_process(delta: float) -> void:
	if not selected_character:
		return

	if not selected_character.is_alive:
		return

	var anim_ctrl = selected_character.get_anim_controller()
	if not anim_ctrl:
		return

	_update_aim_position()

	# Get input
	var move_dir := Vector3(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		0,
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	var aim_dir: Vector3 = aim_position - selected_character.global_position
	aim_dir.y = 0
	var is_running := Input.is_key_pressed(KEY_SHIFT)

	# Update animation
	anim_ctrl.update_animation(move_dir, aim_dir, is_running, delta)

	# Set state
	anim_ctrl.set_stance(
		AnimCtrl.Stance.CROUCH if Input.is_key_pressed(KEY_C)
		else AnimCtrl.Stance.STAND
	)
	anim_ctrl.set_aiming(Input.is_key_pressed(KEY_F))

	# Fire action
	if Input.is_key_pressed(KEY_SPACE) and Input.is_key_pressed(KEY_F):
		anim_ctrl.fire()

	# Movement
	var speed: float = anim_ctrl.get_current_speed()
	if move_dir.length() > 0.1:
		selected_character.velocity.x = move_dir.normalized().x * speed
		selected_character.velocity.z = move_dir.normalized().z * speed
	else:
		selected_character.velocity.x = 0
		selected_character.velocity.z = 0

	if not selected_character.is_on_floor():
		selected_character.velocity.y -= 9.8 * delta

	selected_character.move_and_slide()


func _update_aim_position() -> void:
	if not camera:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)

	var intersection = ground_plane.intersects_ray(ray_origin, ray_dir)
	if intersection:
		aim_position = intersection
