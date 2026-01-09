extends Node3D
## Animation viewer - simple animation testing for character models

@onready var camera: Camera3D = $OrbitCamera
@onready var character_body: CharacterBase = $CharacterBody
@onready var canvas_layer: CanvasLayer = $CanvasLayer

var _animations: Array[String] = []
const GRAVITY: float = 9.8
const DEFAULT_BLEND_TIME: float = 0.3
var blend_time: float = DEFAULT_BLEND_TIME
var blend_time_label: Label = null

# UI Panels (created dynamically)
var left_panel: PanelContainer = null  # キャラクター/武器選択
var right_panel: PanelContainer = null  # アニメーション一覧
var bottom_panel: PanelContainer = null  # IK/オフセット調整

# Character selection
const CHARACTERS_DIR: String = "res://assets/characters/"
var available_characters: Array[String] = []  # 利用可能なキャラクターIDリスト
var current_character_id: String = "vanguard"  # 現在選択中のキャラクターID
var character_model: Node3D = null  # 現在のキャラクターモデルノード
var character_option_button: OptionButton = null
var character_resource: Resource = null  # キャラクターリソース (CharacterResource)

# Upper body rotation
var spine_bone_idx: int = -1
var upper_body_rotation: float = 0.0  # -45 to 45 degrees
var upper_body_rotation_label: Label = null
const UPPER_BODY_ROTATION_MIN: float = -45.0
const UPPER_BODY_ROTATION_MAX: float = 45.0

# Weapon attachment
var right_hand_bone_idx: int = -1
var weapon_attachment: BoneAttachment3D = null
var muzzle_flash: Node3D = null

# Right hand weapon offset - キャラクターごとの武器位置調整
var weapon_position_offset: Vector3 = Vector3.ZERO
var weapon_rotation_offset: Vector3 = Vector3.ZERO

# Weapon resource - 武器の設定を .tres ファイルから読み込み
const WEAPONS_DIR: String = "res://resources/weapons/"
var available_weapons: Array[String] = []  # 利用可能な武器IDリスト
var current_weapon_id: String = "ak47"  # 現在選択中の武器ID
var weapon_resource: WeaponResource = null
var weapon_option_button: OptionButton = null

# Shooting
var is_shooting: bool = false

# Left hand IK - 値は weapon_resource から読み込み
var left_hand_ik: SkeletonIK3D = null
var left_hand_grip_target: Marker3D = null
var left_hand_ik_offset: Vector3 = Vector3.ZERO
var left_hand_ik_rotation: Vector3 = Vector3.ZERO


## 武器ID文字列を整数に変換
func _weapon_id_string_to_int(weapon_id: String) -> int:
	match weapon_id.to_lower():
		"ak47":
			return CharacterSetup.WeaponId.AK47
		"usp":
			return CharacterSetup.WeaponId.USP
		"m4a1":
			return CharacterSetup.WeaponId.M4A1
		_:
			return CharacterSetup.WeaponId.NONE


## 調整機能用に内部参照をキャッシュ
func _cache_internal_references() -> void:
	# CharacterBase から武器のアタッチメントを取得
	weapon_attachment = character_body.weapon_attachment
	print("[AnimViewer] Caching references: weapon_attachment=%s, skeleton=%s" % [
		weapon_attachment != null,
		character_body.skeleton != null
	])

	# 左手IK用の参照を取得
	if character_body.skeleton:
		left_hand_ik = character_body.skeleton.get_node_or_null("LeftHandIK") as SkeletonIK3D
		left_hand_grip_target = character_body.skeleton.get_node_or_null("LeftHandIKTarget") as Marker3D
		print("[AnimViewer] IK references: left_hand_ik=%s, left_hand_grip_target=%s" % [
			left_hand_ik != null,
			left_hand_grip_target != null
		])

	# Note: ボーン操作は CharacterBase._process() で行われるため、
	# skeleton_updated シグナルへの接続は不要

	# LeftHandGrip の参照を取得
	if weapon_attachment:
		for child in weapon_attachment.get_children():
			if child is Node3D:
				var model_node = child.get_node_or_null("Model")
				if model_node:
					var grip_name = "LeftHandGrip_%s" % current_weapon_id.to_upper()
					_left_hand_grip_source = _find_node_by_name(model_node, grip_name)
					if not _left_hand_grip_source:
						_left_hand_grip_source = _find_node_by_name(model_node, "LeftHandGrip")
				break

	# MuzzleFlash の参照を取得
	if weapon_attachment:
		for child in weapon_attachment.get_children():
			if child is Node3D:
				muzzle_flash = child.find_child("MuzzleFlash", true, false)
				break

	# Spine ボーンのインデックスを取得
	_find_spine_bone()
	print("[AnimViewer] Final cache state: spine_bone_idx=%d, muzzle_flash=%s, _left_hand_grip_source=%s" % [
		spine_bone_idx,
		muzzle_flash != null,
		_left_hand_grip_source != null
	])


