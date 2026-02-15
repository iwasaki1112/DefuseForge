extends Node
class_name EnemyVisibilitySystem
## Enemy visibility management system
## Controls enemy character visibility based on friendly vision
## Works with PlayerState, VisionComponent, and FogOfWarSystem (Light2D方式)
##
## Light2D方式ではFoWの描画はGPUで行われるが、
## 敵の可視判定はVisionComponent.is_position_in_view()で行う（単発レイキャスト）

# ============================================
# Signals
# ============================================
signal visibility_changed(enemy: Node, is_visible: bool)

# ============================================
# References
# ============================================
var _fog_of_war_system: Node3D = null
var _characters: Array[Node] = []

# ============================================
# State
# ============================================
var _visibility_cache: Dictionary[int, bool] = {}  # { instance_id: bool }
var _is_enabled: bool = true

# SmokeAreaManager reference
var _smoke_area_manager: SmokeAreaManager = null

# Update settings
const UPDATE_INTERVAL: float = 0.033  # 30Hz
var _update_timer: float = 0.0

# 分散更新設定（CPU負荷均等化）
const ENEMIES_PER_FRAME: int = 2  # 1フレームあたりの最大チェック数
var _enemy_check_index: int = 0   # 次にチェックする敵のインデックス

# ============================================
# Lifecycle
# ============================================

func _physics_process(delta: float) -> void:
	if not _is_enabled:
		return

	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		update_visibility()


# ============================================
# Setup
# ============================================

## Initialize with FogOfWarSystem reference
func setup(fog_of_war: Node3D) -> void:
	_fog_of_war_system = fog_of_war
	PlayerState.team_changed.connect(_on_player_team_changed)


## Set SmokeAreaManager reference
func set_smoke_area_manager(manager: SmokeAreaManager) -> void:
	_smoke_area_manager = manager


## Register a character to be managed
func register_character(character: Node) -> void:
	if character in _characters:
		return
	_characters.append(character)

	# Apply initial visibility
	update_visibility()


## Unregister a character
func unregister_character(character: Node) -> void:
	_characters.erase(character)
	var char_id := character.get_instance_id()
	_visibility_cache.erase(char_id)


# ============================================
# Enable/Disable
# ============================================

## Enable the system (normal gameplay)
func enable() -> void:
	enable_full()


## Disable the system (debug mode - show all)
func disable() -> void:
	_is_enabled = false
	# Show all characters
	for character in _characters:
		character.visible = true


## Enable with full visibility checking (FoW ON)
func enable_full() -> void:
	_is_enabled = true
	update_visibility()


## Enable with lightweight visibility (FoW OFF)
## Same as enable_full in Light2D mode since we always use is_position_in_view()
func enable_lightweight() -> void:
	_is_enabled = true
	update_visibility()


## Check if system is enabled
func is_enabled() -> bool:
	return _is_enabled


# ============================================
# Visibility API
# ============================================

## Update visibility of all enemy characters
## 分散更新: 1フレームあたりENEMIES_PER_FRAME体ずつチェック（CPU負荷均等化）
func update_visibility() -> void:
	if not _is_enabled:
		return

	# Friendly characters are always visible
	for friendly in _get_friendly_characters():
		friendly.visible = true

	# T側は人質を常に表示（T側が人質を警備しているため）
	if PlayerState.get_player_team() == GameCharacter.Team.TERRORIST:
		for character in _characters:
			if character is GameCharacter and character.team == GameCharacter.Team.NONE:
				character.visible = true

	# 敵リストを取得
	var enemies := _get_enemy_characters()
	if enemies.is_empty():
		_enemy_check_index = 0
		return

	# インデックスが範囲外の場合はリセット
	if _enemy_check_index >= enemies.size():
		_enemy_check_index = 0

	# ENEMIES_PER_FRAME体ずつチェック（分散処理）
	var checked_count := 0
	while checked_count < ENEMIES_PER_FRAME and checked_count < enemies.size():
		var enemy := enemies[_enemy_check_index]
		_check_enemy_visibility(enemy)

		_enemy_check_index += 1
		if _enemy_check_index >= enemies.size():
			_enemy_check_index = 0

		checked_count += 1


