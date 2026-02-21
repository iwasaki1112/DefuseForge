class_name MapBase
extends Node3D
## マップ基底クラス
## 壁/ドア/床のコリジョン設定とFoWオクルーダー抽出の共通処理
##
## GridMapマップは.tscnだけで完結（@exportでメタデータ設定）
## 既存Blenderマップは従来通りサブクラス + .tres

const GROUND_COLLISION_LAYER: int = 1
const WALL_COLLISION_LAYER: int = 2
const WINDOW_GLASS_COLLISION_LAYER: int = 4

## ドアパネルGLBパス（フレームとは別にエクスポートされた回転可能なパネル）
const DOOR_PANEL_SCENE_PATH := "res://scenes/tiles/door_panel.glb"
## ドア蝶番のオフセット（タイル原点からの相対位置、Godot座標系）
## 開口部の+X端にヒンジを配置（2mタイル、1.0m開口）
const DOOR_HINGE_OFFSET := Vector3(0.5, 0.0, -0.9)

## マップメタデータ（.tscnのインスペクタで設定）
@export_group("Map Info")
@export var map_id: String = ""  ## マップID（MapRegistryで使用）
@export var display_name: String = ""  ## マップ選択画面の表示名
@export var map_description: String = ""  ## マップの説明

## マップ名（ログ用、レガシーサブクラスでオーバーライド可）
var _map_name: String = "MAP"


func _ready() -> void:
	# @exportのmap_idが設定されていれば使用（GridMapマップ用）
	# レガシーサブクラスは_map_nameを直接設定してからsuper._ready()を呼ぶ
	if _map_name == "MAP" and not map_id.is_empty():
		_map_name = map_id.to_upper()
	_remove_editor_lighting()
	_setup_prop_collisions(self)
	_setup_collisions(self)
	_notify_fow_system()


## エディタ用ライティングをゲーム実行時に削除（GameScreenのEnvironmentSetupが管理するため）
func _remove_editor_lighting() -> void:
	for child in get_children():
		if child is WorldEnvironment or child is DirectionalLight3D:
			child.queue_free()


## コリジョンレイヤーを設定
func _setup_collisions(node: Node) -> void:
	if node is GridMap:
		_setup_gridmap_collisions(node as GridMap)
		return

	if node is StaticBody3D:
		var node_name_lower := node.name.to_lower()

		# ノード自体のプレフィックスをチェック
		if node_name_lower.begins_with("ground_"):
			# 床オブジェクトはレイヤー1（床コリジョン）
			node.collision_layer = GROUND_COLLISION_LAYER
		elif node_name_lower.begins_with("wall_") or node_name_lower.begins_with("door_"):
			# 壁/ドアオブジェクトはレイヤー2（壁コリジョン）
			node.collision_layer = WALL_COLLISION_LAYER
			if node_name_lower.begins_with("door_"):
				node.add_to_group(GameConstants.GROUP_DOORS)
				if Debug.enabled: print("[%s] Added door to group: %s" % [_map_name, node.name])
		else:
			# 親ノードのプレフィックスをチェック
			var parent: Node = node.get_parent()
			if parent:
				var parent_name_lower := parent.name.to_lower()
				if parent_name_lower.begins_with("ground_"):
					node.collision_layer = GROUND_COLLISION_LAYER
				elif parent_name_lower.begins_with("wall_") or parent_name_lower.begins_with("door_"):
					node.collision_layer = WALL_COLLISION_LAYER
				if parent_name_lower.begins_with("door_"):
					parent.add_to_group(GameConstants.GROUP_DOORS)
					if Debug.enabled: print("[%s] Added door to group: %s" % [_map_name, parent.name])

	for child in node.get_children():
		_setup_collisions(child)


## FoWシステムにオクルーダー抽出を通知
func _notify_fow_system() -> void:
	# VisionServiceを探す（GameScreen経由）
	var game_screen := get_tree().get_first_node_in_group("game_screen")
	if Debug.enabled: print("[%s] _notify_fow_system - game_screen: %s" % [_map_name, game_screen != null])
	if game_screen and game_screen.has_method("get_vision_service"):
		var vision_service = game_screen.get_vision_service()
		var fow_str := str(vision_service.fog_of_war_system != null) if vision_service else "false"
		if Debug.enabled: print("[%s] vision_service: %s, fow_system: %s" % [_map_name, vision_service != null, fow_str])
		if vision_service and vision_service.fog_of_war_system:
			# ground_ノードからマップサイズと中心を計算してFoWに設定
			var ground_info = _calculate_ground_bounds()
			if ground_info:
				vision_service.fog_of_war_system.set_map_bounds(ground_info["size"], ground_info["center"])
				if Debug.enabled: print("[%s] Set FoW map_bounds: size=%s, center=%s" % [_map_name, ground_info["size"], ground_info["center"]])
			vision_service.fog_of_war_system.extract_occluders_from_map(self)
			_register_prop_occluders(vision_service.fog_of_war_system)
			if Debug.enabled: print("[%s] Extracted occluders for FoW system" % _map_name)
		else:
			# FoWシステムが準備できていない場合は遅延呼び出し
			if Debug.enabled: print("[%s] FoW system not ready, scheduling deferred call" % _map_name)
			call_deferred("_notify_fow_system_deferred")
	else:
		if Debug.enabled: print("[%s] game_screen not ready, scheduling deferred call" % _map_name)
		call_deferred("_notify_fow_system_deferred")