func _ready() -> void:
	# Remove old UI (created in scene file)
	var old_panel = canvas_layer.get_node_or_null("Panel")
	if old_panel:
		old_panel.queue_free()

	# Create new UI layout
	_create_ui_layout()

	# シーンファイルで設定された初期キャラクターモデルへの参照を取得
	# （キャラクター変更時に正しく削除するため）
	character_model = character_body.get_node_or_null("CharacterModel")

	# Scan available characters first
	_scan_available_characters()

	# Scan available weapons and load current weapon resource
	_scan_available_weapons()
	_load_weapon_resource()

	# Load character resource (for weapon offset)
	_load_character_resource()

	# CharacterBase._ready() でキャラクターセットアップが自動実行される
	# 武器装備は CharacterAPI を使用
	CharacterAPI.equip_weapon(character_body, _weapon_id_string_to_int(current_weapon_id))

	# AnimationViewer では直接 AnimationPlayer を使用するため AnimationTree を無効化
	# anim_blend_tree も null にして CharacterBase による自動再有効化を防ぐ
	if character_body.anim_tree:
		character_body.anim_tree.active = false
		character_body.anim_blend_tree = null

	# アニメーション一覧を収集
	_collect_animations()

	# 内部参照をキャッシュ（調整機能用）
	_cache_internal_references()

	if camera.has_method("set_target") and character_body:
		camera.set_target(character_body)

	_populate_ui()

	# Play idle animation first
	if character_body.anim_player and character_body.anim_player.has_animation("Rifle_Idle"):
		_play_animation("Rifle_Idle")
	elif _animations.size() > 0:
		_play_animation(_animations[0])


func _scan_available_characters() -> void:
	available_characters.clear()
	var dir = DirAccess.open(CHARACTERS_DIR)
	if dir == null:
		push_warning("[AnimViewer] Cannot open characters directory: %s" % CHARACTERS_DIR)
		return

	dir.list_dir_begin()
	var folder_name = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			# Check if glb file exists
			var glb_path = CHARACTERS_DIR + folder_name + "/" + folder_name + ".glb"
			if ResourceLoader.exists(glb_path):
				available_characters.append(folder_name)
				print("[AnimViewer] Found character: %s" % folder_name)
		folder_name = dir.get_next()
	dir.list_dir_end()

	available_characters.sort()
	print("[AnimViewer] Available characters: ", available_characters)


func _create_ui_layout() -> void:
	## UIレイアウトを動的に作成
	## 左上: キャラクター/武器選択
	## 右側: アニメーション一覧
	## 下部: 調整スライダー

	# 左上パネル - キャラクター/武器選択
	left_panel = PanelContainer.new()
	left_panel.name = "LeftPanel"
	left_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left_panel.offset_right = 200
	left_panel.offset_bottom = 220
	left_panel.offset_left = 10
	left_panel.offset_top = 10
	canvas_layer.add_child(left_panel)

	var left_vbox = VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_vbox)

	# 右側パネル - アニメーション一覧 (スクロール可能)
	right_panel = PanelContainer.new()
	right_panel.name = "RightPanel"
	right_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_panel.offset_left = -200
	right_panel.offset_right = -10
	right_panel.offset_top = 10
	right_panel.offset_bottom = -10
	canvas_layer.add_child(right_panel)

	var right_scroll = ScrollContainer.new()
	right_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	right_panel.add_child(right_scroll)

	var right_vbox = VBoxContainer.new()
	right_vbox.name = "AnimationList"
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 4)
	right_scroll.add_child(right_vbox)

	# 下部パネル - 調整スライダー (左右に分割)
	bottom_panel = PanelContainer.new()
	bottom_panel.name = "BottomPanel"
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.offset_left = 10
	bottom_panel.offset_right = -220
	bottom_panel.offset_top = -180
	bottom_panel.offset_bottom = -10
	canvas_layer.add_child(bottom_panel)

	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", 20)
	bottom_panel.add_child(bottom_hbox)


func _populate_ui() -> void:
	## UIにコンテンツを配置
	_populate_left_panel()
	_populate_right_panel()
	_populate_bottom_panel()


func _populate_left_panel() -> void:
	var vbox = left_panel.get_child(0) as VBoxContainer
	if not vbox:
		return

	# Clear existing
	for child in vbox.get_children():
		child.queue_free()

	# Title
	var title = Label.new()
	title.text = "Animation Viewer"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Character selection
	var char_label = Label.new()
	char_label.text = "Character"
	vbox.add_child(char_label)

	character_option_button = OptionButton.new()
	for i in range(available_characters.size()):
		var char_id = available_characters[i]
		character_option_button.add_item(char_id.capitalize(), i)
		if char_id == current_character_id:
			character_option_button.select(i)
	character_option_button.item_selected.connect(_on_character_selected)
	vbox.add_child(character_option_button)

	vbox.add_child(HSeparator.new())

	# Weapon selection
	var weapon_label = Label.new()
	weapon_label.text = "Weapon"
	vbox.add_child(weapon_label)

	weapon_option_button = OptionButton.new()
	for i in range(available_weapons.size()):
		var weapon_id = available_weapons[i]
		weapon_option_button.add_item(weapon_id.to_upper(), i)
		if weapon_id == current_weapon_id:
			weapon_option_button.select(i)
	weapon_option_button.item_selected.connect(_on_weapon_selected)
	vbox.add_child(weapon_option_button)

	vbox.add_child(HSeparator.new())

	# Playback controls
	var stop_btn = Button.new()
	stop_btn.text = "Stop"
	stop_btn.pressed.connect(_on_stop_pressed)
	vbox.add_child(stop_btn)

	var pause_btn = Button.new()
	pause_btn.text = "Pause/Resume"
	pause_btn.pressed.connect(_on_pause_pressed)
	vbox.add_child(pause_btn)


