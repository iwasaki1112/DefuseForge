extends Node
class_name CharacterSelectionManager
## キャラクター選択管理
## 選択状態・アウトライン表示・パス適用対象の管理を担当

## 選択変更時のシグナル
signal selection_changed(selected: Array[Node], primary: Node)
## プライマリキャラクター変更時のシグナル
signal primary_changed(character: Node)

## 選択中の全キャラクター
var selected_characters: Array[Node] = []
## 最後に選択したキャラクター（コンテキストメニュー・パス描画基準）
var primary_character: Node = null
## パス適用対象キャラクター（MOVEモード開始時に確定）
var path_target_characters: Array[Node] = []

## アウトライン適用中のメッシュ { character_id: Array[MeshInstance3D] }
var _outlined_meshes_by_character: Dictionary = {}
## 元のマテリアルオーバーライドを保存 { character_id: { mesh_instance_id: { surface_index: Material } } }
var _original_materials_by_character: Dictionary = {}
## 選択マーカー { character_id: CharacterSelectedMarker }
var _selection_markers: Dictionary = {}

## アウトライン設定
var outline_color: Color = Color(0.0, 0.8, 1.0, 1.0)
var outline_thickness: float = 3.5


## キャラクターを選択（既存の選択は解除される）
func add_to_selection(character: Node) -> void:
	if selected_characters.has(character):
		return

	# 既存の選択を全て解除（シングルセレクトのみ）
	for c in selected_characters.duplicate():
		_remove_outline(c)
	selected_characters.clear()

	selected_characters.append(character)
	primary_character = character
	_apply_outline(character)
	selection_changed.emit(selected_characters.duplicate(), primary_character)
	primary_changed.emit(primary_character)


## 選択リストからキャラクターを削除
func remove_from_selection(character: Node) -> void:
	if not selected_characters.has(character):
		return

	selected_characters.erase(character)
	_remove_outline(character)

	# プライマリキャラクターを更新
	if primary_character == character:
		if selected_characters.size() > 0:
			primary_character = selected_characters[-1]
		else:
			primary_character = null
		primary_changed.emit(primary_character)

	selection_changed.emit(selected_characters.duplicate(), primary_character)


## キャラクターの選択をトグル（選択/解除を切り替え）
func toggle_selection(character: Node) -> void:
	if selected_characters.has(character):
		remove_from_selection(character)
	else:
		add_to_selection(character)


## 全選択解除
func deselect_all() -> void:
	for character in selected_characters.duplicate():
		_remove_outline(character)
	selected_characters.clear()
	primary_character = null
	selection_changed.emit(selected_characters.duplicate(), primary_character)
	primary_changed.emit(primary_character)


## 選択中のキャラクターがいるか
func has_selection() -> bool:
	return not selected_characters.is_empty()


## 選択数を取得
func get_selection_count() -> int:
	return selected_characters.size()


## パス適用対象を確定（MOVEモード開始時に呼ぶ）
func capture_path_targets() -> void:
	path_target_characters = selected_characters.duplicate()


## パス適用対象をクリア
func clear_path_targets() -> void:
	path_target_characters.clear()


## パス適用対象を取得
func get_path_targets() -> Array[Node]:
	return path_target_characters.duplicate()


## パス適用対象がいるか
func has_path_targets() -> bool:
	return not path_target_characters.is_empty()


## アウトラインを適用（ステンシル方式）
func _apply_outline(character: Node) -> void:
	var char_id = character.get_instance_id()

	# 既にアウトラインがある場合はスキップ
	if _outlined_meshes_by_character.has(char_id):
		return

	# CharacterModelだけを検索（武器を除外）
	var model = character.get_node_or_null("CharacterModel")
	var search_root = model if model else character
	var meshes = _find_mesh_instances(search_root)
	var outlined: Array[MeshInstance3D] = []
	var original_materials: Dictionary = {}  # { mesh_instance_id: { surface_index: Material } }

	# Note: Stencil outline (STENCIL_MODE_OUTLINE) removed for Godot 4.4 compatibility
	# Selection is indicated by selection marker only

	_outlined_meshes_by_character[char_id] = []
	_original_materials_by_character[char_id] = {}

	# 選択マーカーを作成
	_create_selection_marker(character)



## 特定キャラクターのアウトラインを削除
func _remove_outline(character: Node) -> void:
	var char_id = character.get_instance_id()
	if not _outlined_meshes_by_character.has(char_id):
		return

	var meshes = _outlined_meshes_by_character[char_id]
	var original_materials: Dictionary = _original_materials_by_character.get(char_id, {})

	for mesh in meshes:
		if is_instance_valid(mesh):
			var mesh_id = mesh.get_instance_id()
			var mesh_originals: Dictionary = original_materials.get(mesh_id, {})
			var surface_count = mesh.mesh.get_surface_count() if mesh.mesh else 0

			for i in range(surface_count):
				# 元のオーバーライドマテリアルを復元
				var original_mat = mesh_originals.get(i, null)
				mesh.set_surface_override_material(i, original_mat)

	_outlined_meshes_by_character.erase(char_id)
	_original_materials_by_character.erase(char_id)

	# 選択マーカーを削除
	_remove_selection_marker(character)



