class_name GameSystemFactory
extends RefCounted
## GameManagerのシステム生成ロジックを分離するファクトリ
##
## 各create_*メソッドはシステムインスタンスを生成・初期化して返す。
## シグナル接続はGameManager側で行う（コールバックがGameManagerのメソッドのため）。


## CharacterSelectionManagerを生成
func create_selection_manager() -> CharacterSelectionManager:
	var manager := CharacterSelectionManager.new()
	manager.name = GameConstants.NODE_SELECTION_MANAGER
	return manager


## IdleCharacterManagerを生成・初期化
func create_idle_manager(
	characters_ref: Array[Node],
	get_primary_callback: Callable
) -> IdleCharacterManager:
	var manager := IdleCharacterManager.new()
	manager.name = GameConstants.NODE_IDLE_MANAGER
	manager.setup(characters_ref, get_primary_callback)
	return manager


## SmokeAreaManagerを生成
func create_smoke_area_manager() -> SmokeAreaManager:
	var manager := SmokeAreaManager.new()
	manager.name = "SmokeAreaManager"
	return manager


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
	default_weapon_id_ct: String,
	default_weapon_id_t: String,
	is_vision_enabled: bool,
	default_vision_fov: float,
	default_vision_range: float
) -> CharacterSetupService:
	var service := CharacterSetupService.new()
	service.setup(
		enemy_visibility_system,
		fog_of_war_system,
		label_manager,
		default_weapon_id_ct,
		default_weapon_id_t,
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
