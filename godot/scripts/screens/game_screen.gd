extends Node3D
class_name GameScreen
## ゲーム画面
##
## MapSelectionScreenで選択されたマップをロードし、
## キャラクターをスポーン、プレイヤーをCT/Tにランダム割り当てする。

## シーン定数
const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"
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

## カメラ移動
var _camera_pan_controller: CameraPanController = null
var _input_controller: InputController = null
var _match_setup_service: MatchSetupService = null



func _ready() -> void:
	_setup_environment()
	_setup_game_manager()
	_setup_hud()
	_setup_match_service()
	_match_setup_service.determine_player_team()
	_load_map()
	_match_setup_service.spawn_characters()
	_update_team_display()
	_match_setup_service.setup_camera_for_player()
	_setup_money()
	_setup_camera_pan()
	_setup_input_controller()

	# 視界システムを初期化（FoW OFF）
	game_manager.set_vision_enabled(false)


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


## プレイヤーチームをランダムに決定
func _determine_player_team() -> void:
	var teams = [GameCharacter.Team.COUNTER_TERRORIST, GameCharacter.Team.TERRORIST]
	var random_team = teams[randi() % 2]
	PlayerState.set_player_team(random_team)


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
		game_manager.all_paths_completed.connect(_on_all_paths_completed)
		game_manager.paths_cleared.connect(_on_paths_cleared)


func _setup_match_service() -> void:
	if _match_setup_service == null:
		_match_setup_service = MatchSetupServiceScript.new()
		_match_setup_service.setup(game_manager, camera)


## コントロールUIのセットアップ
func _setup_hud() -> void:
	if _hud == null:
		_hud = GameHUD.new()
		_hud.name = "GameHUD"
		ui_layer.add_child(_hud)
		_hud.setup()
		_hud.execute_all_requested.connect(_on_execute_button_pressed)
		_hud.clear_paths_requested.connect(_on_clear_paths_button_pressed)


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


func _on_money_changed(_new_amount: int) -> void:
	_update_money_display()
