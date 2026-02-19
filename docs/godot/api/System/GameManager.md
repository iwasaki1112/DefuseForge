# GameManager

## 概要
コアゲームシステムの初期化・更新を一元管理するマネージャークラス。サブシステムを統合制御し、TPS操作のゲームプレイを支える。

システム生成ロジックは`GameSystemFactory`に委譲し、UIコンポーネント（`label_manager`）はGameScreenから注入される。

## ファイル
`scripts/systems/game_manager.gd`

## 責務
- GameSystemFactoryを使用してシステムを正しい順序で初期化
- キャラクター登録時の自動セットアップ（視界、武器、色、ラベル）はCharacterSetupServiceに委譲
- シグナルの中継（サブシステム→外部）
- 毎フレーム処理の統合

## 管理するシステム

| # | システム | 責務 | 生成 |
|---|---------|------|------|
| 1 | CharacterSelectionManager | 選択状態・アウトライン | Factory |
| 2 | IdleCharacterManager | アイドル状態更新 | Factory |
| 3 | FogOfWarSystem | 戦場の霧 | VisionService経由 |
| 4 | EnemyVisibilitySystem | 敵可視性 | VisionService経由 |
| 5 | CharacterLabelManager | キャラクターラベル | **GameScreenから注入** |
| 6 | CharacterSetupService | キャラクター初期セットアップ | Factory |
| 7 | VisionService | 視界/FoW/敵可視性の統合制御 | Factory |
| 8 | SmokeAreaManager | スモークエリア管理 | Factory |
| 9 | MapManager | マップロード/アンロード | Factory |
| 10 | RoundManager | ラウンド制御 | Factory |
| 11 | CharacterManagerService | キャラクター管理 | Factory |
| 12 | GrenadeService | グレネード生成 | Factory |
| 13 | DoorService | ドアキック処理 | Factory |

## シグナル

```gdscript
# グレネード関連
signal grenade_thrown(grenade: Node3D, character: Node)
signal smoke_grenade_thrown(smoke_grenade: Node3D, character: Node)

# ネットワーク同期用シグナル
signal grenade_network_event(start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int)
signal grenade_explode_network_event(grenade_id: int, position: Vector3, is_smoke: bool)
signal door_kick_network_event(door_id: int, character_network_id: int)
signal door_open_network_event(door_id: int, character_network_id: int)
signal damage_network_event(attacker_id: int, target_id: int, damage: float, is_headshot: bool)
```

## プロパティ

```gdscript
# システム生成ファクトリ（内部）
var _factory: GameSystemFactory = null

# コアシステム
var selection_manager: CharacterSelectionManager
var idle_manager: IdleCharacterManager
var fog_of_war_system: Node3D
var enemy_visibility_system: Node
var smoke_area_manager: SmokeAreaManager
var map_manager: MapManager
var character_setup_service: CharacterSetupService
var vision_service: VisionService
var round_manager: RoundManager

# 抽出されたサービス
var character_manager: CharacterManagerService
var grenade_service: GrenadeService
var door_service: DoorService

# UIコンポーネント（GameScreenから注入される）
var label_manager: CharacterLabelManager

# 外部参照
var camera: Camera3D
var characters: Array[Node]

# 設定
var fow_map_size: Vector2 = Vector2(50, 50)
var default_vision_fov: float = 75.0
var default_vision_range: float = 7.0
var default_weapon_id_ct: String = "mark18"
var default_weapon_id_t: String = "ak47"
var is_vision_enabled: bool = false
```

## 主要メソッド

### セットアップ

```gdscript
func setup(cam: Camera3D, mesh_parent: Node3D, ui_layer: CanvasLayer, map_size: Vector2 = Vector2(50, 50), map_container: Node3D = null) -> void
```
全システムを初期化。`_ready()`の直後に呼び出す。

**引数:**
- `cam`: シーンのCamera3D
- `mesh_parent`: オブジェクトを追加する親ノード
- `ui_layer`: UIを追加するCanvasLayer
- `map_size`: FoWマップサイズ（デフォルト50x50）
- `map_container`: マップを追加する親ノード（省略時はmesh_parentを使用）

### キャラクター管理

```gdscript
func register_character(character: Node) -> void
```
キャラクターを登録。視界・武器・色・ラベルも自動セットアップ。

```gdscript
func unregister_character(character: Node) -> void
```
キャラクターを登録解除。関連リソースも自動クリーンアップ。

```gdscript
func refresh_character_colors() -> void
```
全キャラクターの色・ラベルを再割り当て（チーム変更時など）。

