extends Node3D
class_name GameScreen
## ゲーム画面
##
## MapSelectionScreenで選択されたマップをロードし、
## キャラクターをスポーン、プレイヤーをCT/Tにランダム割り当てする。

## シーン定数
const MAIN_MENU_SCENE := "res://scenes/screens/main_menu.tscn"
const MAP_SELECTION_SCENE := "res://scenes/screens/map_selection.tscn"
const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"

## ノード参照
@onready var camera: Camera3D = $Camera3D
@onready var map_container: Node3D = $MapContainer
@onready var ui_layer: CanvasLayer = $UILayer
@onready var team_display_label: Label = $UILayer/TeamDisplayLabel

## コアシステム
var game_manager: GameManager = null
var environment_setup: EnvironmentSetup = null

## UI要素
var _pending_paths_label: Label
var _execute_button: Button
var _clear_paths_button: Button

## カメラ移動
var _camera_drag_active: bool = false
var _camera_drag_start: Vector2 = Vector2.ZERO
var _camera_start_position: Vector3 = Vector3.ZERO
var _camera_pan_speed: float = 0.05

## 地面判定用
var _ground_plane := Plane(Vector3.UP, 0)


func _ready() -> void:
	_setup_environment()
	_determine_player_team()
	_setup_game_manager()
	_setup_control_ui()
	_load_map()
	_spawn_characters()
	_update_team_display()
	_setup_camera_for_player()

	# 視界システムを初期化（FoW OFF）
	game_manager.set_vision_enabled(false)


## ========================================
## 初期化処理
## ========================================

## 環境をセットアップ
func _setup_environment() -> void:
	environment_setup = EnvironmentSetup.new()
	environment_setup.name = "EnvironmentSetup"
	var preset := load(DEFAULT_ENVIRONMENT_PRESET) as EnvironmentPreset
	if preset:
		environment_setup.preset = preset
	add_child(environment_setup)


## プレイヤーチームをランダムに決定
func _determine_player_team() -> void:
	var teams = [GameCharacter.Team.COUNTER_TERRORIST, GameCharacter.Team.TERRORIST]
	var random_team = teams[randi() % 2]
	PlayerState.set_player_team(random_team)


## GameManagerのセットアップ
func _setup_game_manager() -> void:
	game_manager = GameManager.new()
	game_manager.name = "GameManager"
	add_child(game_manager)

	# マップサイズはマップロード後に更新されるため、初期値で設定
	game_manager.setup(camera, self, ui_layer, Vector2(50, 50), map_container)

	# シグナル接続
	game_manager.selection_changed.connect(_on_selection_changed)
	game_manager.path_confirmed.connect(_on_path_confirmed)
	game_manager.all_paths_completed.connect(_on_all_paths_completed)
	game_manager.paths_cleared.connect(_on_paths_cleared)


## コントロールUIのセットアップ
func _setup_control_ui() -> void:
	var control_panel := VBoxContainer.new()
	control_panel.name = "ControlPanel"
	control_panel.anchor_left = 0.0
	control_panel.anchor_top = 0.0
	control_panel.anchor_right = 0.0
	control_panel.anchor_bottom = 0.0
	control_panel.offset_left = 10
	control_panel.offset_top = 80
	control_panel.offset_right = 200
	control_panel.add_theme_constant_override("separation", 10)
	ui_layer.add_child(control_panel)

	# 保留パス数ラベル
	_pending_paths_label = Label.new()
	_pending_paths_label.text = "Pending: 0 paths"
	_pending_paths_label.add_theme_font_size_override("font_size", 18)
	control_panel.add_child(_pending_paths_label)

	# 実行ボタン
	_execute_button = Button.new()
	_execute_button.text = "Execute All"
	_execute_button.custom_minimum_size = Vector2(180, 45)
	_execute_button.add_theme_font_size_override("font_size", 18)
	_execute_button.pressed.connect(_on_execute_button_pressed)
	control_panel.add_child(_execute_button)

	# クリアボタン
	_clear_paths_button = Button.new()
	_clear_paths_button.text = "Clear All Paths"
	_clear_paths_button.custom_minimum_size = Vector2(180, 45)
	_clear_paths_button.add_theme_font_size_override("font_size", 18)
	_clear_paths_button.pressed.connect(_on_clear_paths_button_pressed)
	control_panel.add_child(_clear_paths_button)

	# 操作説明ラベル
	var help_label := Label.new()
	help_label.text = "Right-drag: Move camera"
	help_label.add_theme_font_size_override("font_size", 14)
	help_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	control_panel.add_child(help_label)


## マップをロード
func _load_map() -> void:
	var map_id := SettingsManager.get_selected_map()
	if map_id.is_empty():
		push_error("[GameScreen] No map selected")
		return

	var preset := MapRegistry.get_preset(map_id)
	if not preset:
		push_error("[GameScreen] Map preset not found: %s" % map_id)
		return

	# マップをロード
	var map_instance := game_manager.load_map(map_id)
	if not map_instance:
		push_error("[GameScreen] Failed to load map: %s" % map_id)
		return

	# マップサイズでFoWを更新（FogOfWarSystemにも反映）
	game_manager.fow_map_size = preset.map_size
	if game_manager.fog_of_war_system:
		game_manager.fog_of_war_system.set_map_size(preset.map_size)