func _populate_right_panel() -> void:
	var scroll = right_panel.get_child(0) as ScrollContainer
	if not scroll:
		return
	var vbox = scroll.get_node_or_null("AnimationList") as VBoxContainer
	if not vbox:
		return

	# Clear existing
	for child in vbox.get_children():
		child.queue_free()

	# Title
	var title = Label.new()
	title.text = "Animations"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Animation buttons
	for anim_name in _animations:
		var btn = Button.new()
		btn.text = anim_name
		btn.pressed.connect(_on_animation_button_pressed.bind(anim_name))
		vbox.add_child(btn)

	# Shooting controls
	vbox.add_child(HSeparator.new())

	var shoot_label = Label.new()
	shoot_label.text = "Shooting"
	shoot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(shoot_label)

	var shoot_btn = Button.new()
	shoot_btn.text = "Shoot (Single)"
	shoot_btn.pressed.connect(_on_shoot_pressed)
	vbox.add_child(shoot_btn)

	var auto_btn = Button.new()
	auto_btn.text = "Auto-Fire (Toggle)"
	auto_btn.pressed.connect(_on_auto_fire_pressed)
	vbox.add_child(auto_btn)


func _populate_bottom_panel() -> void:
	var hbox = bottom_panel.get_child(0) as HBoxContainer
	if not hbox:
		return

	# Clear existing
	for child in hbox.get_children():
		child.queue_free()

	# Left section: Playback & Body rotation
	var left_section = VBoxContainer.new()
	left_section.add_theme_constant_override("separation", 4)
	hbox.add_child(left_section)

	var blend_label = Label.new()
	blend_label.text = "Blend Time"
	left_section.add_child(blend_label)

	blend_time_label = Label.new()
	blend_time_label.text = "%.2f sec" % blend_time
	left_section.add_child(blend_time_label)

	var blend_slider = HSlider.new()
	blend_slider.min_value = 0.0
	blend_slider.max_value = 1.0
	blend_slider.step = 0.05
	blend_slider.value = blend_time
	blend_slider.custom_minimum_size.x = 150
	blend_slider.value_changed.connect(_on_blend_time_changed)
	left_section.add_child(blend_slider)

	left_section.add_child(HSeparator.new())

	var rotation_label = Label.new()
	rotation_label.text = "Upper Body Twist"
	left_section.add_child(rotation_label)

	upper_body_rotation_label = Label.new()
	upper_body_rotation_label.text = "%.0f deg" % upper_body_rotation
	left_section.add_child(upper_body_rotation_label)

	var rotation_slider = HSlider.new()
	rotation_slider.min_value = UPPER_BODY_ROTATION_MIN
	rotation_slider.max_value = UPPER_BODY_ROTATION_MAX
	rotation_slider.step = 1.0
	rotation_slider.value = upper_body_rotation
	rotation_slider.custom_minimum_size.x = 150
	rotation_slider.value_changed.connect(_on_upper_body_rotation_changed)
	left_section.add_child(rotation_slider)

	# Middle section: Right hand weapon offset
	var mid_section = VBoxContainer.new()
	mid_section.add_theme_constant_override("separation", 4)
	hbox.add_child(mid_section)

	var weapon_offset_label = Label.new()
	weapon_offset_label.text = "Weapon Offset (Character)"
	weapon_offset_label.add_theme_font_size_override("font_size", 14)
	mid_section.add_child(weapon_offset_label)

	_create_offset_slider(mid_section, "W Pos X", weapon_position_offset.x, -0.1, 0.1, _on_weapon_pos_x_changed)
	_create_offset_slider(mid_section, "W Pos Y", weapon_position_offset.y, -0.1, 0.1, _on_weapon_pos_y_changed)
	_create_offset_slider(mid_section, "W Pos Z", weapon_position_offset.z, -0.1, 0.1, _on_weapon_pos_z_changed)
	_create_offset_slider(mid_section, "W Rot X", weapon_rotation_offset.x, -45, 45, _on_weapon_rot_x_changed)
	_create_offset_slider(mid_section, "W Rot Y", weapon_rotation_offset.y, -45, 45, _on_weapon_rot_y_changed)
	_create_offset_slider(mid_section, "W Rot Z", weapon_rotation_offset.z, -45, 45, _on_weapon_rot_z_changed)

	# Right section: Left hand IK
	var right_section = VBoxContainer.new()
	right_section.add_theme_constant_override("separation", 4)
	hbox.add_child(right_section)

	var ik_label = Label.new()
	ik_label.text = "Left Hand IK (Weapon)"
	ik_label.add_theme_font_size_override("font_size", 14)
	right_section.add_child(ik_label)

	_create_offset_slider(right_section, "IK Pos X", left_hand_ik_offset.x, -0.2, 0.2, _on_ik_pos_x_changed)
	_create_offset_slider(right_section, "IK Pos Y", left_hand_ik_offset.y, -0.2, 0.2, _on_ik_pos_y_changed)
	_create_offset_slider(right_section, "IK Pos Z", left_hand_ik_offset.z, -0.2, 0.2, _on_ik_pos_z_changed)
	_create_offset_slider(right_section, "IK Rot X", left_hand_ik_rotation.x, -180, 180, _on_ik_rot_x_changed)
	_create_offset_slider(right_section, "IK Rot Y", left_hand_ik_rotation.y, -180, 180, _on_ik_rot_y_changed)
	_create_offset_slider(right_section, "IK Rot Z", left_hand_ik_rotation.z, -180, 180, _on_ik_rot_z_changed)

	# Print values buttons
	var btn_section = VBoxContainer.new()
	btn_section.add_theme_constant_override("separation", 8)
	hbox.add_child(btn_section)

	var print_weapon_btn = Button.new()
	print_weapon_btn.text = "Print Weapon Offset"
	print_weapon_btn.pressed.connect(_on_print_weapon_offset)
	btn_section.add_child(print_weapon_btn)

	var print_ik_btn = Button.new()
	print_ik_btn.text = "Print IK Values"
	print_ik_btn.pressed.connect(_on_print_ik_values)
	btn_section.add_child(print_ik_btn)