## 遅延オクルーダー抽出
func _notify_fow_system_deferred() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var game_screen := get_tree().get_first_node_in_group("game_screen")
	if game_screen and game_screen.has_method("get_vision_service"):
		var vision_service = game_screen.get_vision_service()
		if vision_service and vision_service.fog_of_war_system:
			# ground_ノードからマップサイズと中心を計算してFoWに設定
			var ground_info = _calculate_ground_bounds()
			if ground_info:
				vision_service.fog_of_war_system.set_map_bounds(ground_info["size"], ground_info["center"])
				if Debug.enabled: print("[%s] Set FoW map_bounds (deferred): size=%s, center=%s" % [_map_name, ground_info["size"], ground_info["center"]])
			vision_service.fog_of_war_system.extract_occluders_from_map(self)
			_register_prop_occluders(vision_service.fog_of_war_system)
			if Debug.enabled: print("[%s] Extracted occluders for FoW system (deferred)" % _map_name)


## プロップのStaticBody3DをFoWオクルーダーとして登録
## _setup_prop_collisions()で追加したノードがSceneTreeに入るまで待ってから登録
func _register_prop_occluders(fow_system) -> void:
	var prop_bodies: Array = []
	_find_prop_bodies(self, prop_bodies)
	for body in prop_bodies:
		if not body.is_inside_tree():
			await body.tree_entered
		for child in body.get_children():
			if child is CollisionShape3D and not child.is_inside_tree():
				await child.tree_entered
		fow_system.add_prop_occluder(body)
	if Debug.enabled and prop_bodies.size() > 0:
		print("[%s] Registered %d prop occluders" % [_map_name, prop_bodies.size()])


## _collision サフィックス付きのStaticBody3Dを再帰検索
func _find_prop_bodies(node: Node, result: Array) -> void:
	if node is StaticBody3D and node.name.ends_with("_collision"):
		result.append(node)
	for child in node.get_children():
		_find_prop_bodies(child, result)


## -object サフィックスのノードにランタイムでConvexHullコリジョンを生成
func _setup_prop_collisions(node: Node) -> void:
	if node is MeshInstance3D and node.name.ends_with("-object") and node.mesh:
		var body := StaticBody3D.new()
		body.name = node.name.replace("-object", "") + "_collision"
		body.collision_layer = WALL_COLLISION_LAYER

		var convex = node.mesh.create_convex_shape(true, true)
		var col_shape := CollisionShape3D.new()
		col_shape.shape = convex
		col_shape.name = "ConvexCollision"

		node.add_child(body)
		body.add_child(col_shape)

		if Debug.enabled:
			print("[%s] Created prop collision: %s" % [_map_name, body.name])

	for child in node.get_children():
		_setup_prop_collisions(child)


## ground_ノードからマップの床サイズと中心を計算
## 戻り値: { "size": Vector2, "center": Vector2 } or null
func _calculate_ground_bounds() -> Variant:
	var bounds := {
		"min": Vector3(INF, INF, INF),
		"max": Vector3(-INF, -INF, -INF),
		"found": false
	}

	_collect_ground_bounds(self, bounds)

	if not bounds["found"]:
		if Debug.enabled: print("[%s] No ground_ nodes found for bounds calculation" % _map_name)
		return null

	# X-Z平面でのサイズと中心を返す（Fogがグラウンド外にも広がるようパディング追加）
	const FOG_PADDING := 14.0  # カメラ高さ分のパディング（グラウンド外もFogで覆う）
	var size_x: float = bounds["max"].x - bounds["min"].x + FOG_PADDING * 2.0
	var size_z: float = bounds["max"].z - bounds["min"].z + FOG_PADDING * 2.0
	var center_x: float = (bounds["min"].x + bounds["max"].x) / 2.0
	var center_z: float = (bounds["min"].z + bounds["max"].z) / 2.0
	if Debug.enabled: print("[%s] Ground bounds: min=%s, max=%s, size=(%s, %s), center=(%s, %s)" % [_map_name, bounds["min"], bounds["max"], size_x, size_z, center_x, center_z])
	return { "size": Vector2(size_x, size_z), "center": Vector2(center_x, center_z) }


