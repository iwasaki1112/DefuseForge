# GameManager

## 概要
コアゲームシステムの初期化・更新・入力処理・UI管理を一元管理するマネージャークラス。テストシーンとゲームロジックを完全に分離し、14個のサブシステムを統合制御する。

## ファイル
`scripts/systems/game_manager.gd`

## 責務
- システムの初期化を正しい順序で実行
- 入力処理（レイキャスト、クリック）
- UI管理（ラベル）
- キャラクター登録時の自動セットアップ（視界、武器、色、ラベル）はCharacterSetupServiceに委譲
- シグナルの中継（サブシステム→外部）
- 毎フレーム処理の統合

## 管理するシステム

| # | システム | 責務 |
|---|---------|------|
| 1 | CharacterSelectionManager | 選択状態・アウトライン |
| 2 | PathExecutionManager | パス確定・実行 |
| 3 | IdleCharacterManager | アイドル状態更新 |
| 4 | PathDrawer | パス描画入力 |
| 5 | PathModeController | パスモード制御 |
| 6 | FogOfWarSystem | 戦場の霧 |
| 7 | EnemyVisibilitySystem | 敵可視性 |
| 8 | CharacterLabelManager | キャラクターラベル |
| 9 | CharacterSetupService | キャラクター初期セットアップ |
| 10 | PathService | パス描画/編集/実行の統合制御 |
| 11 | VisionService | 視界/FoW/敵可視性の統合制御 |

## シグナル

```gdscript
# 選択関連
signal selection_changed(selected: Array[Node], primary: Node)
signal primary_changed(character: Node)

# パスモード関連
signal path_mode_started(character: Node)
signal path_mode_ended()
signal path_mode_cancelled()
signal path_ready()
signal path_confirmed(count: int)
signal paths_execution_started(count: int)
signal all_paths_completed()
signal paths_cleared()
signal path_mode_changed(mode: int)
signal vision_point_added(anchor: Vector3, direction: Vector3)
signal run_segment_added(start_ratio: float, end_ratio: float)

# グレネード関連
signal grenade_thrown(grenade: Node3D, character: Node)
signal smoke_grenade_thrown(smoke_grenade: Node3D, character: Node)

# ネットワーク同期用シグナル
signal grenade_network_event(start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int)
signal grenade_explode_network_event(grenade_id: int, position: Vector3, is_smoke: bool)
signal door_kick_network_event(door_id: int, character_network_id: int)

# ラウンド関連
signal round_started()
signal round_ended(winner: int, reason: int)
signal round_timer_updated(remaining: float)
signal survivor_count_changed(ct_count: int, t_count: int)
```

## プロパティ

```gdscript
# コアシステム
var selection_manager: CharacterSelectionManager
var path_execution_manager: PathExecutionManager
var idle_manager: IdleCharacterManager
var path_mode_controller: PathModeController
var fog_of_war_system: Node3D
var enemy_visibility_system: Node
var path_drawer: Node3D
var character_setup_service: CharacterSetupService
var path_service: PathService
var vision_service: VisionService

# UIコンポーネント
var label_manager: CharacterLabelManager

# 外部参照
var camera: Camera3D
var characters: Array[Node]

# 設定
var fow_map_size: Vector2 = Vector2(50, 50)
var default_vision_fov: float = 90.0
var default_vision_range: float = 15.0
var default_weapon_id: String = "glock"
var is_vision_enabled: bool = false
```

## 主要メソッド

### セットアップ

```gdscript
func setup(cam: Camera3D, mesh_parent: Node3D, ui_layer: CanvasLayer, map_size: Vector2 = Vector2(50, 50)) -> void
```
全システムを初期化。`_ready()`の直後に呼び出す。

**引数:**
- `cam`: シーンのCamera3D
- `mesh_parent`: パスメッシュを追加する親ノード
- `ui_layer`: UIを追加するCanvasLayer
- `map_size`: FoWマップサイズ（デフォルト50x50）

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

### 入力処理

```gdscript
func handle_click(screen_pos: Vector2, button_index: int) -> bool
```
マウス/タッチクリック処理。選択を行う。
キャラクター選択中にドアをクリックするとドアキックを開始する。

```gdscript
func raycast_character(screen_pos: Vector2) -> Node
```
画面座標からキャラクターを検出。

