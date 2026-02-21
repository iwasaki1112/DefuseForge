extends SceneTree
## 新しいGridMapベースのマップを一括作成
##
## 使い方:
##   godot --headless --script res://scripts/editor/new_gridmap_map.gd -- <map_id>
##
## 例:
##   godot --headless --script res://scripts/editor/new_gridmap_map.gd -- warehouse
##
## 生成ファイル:
##   scenes/maps/<map_id>.tscn — GridMapシーン（エディタで開いてタイル配置）
##
## .tscnにMapBaseの@exportでメタデータを埋め込むため、
## 個別の.gdや.tresは不要。MapRegistryが自動検出する。


const FLOOR_LIBRARY_PATH := "res://data/tiles/tile_library_floor.tres"
const WALL_LIBRARY_PATH := "res://data/tiles/tile_library_wall.tres"
const DOOR_LIBRARY_PATH := "res://data/tiles/tile_library_door.tres"
const WINDOW_LIBRARY_PATH := "res://data/tiles/tile_library_window.tres"
const MAP_BASE_SCRIPT := "res://scripts/maps/map_base.gd"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1:
		print("Usage: godot --headless --script new_gridmap_map.gd -- <map_id>")
		print("Example: ... -- warehouse")
		quit()
		return

	var map_id := args[0]
	var disp_name := map_id.to_pascal_case()
	var scene_path := "res://scenes/maps/%s.tscn" % map_id

	print("=== New GridMap Map: %s ===" % map_id)

	# 既存チェック
	var abs_path := ProjectSettings.globalize_path(scene_path)
	if FileAccess.file_exists(abs_path):
		print("WARNING: Already exists: %s (will be overwritten)" % scene_path)

	# .tscn生成（MapBase直接方式 — map_id/display_nameを@exportで埋め込み）
	_write_file(scene_path, '[gd_scene load_steps=6 format=3]

[ext_resource type="MeshLibrary" path="%s" id="1"]
[ext_resource type="Script" path="%s" id="2"]
[ext_resource type="MeshLibrary" path="%s" id="3"]
[ext_resource type="MeshLibrary" path="%s" id="4"]
[ext_resource type="MeshLibrary" path="%s" id="5"]

[node name="%s" type="Node3D"]
script = ExtResource("2")
map_id = "%s"
display_name = "%s"

[node name="GridMapGround" type="GridMap" parent="."]
mesh_library = ExtResource("1")
cell_size = Vector3(2, 2, 2)
cell_center_y = false
data = {
"cells": PackedInt32Array()
}

[node name="GridMapWall" type="GridMap" parent="."]
mesh_library = ExtResource("3")
cell_size = Vector3(2, 2, 2)
cell_center_y = false
data = {
"cells": PackedInt32Array()
}

[node name="GridMapDoor" type="GridMap" parent="."]
mesh_library = ExtResource("4")
cell_size = Vector3(2, 2, 2)
cell_center_y = false
data = {
"cells": PackedInt32Array()
}

[node name="GridMapWindow" type="GridMap" parent="."]
mesh_library = ExtResource("5")
cell_size = Vector3(2, 2, 2)
cell_center_y = false
data = {
"cells": PackedInt32Array()
}

[node name="spawn_ct_0" type="Marker3D" parent="."]
transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 10, 0, -2)

[node name="spawn_ct_1" type="Marker3D" parent="."]
transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 10, 0, 2)

[node name="spawn_t_0" type="Marker3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -2, 0, -2)

[node name="spawn_t_1" type="Marker3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -2, 0, 2)
' % [FLOOR_LIBRARY_PATH, MAP_BASE_SCRIPT, WALL_LIBRARY_PATH, DOOR_LIBRARY_PATH, WINDOW_LIBRARY_PATH, disp_name, map_id, disp_name])

	print("")
	print("Created: %s" % scene_path)
	print("")
	print("次のステップ:")
	print("  1. Godotエディタで %s を開く" % scene_path)
	print("  2. GridMapノードを選択してタイルを配置")
	print("  3. スポーンポイント(Marker3D)の位置を調整")
	print("  4. 保存 → マップ選択画面に自動で表示される")

	quit()


func _write_file(res_path: String, content: String) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(res_path), FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
		print("  Saved: %s" % res_path)
	else:
		print("  ERROR: Could not write %s" % res_path)
