extends SceneTree
## GridMapシーンをMapBase互換のベイク済みシーンに変換
##
## 使い方:
##   godot --headless --script res://scripts/editor/bake_gridmap.gd -- <input.tscn> <output.tscn> <map_id>
##
## 例:
##   godot --headless --script res://scripts/editor/bake_gridmap.gd -- \
##     res://scenes/maps/gridmap_test.tscn res://scenes/maps/tile_test.tscn tile_test

## MeshLibraryアイテム名 → MapBase接頭辞
const ITEM_PREFIX := {
	"floor_concrete": "Ground_Floor",
	"wall_exterior": "Wall_Ext",
	"wall_interior": "Wall_Int",
	"door_frame": "Door_Frame",
}

## MapBase互換スクリプトのテンプレート
const MAP_SCRIPT_TEMPLATE := """extends MapBase

func _ready() -> void:
	_map_name = "%s"
	super._ready()
"""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		print("Usage: godot --headless --script bake_gridmap.gd -- <input.tscn> <output.tscn> <map_id>")
		print("Example: ... -- res://scenes/maps/gridmap_test.tscn res://scenes/maps/tile_test.tscn tile_test")
		quit()
		return

	var input_path := args[0]
	var output_path := args[1]
	var map_id := args[2]

	print("=== GridMap Bake ===")
	print("Input:  ", input_path)
	print("Output: ", output_path)
	print("Map ID: ", map_id)

	# 入力シーンをロード
	var scene := load(input_path) as PackedScene
	if not scene:
		print("ERROR: Could not load ", input_path)
		quit()
		return

	var source := scene.instantiate()

	# GridMapを探す
	var grid_map := _find_node_by_class(source, "GridMap") as GridMap
	if not grid_map:
		print("ERROR: No GridMap found in scene")
		source.free()
		quit()
		return

	var lib := grid_map.mesh_library
	if not lib:
		print("ERROR: GridMap has no MeshLibrary")
		source.free()
		quit()
		return

	var cell_size := grid_map.cell_size
	print("Cell size: ", cell_size)

	# 出力ルートノード
	var output := Node3D.new()
	output.name = map_id.to_pascal_case()

	var cells := grid_map.get_used_cells()
	print("Baking ", cells.size(), " cells...")

	for cell in cells:
		var item_id := grid_map.get_cell_item(cell)
		if item_id == GridMap.INVALID_CELL_ITEM:
			continue

		var item_name := lib.get_item_name(item_id)
		var prefix: String = ITEM_PREFIX.get(item_name, item_name)

		# ワールド座標（GridMapの配置を考慮）
		var world_pos := Vector3(
			cell.x * cell_size.x,
			cell.y * cell_size.y,
			cell.z * cell_size.z,
		)

		# セルの回転
		var orientation := grid_map.get_cell_item_orientation(cell)
		var basis := grid_map.get_basis_with_orthogonal_index(orientation)

		# メッシュ
		var mesh := lib.get_item_mesh(item_id)
		if not mesh:
			continue

		var node_name := "%s_T%d_%d" % [prefix, cell.x, cell.z]

		# MeshInstance3D
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = node_name
		mesh_inst.mesh = mesh

		# mesh_transformを適用
		var mesh_transform := lib.get_item_mesh_transform(item_id)
		mesh_inst.transform = Transform3D(basis, world_pos) * mesh_transform

		output.add_child(mesh_inst)
		mesh_inst.owner = output

		# StaticBody3D + CollisionShape3D
		# owner設定はツリーに追加した後でないと無効
		var shapes := lib.get_item_shapes(item_id)
		if shapes.size() >= 2:
			var body := StaticBody3D.new()
			body.name = node_name + "_body"
			mesh_inst.add_child(body)
			body.owner = output
			var i := 0
			while i < shapes.size():
				if shapes[i] is Shape3D:
					var col := CollisionShape3D.new()
					col.shape = shapes[i]
					if i + 1 < shapes.size() and shapes[i + 1] is Transform3D:
						col.transform = shapes[i + 1]
					body.add_child(col)
					col.owner = output
				i += 2

	# スポーンポイントをコピー
	var spawn_count := 0
	for child in source.get_children():
		if child.name.to_lower().begins_with("spawn_") and child is Node3D:
			var marker := Marker3D.new()
			marker.name = child.name
			marker.transform = (child as Node3D).transform
			output.add_child(marker)
			marker.owner = output
			spawn_count += 1

	print("Spawns copied: ", spawn_count)

	# マップスクリプト生成
	var script_path := output_path.replace(".tscn", ".gd")
	var script_content := MAP_SCRIPT_TEMPLATE % map_id.to_upper()
	var file := FileAccess.open(
		ProjectSettings.globalize_path(script_path), FileAccess.WRITE
	)
	if file:
		file.store_string(script_content)
		file.close()
		print("Script saved: ", script_path)

	# シーン保存（スクリプトは.tscnに直接記述）
	var packed := PackedScene.new()
	packed.pack(output)
	var err := ResourceSaver.save(packed, output_path)

	source.free()
	output.free()

	if err == OK:
		# .tscnにスクリプト参照を追記
		_patch_scene_script(output_path, script_path)
		print("=== Baked: ", output_path, " (", cells.size(), " cells) ===")
	else:
		print("=== ERROR saving: ", err, " ===")

	# MapPreset生成
	_generate_preset(map_id, output_path, cells, cell_size)

	quit()


