class_name CharacterSetupService
extends RefCounted
## キャラクターの初期セットアップを担当

const AnimCtrl = preload("res://scripts/animation/character_animation_controller.gd")

var enemy_visibility_system: Node = null
var fog_of_war_system: Node3D = null
var label_manager: CharacterLabelManager = null
var default_weapon_id: String = "glock"
var is_vision_enabled: bool = false
var default_vision_fov: float = 90.0
var default_vision_range: float = 15.0


func setup(
	visibility_system: Node,
	fow_system: Node3D,
	label_mgr: CharacterLabelManager,
	weapon_id: String,
	vision_enabled: bool,
	vision_fov: float,
	vision_range: float
) -> void:
	enemy_visibility_system = visibility_system
	fog_of_war_system = fow_system
	label_manager = label_mgr
	default_weapon_id = weapon_id
	is_vision_enabled = vision_enabled
	default_vision_fov = vision_fov
	default_vision_range = vision_range
	if Debug.enabled: print("[FOW] setup - fog_of_war_system: ", fog_of_war_system, ", is_vision_enabled: ", is_vision_enabled)


func setup_character(character: Node) -> void:
	if not character:
		if Debug.enabled: print("[FOW] setup_character: character is null")
		return

	if Debug.enabled: print("[FOW] setup_character: ", character.name)

	# Setup vision component
	var vision = character.setup_vision(default_vision_fov, default_vision_range)

	# 遅延セットアップ
	if vision:
		_complete_character_setup.call_deferred(character)
	else:
		_complete_character_setup(character)


func _complete_character_setup(character: Node) -> void:
	if not character or not is_instance_valid(character):
		return

	# EnemyVisibilitySystemに登録
	if enemy_visibility_system:
		enemy_visibility_system.register_character(character)

	# FogOfWarSystemに登録（味方キャラクターのみ）
	if fog_of_war_system and PlayerState.is_friendly(character):
		if Debug.enabled: print("[FOW] Registering to FoW: ", character.name)
		fog_of_war_system.register_character(character)

	# Combat awarenessセットアップ
	character.setup_combat_awareness()
	if character.combat_awareness:
		character.combat_awareness.enable_firing()

	# 視界状態を適用
	var vision = character.vision
	if not is_vision_enabled and vision:
		vision.disable()
		if fog_of_war_system:
			fog_of_war_system.set_fog_visible(false)

	# デフォルト武器を装備
	var anim_ctrl = character.get_anim_controller()
	if anim_ctrl:
		anim_ctrl.set_weapon(AnimCtrl.Weapon.PISTOL)

	var default_weapon = WeaponRegistry.get_preset(default_weapon_id)
	if default_weapon:
		_equip_weapon(character, default_weapon)

	# 味方の場合、色とラベルを割り当て
	if not PlayerState.is_enemy(character):
		_assign_color_and_label(character)


func _equip_weapon(character: Node, weapon_preset: Resource) -> void:
	if not character or not weapon_preset:
		return

	if character.has_method("equip_weapon"):
		character.equip_weapon(weapon_preset)


func _assign_color_and_label(character: Node) -> void:
	if not character:
		return

	# 敵には割り当てない
	if PlayerState.is_enemy(character):
		return

	# 色を割り当て
	var color_index = CharacterColorManager.assign_color(character)
	if color_index == -1:
		if label_manager:
			label_manager.add_label(character)
		return

	# ラベルを追加
	if label_manager:
		label_manager.add_label(character)
		var color = CharacterColorManager.get_character_color(character)
		var label_char = CharacterColorManager.get_character_label(character)
		label_manager.set_label_color(character, color)
		label_manager.set_label_text(character, label_char)


## 色とラベルを割り当て（外部用）
func assign_color_and_label(character: Node) -> void:
	_assign_color_and_label(character)