```gdscript
func raycast_door(screen_pos: Vector2) -> Node3D
```
画面座標からドアを検出（`doors`グループに属するノード）。

### パスモード操作

```gdscript
func start_move_mode() -> bool
```
選択中キャラクターで移動モード開始。

```gdscript
func try_start_path_extension_at_position(screen_pos: Vector2) -> bool
```
指定位置近くのパス終端を検索し、パス延長モードを開始する（確定済みパス・移動中パス両対応）。

```gdscript
func try_start_vision_marker_on_confirmed_path(screen_pos: Vector2, ground_pos: Vector3 = Vector3.ZERO) -> bool
```
確認済みパス上での長押しによるVisionマーカー追加モードを開始する。

```gdscript
func try_start_vision_marker_on_moving_path(screen_pos: Vector2, ground_pos: Vector3 = Vector3.ZERO) -> Dictionary
```
移動中パス上での長押し判定を行い、成功すれば対象データを返す。

```gdscript
func add_vision_marker_to_moving_path(character: Node, path_ratio: float, anchor: Vector3, target_point: Vector3) -> bool
```
移動中のパスにVisionマーカーを追加する。

```gdscript
func update_moving_path_vision_preview(character: Node, anchor: Vector3, target_point: Vector3) -> void
```
移動中パスVisionマーカーのプレビュー表示を更新する。

```gdscript
func clear_moving_path_vision_preview() -> void
```
移動中パスVisionマーカーのプレビューを消去する。

```gdscript
func clear_moving_path_vision_markers_for_character(character: Node) -> void
```
指定キャラクターの移動中パスVisionマーカーをクリアする（パス完了時など）。

```gdscript
func confirm_path() -> void
func cancel_path() -> void
func execute_all_paths(run: bool) -> int
func clear_all_pending_paths() -> void
```

### ネットワーク同期・イベント

```gdscript
func spawn_grenade_from_network(start_pos: Vector3, velocity: Vector3, grenade_id: int) -> void
```
ネットワーク経由でグレネードを生成・投擲する。

```gdscript
func spawn_smoke_grenade_from_network(start_pos: Vector3, velocity: Vector3, grenade_id: int) -> void
```
ネットワーク経由でスモークグレネードを生成・投擲する。

```gdscript
func apply_door_kick_from_network(door_id: int, character_network_id: int) -> void
```
ネットワーク経由でドアキックイベントを適用する。

### ドア管理

```gdscript
func register_door(door: Node3D) -> int
```
ドアを登録し、ネットワーク同期用のIDを割り当てる。

```gdscript
func get_door_by_id(door_id: int) -> Node3D
```
IDからドアノードを取得する。

### 視界/FoW制御

```gdscript
func set_vision_enabled(enabled: bool) -> void
```

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

### ドアキック処理

キャラクター選択中にドア（`doors`グループ）をクリックすると自動的に発動。

**フロー:**
1. ドアの前後にアンカー位置を計算（ドアのローカルZ軸方向±1m）
2. キャラクターに近い方のアンカーを選択
3. キャラクターがアンカー位置まで移動
4. `GameCharacter.face_towards()`でドア方向を向く
5. ドアキックアニメーション再生（`CharacterAnimationController.play_door_kick()`）
6. **インパクトタイミング**（フレーム36/66、1.2秒）でドアをY軸で170度回転開始（Tween、キャラクターから離れる方向）
7. **アニメーション完了時**にキャラクターの向きをドア方向に維持（`set_facing_direction_vec()`）

**アンカーベースのアプローチ:**
- `anchor_front`: `door_pos + door_forward * 1.0`（+Z側）
- `anchor_back`: `door_pos - door_forward * 1.0`（-Z側）
- キャラクターに近い方を自動選択

**キャラクターの向き設定:**
> **重要:** `CharacterBody3D.look_at()`を使用せず、`GameCharacter.face_towards()`を使用すること。
> Mixamoモデルは+Z方向が前方のため、`look_at()`を直接使用すると180度ずれる。

**内部メソッド:**
- `_start_door_kick(character, door)`: ドアキック開始、アンカー選択
- `_on_door_approach_completed(character, door)`: ドア前到達完了、向き設定
- `_on_door_kick_done(door, character)`: インパクト時、ドア回転開始
- `_on_door_kick_animation_finished(character)`: アニメーション完了、ドア方向を維持

### 毎フレーム処理

```gdscript
func process_frame(delta: float) -> void
```

