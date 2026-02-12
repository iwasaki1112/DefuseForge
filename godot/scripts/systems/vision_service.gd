class_name VisionService
extends Node
## 視界/FoW/敵可視性の統合サービス
## Light2D + LightOccluder2D方式のFoWシステムを管理


var fog_of_war_system: Node3D = null
var enemy_visibility_system: Node = null
var is_vision_enabled: bool = false

## SmokeAreaManager参照
var _smoke_area_manager: SmokeAreaManager = null

## デバッグ表示設定
var _debug_draw_enabled: bool = false
var _registered_visions: Array = []  # 登録済みVisionComponentの追跡


func setup(map_size: Vector2, vision_enabled: bool) -> void:
	if Debug.enabled: print("[FOW] setup - map_size: ", map_size, ", vision_enabled: ", vision_enabled)
	is_vision_enabled = vision_enabled
	_setup_fog_of_war(map_size)
	_setup_enemy_visibility_system()
	set_enabled(vision_enabled)
	if Debug.enabled: print("[FOW] fog_of_war_system: ", fog_of_war_system)


func set_enabled(enabled: bool) -> void:
	if Debug.enabled: print("[FOW] VisionService.set_enabled: ", enabled)
	is_vision_enabled = enabled
	if fog_of_war_system:
		fog_of_war_system.set_fog_visible(enabled)
		if Debug.enabled: print("[FOW] set_fog_visible called with: ", enabled)
	if enemy_visibility_system:
		if enabled:
			enemy_visibility_system.enable_full()
		else:
			enemy_visibility_system.enable_lightweight()


## SmokeAreaManagerを設定
func set_smoke_area_manager(manager: SmokeAreaManager) -> void:
	_smoke_area_manager = manager

	# EnemyVisibilitySystemにも設定
	if enemy_visibility_system:
		enemy_visibility_system.set_smoke_area_manager(manager)

	# シグナル接続
	if manager:
		if not manager.smoke_area_added.is_connected(_on_smoke_area_added):
			manager.smoke_area_added.connect(_on_smoke_area_added)
		if not manager.smoke_area_removed.is_connected(_on_smoke_area_removed):
			manager.smoke_area_removed.connect(_on_smoke_area_removed)


## キャラクターのVisionComponentを登録
func register_character(character: Node) -> void:
	if not character:
		if Debug.enabled: print("[FOW] register_character: character is null")
		return

	if Debug.enabled: print("[FOW] register_character: ", character.name)

	var game_char = character as GameCharacter
	if game_char and game_char.vision:
		if Debug.enabled: print("[FOW] Character has vision component")
		# FoWに登録（Light2D方式ではキャラクターを直接登録）
		var is_friendly := PlayerState.is_friendly(character)
		if Debug.enabled: print("[FOW] is_friendly: ", is_friendly, ", fog_of_war_system: ", fog_of_war_system)
		if fog_of_war_system and is_friendly:
			fog_of_war_system.register_character(character)
		else:
			if Debug.enabled: print("[FOW] Skipping FoW registration - not friendly or no FoW system")

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
			fog_of_war_system.unregister_character(character)

	if enemy_visibility_system:
		enemy_visibility_system.unregister_character(character)


## マップからオクルーダーを抽出
func extract_occluders_from_map(map_node: Node3D) -> void:
	if fog_of_war_system:
		fog_of_war_system.extract_occluders_from_map(map_node)


## ドアオクルーダーの有効/無効を切り替え
## @param door: ドアノード
## @param is_open: ドアが開いているか（trueならオクルーダー無効）
func set_door_open(door: Node3D, is_open: bool) -> void:
	if fog_of_war_system:
		fog_of_war_system.set_door_occluder_enabled(door, not is_open)


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
	if Debug.enabled: print("[FOW] Creating FogOfWarSystem with map_size: ", map_size)
	fog_of_war_system = FogOfWarSystem.new()
	fog_of_war_system.name = "FogOfWarSystem"
	fog_of_war_system.map_size = map_size
	if Debug.enabled: print("[FOW] FogOfWarSystem.map_size after set: ", fog_of_war_system.map_size)
	add_child(fog_of_war_system)
	if Debug.enabled: print("[FOW] FogOfWarSystem added to tree, map_size: ", fog_of_war_system.map_size)


func _setup_enemy_visibility_system() -> void:
	enemy_visibility_system = EnemyVisibilitySystem.new()
	enemy_visibility_system.name = "EnemyVisibilitySystem"
	add_child(enemy_visibility_system)
	enemy_visibility_system.setup(fog_of_war_system)


# ============================================
# スモーク連携
# ============================================

func _on_smoke_area_added(_area: Node3D) -> void:
	# FoWオクルーダーは追加しない（扇形の視界表示はそのまま維持）
	# 敵キャラクターの表示/非表示はEnemyVisibilitySystemで制御
	pass


func _on_smoke_area_removed(_area: Node3D) -> void:
	pass


func _on_smoke_radius_changed(_area: Node3D) -> void:
	pass
