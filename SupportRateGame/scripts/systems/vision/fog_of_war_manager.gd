class_name FogOfWarManagerNode
extends Node

## 視界マネージャー（シーンノード）
## 視界システム全体を管理し、敵の可視性を制御
## ゲームシーン内に配置して使用（Autoloadではない）

signal fog_updated
signal character_visibility_changed(character: CharacterBody3D, is_visible: bool)

# 登録された視野コンポーネント
var vision_components: Array = []  # Array of VisionComponent

# コンポーネントごとのコールバックを保存（disconnect用）
var _component_callbacks: Dictionary = {}  # key: VisionComponent, value: Callable

# 現在の視野ポリゴン（全味方の視野を結合）
var current_visible_points: Array = []  # Array of Vector3

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

	for enemy in GameManager.enemies:
		if enemy and is_instance_valid(enemy):
			set_character_visible(enemy, false)
			enemy_visibility[enemy] = false


## 視野コンポーネントを登録
func register_vision_component(component: Node) -> void:
	if component not in vision_components:
		vision_components.append(component)
		# バインドされたCallableを保存して、後でdisconnectできるようにする
		var callback := _on_visibility_changed.bind(component)
		_component_callbacks[component] = callback
		component.visibility_changed.connect(callback)


## 視野コンポーネントを解除
func unregister_vision_component(component: Node) -> void:
	if component in vision_components:
		vision_components.erase(component)
		# 保存したCallableを使ってdisconnect
		if component in _component_callbacks:
			var callback: Callable = _component_callbacks[component]
			if component.visibility_changed.is_connected(callback):
				component.visibility_changed.disconnect(callback)
			_component_callbacks.erase(component)


## 視野が更新されたときのコールバック
func _on_visibility_changed(_visible_points: Array, _component: Node) -> void:
	_update_combined_visibility()
	_update_enemy_visibility()
	fog_updated.emit()


## 全味方の視野を結合
func _update_combined_visibility() -> void:
	current_visible_points.clear()

	for component in vision_components:
		if component and component.character:
			for point in component.visible_points:
				current_visible_points.append(point)


## 指定位置が現在視野内かどうか
func is_position_visible(pos: Vector3) -> bool:
	for component in vision_components:
		if component and component.is_position_visible(pos):
			return true
	return false


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
			set_character_visible(enemy, is_visible)


## キャラクターの表示/非表示を設定（公開API）
func set_character_visible(character: CharacterBody3D, is_visible: bool) -> void:
	if not character:
		return

	# CharacterModelを取得して可視性を設定
	var model := character.get_node_or_null("CharacterModel")
	if model:
		model.visible = is_visible
	else:
		character.visible = is_visible


## 敵が現在視野内かどうか
func is_enemy_visible(enemy: CharacterBody3D) -> bool:
	return enemy_visibility.get(enemy, false)


## 視界をリセット（ラウンド開始時など）
func reset_visibility() -> void:
	enemy_visibility.clear()
	current_visible_points.clear()

	# 全敵を非表示にする
	if GameManager:
		for enemy in GameManager.enemies:
			if enemy and is_instance_valid(enemy):
				set_character_visible(enemy, false)

	fog_updated.emit()


## FogOfWarRendererを設定
func set_fog_renderer(renderer: Node3D) -> void:
	fog_renderer = renderer


## 現在の視野ポイントを取得
func get_current_visible_points() -> Array:
	return current_visible_points
