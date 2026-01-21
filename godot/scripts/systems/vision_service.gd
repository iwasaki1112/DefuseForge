class_name VisionService
extends Node
## 視界/FoW/敵可視性の統合サービス

const FogOfWarSystemScript = preload("res://scripts/systems/fog_of_war_system.gd")
const EnemyVisibilitySystemScript = preload("res://scripts/systems/enemy_visibility_system.gd")

var fog_of_war_system: Node3D = null
var enemy_visibility_system: Node = null
var is_vision_enabled: bool = false


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


func unregister_character(character: Node) -> void:
	if not character:
		return
	if character.vision and fog_of_war_system:
		fog_of_war_system.unregister_vision(character.vision)
	if enemy_visibility_system:
		enemy_visibility_system.unregister_character(character)


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
