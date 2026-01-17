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

## アウトライン設定
var outline_color: Color = Color(0.0, 0.8, 1.0, 1.0)
var outline_thickness: float = 3.5


## 選択リストにキャラクターを追加
func add_to_selection(character: Node) -> void:
	if selected_characters.has(character):
		return

	selected_characters.append(character)
	primary_character = character
	_apply_outline(character)
	selection_changed.emit(selected_characters.duplicate(), primary_character)
	primary_changed.emit(primary_character)
	print("[Selection] Added %s (total: %d)" % [character.name, selected_characters.size()])


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
	print("[Selection] Removed %s (total: %d)" % [character.name, selected_characters.size()])


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
	print("[Selection] Deselected all")


## 選択中のキャラクターがいるか
func has_selection() -> bool:
	return not selected_characters.is_empty()


## 選択数を取得
func get_selection_count() -> int:
	return selected_characters.size()


## パス適用対象を確定（MOVEモード開始時に呼ぶ）
func capture_path_targets() -> void:
	path_target_characters = selected_characters.duplicate()
	print("[Selection] Captured %d path targets" % path_target_characters.size())


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

	var meshes = _find_mesh_instances(character)
	var outlined: Array[MeshInstance3D] = []

	for mesh in meshes:
		var surface_count = mesh.mesh.get_surface_count() if mesh.mesh else 0
		for i in range(surface_count):
			var mat = mesh.get_active_material(i)
			if mat and mat is StandardMaterial3D:
				# マテリアルを複製してステンシルアウトラインを設定
				var mat_copy: StandardMaterial3D = mat.duplicate()
				mat_copy.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE
				mat_copy.stencil_outline_thickness = outline_thickness
				mat_copy.stencil_color = outline_color
				mesh.set_surface_override_material(i, mat_copy)
			elif mat:
				# 新しいStandardMaterial3Dを作成
				var new_mat = StandardMaterial3D.new()
				new_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE
				new_mat.stencil_outline_thickness = outline_thickness
				new_mat.stencil_color = outline_color
				mesh.set_surface_override_material(i, new_mat)
		outlined.append(mesh)

	_outlined_meshes_by_character[char_id] = outlined
	print("[Outline] Applied outline to %s (%d meshes)" % [character.name, outlined.size()])


## 特定キャラクターのアウトラインを削除
func _remove_outline(character: Node) -> void:
	var char_id = character.get_instance_id()
	if not _outlined_meshes_by_character.has(char_id):
		return

	var meshes = _outlined_meshes_by_character[char_id]
	for mesh in meshes:
		if is_instance_valid(mesh):
			# サーフェスオーバーライドをクリア（元のマテリアルに戻る）
			var surface_count = mesh.mesh.get_surface_count() if mesh.mesh else 0
			for i in range(surface_count):
				mesh.set_surface_override_material(i, null)

	_outlined_meshes_by_character.erase(char_id)
	print("[Outline] Removed outline from %s" % character.name)


## 全てのアウトラインを削除
func clear_all_outlines() -> void:
	for char_id in _outlined_meshes_by_character.keys():
		var meshes = _outlined_meshes_by_character[char_id]
		for mesh in meshes:
			if is_instance_valid(mesh):
				var surface_count = mesh.mesh.get_surface_count() if mesh.mesh else 0
				for i in range(surface_count):
					mesh.set_surface_override_material(i, null)
	_outlined_meshes_by_character.clear()


## MeshInstance3Dを再帰的に探す
func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_mesh_instances(child))
	return result