## キャラクターをスポーン
func _spawn_characters() -> void:
	if not game_manager.has_map():
		push_error("[GameScreen] Cannot spawn characters - no map loaded")
		return

	var preset = game_manager.map_manager.current_preset
	if not preset:
		push_error("[GameScreen] Cannot spawn characters - no map preset")
		return

	# CT側キャラクターをスポーン
	var ct_presets = CharacterRegistry.get_counter_terrorists()
	var ct_spawns = preset.spawn_points_ct
	_spawn_team_characters(ct_presets, ct_spawns)

	# T側キャラクターをスポーン
	var t_presets = CharacterRegistry.get_terrorists()
	var t_spawns = preset.spawn_points_t
	_spawn_team_characters(t_presets, t_spawns)

	# IdleManagerにキャラクターリストを更新
	if game_manager.idle_manager:
		game_manager.idle_manager.set_characters(game_manager.characters)


## チームのキャラクターをスポーン
func _spawn_team_characters(presets: Array, spawn_points: Array) -> void:
	var count := mini(presets.size(), spawn_points.size())
	for i in range(count):
		var char_preset = presets[i]
		var spawn_pos: Vector3 = spawn_points[i]
		var character = CharacterRegistry.create_character(char_preset.id, spawn_pos)
		if character:
			add_child(character)
			game_manager.register_character(character)


## カメラを自分のキャラクターに合わせる
func _setup_camera_for_player() -> void:
	# 自分のチームのキャラクターを探す
	var player_team := PlayerState.get_player_team()
	var player_character: Node3D = null

	for character in game_manager.characters:
		if character is GameCharacter and character.team == player_team:
			player_character = character
			break

	if player_character:
		# カメラを少しズーム
		camera.size = 6.0

		# キャラクターの頭上にカメラを移動（Y軸とZ軸のオフセットを維持）
		var target_pos := player_character.global_position
		var camera_offset := Vector3(0, 15, 5.5)  # 現在のカメラ高さとZ位置を維持
		camera.global_position = Vector3(target_pos.x, camera_offset.y, target_pos.z + camera_offset.z)


## チーム表示を更新
func _update_team_display() -> void:
	if team_display_label:
		var team_name := PlayerState.get_team_name()
		var full_name := "Counter-Terrorist" if team_name == "CT" else "Terrorist"
		team_display_label.text = "You are: %s (%s)" % [full_name, team_name]


## 保留パス数ラベルを更新
func _update_pending_paths_label() -> void:
	if _pending_paths_label:
		_pending_paths_label.text = "Pending: %d paths" % game_manager.get_pending_path_count()


## ========================================
## ボタンコールバック
## ========================================

func _on_execute_button_pressed() -> void:
	game_manager.execute_all_paths(false)


func _on_clear_paths_button_pressed() -> void:
	game_manager.clear_all_pending_paths()


## ========================================
## 入力処理
## ========================================

func _unhandled_input(event: InputEvent) -> void:
	# カメラドラッグ（右クリック）
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_camera_drag_active = true
				_camera_drag_start = event.position
				_camera_start_position = camera.global_position
			else:
				_camera_drag_active = false
			return

	# カメラドラッグ移動
	if event is InputEventMouseMotion and _camera_drag_active:
		var delta = event.position - _camera_drag_start
		var move_x = -delta.x * _camera_pan_speed
		var move_z = -delta.y * _camera_pan_speed
		camera.global_position = _camera_start_position + Vector3(move_x, 0, move_z)
		return

	# 回転モード中
	if game_manager.is_rotation_active() and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			game_manager.handle_rotation_input(event.position)
		return

	# パスモード中：パス描画後にキャラクター以外をクリックでキャンセル
	if game_manager.is_path_mode() and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if game_manager.has_pending_path():
				var clicked = game_manager.raycast_character(event.position)
				game_manager.path_mode_controller.handle_click_to_cancel(clicked)
		return

	# 通常クリック処理（左クリックのみ）
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not game_manager.is_rotation_active() and not game_manager.is_path_mode():
				game_manager.handle_click(event.position, event.button_index)


func _input(event: InputEvent) -> void:
	# ESCキー処理
	if event.is_action_pressed("ui_cancel"):
		if game_manager.is_any_path_following_active():
			game_manager.cancel_all_path_following()
		elif game_manager.is_rotation_active():
			game_manager.cancel_rotation()
		elif game_manager.is_path_mode():
			game_manager.cancel_path()


## ========================================
## 毎フレーム処理
## ========================================

func _physics_process(delta: float) -> void:
	game_manager.process_frame(delta)


## ========================================
## シグナルハンドラ
## ========================================

func _on_selection_changed(_selected: Array[Node], _primary: Node) -> void:
	pass


func _on_path_confirmed(_count: int) -> void:
	_update_pending_paths_label()


func _on_all_paths_completed() -> void:
	_update_pending_paths_label()


func _on_paths_cleared() -> void:
	_update_pending_paths_label()
