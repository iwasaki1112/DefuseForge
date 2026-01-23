class_name VisionService
extends Node
## 視界/FoW/敵可視性の統合サービス

const FogOfWarSystemScript = preload("res://scripts/systems/fog_of_war_system.gd")
const EnemyVisibilitySystemScript = preload("res://scripts/systems/enemy_visibility_system.gd")

var fog_of_war_system: Node3D = null
var enemy_visibility_system: Node = null
var is_vision_enabled: bool = false

## デバッグ表示設定
var _debug_draw_enabled: bool = false
var _registered_visions: Array = []  # 登録済みVisionComponentの追跡


func setup(map_size: Vector2, vision_enabled: bool) -> void:
	is_vision_enabled = vision_enabled
	_setup_fog_of_war(map_size)
	_setup_enemy_visibility_system()
	set_enabled(vision_enabled)


func set_enabled(enabled: bool) -> void:
	is_vision_enabled = enabled
	if fog_of_war_system:
		fog_of_war_system.set_fog_visible(enabled)
	if enemy_visibility_system:
		if enabled:
			enemy_visibility_system.enable_full()
		else:
			enemy_visibility_system.enable_lightweight()


## キャラクターのVisionComponentを登録
func register_character(character: Node) -> void:
	if not character:
		return

	var game_char = character as GameCharacter
	if game_char and game_char.vision:
		# FoWに登録
		if fog_of_war_system and PlayerState.is_friendly(character):
			fog_of_war_system.register_vision(game_char.vision)

		# 追跡リストに追加
		if game_char.vision not in _registered_visions:
			_registered_visions.append(game_char.vision)

		# デバッグ表示が有効なら適用
		if _debug_draw_enabled and PlayerState.is_friendly(character):
			game_char.vision.set_debug_draw(true)

	# EnemyVisibilitySystemに登録
	if enemy_visibility_system:
		enemy_visibility_system.register_character(character)


func unregister_character(character: Node) -> void:
	if not character:
		return

	var game_char = character as GameCharacter
	if game_char and game_char.vision:
		# 追跡リストから削除
		_registered_visions.erase(game_char.vision)

		if fog_of_war_system:
			fog_of_war_system.unregister_vision(game_char.vision)

	if enemy_visibility_system:
		enemy_visibility_system.unregister_character(character)


## 味方キャラクターの視界デバッグ表示を切り替え
func set_debug_draw(enabled: bool) -> void:
	_debug_draw_enabled = enabled

	# 登録済みの全VisionComponentに適用
	for vision in _registered_visions:
		if is_instance_valid(vision):
			# 味方のみデバッグ表示
			var character = vision.get_parent()
			if character and PlayerState.is_friendly(character):
				vision.set_debug_draw(enabled)


## デバッグ表示が有効か確認
func is_debug_draw_enabled() -> bool:
	return _debug_draw_enabled


func _setup_fog_of_war(map_size: Vector2) -> void:
	fog_of_war_system = Node3D.new()
	fog_of_war_system.set_script(FogOfWarSystemScript)
	fog_of_war_system.name = "FogOfWarSystem"
	fog_of_war_system.map_size = map_size
	add_child(fog_of_war_system)


func _setup_enemy_visibility_system() -> void:
	enemy_visibility_system = Node.new()
	enemy_visibility_system.set_script(EnemyVisibilitySystemScript)
	enemy_visibility_system.name = "EnemyVisibilitySystem"
	add_child(enemy_visibility_system)
	enemy_visibility_system.setup(fog_of_war_system)