## GridMapのセルからコリジョンボディを生成
func _setup_gridmap_collisions(grid_map: GridMap) -> void:
	var lib := grid_map.mesh_library
	if not lib:
		return

	# GridMapの内蔵コリジョンを無効化（個別にStaticBody3Dを生成するため）
	grid_map.collision_layer = 0
	grid_map.collision_mask = 0

	var cells := grid_map.get_used_cells()
	if Debug.enabled: print("[%s] Setting up GridMap collisions: %d cells" % [_map_name, cells.size()])

	for cell in cells:
		var item_id := grid_map.get_cell_item(cell)
		if item_id == GridMap.INVALID_CELL_ITEM:
			continue

		var item_name := lib.get_item_name(item_id)
		var item_type := _classify_gridmap_item(item_name)

		# コリジョンレイヤー決定
		var col_layer: int
		match item_type:
			1, 2:  # wall, door
				col_layer = WALL_COLLISION_LAYER
			_:  # floor or unknown
				col_layer = GROUND_COLLISION_LAYER

		# MeshLibraryからシェイプを取得
		var shapes := lib.get_item_shapes(item_id)
		if shapes.size() < 2:
			continue

		# セルのローカル位置と回転を取得
		var local_pos := grid_map.map_to_local(cell)
		var orientation := grid_map.get_cell_item_orientation(cell)
		var cell_basis := grid_map.get_basis_with_orthogonal_index(orientation)

		# StaticBody3D生成（壁・床・ドアフレーム共通）
		var body := StaticBody3D.new()
		body.name = "GridCol_%s_%d_%d_%d" % [item_name, cell.x, cell.y, cell.z]
		body.collision_layer = col_layer
		body.collision_mask = 0
		body.transform = Transform3D(cell_basis, local_pos)
		grid_map.add_child(body)

		# 窓タイル: 柱シェイプ→レイヤー2（壁構造、グレネード・射撃はここで判定）
		# ガラスブロッカー→レイヤー4（キャラ移動ブロック専用、グレネード・視線は透過）
		if "window" in item_name.to_lower():
			_add_collision_shapes(body, shapes)
			var mesh := lib.get_item_mesh(item_id)
			if mesh:
				var aabb := mesh.get_aabb()
				var glass_body := StaticBody3D.new()
				glass_body.name = "WindowGlass_%s_%d_%d_%d" % [item_name, cell.x, cell.y, cell.z]
				glass_body.collision_layer = WINDOW_GLASS_COLLISION_LAYER
				glass_body.collision_mask = 0
				glass_body.transform = Transform3D(cell_basis, local_pos)
				grid_map.add_child(glass_body)
				var col := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = aabb.size
				col.shape = box
				col.position = aabb.get_center()
				glass_body.add_child(col)
		else:
			_add_collision_shapes(body, shapes)

		# ドアタイルの場合: フレームはGridMapに残し、パネルだけ独立ノードで回転可能にする
		if item_type == 2:
			_create_door_panel(grid_map, cell, local_pos, cell_basis)


## GridMapアイテム名からカテゴリを判定
## 0=floor, 1=wall, 2=door
static func _classify_gridmap_item(item_name: String) -> int:
	var name_lower := item_name.to_lower()
	if "door" in name_lower:
		return 2
	elif "wall" in name_lower or "glass" in name_lower or "straight" in name_lower or "corner" in name_lower or "window" in name_lower:
		return 1
	return 0