func _create_offset_slider(container: VBoxContainer, label_text: String, initial_value: float, min_val: float, max_val: float, callback: Callable) -> void:
	var hbox = HBoxContainer.new()

	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 60
	hbox.add_child(label)

	var slider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = 0.01 if max_val <= 1.0 else 1.0
	slider.value = initial_value
	slider.custom_minimum_size.x = 100
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(callback)
	hbox.add_child(slider)

	var value_label = Label.new()
	value_label.text = "%.2f" % initial_value if max_val <= 1.0 else "%.0f" % initial_value
	value_label.custom_minimum_size.x = 40
	value_label.name = label_text.replace(" ", "") + "Value"
	hbox.add_child(value_label)

	container.add_child(hbox)


func _on_weapon_pos_x_changed(value: float) -> void:
	weapon_position_offset.x = value
	_update_slider_label("WPosX", value, true)
	_apply_weapon_offset()


func _on_weapon_pos_y_changed(value: float) -> void:
	weapon_position_offset.y = value
	_update_slider_label("WPosY", value, true)
	_apply_weapon_offset()


func _on_weapon_pos_z_changed(value: float) -> void:
	weapon_position_offset.z = value
	_update_slider_label("WPosZ", value, true)
	_apply_weapon_offset()


func _on_weapon_rot_x_changed(value: float) -> void:
	weapon_rotation_offset.x = value
	_update_slider_label("WRotX", value, false)
	_apply_weapon_offset()


func _on_weapon_rot_y_changed(value: float) -> void:
	weapon_rotation_offset.y = value
	_update_slider_label("WRotY", value, false)
	_apply_weapon_offset()


func _on_weapon_rot_z_changed(value: float) -> void:
	weapon_rotation_offset.z = value
	_update_slider_label("WRotZ", value, false)
	_apply_weapon_offset()


func _update_slider_label(slider_name: String, value: float, is_position: bool) -> void:
	var label = bottom_panel.find_child(slider_name + "Value", true, false)
	if label:
		label.text = "%.2f" % value if is_position else "%.0f" % value


func _apply_weapon_offset() -> void:
	## 武器モデルにオフセットを適用
	if not weapon_attachment:
		return

	var weapon_node: Node3D = null
	for child in weapon_attachment.get_children():
		if child is Node3D:
			weapon_node = child as Node3D
			break

	if weapon_node:
		weapon_node.position = weapon_position_offset
		weapon_node.rotation_degrees = weapon_rotation_offset


func _on_print_weapon_offset() -> void:
	print("[AnimViewer] Character Weapon Offset for '%s':" % current_character_id)
	print("  weapon_position_offset = Vector3(%.3f, %.3f, %.3f)" % [weapon_position_offset.x, weapon_position_offset.y, weapon_position_offset.z])
	print("  weapon_rotation_offset = Vector3(%.1f, %.1f, %.1f)" % [weapon_rotation_offset.x, weapon_rotation_offset.y, weapon_rotation_offset.z])


func _load_character_resource() -> void:
	## キャラクターリソースを読み込み
	var resource_path = CHARACTERS_DIR + current_character_id + "/" + current_character_id + ".tres"
	if ResourceLoader.exists(resource_path):
		character_resource = load(resource_path)
		if character_resource and character_resource.get("weapon_position_offset") != null:
			weapon_position_offset = character_resource.weapon_position_offset
			weapon_rotation_offset = character_resource.weapon_rotation_offset
			print("[AnimViewer] Loaded character resource: %s" % current_character_id)
			print("[AnimViewer]   Weapon Position: %s" % weapon_position_offset)
			print("[AnimViewer]   Weapon Rotation: %s" % weapon_rotation_offset)
		else:
			push_warning("[AnimViewer] Failed to load character resource: %s" % resource_path)
			weapon_position_offset = Vector3.ZERO
			weapon_rotation_offset = Vector3.ZERO
	else:
		# No resource file, use defaults
		character_resource = null
		weapon_position_offset = Vector3.ZERO
		weapon_rotation_offset = Vector3.ZERO
		print("[AnimViewer] No character resource found for: %s (using defaults)" % current_character_id)


