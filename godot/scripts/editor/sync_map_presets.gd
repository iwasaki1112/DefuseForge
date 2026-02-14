extends SceneTree
## map_registry.gd の PRESET_FILES を自動更新
##
## 使い方:
##   godot --headless --script res://scripts/editor/sync_map_presets.gd
##
## scenes/maps/ の map_id付き.tscn を検出し、
## map_registry.gd の PRESET_FILES 配列を更新する。
## iOSデプロイ前に実行すること。


const SCENE_DIR := "res://scenes/maps/"
const REGISTRY_PATH := "res://scripts/registries/map_registry.gd"


func _init() -> void:
	var preset_paths: Array[String] = []

	# scenes/maps/ から map_id付き .tscn を検出
	var scene_dir := DirAccess.open(SCENE_DIR)
	if scene_dir:
		scene_dir.list_dir_begin()
		var file_name := scene_dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tscn"):
				var path := SCENE_DIR + file_name
				var scene := load(path) as PackedScene
				if scene and _has_map_id(scene):
					preset_paths.append(path)
			file_name = scene_dir.get_next()
		scene_dir.list_dir_end()

	preset_paths.sort()

	print("Found %d map presets:" % preset_paths.size())
	for p in preset_paths:
		print("  ", p)

	# map_registry.gd を読み込み
	var abs_path := ProjectSettings.globalize_path(REGISTRY_PATH)
	var content := FileAccess.get_file_as_string(abs_path)
	if content.is_empty():
		print("ERROR: Could not read ", REGISTRY_PATH)
		quit()
		return

	# PRESET_FILES配列を置換
	var regex := RegEx.new()
	regex.compile("const PRESET_FILES := \\[([^\\]]*?)\\]")
	var match := regex.search(content)
	if not match:
		print("ERROR: Could not find PRESET_FILES in ", REGISTRY_PATH)
		quit()
		return

	var new_entries := ""
	for p in preset_paths:
		new_entries += "\n\t\"%s\"," % p
	var new_array := "const PRESET_FILES := [%s\n]" % new_entries

	content = content.substr(0, match.get_start()) + new_array + content.substr(match.get_end())

	# 書き込み
	var file := FileAccess.open(abs_path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
		print("Updated PRESET_FILES in ", REGISTRY_PATH)
	else:
		print("ERROR: Could not write to ", REGISTRY_PATH)

	quit()


## PackedSceneのルートノードにmap_idプロパティがあるか確認
func _has_map_id(scene: PackedScene) -> bool:
	var state := scene.get_state()
	if state.get_node_count() == 0:
		return false

	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"map_id":
			var val = state.get_node_property_value(0, i)
			return not str(val).is_empty()
	return false