## ドアパネルを独立ノードとして生成
## フレーム（コンクリート柱）はGridMapに残し、パネル（木製ドア板）だけ独立ノードで回転可能にする
## DoorServiceがピボットのrotation_degrees.yをTweenして開閉アニメーションする
func _create_door_panel(grid_map: GridMap, cell: Vector3i, local_pos: Vector3, cell_basis: Basis) -> void:
	var panel_scene := load(DOOR_PANEL_SCENE_PATH) as PackedScene
	if not panel_scene:
		push_warning("[%s] Could not load door panel: %s" % [_map_name, DOOR_PANEL_SCENE_PATH])
		return

	# ピボットノード（蝶番位置）— DoorServiceがrotation_degrees.yをTweenする対象
	var pivot := Node3D.new()
	pivot.name = "DoorPanel_%d_%d_%d" % [cell.x, cell.y, cell.z]

	# 蝶番位置 = セル中心 + セル回転 * ヒンジオフセット
	var hinge_pos := local_pos + cell_basis * DOOR_HINGE_OFFSET
	pivot.transform = Transform3D(cell_basis, hinge_pos)
	grid_map.add_child(pivot)

	# パネルメッシュ（ヒンジが+X端なので、モデルを-Xにオフセット）
	var panel_instance := panel_scene.instantiate()
	panel_instance.name = "PanelMesh"
	panel_instance.position = Vector3(-1.0, 0.0, 0.0)
	pivot.add_child(panel_instance)

	# パネルコリジョン（閉じた状態でドア開口部をブロック）
	var body := StaticBody3D.new()
	body.name = "PanelCollision"
	body.collision_layer = WALL_COLLISION_LAYER
	body.collision_mask = 0
	pivot.add_child(body)

	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 2.0, 0.154)
	var col_shape := CollisionShape3D.new()
	col_shape.shape = box
	# パネル中心 = 蝶番からのオフセット（-X方向: 半幅, Y: 半高さ）
	col_shape.position = Vector3(-0.5, 1.0, 0.0)
	body.add_child(col_shape)

	# ドアグループに追加
	pivot.add_to_group(GameConstants.GROUP_DOORS)
	if Debug.enabled: print("[%s] Created door panel: %s at %s" % [_map_name, pivot.name, hinge_pos])


## StaticBody3Dにコリジョンシェイプを追加（MeshLibraryのshapes配列から）
func _add_collision_shapes(body: StaticBody3D, shapes: Array) -> void:
	var i := 0
	while i < shapes.size():
		if shapes[i] is Shape3D:
			var col := CollisionShape3D.new()
			col.shape = shapes[i]
			if i + 1 < shapes.size() and shapes[i + 1] is Transform3D:
				col.transform = shapes[i + 1]
			body.add_child(col)
		i += 2


## 再帰的にground_ノードを探索してバウンディングボックスを収集
func _collect_ground_bounds(node: Node, bounds: Dictionary) -> void:
	# GridMap handling
	if node is GridMap:
		_collect_gridmap_ground_bounds(node as GridMap, bounds)

	var node_name_lower := node.name.to_lower()
	var is_ground := node_name_lower.begins_with("ground_")

	# 親がground_の場合も対象
	if not is_ground and node.get_parent():
		var parent_name_lower := node.get_parent().name.to_lower()
		is_ground = parent_name_lower.begins_with("ground_")

	if is_ground and node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var aabb := mesh_instance.get_aabb()
		var gtransform := mesh_instance.global_transform

		# AABBの8頂点をグローバル座標に変換してmin/maxを更新
		for i in range(8):
			var corner := aabb.position
			if i & 1: corner.x += aabb.size.x
			if i & 2: corner.y += aabb.size.y
			if i & 4: corner.z += aabb.size.z
			var global_corner: Vector3 = gtransform * corner

			bounds["min"].x = minf(bounds["min"].x, global_corner.x)
			bounds["min"].y = minf(bounds["min"].y, global_corner.y)
			bounds["min"].z = minf(bounds["min"].z, global_corner.z)
			bounds["max"].x = maxf(bounds["max"].x, global_corner.x)
			bounds["max"].y = maxf(bounds["max"].y, global_corner.y)
			bounds["max"].z = maxf(bounds["max"].z, global_corner.z)
		bounds["found"] = true

	for child in node.get_children():
		_collect_ground_bounds(child, bounds)


## GridMapのフロアセルからバウンディングボックスを収集
func _collect_gridmap_ground_bounds(grid_map: GridMap, bounds: Dictionary) -> void:
	var lib := grid_map.mesh_library
	if not lib:
		return

	var cell_size := grid_map.cell_size

	for cell in grid_map.get_used_cells():
		var item_id := grid_map.get_cell_item(cell)
		if item_id == GridMap.INVALID_CELL_ITEM:
			continue

		var item_name := lib.get_item_name(item_id)
		if _classify_gridmap_item(item_name) != 0:
			continue

		var local_pos := grid_map.map_to_local(cell)
		var world_pos: Vector3 = grid_map.global_transform * local_pos

		# セル中心から±cell_size/2の範囲
		bounds["min"].x = minf(bounds["min"].x, world_pos.x - cell_size.x / 2.0)
		bounds["min"].z = minf(bounds["min"].z, world_pos.z - cell_size.z / 2.0)
		bounds["max"].x = maxf(bounds["max"].x, world_pos.x + cell_size.x / 2.0)
		bounds["max"].z = maxf(bounds["max"].z, world_pos.z + cell_size.z / 2.0)
		bounds["found"] = true