func _generate_preset(map_id: String, scene_path: String, cells: Array, cell_size: Vector3) -> void:
	# マップサイズをセルから計算
	var min_pos := Vector3(INF, INF, INF)
	var max_pos := Vector3(-INF, -INF, -INF)
	for cell in cells:
		min_pos.x = minf(min_pos.x, cell.x * cell_size.x)
		min_pos.z = minf(min_pos.z, cell.z * cell_size.z)
		max_pos.x = maxf(max_pos.x, (cell.x + 1) * cell_size.x)
		max_pos.z = maxf(max_pos.z, (cell.z + 1) * cell_size.z)

	var map_size := Vector2(max_pos.x - min_pos.x, max_pos.z - min_pos.z)

	var preset_path := "res://data/maps/%s.tres" % map_id
	var preset_content := """[gd_resource type="Resource" script_class="MapPreset" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/resources/map_preset.gd" id="1_script"]
[ext_resource type="PackedScene" path="%s" id="2_scene"]

[resource]
script = ExtResource("1_script")
id = "%s"
display_name = "%s"
description = "Tile-based map"
map_scene = ExtResource("2_scene")
map_size = Vector2(%s, %s)
spawn_points_ct = Array[Vector3]([])
spawn_points_t = Array[Vector3]([])
spawn_rotations_ct = Array[float]([])
spawn_rotations_t = Array[float]([])
spawn_points_hostage = Array[Vector3]([])
spawn_rotations_hostage = Array[float]([])
""" % [scene_path, map_id, map_id.to_pascal_case(), map_size.x, map_size.y]

	var file := FileAccess.open(
		ProjectSettings.globalize_path(preset_path), FileAccess.WRITE
	)
	if file:
		file.store_string(preset_content)
		file.close()
		print("Preset saved: ", preset_path)
	else:
		print("ERROR: Could not save preset to ", preset_path)


func _patch_scene_script(scene_path: String, script_path: String) -> void:
	## .tscnファイルにスクリプト参照を追記
	var abs_path := ProjectSettings.globalize_path(scene_path)
	var content := FileAccess.get_file_as_string(abs_path)
	if content.is_empty():
		return

	var lines := content.split("\n")
	var new_lines: PackedStringArray = []
	var script_ext_added := false
	var root_node_found := false

	for line in lines:
		# [gd_scene ...] 行のload_stepsを+1
		if line.begins_with("[gd_scene"):
			# load_stepsがあればインクリメント、なければ追加
			var regex := RegEx.new()
			regex.compile("load_steps=(\\d+)")
			var result := regex.search(line)
			if result:
				var steps := result.get_string(1).to_int() + 1
				line = regex.sub(line, "load_steps=%d" % steps)
			else:
				line = line.replace("[gd_scene", "[gd_scene load_steps=2")
			new_lines.append(line)
			# スクリプトext_resourceを追加
			new_lines.append("")
			new_lines.append("[ext_resource type=\"Script\" path=\"%s\" id=\"script_1\"]" % script_path)
			script_ext_added = true
			continue

		# 最初の[node ...]にscript設定を追加
		if not root_node_found and line.begins_with("[node name=") and "parent=" not in line:
			# ルートノード行の末尾 ']' を除去してscript追加
			if line.ends_with("]"):
				line = line.substr(0, line.length() - 1)
			new_lines.append(line)
			new_lines.append("script = ExtResource(\"script_1\")]")
			root_node_found = true
			continue

		new_lines.append(line)

	var file := FileAccess.open(abs_path, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(new_lines))
		file.close()
		print("Script patched into: ", scene_path)


func _find_node_by_class(node: Node, class_name_str: String) -> Node:
	if node.get_class() == class_name_str:
		return node
	for child in node.get_children():
		var result := _find_node_by_class(child, class_name_str)
		if result:
			return result
	return null