func _change_character(character_id: String) -> void:
	if character_id == current_character_id:
		return

	print("[AnimViewer] Changing character to: %s" % character_id)

	# 旧い参照をクリア
	_left_hand_grip_source = null
	muzzle_flash = null
	left_hand_ik = null
	left_hand_grip_target = null
	weapon_attachment = null
	spine_bone_idx = -1
	right_hand_bone_idx = -1
	_animations.clear()

	# 古いモデルを削除（即座にツリーから外す）
	if character_model:
		character_body.remove_child(character_model)
		character_model.queue_free()
		character_model = null

	# CharacterBase の内部状態をリセット
	character_body.anim_player = null
	character_body.skeleton = null
	character_body.weapon_attachment = null
	character_body.current_weapon_id = CharacterSetup.WeaponId.NONE  # 武器IDをリセット（再装備を強制）
	character_body._explicit_character_id = ""  # 明示的IDをリセット

	# Update current character ID
	current_character_id = character_id

	# Load character resource (for weapon offset)
	_load_character_resource()

	# Load and instantiate new character
	var glb_path = CHARACTERS_DIR + character_id + "/" + character_id + ".glb"
	var character_scene = load(glb_path)
	if not character_scene:
		push_warning("[AnimViewer] Failed to load character: %s" % glb_path)
		return

	character_model = character_scene.instantiate()
	character_model.name = "CharacterModel"  # CharacterBase が期待する名前
	character_body.add_child(character_model)

	# 明示的にキャラクターIDを設定（動的ロードではscene_file_pathからの検出が失敗するため）
	character_body._explicit_character_id = character_id

	# CharacterBase._setup_character() を手動で再呼び出し
	character_body._setup_character()

	# AnimationViewer では直接 AnimationPlayer を使用するため AnimationTree を無効化
	# anim_blend_tree も null にして CharacterBase による自動再有効化を防ぐ
	if character_body.anim_tree:
		character_body.anim_tree.active = false
		character_body.anim_blend_tree = null

	# 武器を再装備
	var weapon_int_id = _weapon_id_string_to_int(current_weapon_id)
	print("[AnimViewer] Equipping weapon: %s (id=%d), skeleton=%s, current_weapon_id=%d" % [
		current_weapon_id, weapon_int_id,
		character_body.skeleton != null,
		character_body.current_weapon_id
	])
	CharacterAPI.equip_weapon(character_body, weapon_int_id)

	# アニメーション一覧を収集
	_collect_animations()

	# 内部参照をキャッシュ
	_cache_internal_references()

	# Recreate UI (animation buttons and sliders)
	_populate_ui()

	# Apply weapon offset
	_apply_weapon_offset()

	# Play idle animation
	if character_body.anim_player and character_body.anim_player.has_animation("Rifle_Idle"):
		_play_animation("Rifle_Idle")
	elif _animations.size() > 0:
		_play_animation(_animations[0])

	# カメラ位置を更新（ターゲットが変わらないように維持）
	_ensure_camera_target()


func _ensure_camera_target() -> void:
	## カメラのターゲットがcharacter_bodyを指していることを確認
	if camera and camera.has_method("set_target") and character_body:
		if camera.target != character_body:
			camera.set_target(character_body)


func _physics_process(delta: float) -> void:
	if character_body:
		if not character_body.is_on_floor():
			character_body.velocity.y -= GRAVITY * delta
		else:
			character_body.velocity.y = 0
		character_body.move_and_slide()

	# IKターゲットを物理フレームで更新（遅延を減らす）
	_update_left_hand_ik_target()


func _process(_delta: float) -> void:
	# Note: _apply_upper_body_rotation is now called from skeleton_updated signal
	# to ensure it runs after animation has been applied
	pass


func _input(event: InputEvent) -> void:
	# Space key to shoot (for easy testing)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_shoot()
		elif event.keycode == KEY_T:
			# T key to toggle upper body rotation for testing
			upper_body_rotation = 30.0 if upper_body_rotation < 1.0 else 0.0
			# CharacterBase APIを使用
			character_body.set_external_twist_degrees(upper_body_rotation)
			print("[AnimViewer] Upper body rotation set to: %.1f" % upper_body_rotation)


func _print_bone_hierarchy(skel: Skeleton3D) -> void:
	print("[BotViewer] Bone hierarchy:")
	for i in range(skel.get_bone_count()):
		var bone_name := skel.get_bone_name(i)
		var parent_idx := skel.get_bone_parent(i)
		var parent_name := skel.get_bone_name(parent_idx) if parent_idx >= 0 else "ROOT"
		print("  [%d] %s (parent: %s)" % [i, bone_name, parent_name])


func _find_spine_bone() -> void:
	if not character_body.skeleton:
		return

	# Look for spine bone - common names for Mixamo and other rigs
	# mixamorig_Spine1 is ideal for upper body rotation (chest level)
	var spine_names := ["mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Spine",
						"Spine1", "Spine2", "Spine", "spine1", "spine2", "spine",
						"mixamorig:Spine1", "mixamorig:Spine2", "mixamorig:Spine"]

	for bone_name in spine_names:
		var idx := character_body.skeleton.find_bone(bone_name)
		if idx >= 0:
			spine_bone_idx = idx
			print("[AnimViewer] Found spine bone: %s (index: %d)" % [bone_name, idx])
			return

	push_warning("[AnimViewer] Spine bone not found")