## 単一の敵の可視性をチェック
func _check_enemy_visibility(enemy: Node) -> void:
	var enemy_node3d := enemy as Node3D
	if not enemy_node3d:
		return

	var enemy_pos: Vector3 = enemy_node3d.global_position
	var is_visible := _is_position_visible_to_friendlies(enemy_pos)

	# スモーク可視性チェック（双方向で不透明）
	var _hide_reason := ""
	if is_visible and _smoke_area_manager:
		if _smoke_area_manager.is_position_in_smoke(enemy_pos):
			# 敵がスモーク内 → 非表示（外から中が見えない）
			is_visible = false
			_hide_reason = "in_smoke"
		elif _are_all_friendlies_in_smoke():
			# 全味方がスモーク内 → 外の敵も非表示（中から外が見えない）
			is_visible = false
			_hide_reason = "all_friendlies_in_smoke"
	elif not is_visible:
		_hide_reason = "fow"

	var instance_id := enemy.get_instance_id()

	# Update only if changed
	if _visibility_cache.get(instance_id) != is_visible:
		_visibility_cache[instance_id] = is_visible
		enemy.visible = is_visible
		visibility_changed.emit(enemy, is_visible)
		if Debug.enabled:
			var state_str := "VISIBLE" if is_visible else "HIDDEN"
			var smoke_info := _get_nearest_smoke_debug_info(enemy_pos)
			print("[EVS] ", enemy.name, " -> ", state_str,
				" reason=", _hide_reason if not is_visible else "ok",
				" enemy_pos=", enemy_pos, smoke_info)


## 全ての生存味方がスモーク内にいるか判定
func _are_all_friendlies_in_smoke() -> bool:
	if not _smoke_area_manager:
		return false
	for friendly in _get_friendly_characters():
		var game_char := friendly as GameCharacter
		if not game_char or not game_char.is_alive:
			continue
		if not _smoke_area_manager.is_position_in_smoke(friendly.global_position):
			return false  # スモーク外の味方がいる → false
	return true  # 全味方がスモーク内


## Check if a world position is visible to any friendly character
func is_position_visible(world_pos: Vector3) -> bool:
	return _is_position_visible_to_friendlies(world_pos)


## Get cached visibility state for a character
func get_visibility(character: Node) -> bool:
	return _visibility_cache.get(character.get_instance_id(), false)


# ============================================
# Internal - Vision Check
# ============================================

## FoWテクスチャを直接サンプリングして可視判定
## Light2D方式では視覚的なFoW表示と完全に同期した判定を行う
func _is_position_visible_to_friendlies(world_pos: Vector3) -> bool:
	# FogOfWarSystemのテクスチャサンプリングを使用
	# これにより視覚的な可視性と論理的な可視性が完全に一致する
	if _fog_of_war_system and _fog_of_war_system.has_method("is_position_visible_in_fow"):
		return _fog_of_war_system.is_position_visible_in_fow(world_pos)

	# フォールバック: FoWシステムが利用できない場合はVisionComponentを使用
	for friendly in _get_friendly_characters():
		var game_char := friendly as GameCharacter
		if not game_char or not game_char.vision or not game_char.is_alive:
			continue

		if game_char.vision.is_position_in_view(world_pos):
			return true

	return false


# ============================================
# Internal - Character Classification
# ============================================

func _get_friendly_characters() -> Array[Node]:
	return PlayerState.filter_friendlies(_characters)


func _get_enemy_characters() -> Array[Node]:
	var result: Array[Node] = []
	for character in _characters:
		if PlayerState.is_enemy(character):
			result.append(character)
		# Team.NONE（hostage等）: CT側はFoWで可視性を制御、T側は常に表示（update_visibilityで処理済み）
		elif character is GameCharacter and character.team == GameCharacter.Team.NONE:
			if PlayerState.get_player_team() != GameCharacter.Team.TERRORIST:
				result.append(character)
	return result


# ============================================
# Signal Handlers
# ============================================

func _on_player_team_changed(_new_team: GameCharacter.Team) -> void:
	_visibility_cache.clear()
	update_visibility()


## デバッグ用: 最寄りスモークエリアの情報を文字列で返す
func _get_nearest_smoke_debug_info(pos: Vector3) -> String:
	if not _smoke_area_manager:
		return ""
	var areas: Array[Node3D] = _smoke_area_manager._active_areas
	if areas.is_empty():
		return " smoke_areas=0"
	var nearest_dist := INF
	var nearest_radius := 0.0
	var nearest_pos := Vector3.ZERO
	for area in areas:
		if not is_instance_valid(area):
			continue
		var dist := pos.distance_to(area.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_pos = area.global_position
			if area.has_method("get_current_radius"):
				nearest_radius = area.get_current_radius()
	return " smoke_areas=%d nearest_smoke_dist=%.1f smoke_radius=%.1f smoke_pos=%s" % [
		areas.size(), nearest_dist, nearest_radius, str(nearest_pos)]