## 全てのアウトラインを削除
func clear_all_outlines() -> void:
	for char_id in _outlined_meshes_by_character.keys():
		var meshes = _outlined_meshes_by_character[char_id]
		var original_materials: Dictionary = _original_materials_by_character.get(char_id, {})

		for mesh in meshes:
			if is_instance_valid(mesh):
				var mesh_id = mesh.get_instance_id()
				var mesh_originals: Dictionary = original_materials.get(mesh_id, {})
				var surface_count = mesh.mesh.get_surface_count() if mesh.mesh else 0

				for i in range(surface_count):
					var original_mat = mesh_originals.get(i, null)
					mesh.set_surface_override_material(i, original_mat)

	_outlined_meshes_by_character.clear()
	_original_materials_by_character.clear()

	# 全ての選択マーカーを削除
	_clear_all_selection_markers()


## MeshInstance3Dを再帰的に探す（WeaponAttachmentは除外）
func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []

	# WeaponAttachment以下は武器なので除外
	if node is BoneAttachment3D and node.name == "WeaponAttachment":
		return result

	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_mesh_instances(child))
	return result


## 選択マーカーを作成
func _create_selection_marker(character: Node) -> void:
	var char_id = character.get_instance_id()

	# 既にマーカーがある場合はスキップ
	if _selection_markers.has(char_id):
		return

	var marker: CharacterSelectedMarker = CharacterSelectedMarker.new()
	marker.attach_to_character(character)

	# シーンツリーに追加（キャラクターの親に追加して独立して動作させる）
	var parent: Node = character.get_parent()
	if parent:
		parent.add_child(marker)
	else:
		add_child(marker)

	_selection_markers[char_id] = marker


## 選択マーカーを削除
func _remove_selection_marker(character: Node) -> void:
	var char_id = character.get_instance_id()

	if not _selection_markers.has(char_id):
		return

	var marker: CharacterSelectedMarker = _selection_markers[char_id]
	if is_instance_valid(marker):
		marker.queue_free()

	_selection_markers.erase(char_id)


## 全ての選択マーカーを削除
func _clear_all_selection_markers() -> void:
	for char_id in _selection_markers.keys():
		var marker: CharacterSelectedMarker = _selection_markers[char_id]
		if is_instance_valid(marker):
			marker.queue_free()

	_selection_markers.clear()


# ============================================
# Multiplayer API
# ============================================

## プレイヤーごとの選択状態（マルチプレイヤー用）
## { player_id: { "selected": Array[Node], "primary": Node } }
var _selection_by_player: Dictionary = {}


## プレイヤーの選択状態を設定（リモートプレイヤー用）
func set_selection_for_player(player_id: int, selected: Array[Node], primary: Node) -> void:
	_selection_by_player[player_id] = {
		"selected": selected.duplicate(),
		"primary": primary
	}


## プレイヤーの選択状態を取得
func get_selection_for_player(player_id: int) -> Dictionary:
	return _selection_by_player.get(player_id, { "selected": [], "primary": null })


## プレイヤーの選択状態をクリア
func clear_selection_for_player(player_id: int) -> void:
	_selection_by_player.erase(player_id)


## 全プレイヤーの選択状態をクリア
func clear_all_player_selections() -> void:
	_selection_by_player.clear()


## 現在の選択状態をDictionaryに変換（ネットワーク同期用）
func to_selection_dict() -> Dictionary:
	var selected_ids: Array[int] = []
	for character in selected_characters:
		var game_char := character as GameCharacter
		if game_char and game_char.network_id != 0:
			selected_ids.append(game_char.network_id)
		else:
			selected_ids.append(character.get_instance_id())

	var primary_id: int = 0
	if primary_character:
		var game_char := primary_character as GameCharacter
		if game_char and game_char.network_id != 0:
			primary_id = game_char.network_id
		else:
			primary_id = primary_character.get_instance_id()

	return {
		"selected_ids": selected_ids,
		"primary_id": primary_id
	}


## Dictionaryから選択状態を復元（ネットワーク同期用）
## character_resolver: network_id -> Node を返すCallable
func from_selection_dict(data: Dictionary, character_resolver: Callable) -> void:
	deselect_all()

	var selected_ids: Array = data.get("selected_ids", [])
	var primary_id: int = data.get("primary_id", 0)

	for char_id in selected_ids:
		var character = character_resolver.call(char_id)
		if character:
			add_to_selection(character)

	# プライマリを更新（異なる場合）
	if primary_id != 0:
		var primary = character_resolver.call(primary_id)
		if primary and primary != primary_character:
			primary_character = primary
			primary_changed.emit(primary_character)


## キャラクターがローカルプレイヤーのものか確認してから選択
## リモートキャラクターは選択不可
func add_to_selection_if_local(character: Node) -> bool:
	var game_char := character as GameCharacter
	if game_char and not game_char.is_local():
		return false  # リモートキャラクターは選択不可

	add_to_selection(character)
	return true


## キャラクターがローカルプレイヤーのものか確認してからトグル選択
func toggle_selection_if_local(character: Node) -> bool:
	var game_char := character as GameCharacter
	if game_char and not game_char.is_local():
		return false  # リモートキャラクターは選択不可

	toggle_selection(character)
	return true