func _scan_available_weapons() -> void:
	available_weapons.clear()
	var dir = DirAccess.open(WEAPONS_DIR)
	if dir == null:
		push_warning("[BotViewer] Cannot open weapons directory: %s" % WEAPONS_DIR)
		return

	dir.list_dir_begin()
	var folder_name = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var tres_path = WEAPONS_DIR + folder_name + "/" + folder_name + ".tres"
			if ResourceLoader.exists(tres_path):
				available_weapons.append(folder_name)
				print("[BotViewer] Found weapon: %s" % folder_name)
		folder_name = dir.get_next()
	dir.list_dir_end()

	available_weapons.sort()
	print("[BotViewer] Available weapons: ", available_weapons)


func _load_weapon_resource() -> void:
	_load_weapon_resource_by_id(current_weapon_id)


func _change_weapon(weapon_id: String) -> void:
	if weapon_id == current_weapon_id:
		return

	print("[AnimViewer] Changing weapon to: %s" % weapon_id)

	# 旧い参照をクリア
	_left_hand_grip_source = null
	muzzle_flash = null
	left_hand_ik = null
	left_hand_grip_target = null
	weapon_attachment = null

	# Update current weapon ID and load new resource
	current_weapon_id = weapon_id
	_load_weapon_resource_by_id(weapon_id)

	# CharacterAPI を使用して武器を装備
	CharacterAPI.equip_weapon(character_body, _weapon_id_string_to_int(weapon_id))

	# 内部参照を再キャッシュ
	_cache_internal_references()

	# Update IK sliders to reflect new weapon's values
	_update_ik_sliders()


func _load_weapon_resource_by_id(weapon_id: String) -> void:
	var resource_path = WEAPONS_DIR + weapon_id + "/" + weapon_id + ".tres"

	if ResourceLoader.exists(resource_path):
		weapon_resource = load(resource_path) as WeaponResource
		if weapon_resource:
			# IK設定を武器リソースから読み込み
			left_hand_ik_offset = weapon_resource.left_hand_ik_position
			left_hand_ik_rotation = weapon_resource.left_hand_ik_rotation
			print("[BotViewer] Loaded weapon resource: %s" % weapon_resource.weapon_name)
			print("[BotViewer]   IK Position: %s" % left_hand_ik_offset)
			print("[BotViewer]   IK Rotation: %s" % left_hand_ik_rotation)
		else:
			push_warning("[BotViewer] Failed to load weapon resource: %s" % resource_path)
	else:
		push_warning("[BotViewer] Weapon resource not found: %s" % resource_path)


var _left_hand_grip_source: Node3D = null


func _update_left_hand_ik_target() -> void:
	if not left_hand_grip_target or not _left_hand_grip_source:
		return

	# Note: Always update target position even if IK is not running
	# so that when IK starts, it uses the correct target position

	# Update IK target to match LeftHandGrip global position with offset
	# オフセットを適用して手のひらがターゲットに来るように調整
	var grip_transform := _left_hand_grip_source.global_transform

	# 位置オフセットを適用
	var offset_global := grip_transform.basis * left_hand_ik_offset
	grip_transform.origin += offset_global

	# 角度オフセットを適用（度数→ラジアン）
	var rotation_offset := Basis.from_euler(Vector3(
		deg_to_rad(left_hand_ik_rotation.x),
		deg_to_rad(left_hand_ik_rotation.y),
		deg_to_rad(left_hand_ik_rotation.z)
	))
	grip_transform.basis = grip_transform.basis * rotation_offset

	left_hand_grip_target.global_transform = grip_transform


