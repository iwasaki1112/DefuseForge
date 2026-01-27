class_name MatchSetupService
extends RefCounted
## マッチ開始時のセットアップを担当

var game_manager: GameManager = null
var camera: Camera3D = null


func setup(manager: GameManager, cam: Camera3D) -> void:
	game_manager = manager
	camera = cam


func determine_player_team() -> void:
	var teams = [GameCharacter.Team.COUNTER_TERRORIST, GameCharacter.Team.TERRORIST]
	var random_team = teams[randi() % 2]
	PlayerState.set_player_team(random_team)


func load_selected_map(map_id: String) -> bool:
	if map_id.is_empty():
		push_error("[MatchSetup] No map selected")
		return false

	var preset := MapRegistry.get_preset(map_id)
	if not preset:
		push_error("[MatchSetup] Map preset not found: %s" % map_id)
		return false

	var map_instance := game_manager.load_map(map_id)
	if not map_instance:
		push_error("[MatchSetup] Failed to load map: %s" % map_id)
		return false

	return true


func spawn_characters() -> void:
	if not game_manager.has_map():
		push_error("[MatchSetup] Cannot spawn characters - no map loaded")
		return

	var preset = game_manager.get_current_map_preset()
	if not preset:
		push_error("[MatchSetup] Cannot spawn characters - no map preset")
		return

	# CT側キャラクターをスポーン（alphaを2体）
	var alpha_preset = CharacterRegistry.get_preset("alpha")
	var ct_spawns = preset.spawn_points_ct
	var ct_rotations = preset.spawn_rotations_ct
	if alpha_preset:
		_spawn_team_characters([alpha_preset, alpha_preset], ct_spawns, ct_rotations)

	# T側キャラクターをスポーン（aresを2体）
	var ares_preset = CharacterRegistry.get_preset("ares")
	var t_spawns = preset.spawn_points_t
	var t_rotations = preset.spawn_rotations_t
	if ares_preset:
		_spawn_team_characters([ares_preset, ares_preset], t_spawns, t_rotations)

	# IdleManagerにキャラクターリストを更新
	if game_manager.idle_manager:
		game_manager.idle_manager.set_characters(game_manager.characters)


func setup_camera_for_player() -> void:
	if not camera:
		return

	var player_team := PlayerState.get_player_team()
	var player_character: Node3D = null

	for character in game_manager.characters:
		if character is GameCharacter and character.team == player_team:
			player_character = character
			break

	if player_character:
		camera.size = 6.0
		var target_pos := player_character.global_position
		var camera_offset := Vector3(0, 15, 5.5)
		camera.global_position = Vector3(target_pos.x, camera_offset.y, target_pos.z + camera_offset.z)


func _spawn_team_characters(presets: Array, spawn_points: Array, spawn_rotations: Array) -> void:
	var count := mini(presets.size(), spawn_points.size())
	for i in range(count):
		var char_preset = presets[i]
		var spawn_pos: Vector3 = spawn_points[i]
		var character = CharacterRegistry.create_character(char_preset.id, spawn_pos)
		if character:
			# add_child()前に向きを設定（readyコールバックで適用される）
			if i < spawn_rotations.size():
				var spawn_rot: float = spawn_rotations[i]
				var direction := Vector3(sin(spawn_rot), 0, cos(spawn_rot))
				character._facing_direction = direction
			var character_parent = game_manager.get_character_parent()
			character_parent.add_child(character)
			game_manager.register_character(character)