```gdscript
func get_character_parent() -> Node3D
```
キャラクターを追加する親ノードを取得（MapContainer優先）。

### 視界/FoW制御

```gdscript
func set_vision_enabled(enabled: bool) -> void
```
視界/FoWの有効化切り替え。

```gdscript
func set_vision_debug_draw(enabled: bool) -> void
```
味方キャラクターの視界デバッグ表示を切り替え。

### マップ管理

```gdscript
func load_map(map_preset_id: String, auto_cleanup: bool = true) -> Node3D
func unload_map(cleanup_characters: bool = true) -> void
func switch_map(new_map_id: String) -> Node3D
func has_map() -> bool
func get_current_map_id() -> String
func get_current_map_preset() -> MapPreset
func get_map_size() -> Vector2
func get_spawn_points(is_ct: bool) -> Array[Vector3]
func get_spawn_points_for_map(map_preset_id: String, is_ct: bool) -> Array[Vector3]
```

### ドア管理

```gdscript
func register_door(door: Node3D) -> int
func get_door_by_id(door_id: int) -> Node3D
func get_door_id(door: Node3D) -> int
func clear_door_registry() -> void
func register_all_doors_in_map() -> void
func apply_door_kick_from_network(door_id: int, character_network_id: int) -> void
func apply_door_open_from_network(door_id: int, character_network_id: int) -> void
```

### グレネード関連

```gdscript
func spawn_grenade_from_network(start_pos: Vector3, velocity: Vector3, grenade_id: int) -> void
func spawn_smoke_grenade_from_network(start_pos: Vector3, velocity: Vector3, grenade_id: int) -> void
func handle_grenade_explode_from_network(grenade_id: int, position: Vector3, is_smoke: bool) -> void
```

### 毎フレーム処理

```gdscript
func process_frame(delta: float) -> void
```
ラウンドタイマー、アイドルキャラクター、リモートキャラクター補間を処理。

### 状態取得

```gdscript
func get_primary_character() -> Node
func get_selection_count() -> int
```

### UI注入（GameScreenから呼び出し）

```gdscript
func set_label_manager(mgr: CharacterLabelManager) -> void
```

## Multiplayer API

```gdscript
func enable_multiplayer_mode(local_peer_id: int) -> void
func disable_multiplayer_mode() -> void
func is_multiplayer_mode() -> bool
func get_local_peer_id() -> int
func is_local_character(character: Node) -> bool
func has_control_permission(character: Node) -> bool
func filter_local_characters(chars: Array) -> Array[Node]
func filter_remote_characters(chars: Array) -> Array[Node]
func get_local_friendly_characters() -> Array[Node]
func get_remote_characters() -> Array[Node]
func register_character_with_network(character: Node, owner_peer_id: int, network_id: int) -> void
func find_character_by_network_id(network_id: int) -> GameCharacter
func find_characters_by_owner(owner_peer_id: int) -> Array[GameCharacter]
func get_all_character_snapshots() -> Array[SyncState.CharacterSnapshot]
func get_game_state_snapshot() -> SyncState.GameStateSnapshot
func apply_game_state_snapshot(snapshot: SyncState.GameStateSnapshot) -> void
```

## 使用例

```gdscript
# GameScreenでのセットアップ
var game_manager: GameManager

func _ready() -> void:
    game_manager = GameManager.new()
    game_manager.name = "GameManager"
    add_child(game_manager)
    game_manager.set_label_manager(label_manager)
    game_manager.setup(camera, self, ui_layer)

    # キャラクター登録（視界・武器・色・ラベルは自動セットアップ）
    var ct = CharacterRegistry.create_character("dummy_ct", Vector3.ZERO)
    add_child(ct)
    game_manager.register_character(ct)

func _physics_process(delta: float) -> void:
    game_manager.process_frame(delta)
```

## 関連クラス
- [GameSystemFactory](GameSystemFactory.md) - システム生成ファクトリ
- [CharacterSelectionManager](CharacterSelectionManager.md)
- [IdleCharacterManager](IdleCharacterManager.md)
- [FogOfWarSystem](FogOfWarSystem.md)
- [EnemyVisibilitySystem](EnemyVisibilitySystem.md)
- [CharacterLabelManager](../UI/CharacterLabelManager.md)
- [VisionService](VisionService.md)
- [NetworkMessages](../Network/NetworkMessages.md)
- [SyncState](../Network/SyncState.md)
- [GameScreen](../Screen/GameScreen.md) - UIコンポーネント注入元
