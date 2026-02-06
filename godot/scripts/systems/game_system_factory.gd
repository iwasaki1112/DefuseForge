class_name GameSystemFactory
extends RefCounted
## GameManagerのシステム生成ロジックを分離するファクトリ
##
## 各create_*メソッドはシステムインスタンスを生成・初期化して返す。
## シグナル接続はGameManager側で行う（コールバックがGameManagerのメソッドのため）。

## iOS互換性のため遅延ロード（preloadは使用しない）
var PathDrawerScript: GDScript = null


func _init() -> void:
	PathDrawerScript = load("res://scripts/effects/path_drawer.gd")


## CharacterSelectionManagerを生成
func create_selection_manager() -> CharacterSelectionManager:
	var manager := CharacterSelectionManager.new()
	manager.name = GameConstants.NODE_SELECTION_MANAGER
	return manager


## PathExecutionManagerを生成・初期化
func create_path_execution_manager(mesh_parent: Node3D) -> PathExecutionManager:
	var manager := PathExecutionManager.new()
	manager.name = GameConstants.NODE_PATH_EXECUTION_MANAGER
	manager.setup(mesh_parent)
	return manager


## IdleCharacterManagerを生成・初期化
func create_idle_manager(
	characters_ref: Array[Node],
	is_following_callback: Callable,
	get_primary_callback: Callable
) -> IdleCharacterManager:
	var manager := IdleCharacterManager.new()
	manager.name = GameConstants.NODE_IDLE_MANAGER
	manager.setup(characters_ref, is_following_callback, get_primary_callback)
	return manager


## SmokeAreaManagerを生成
func create_smoke_area_manager() -> SmokeAreaManager:
	var manager := SmokeAreaManager.new()
	manager.name = "SmokeAreaManager"
	return manager


## PathDrawerを生成・初期化
func create_path_drawer(_cam: Camera3D, _path_execution_manager: PathExecutionManager) -> Node3D:
	var drawer := Node3D.new()
	drawer.set_script(PathDrawerScript)
	drawer.name = GameConstants.NODE_PATH_DRAWER
	return drawer


## PathDrawerのセットアップ（add_child後に呼ぶ）
func setup_path_drawer(drawer: Node3D, cam: Camera3D, path_execution_manager: PathExecutionManager) -> void:
	drawer.setup(cam, null)
	drawer.set_path_execution_manager(path_execution_manager)


## PathModeControllerを生成・初期化
func create_path_mode_controller(
	drawer: Node3D,
	selection_manager: CharacterSelectionManager,
	path_execution_manager: PathExecutionManager
) -> PathModeController:
	var controller := PathModeController.new()
	controller.name = GameConstants.NODE_PATH_MODE_CONTROLLER
	controller.setup(drawer, selection_manager, path_execution_manager)
	return controller


## VisionServiceを生成・初期化
func create_vision_service(
	fow_map_size: Vector2,
	is_vision_enabled: bool,
	smoke_area_manager: SmokeAreaManager
) -> VisionService:
	var service := VisionService.new()
	service.name = GameConstants.NODE_VISION_SERVICE
	service.setup(fow_map_size, is_vision_enabled)
	if smoke_area_manager:
		service.set_smoke_area_manager(smoke_area_manager)
	return service


## MapManagerを生成・初期化
func create_map_manager(map_container: Node3D, game_manager: GameManager) -> MapManager:
	var manager := MapManager.new()
	manager.name = GameConstants.NODE_MAP_MANAGER
	manager.setup(map_container, game_manager)
	return manager


## PathServiceを生成・初期化
func create_path_service(
	drawer: Node3D,
	selection_manager: CharacterSelectionManager,
	path_execution_manager: PathExecutionManager,
	path_mode_controller: PathModeController
) -> PathService:
	var service := PathService.new()
	service.name = GameConstants.NODE_PATH_SERVICE
	service.setup(drawer, selection_manager, path_execution_manager, path_mode_controller)
	return service


## RoundManagerを生成・初期化
func create_round_manager(game_manager: GameManager) -> RoundManager:
	var manager := RoundManager.new()
	manager.name = GameConstants.NODE_ROUND_MANAGER
	manager.setup(game_manager)
	return manager


## CharacterSetupServiceを生成・初期化
func create_character_setup_service(
	enemy_visibility_system: Node,
	fog_of_war_system: Node3D,
	label_manager: CharacterLabelManager,
	default_weapon_id: String,
	is_vision_enabled: bool,
	default_vision_fov: float,
	default_vision_range: float
) -> CharacterSetupService:
	var service := CharacterSetupService.new()
	service.setup(
		enemy_visibility_system,
		fog_of_war_system,
		label_manager,
		default_weapon_id,
		is_vision_enabled,
		default_vision_fov,
		default_vision_range
	)
	return service


## CharacterManagerServiceを生成
func create_character_manager_service() -> CharacterManagerService:
	var manager := CharacterManagerService.new()
	manager.name = "CharacterManagerService"
	return manager


## GrenadeServiceを生成・初期化
func create_grenade_service(mesh_parent: Node3D, smoke_area_manager: SmokeAreaManager) -> GrenadeService:
	var service := GrenadeService.new()
	service.name = "GrenadeService"
	service.setup(mesh_parent, smoke_area_manager)
	return service


## DoorServiceを生成・初期化
func create_door_service(
	character_manager: CharacterManagerService,
	vision_update_callback: Callable
) -> DoorService:
	var service := DoorService.new()
	service.name = "DoorService"
	service.setup(character_manager)
	service.set_vision_update_callback(vision_update_callback)
	return service


## MovingPathVisionServiceを生成・初期化
func create_moving_path_vision_service(mesh_parent: Node3D, path_execution_manager: PathExecutionManager) -> MovingPathVisionService:
	var service := MovingPathVisionService.new()
	service.setup(mesh_parent, path_execution_manager)
	return service
