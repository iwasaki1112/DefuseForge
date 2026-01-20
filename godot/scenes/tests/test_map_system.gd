extends Node3D
## マップシステムテストシーン
## GridMap + MeshLibraryを使用したマップロードをテスト

var game_manager: GameManager = null
var current_map: Node3D = null
var current_map_id: String = ""

@onready var camera: Camera3D = $Camera3D
@onready var ui_layer: CanvasLayer = $UILayer
@onready var map_container: Node3D = $MapContainer
@onready var character_container: Node3D = $CharacterContainer
@onready var info_label: Label = $UILayer/InfoLabel


func _ready() -> void:
	_setup_game_manager()
	_update_info_label()

	# FogOfWarを無効化
	game_manager.set_vision_enabled(false)

	# 利用可能なマップを表示
	print("[TestMapSystem] Available maps:")
	for preset in MapRegistry.get_all():
		print("  - %s: %s" % [preset.id, preset.display_name])


func _setup_game_manager() -> void:
	game_manager = GameManager.new()
	game_manager.name = "GameManager"
	add_child(game_manager)
	game_manager.setup(camera, character_container, ui_layer)

	# シグナル接続
	game_manager.selection_changed.connect(_on_selection_changed)
	game_manager.all_paths_completed.connect(_on_all_paths_completed)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_load_map("test_map")
			KEY_2:
				_load_map("gridmap_test")
			KEY_3:
				_load_map("iwasaki_test")
			KEY_C:
				_spawn_characters()
			KEY_R:
				_reload_map()
			KEY_SPACE:
				_execute_paths()

	# マウスクリック
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			game_manager.handle_click(event.position, MOUSE_BUTTON_LEFT)


func _physics_process(delta: float) -> void:
	if game_manager:
		game_manager.process_frame(delta)


func _load_map(map_id: String) -> void:
	# 既存マップを削除
	if current_map:
		current_map.queue_free()
		current_map = null

	# マップをロード
	current_map_id = map_id
	current_map = game_manager.load_map(current_map_id)

	if current_map:
		map_container.add_child(current_map)
		print("[TestMapSystem] Map loaded: %s" % current_map_id)
		_update_info_label()
	else:
		print("[TestMapSystem] Failed to load map: %s" % map_id)


func _spawn_characters() -> void:
	if not current_map or current_map_id.is_empty():
		print("[TestMapSystem] Load a map first (press M)")
		return

	# 既存キャラクターを削除
	for child in character_container.get_children():
		if child.has_method("get_team"):
			game_manager.unregister_character(child)
			child.queue_free()

	# CTスポーン
	var ct_spawns = game_manager.get_spawn_points(current_map_id, true)
	for i in range(mini(ct_spawns.size(), 2)):  # 最大2体
		var pos = ct_spawns[i]
		var character = CharacterRegistry.create_character("dummy_ct", pos)
		if character:
			character_container.add_child(character)
			game_manager.register_character(character)
			print("[TestMapSystem] Spawned CT at %s" % pos)

	# Tスポーン
	var t_spawns = game_manager.get_spawn_points(current_map_id, false)
	for i in range(mini(t_spawns.size(), 2)):  # 最大2体
		var pos = t_spawns[i]
		var character = CharacterRegistry.create_character("dummy_t", pos)
		if character:
			character_container.add_child(character)
			game_manager.register_character(character)
			print("[TestMapSystem] Spawned T at %s" % pos)

	_update_info_label()


func _reload_map() -> void:
	# キャラクターを全削除
	for child in character_container.get_children():
		if child.has_method("get_team"):
			game_manager.unregister_character(child)
			child.queue_free()

	# マップを再ロード
	if current_map_id:
		_load_map(current_map_id)


func _execute_paths() -> void:
	var count = game_manager.execute_all_paths(false)
	if count > 0:
		print("[TestMapSystem] Executing %d paths" % count)


func _update_info_label() -> void:
	var text := "=== Test Map System ===\n"
	text += "1: test_map | 2: gridmap_test\n"
	text += "3: iwasaki_test\n"
	text += "C: Spawn characters\n"
	text += "R: Reload map\n"
	text += "Click: Select character\n"
	text += "Space: Execute paths\n"
	text += "\n"
	text += "Current map: %s\n" % (current_map_id if current_map else "None")
	text += "Characters: %d\n" % character_container.get_child_count()

	var available_maps := []
	for preset in MapRegistry.get_all():
		available_maps.append(preset.id)
	text += "Available: %s" % str(available_maps)

	info_label.text = text


func _on_selection_changed(selected: Array[Node], primary: Node) -> void:
	if primary:
		print("[TestMapSystem] Selected: %s" % primary.name)


func _on_all_paths_completed() -> void:
	print("[TestMapSystem] All paths completed")