func _find_node_by_name(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child in root.get_children():
		var result = _find_node_by_name(child, target_name)
		if result:
			return result
	return null


func _collect_animations() -> void:
	if not character_body.anim_player:
		return

	_animations.clear()
	print("[AnimViewer] Animation details:")
	for anim_name in character_body.anim_player.get_animation_list():
		if anim_name == "RESET":
			continue
		# CharacterSetupが生成した小文字のアニメーション（idle_rifle等）を除外
		# オリジナルのGLBアニメーション（Rifle_Idle等）のみを表示
		if anim_name[0] == anim_name[0].to_lower():
			continue
		_animations.append(anim_name)
		var anim = character_body.anim_player.get_animation(anim_name)
		if anim:
			print("  - %s (loop_mode=%d, length=%.2fs)" % [anim_name, anim.loop_mode, anim.length])

	_animations.sort()
	print("[AnimViewer] Animations: ", _animations)


func _on_ik_pos_x_changed(value: float) -> void:
	left_hand_ik_offset.x = value
	_update_slider_label("IKPosX", value, true)
	# CharacterBase APIを使用してIKオフセットを適用
	character_body.set_left_hand_ik_offset(left_hand_ik_offset)

func _on_ik_pos_y_changed(value: float) -> void:
	left_hand_ik_offset.y = value
	_update_slider_label("IKPosY", value, true)
	character_body.set_left_hand_ik_offset(left_hand_ik_offset)

func _on_ik_pos_z_changed(value: float) -> void:
	left_hand_ik_offset.z = value
	_update_slider_label("IKPosZ", value, true)
	character_body.set_left_hand_ik_offset(left_hand_ik_offset)

func _on_ik_rot_x_changed(value: float) -> void:
	left_hand_ik_rotation.x = value
	_update_slider_label("IKRotX", value, false)
	# CharacterBase APIを使用してIK回転オフセットを適用
	character_body.set_left_hand_ik_rotation(left_hand_ik_rotation)

func _on_ik_rot_y_changed(value: float) -> void:
	left_hand_ik_rotation.y = value
	_update_slider_label("IKRotY", value, false)
	character_body.set_left_hand_ik_rotation(left_hand_ik_rotation)

func _on_ik_rot_z_changed(value: float) -> void:
	left_hand_ik_rotation.z = value
	_update_slider_label("IKRotZ", value, false)
	character_body.set_left_hand_ik_rotation(left_hand_ik_rotation)

func _on_print_ik_values() -> void:
	print("[BotViewer] Left Hand IK Values:")
	print("  Position Offset: Vector3(%.3f, %.3f, %.3f)" % [left_hand_ik_offset.x, left_hand_ik_offset.y, left_hand_ik_offset.z])
	print("  Rotation Offset: Vector3(%.1f, %.1f, %.1f)" % [left_hand_ik_rotation.x, left_hand_ik_rotation.y, left_hand_ik_rotation.z])


func _on_character_selected(index: int) -> void:
	if index < 0 or index >= available_characters.size():
		return
	var char_id = available_characters[index]
	_change_character(char_id)


func _on_weapon_selected(index: int) -> void:
	if index < 0 or index >= available_weapons.size():
		return
	var weapon_id = available_weapons[index]
	_change_weapon(weapon_id)


func _update_ik_sliders() -> void:
	# Update IK slider values to match current weapon's settings
	if not bottom_panel:
		return

	# Find and update position sliders
	var pos_x_slider = _find_slider_by_label("IK Pos X")
	var pos_y_slider = _find_slider_by_label("IK Pos Y")
	var pos_z_slider = _find_slider_by_label("IK Pos Z")
	var rot_x_slider = _find_slider_by_label("IK Rot X")
	var rot_y_slider = _find_slider_by_label("IK Rot Y")
	var rot_z_slider = _find_slider_by_label("IK Rot Z")

	if pos_x_slider:
		pos_x_slider.value = left_hand_ik_offset.x
	if pos_y_slider:
		pos_y_slider.value = left_hand_ik_offset.y
	if pos_z_slider:
		pos_z_slider.value = left_hand_ik_offset.z
	if rot_x_slider:
		rot_x_slider.value = left_hand_ik_rotation.x
	if rot_y_slider:
		rot_y_slider.value = left_hand_ik_rotation.y
	if rot_z_slider:
		rot_z_slider.value = left_hand_ik_rotation.z


func _find_slider_by_label(label_text: String) -> HSlider:
	if not bottom_panel:
		return null
	return _find_slider_in_node(bottom_panel, label_text)


func _find_slider_in_node(node: Node, label_text: String) -> HSlider:
	if node is HBoxContainer:
		for child in node.get_children():
			if child is Label and child.text == label_text:
				for sibling in node.get_children():
					if sibling is HSlider:
						return sibling
	for child in node.get_children():
		var result = _find_slider_in_node(child, label_text)
		if result:
			return result
	return null


func _play_animation(anim_name: String) -> void:
	if not character_body.anim_player:
		return

	if character_body.anim_player.has_animation(anim_name):
		# ループアニメーションのloop_modeを強制設定
		var anim = character_body.anim_player.get_animation(anim_name)
		if anim and anim_name in ["Rifle_Idle", "Rifle_WalkFwdLoop", "Rifle_SprintLoop", "Rifle_CrouchLoop"]:
			if anim.loop_mode != Animation.LOOP_LINEAR:
				anim.loop_mode = Animation.LOOP_LINEAR
				print("[AnimViewer] Set loop_mode to LINEAR for: %s" % anim_name)

		character_body.anim_player.play(anim_name, blend_time)
		print("[AnimViewer] Playing: %s (blend: %.2fs)" % [anim_name, blend_time])

		# 左手IKの有効/無効を切り替え
		_update_left_hand_ik_enabled(anim_name)
	else:
		push_warning("[AnimViewer] Animation not found: ", anim_name)


const IK_BLEND_DURATION: float = 0.25  # IK補間時間（秒）
var _ik_interpolation_tween: Tween = null  # IK補間用Tween

func _update_left_hand_ik_enabled(anim_name: String) -> void:
	if not left_hand_ik:
		return

	var should_disable := _should_disable_ik_for_animation(anim_name)

	if should_disable:
		# IKを無効化（即座に）
		_cancel_ik_tween()
		if left_hand_ik.is_running():
			left_hand_ik.interpolation = 0.0
			left_hand_ik.stop()
			print("[BotViewer] Left hand IK disabled for: %s" % anim_name)
	else:
		# IKを有効化（スムーズに補間）
		if not left_hand_ik.is_running():
			left_hand_ik.interpolation = 0.0
			left_hand_ik.start()
			_blend_ik_interpolation(1.0, IK_BLEND_DURATION)
			print("[BotViewer] Left hand IK enabled (blending) for: %s" % anim_name)


## IK補間Tweenをキャンセル
func _cancel_ik_tween() -> void:
	if _ik_interpolation_tween and _ik_interpolation_tween.is_valid():
		_ik_interpolation_tween.kill()
		_ik_interpolation_tween = null


## IK interpolationをスムーズに変更
func _blend_ik_interpolation(target_value: float, duration: float) -> void:
	_cancel_ik_tween()
	if not left_hand_ik:
		return

	_ik_interpolation_tween = create_tween()
	_ik_interpolation_tween.tween_property(left_hand_ik, "interpolation", target_value, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## アニメーション名からIKを無効にすべきか判定
## Convention over Configuration: 命名規則に基づいて自動判定
func _should_disable_ik_for_animation(anim_name: String) -> bool:
	# 武器リソースがIK無効の場合は常に無効
	if weapon_resource and not weapon_resource.left_hand_ik_enabled:
		return true

	# パターンマッチングで判定（命名規則に基づく）
	if anim_name.begins_with("reload") or anim_name.contains("Reload"):
		return true
	if anim_name.begins_with("dying") or anim_name.contains("Death"):
		return true
	if anim_name == "open_door" or anim_name.contains("OpenDoor"):
		return true

	return false


func _on_animation_button_pressed(anim_name: String) -> void:
	_play_animation(anim_name)


func _on_stop_pressed() -> void:
	if character_body.anim_player:
		character_body.anim_player.stop()
		# Reset speed scale in case it was paused
		character_body.anim_player.speed_scale = 1.0


func _on_pause_pressed() -> void:
	if character_body.anim_player:
		# Toggle pause using speed_scale (0 = paused, 1 = playing)
		if character_body.anim_player.speed_scale > 0:
			character_body.anim_player.speed_scale = 0.0
			print("[AnimViewer] Animation paused")
		else:
			character_body.anim_player.speed_scale = 1.0
			print("[AnimViewer] Animation resumed")


func _on_blend_time_changed(value: float) -> void:
	blend_time = value
	if blend_time_label:
		blend_time_label.text = "%.2f sec" % blend_time


func _on_upper_body_rotation_changed(value: float) -> void:
	upper_body_rotation = value
	# CharacterBase APIを使用して上半身ツイストを適用
	character_body.set_external_twist_degrees(value)
	if upper_body_rotation_label:
		upper_body_rotation_label.text = "%.0f°" % upper_body_rotation


func _on_reset_rotation_pressed() -> void:
	upper_body_rotation = 0.0
	# CharacterBase APIを使用してリセット
	character_body.set_external_twist_degrees(0.0)
	if upper_body_rotation_label:
		upper_body_rotation_label.text = "0°"
	# Find and reset the slider using the new UI structure
	var slider = _find_slider_by_label("Upper Body Twist")
	if slider:
		slider.value = 0.0


## ========================================
## Shooting Handlers
## ========================================

func _on_shoot_pressed() -> void:
	_shoot()


func _shoot() -> void:
	# Trigger muzzle flash
	if muzzle_flash and muzzle_flash.has_method("flash"):
		muzzle_flash.flash()

	# Apply recoil
	_apply_recoil()

	print("[BotViewer] Shot fired!")


func _apply_recoil() -> void:
	# CharacterBase.apply_recoil()を呼ぶだけ
	# 復帰はCharacterBase._recover_weapon_recoil()で自動処理
	character_body.apply_recoil(1.0)
	print("[AnimViewer] Recoil applied (weapon kick)")


func _on_auto_fire_pressed() -> void:
	is_shooting = not is_shooting
	if is_shooting:
		_start_auto_fire()
	print("[BotViewer] Auto-fire: %s" % ("ON" if is_shooting else "OFF"))


func _start_auto_fire() -> void:
	if not is_shooting:
		return
	_shoot()
	# Schedule next shot (fire rate: ~600 RPM = 100ms interval)
	get_tree().create_timer(0.1).timeout.connect(_start_auto_fire)


func _print_node_tree(node: Node, depth: int) -> void:
	var indent := ""
	for i in range(depth):
		indent += "  "
	var extra := ""
	if node is MeshInstance3D:
		extra = " [Mesh]"
	elif node is Skeleton3D:
		extra = " [Skeleton: %d bones]" % node.get_bone_count()
	print(indent + "- " + node.name + " (" + node.get_class() + ")" + extra)
	if depth < 6:
		for child in node.get_children():
			_print_node_tree(child, depth + 1)


func _get_model_aabb(node: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_inst := child as MeshInstance3D
			var mesh_aabb: AABB = mesh_inst.get_aabb()
			if first:
				aabb = mesh_aabb
				first = false
			else:
				aabb = aabb.merge(mesh_aabb)
		if child is Node3D:
			var child_aabb: AABB = _get_model_aabb(child as Node3D)
			if child_aabb.size != Vector3.ZERO:
				if first:
					aabb = child_aabb
					first = false
				else:
					aabb = aabb.merge(child_aabb)
	return aabb
