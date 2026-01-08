class_name FogOfWarManagerNode
extends Node

## 視界マネージャー（シーンノード、グリッドベース版）
## 視界システム全体を管理し、敵の可視性を制御
## ゲームシーン内に配置して使用（Autoloadではない）

signal fog_updated
signal character_visibility_changed(character: CharacterBody3D, is_visible: bool)

# 登録された視野コンポーネント
var vision_components: Array = []  # Array of VisionComponent

# コンポーネントごとのコールバックを保存（disconnect用）
var _component_callbacks: Dictionary = {}  # key: VisionComponent, value: Callable

# 現在の可視セル（全味方の視野を結合）
var current_visible_cells: Array[Vector2i] = []

# 敵の可視性状態
var enemy_visibility: Dictionary = {}  # key: CharacterBody3D, value: bool

# FogOfWarRenderer参照
var fog_renderer: Node3D = null

# キャッシュされた敵リスト（get_nodes_in_groupの呼び出しを削減）
var _cached_enemies: Array = []  # Array of CharacterBody3D
var _enemies_cache_dirty: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 敵のスポーン/デスポーンを監視
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	# 初期状態で全敵を非表示にする（遅延実行）
	_initialize_enemy_visibility.call_deferred()


## ノード追加時のコールバック
func _on_node_added(node: Node) -> void:
	if node.is_in_group("enemies"):
		_enemies_cache_dirty = true


## ノード削除時のコールバック
func _on_node_removed(node: Node) -> void:
	if node.is_in_group("enemies"):
		_enemies_cache_dirty = true
		# 削除されたノードをキャッシュから即座に除去
		_cached_enemies.erase(node)
		enemy_visibility.erase(node)


## 敵リストを取得（キャッシュ利用）
## 注: グループから外れたノードはキャッシュから自動除去
func _get_enemies() -> Array:
	if _enemies_cache_dirty:
		_cached_enemies = get_tree().get_nodes_in_group("enemies")
		_enemies_cache_dirty = false
	else:
		# キャッシュ有効時も、グループ離脱したノードを除去（低コスト検証）
		var i := 0
		while i < _cached_enemies.size():
			var enemy = _cached_enemies[i]
			if not is_instance_valid(enemy) or not enemy.is_in_group("enemies"):
				_cached_enemies.remove_at(i)
				enemy_visibility.erase(enemy)
			else:
				i += 1
	return _cached_enemies


## 敵の初期可視性を設定
func _initialize_enemy_visibility() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	# キャッシュから敵を取得
	for enemy in _get_enemies():
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
		# レンダラーにも登録
		if fog_renderer and fog_renderer.has_method("register_vision_component"):
			fog_renderer.register_vision_component(component)


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
		# レンダラーからも解除
		if fog_renderer and fog_renderer.has_method("unregister_vision_component"):
			fog_renderer.unregister_vision_component(component)


## 視野が更新されたときのコールバック
func _on_visibility_changed(_visible_cells: Array, _component: Node) -> void:
	_update_combined_visibility()
	_update_enemy_visibility()
	fog_updated.emit()


## 全味方の視野を結合（グリッドベース）
func _update_combined_visibility() -> void:
	current_visible_cells.clear()

	for component in vision_components:
		if component and component.character:
			# visible_cellsプロパティを使用
			if "visible_cells" in component:
				for cell in component.visible_cells:
					if cell not in current_visible_cells:
						current_visible_cells.append(cell)


## 指定位置が現在視野内かどうか
func is_position_visible(pos: Vector3) -> bool:
	for component in vision_components:
		if component and component.is_position_visible(pos):
			return true
	return false


## 敵の可視性を更新
func _update_enemy_visibility() -> void:
	# キャッシュから敵を取得
	for enemy in _get_enemies():
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


## 敵の可視性を設定（公開API）
## 外部から敵の可視性状態を設定する場合はこのメソッドを使用
func set_enemy_visibility(enemy: CharacterBody3D, is_visible: bool) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return

	var was_visible: bool = enemy_visibility.get(enemy, false)
	enemy_visibility[enemy] = is_visible

	# 表示状態が変わった場合のみシグナルを発火
	if was_visible != is_visible:
		character_visibility_changed.emit(enemy, is_visible)

	# キャラクターの表示/非表示を設定
	set_character_visible(enemy, is_visible)


## 視界をリセット（ラウンド開始時など）
func reset_visibility() -> void:
	enemy_visibility.clear()
	current_visible_cells.clear()
	_enemies_cache_dirty = true  # キャッシュを更新

	# 全敵を非表示にする（キャッシュから取得）
	for enemy in _get_enemies():
		if enemy and is_instance_valid(enemy):
			set_character_visible(enemy, false)

	fog_updated.emit()


## FogOfWarRendererを設定
func set_fog_renderer(renderer: Node3D) -> void:
	fog_renderer = renderer
	# 既存の視野コンポーネントをレンダラーに登録
	if fog_renderer and fog_renderer.has_method("register_vision_component"):
		for component in vision_components:
			fog_renderer.register_vision_component(component)


## 現在の可視セルを取得
func get_current_visible_cells() -> Array[Vector2i]:
	return current_visible_cells
