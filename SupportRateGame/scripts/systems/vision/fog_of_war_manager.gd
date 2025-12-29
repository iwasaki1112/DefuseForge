extends Node

## Fog of War マネージャー（Autoload）
## 視界システム全体を管理し、探索済みエリアを記録

signal fog_updated
signal character_visibility_changed(character: CharacterBody3D, is_visible: bool)

# VisionComponentスクリプト参照
const VisionComponentScript = preload("res://scripts/systems/vision/vision_component.gd")

# 登録された視野コンポーネント
var vision_components: Array = []  # Array of VisionComponent

# 現在の視野ポリゴン（全味方の視野を結合）
var current_visible_points: Array = []  # Array of Vector3

# 探索済みエリア（GridMapのようなデータ構造）
var explored_cells: Dictionary = {}  # key: Vector2i, value: bool

# 探索グリッドの設定
var grid_cell_size: float = 1.0  # 1メートル単位

# 敵の可視性状態
var enemy_visibility: Dictionary = {}  # key: CharacterBody3D, value: bool

# FogOfWarRenderer参照
var fog_renderer: Node3D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 初期状態で全敵を非表示にする（遅延実行）
	_initialize_enemy_visibility.call_deferred()


## 敵の初期可視性を設定
func _initialize_enemy_visibility() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not GameManager:
		return

	print("[FogOfWarManager] Initializing enemy visibility, enemies: %d" % GameManager.enemies.size())
	for enemy in GameManager.enemies:
		if enemy and is_instance_valid(enemy):
			_set_character_visible(enemy, false)
			enemy_visibility[enemy] = false
			print("[FogOfWarManager] Enemy '%s' hidden initially" % enemy.name)


## 視野コンポーネントを登録
func register_vision_component(component: Node) -> void:
	if component not in vision_components:
		vision_components.append(component)
		component.visibility_changed.connect(_on_visibility_changed.bind(component))
		print("[FogOfWarManager] Vision component registered")


## 視野コンポーネントを解除
func unregister_vision_component(component: Node) -> void:
	if component in vision_components:
		vision_components.erase(component)
		if component.visibility_changed.is_connected(_on_visibility_changed):
			component.visibility_changed.disconnect(_on_visibility_changed)
		print("[FogOfWarManager] Vision component unregistered")


## 視野が更新されたときのコールバック
func _on_visibility_changed(_visible_points: Array, _component: Node) -> void:
	_update_combined_visibility()
	_update_explored_cells()
	_update_enemy_visibility()
	fog_updated.emit()


## 全味方の視野を結合
func _update_combined_visibility() -> void:
	current_visible_points.clear()

	for component in vision_components:
		if component and component.character:
			for point in component.visible_points:
				current_visible_points.append(point)


## 探索済みセルを更新
func _update_explored_cells() -> void:
	for point in current_visible_points:
		var cell := _world_to_grid(point)
		explored_cells[cell] = true


## ワールド座標からグリッド座標に変換
func _world_to_grid(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / grid_cell_size)),
		int(floor(world_pos.z / grid_cell_size))
	)


## グリッド座標からワールド座標に変換（セル中心）
func _grid_to_world(grid_pos: Vector2i) -> Vector3:
	return Vector3(
		(grid_pos.x + 0.5) * grid_cell_size,
		0.0,
		(grid_pos.y + 0.5) * grid_cell_size
	)


## 指定位置が現在視野内かどうか
func is_position_visible(pos: Vector3) -> bool:
	for component in vision_components:
		if component and component.is_position_visible(pos):
			return true
	return false


## 指定位置が探索済みかどうか
func is_position_explored(pos: Vector3) -> bool:
	var cell := _world_to_grid(pos)
	return explored_cells.get(cell, false)


## 敵の可視性を更新
func _update_enemy_visibility() -> void:
	if not GameManager:
		return

	for enemy in GameManager.enemies:
		if not enemy or not is_instance_valid(enemy):
			continue

		var was_visible: bool = enemy_visibility.get(enemy, false)
		var is_visible: bool = is_position_visible(enemy.global_position)

		if was_visible != is_visible:
			enemy_visibility[enemy] = is_visible
			character_visibility_changed.emit(enemy, is_visible)

			# 敵の表示/非表示を切り替え
			_set_character_visible(enemy, is_visible)
			print("[FogOfWarManager] Enemy '%s' visibility changed: %s" % [enemy.name, is_visible])


## キャラクターの表示/非表示を設定
func _set_character_visible(character: CharacterBody3D, visible: bool) -> void:
	if not character:
		return

	# CharacterModelを取得して可視性を設定
	var model := character.get_node_or_null("CharacterModel")
	if model:
		model.visible = visible
	else:
		character.visible = visible


## 敵が現在視野内かどうか
func is_enemy_visible(enemy: CharacterBody3D) -> bool:
	return enemy_visibility.get(enemy, false)


## Fog of Warをリセット（ラウンド開始時など）
func reset_fog() -> void:
	explored_cells.clear()
	enemy_visibility.clear()
	current_visible_points.clear()

	# 全敵を非表示にする
	if GameManager:
		for enemy in GameManager.enemies:
			if enemy and is_instance_valid(enemy):
				_set_character_visible(enemy, false)

	fog_updated.emit()
	print("[FogOfWarManager] Fog reset")


## FogOfWarRendererを設定
func set_fog_renderer(renderer: Node3D) -> void:
	fog_renderer = renderer


## 現在の視野ポイントを取得
func get_current_visible_points() -> Array:
	return current_visible_points


## デバッグ情報を取得
func get_debug_info() -> Dictionary:
	return {
		"vision_components": vision_components.size(),
		"visible_points": current_visible_points.size(),
		"explored_cells": explored_cells.size(),
		"visible_enemies": enemy_visibility.values().count(true)
	}
