extends Node3D
class_name GameScreen
## ゲーム画面
##
## MapSelectionScreenで選択されたマップをロードし、
## キャラクターをスポーン、プレイヤーをCT/Tにランダム割り当てする。

## シーン定数
const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"
const GameHUDScene := preload("res://scenes/ui/game_hud.tscn")
const CameraPanControllerScript := preload("res://scripts/utils/camera_pan_controller.gd")
const MatchSetupServiceScript := preload("res://scripts/screens/match_setup_service.gd")

## ノード参照
@onready var camera: Camera3D = $Camera3D
@onready var map_container: Node3D = $MapContainer
@onready var ui_layer: CanvasLayer = $UILayer
@onready var team_display_label: Label = $UILayer/TeamDisplayLabel
@onready var money_label: Label = $UILayer/MoneyLabel

## コアシステム
var game_manager: GameManager = null
var environment_setup: EnvironmentSetup = null

## UI要素
var _hud: GameHUD = null
var _round_hud: RoundHUD = null

## カメラ移動
var _camera_pan_controller: CameraPanController = null
var _input_controller: InputController = null
var _match_setup_service: MatchSetupService = null

## デバッグ
var _vision_debug_enabled: bool = false



func _ready() -> void:
	add_to_group("game_screen")
	_setup_environment()
	_setup_game_manager()
	_setup_hud()
	_setup_round_hud()
	_setup_match_service()
	_match_setup_service.determine_player_team()
	_load_map()
	_match_setup_service.spawn_characters()
	_register_character_markers()
	_update_team_display()
	_match_setup_service.setup_camera_for_player()
	_setup_money()
	_setup_camera_pan()
	_setup_input_controller()

	# 視界システムを初期化（FoW OFF）
	game_manager.set_vision_enabled(false)

	# ラウンド開始（タイマー開始）
	if game_manager.round_manager:
		game_manager.round_manager.start_round()


## ========================================
## 初期化処理
## ========================================

## 環境をセットアップ
func _setup_environment() -> void:
	if environment_setup == null:
		environment_setup = EnvironmentSetup.new()
		environment_setup.name = "EnvironmentSetup"
		var preset := load(DEFAULT_ENVIRONMENT_PRESET) as EnvironmentPreset
		if preset:
			environment_setup.preset = preset
		add_child(environment_setup)


## GameManagerのセットアップ
func _setup_game_manager() -> void:
	if game_manager == null:
		game_manager = GameManager.new()
		game_manager.name = "GameManager"
		add_child(game_manager)

		# マップサイズはマップロード後に更新されるため、初期値で設定
		game_manager.setup(camera, self, ui_layer, Vector2(50, 50), map_container)

		# シグナル接続
		game_manager.selection_changed.connect(_on_selection_changed)
		game_manager.path_confirmed.connect(_on_path_confirmed)
		game_manager.paths_execution_started.connect(_on_paths_execution_started)
		game_manager.all_paths_completed.connect(_on_all_paths_completed)
		game_manager.paths_cleared.connect(_on_paths_cleared)
		game_manager.path_ready.connect(_on_path_ready)
		game_manager.path_mode_ended.connect(_on_path_mode_ended)
		game_manager.path_mode_cancelled.connect(_on_path_mode_cancelled)


func _setup_match_service() -> void:
	if _match_setup_service == null:
		_match_setup_service = MatchSetupServiceScript.new()
		_match_setup_service.setup(game_manager, camera)


## コントロールUIのセットアップ
func _setup_hud() -> void:
	if _hud == null:
		_hud = GameHUDScene.instantiate()
		ui_layer.add_child(_hud)
		_hud.setup()
		_hud.execute_all_requested.connect(_on_execute_button_pressed)
		_hud.clear_paths_requested.connect(_on_clear_paths_button_pressed)
		_hud.character_marker_pressed.connect(_on_character_marker_pressed)
		_hud.marker_edit_requested.connect(_on_marker_edit_requested)
		_hud.marker_undo_requested.connect(_on_marker_undo_requested)
		_hud.marker_confirm_requested.connect(_on_marker_confirm_requested)
		_hud.marker_cancel_requested.connect(_on_marker_cancel_requested)


## ラウンドHUDのセットアップ
func _setup_round_hud() -> void:
	if _round_hud == null:
		_round_hud = RoundHUD.new()
		_round_hud.name = GameConstants.NODE_ROUND_HUD
		ui_layer.add_child(_round_hud)

		# シグナル接続
		game_manager.round_timer_updated.connect(_hud.update_timer)
		game_manager.survivor_count_changed.connect(_round_hud.update_survivor_counts)
		game_manager.round_ended.connect(_round_hud.show_result)
		game_manager.round_ended.connect(_on_round_ended)


## カメラのパン操作をセットアップ
func _setup_camera_pan() -> void:
	if _camera_pan_controller == null:
		_camera_pan_controller = CameraPanControllerScript.new()
		_camera_pan_controller.setup(camera, 0.05)


## 入力コントローラーをセットアップ
func _setup_input_controller() -> void:
	if _input_controller == null:
		_input_controller = InputController.new()
		_input_controller.name = "InputController"
		add_child(_input_controller)
		_input_controller.setup(game_manager, _camera_pan_controller)


## マップをロード
func _load_map() -> void:
	var map_id := SettingsManager.get_selected_map()
	if not _match_setup_service.load_selected_map(map_id):
		return