- ドアキック用パス追従コントローラーの処理を含む

### 状態取得

```gdscript
func is_path_mode() -> bool
func is_any_path_following_active() -> bool
func is_character_following_path(character: Node) -> bool
func get_pending_path_count() -> int
func get_path_target_count() -> int
func get_primary_character() -> Node
func get_selection_count() -> int
```

## 使用例

### 基本的な使用

```gdscript
# シーンスクリプト
var game_manager: GameManager

func _ready() -> void:
    game_manager = GameManager.new()
    game_manager.name = "GameManager"
    add_child(game_manager)
    game_manager.setup(camera, self, ui_layer)

    # シグナル接続（UI更新用）
    game_manager.selection_changed.connect(_on_selection_changed)
    game_manager.path_confirmed.connect(_on_path_confirmed)

    # キャラクター登録（視界・武器・色・ラベルは自動セットアップ）
    var ct = CharacterRegistry.create_character("dummy_ct", Vector3.ZERO)
    add_child(ct)
    game_manager.register_character(ct)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        game_manager.handle_click(event.position, event.button_index)

func _physics_process(delta: float) -> void:
    game_manager.process_frame(delta)
```

### テストシーンの構成

```gdscript
# テストシーンに残すもの
# - UI参照（@onready）
# - デバッグボタンのシグナル接続
# - キャラクター生成位置の指定
# - デバッグ用WASD操作
# - 情報ラベル更新

func _spawn_initial_characters() -> void:
    var ct = CharacterRegistry.create_character("dummy_ct", Vector3(-3, 0, 0))
    add_child(ct)
    game_manager.register_character(ct)  # これだけでOK
```

## シーン固有の責務

GameManagerはゲームロジックを担当。以下はシーン固有：
- キャラクター生成位置の決定
- デバッグ用WASD操作
- 情報ラベルの表示内容

## Multiplayer API

### enable_multiplayer_mode(local_peer_id: int) -> void
マルチプレイヤーモードを有効化する。

```gdscript
game_manager.enable_multiplayer_mode(multiplayer.get_unique_id())
```

### disable_multiplayer_mode() -> void
マルチプレイヤーモードを無効化する。

### is_multiplayer_mode() -> bool
マルチプレイヤーモードかどうかを返す。

### is_local_character(character: Node) -> bool
キャラクターがローカルプレイヤーのものか判定する。

### has_control_permission(character: Node) -> bool
キャラクターの操作権限があるか判定する。

### filter_local_characters(chars: Array) -> Array[Node]
ローカルプレイヤーのキャラクターのみをフィルタする。

### filter_remote_characters(chars: Array) -> Array[Node]
リモートプレイヤーのキャラクターのみをフィルタする。

### get_local_friendly_characters() -> Array[Node]
ローカルプレイヤーの味方キャラクターを取得する。

### register_character_with_network(character: Node, owner_peer_id: int, network_id: int) -> void
ネットワーク情報付きでキャラクターを登録する。

```gdscript
game_manager.register_character_with_network(character, peer_id, net_id)
```

### find_character_by_network_id(network_id: int) -> GameCharacter
ネットワークIDからキャラクターを検索する。

### find_characters_by_owner(owner_peer_id: int) -> Array[GameCharacter]
所有者のpeer_idからキャラクターを検索する。

### get_all_character_snapshots() -> Array[SyncState.CharacterSnapshot]
全キャラクターのスナップショットを取得する。

### get_game_state_snapshot() -> SyncState.GameStateSnapshot
ゲーム全体の状態スナップショットを取得する（ホスト用）。

### apply_game_state_snapshot(snapshot: SyncState.GameStateSnapshot) -> void
ゲーム状態スナップショットを適用する（クライアント用）。

## 関連クラス
- [CharacterSelectionManager](CharacterSelectionManager.md)
- [PathExecutionManager](PathExecutionManager.md)
- [IdleCharacterManager](IdleCharacterManager.md)
- [PathModeController](PathModeController.md)
- [PathDrawer](PathDrawer.md)
- [FogOfWarSystem](FogOfWarSystem.md)
- [EnemyVisibilitySystem](EnemyVisibilitySystem.md)
- [CharacterLabelManager](CharacterLabelManager.md)
- [NetworkMessages](NetworkMessages.md)
- [SyncState](SyncState.md)

## APIリファレンス