## 所持金をセットアップ
func _setup_money() -> void:
	# 初期資金にリセット
	PlayerState.reset_money()
	# シグナル接続
	PlayerState.money_changed.connect(_on_money_changed)
	# 初期表示更新
	_update_money_display()


## キャラクターマーカーを登録
func _register_character_markers() -> void:
	if not _hud or not game_manager:
		return

	# プレイヤーチームのキャラクターをマーカーに登録
	var player_team: GameCharacter.Team = PlayerState.get_player_team()
	for character in game_manager.characters:
		if not is_instance_valid(character):
			continue
		if character.team == player_team and not character.marker_name.is_empty():
			_hud.register_character_marker(character)


## チーム表示を更新
func _update_team_display() -> void:
	if team_display_label:
		var team_name := PlayerState.get_team_name()
		var full_name := "Counter-Terrorist" if team_name == "CT" else "Terrorist"
		team_display_label.text = "You are: %s (%s)" % [full_name, team_name]


## 所持金表示を更新
func _update_money_display() -> void:
	if money_label:
		money_label.text = "$%d" % PlayerState.get_money()


## 保留パス数ラベルを更新
func _update_pending_paths_label() -> void:
	if _hud:
		_hud.set_pending_paths(game_manager.get_pending_path_count())


## ========================================
## ボタンコールバック
## ========================================

func _on_execute_button_pressed() -> void:
	game_manager.execute_all_paths(false)


func _on_clear_paths_button_pressed() -> void:
	game_manager.clear_all_pending_paths()


## マーカーエディットボタン押下時のコールバック
func _on_marker_edit_requested(action: String) -> void:
	if not game_manager or not game_manager.path_service:
		return

	var path_service = game_manager.path_service
	if not path_service.has_pending_path():
		return

	match action:
		"vision":
			path_service.start_vision_mode()
		"run":
			path_service.start_run_mode()
		"clear":
			path_service.start_clear_mode()
		"grenade":
			path_service.start_grenade_mode()
		"smoke":
			path_service.start_smoke_grenade_mode()
		"door":
			path_service.start_door_mode()
		"wait":
			path_service.start_wait_mode()


## Undoボタン押下時のコールバック
func _on_marker_undo_requested() -> void:
	if game_manager and game_manager.path_service:
		game_manager.path_service.undo_last_marker()


## Confirmボタン押下時のコールバック
func _on_marker_confirm_requested() -> void:
	if game_manager and game_manager.path_service:
		game_manager.path_service.confirm_path()


## Cancelボタン押下時のコールバック
func _on_marker_cancel_requested() -> void:
	if game_manager and game_manager.path_service:
		game_manager.path_service.cancel_path()


## パス描画完了時のコールバック（マーカー追加モードへ移行）
func _on_path_ready() -> void:
	if _hud:
		_hud.show_marker_edit_panel()


## パスモード終了時のコールバック
func _on_path_mode_ended() -> void:
	if _hud:
		_hud.hide_marker_edit_panel()


## パスモードキャンセル時のコールバック
func _on_path_mode_cancelled() -> void:
	if _hud:
		_hud.hide_marker_edit_panel()


## ========================================
## 毎フレーム処理
## ========================================

func _physics_process(delta: float) -> void:
	game_manager.process_frame(delta)
	if _camera_pan_controller:
		_camera_pan_controller.process(delta)


## ========================================
## シグナルハンドラ
## ========================================

func _on_selection_changed(_selected: Array[Node], _primary: Node) -> void:
	pass


func _on_path_confirmed(_count: int) -> void:
	_update_pending_paths_label()


func _on_paths_execution_started(_count: int) -> void:
	pass


func _on_all_paths_completed() -> void:
	_update_pending_paths_label()


func _on_paths_cleared() -> void:
	_update_pending_paths_label()


func _on_money_changed(_new_amount: int) -> void:
	_update_money_display()


func _on_round_ended(_winner: int, _reason: int) -> void:
	# すべてのキャラクターの移動を停止
	if game_manager:
		game_manager.cancel_all_path_following()

	# 3秒後にマップ選択画面に遷移
	await get_tree().create_timer(3.0).timeout
	get_tree().change_scene_to_file("res://scenes/screens/map_selection.tscn")


## キャラクターマーカー押下時のコールバック
func _on_character_marker_pressed(character: Node) -> void:
	if not is_instance_valid(character) or not camera:
		return

	# キャラクターの位置にカメラをパン
	var target_pos: Vector3 = character.global_position
	_pan_camera_to_position(target_pos)


## カメラを指定位置にパン（アニメーション付き）
func _pan_camera_to_position(target_pos: Vector3) -> void:
	if not camera:
		return

	# カメラの高さを維持しながらXZ平面で移動
	var new_camera_pos := Vector3(target_pos.x, camera.global_position.y, target_pos.z + 5.0)

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(camera, "global_position", new_camera_pos, 0.4)


## SmokeAreaManagerを取得（VisionComponentから呼び出される）
func get_smoke_area_manager() -> SmokeAreaManager:
	if game_manager:
		return game_manager.smoke_area_manager
	return null


## ========================================
## デバッグ入力
## ========================================

func _unhandled_input(event: InputEvent) -> void:
	# F3: 視界デバッグ表示の切り替え
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_vision_debug_enabled = not _vision_debug_enabled
			game_manager.set_vision_debug_draw(_vision_debug_enabled)
			print("[DEBUG] Vision debug draw: %s" % ("ON" if _vision_debug_enabled else "OFF"))