### シグナル
| シグナル | 引数 | 説明 |
|---------|------|------|
| `selection_changed` | `selected: Array[Node], primary: Node` | 選択状態変更時 |
| `primary_changed` | `character: Node` | プライマリキャラクター変更時 |
| `path_mode_started` | `character: Node` | パスモード開始時 |
| `path_mode_ended` | なし | パスモード正常終了時 |
| `path_mode_cancelled` | なし | パスモードキャンセル時 |
| `path_ready` | なし | パス描画完了時（確定可能状態） |
| `path_confirmed` | `count: int` | パス確定時（確定したパス数） |
| `paths_execution_started` | `count: int` | パス実行開始時（実行するパス数） |
| `all_paths_completed` | なし | 全パス実行完了時 |
| `paths_cleared` | なし | 全パスクリア時 |
| `path_mode_changed` | `mode: int` | パス描画モード変更時 |
| `vision_point_added` | `anchor: Vector3, direction: Vector3` | 視線ポイント追加時 |
| `run_segment_added` | `start_ratio: float, end_ratio: float` | Run区間追加時 |
| `grenade_thrown` | `grenade: Node3D, character: Node` | グレネード投擲時 |
| `smoke_grenade_thrown` | `smoke_grenade: Node3D, character: Node` | スモークグレネード投擲時 |
| `grenade_network_event` | `start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int` | グレネード投擲のネットワーク同期用 |
| `grenade_explode_network_event` | `grenade_id: int, position: Vector3, is_smoke: bool` | グレネード爆発のネットワーク同期用 |
| `door_kick_network_event` | `door_id: int, character_network_id: int` | ドアキックのネットワーク同期用 |
| `round_started` | なし | ラウンド開始時 |
| `round_ended` | `winner: int, reason: int` | ラウンド終了時 |
| `round_timer_updated` | `remaining: float` | ラウンドタイマー更新時 |
| `survivor_count_changed` | `ct_count: int, t_count: int` | 生存者数変更時 |

### メソッド
- `setup(cam: Camera3D, mesh_parent: Node3D, ui_layer: CanvasLayer, map_size: Vector2 = Vector2(50, 50), map_container: Node3D = null) -> void`
- `register_character(character: Node) -> void`
- `unregister_character(character: Node) -> void`
- `handle_click(screen_pos: Vector2, button_index: int) -> bool`
- `raycast_character(screen_pos: Vector2) -> Node`
- `raycast_door(screen_pos: Vector2) -> Node3D`
- `start_move_mode() -> bool`
- `start_path_mode(primary: Node, char_color: Color = Color.WHITE) -> bool`
- `confirm_path() -> void`
- `cancel_path() -> void`
- `execute_all_paths(run: bool) -> int`
- `clear_all_pending_paths() -> void`
- `cancel_all_path_following() -> void`
- `set_vision_enabled(enabled: bool) -> void`
- `load_map(map_preset_id: String, auto_cleanup: bool = true) -> Node3D`
- `unload_map(cleanup_characters: bool = true) -> void`
- `switch_map(new_map_id: String) -> Node3D`
- `has_map() -> bool`
- `get_current_map_id() -> String`
- `get_current_map_preset() -> MapPreset`
- `get_map_size() -> Vector2`
- `get_spawn_points(is_ct: bool) -> Array[Vector3]`
- `get_spawn_points_for_map(map_preset_id: String, is_ct: bool) -> Array[Vector3]`
- `get_character_parent() -> Node3D`
- `process_frame(delta: float) -> void`
- `is_path_mode() -> bool`
- `is_any_path_following_active() -> bool`
- `is_character_following_path(character: Node) -> bool`
- `get_pending_path_count() -> int`
- `get_path_target_count() -> int`
- `get_primary_character() -> Node`
- `get_selection_count() -> int`
- `has_pending_path() -> bool`
- `start_vision_mode() -> bool`
- `remove_last_vision_point() -> void`
- `start_run_mode() -> void`
- `remove_last_run_segment() -> void`
- `get_vision_point_count() -> int`
- `get_run_segment_count() -> int`
- `has_incomplete_run_start() -> bool`
- `is_multi_character_mode() -> bool`
- `start_multi_character_mode(selected_chars: Array[Node]) -> void`
- `set_active_edit_character(character: Node) -> void`
- `set_path_drawer_color(color: Color) -> void`
- `refresh_character_colors() -> void`
