# MapManager

マップライフサイクル管理クラス。マップのロード・アンロード・状態追跡・クリーンアップを一元管理する。

## 基本情報

| 項目 | 内容 |
|------|------|
| スクリプト | `res://scripts/systems/map_manager.gd` |
| 基底クラス | Node |
| class_name | `MapManager` |

## 責務

MapManagerは以下の責務を持つ：

| 責務 | 説明 |
|------|------|
| ライフサイクル管理 | マップのロード・アンロード・切り替え |
| 状態追跡 | 現在のマップ・プリセット・IDの管理 |
| クリーンアップ | キャラクター・パスの自動削除 |
| シグナル通知 | ロード前後・アンロード前後のイベント発火 |

## シグナル

| シグナル | 引数 | 説明 |
|----------|------|------|
| `map_will_load` | `map_id: String` | マップロード前に発火 |
| `map_loaded` | `map_id: String, map_instance: Node3D` | マップロード完了時に発火 |
| `map_will_unload` | `map_id: String` | マップアンロード前に発火 |
| `map_unloaded` | `map_id: String` | マップアンロード完了時に発火 |

## プロパティ

| プロパティ | 型 | 説明 |
|------------|-----|------|
| `current_map` | `Node3D` | 現在のマップインスタンス |
| `current_preset` | `MapPreset` | 現在のマッププリセット |
| `current_map_id` | `String` | 現在のマップID |

## API

### セットアップ

#### `setup(map_container: Node3D, game_manager) -> void`
MapManagerを初期化する。

```gdscript
# GameManager内部で呼び出される
map_manager.setup(_map_container, self)
```

### マップロードAPI

#### `load_map(map_id: String, auto_cleanup: bool = true) -> Node3D`
マップをロードする。

- `auto_cleanup`: trueの場合、既存マップを自動アンロード（デフォルトtrue）
- Returns: マップインスタンス、失敗時はnull

```gdscript
var map = map_manager.load_map("test_map")
if map:
    print("Map loaded: ", map_manager.current_map_id)
```

#### `unload_map(cleanup_characters: bool = true) -> void`
現在のマップをアンロードする。

- `cleanup_characters`: trueの場合、キャラクターとパスもクリーンアップ

```gdscript
map_manager.unload_map(true)  # キャラクターも削除
map_manager.unload_map(false) # マップのみ削除
```

#### `switch_map(new_map_id: String) -> Node3D`
マップを切り替える（アンロード→ロードを一括実行）。

```gdscript
# マップ切り替え（キャラクター・パスは自動クリーンアップ）
var new_map = map_manager.switch_map("warehouse")
```

### クリーンアップAPI

#### `cleanup_characters() -> void`
登録済みキャラクターをすべて削除する。

```gdscript
map_manager.cleanup_characters()
```

処理内容：
1. GameManagerに登録された全キャラクターを取得
2. `unregister_character()`で登録解除
3. `queue_free()`でノード削除

#### `cleanup_paths() -> void`
パス関連の状態をすべてクリアする。

```gdscript
map_manager.cleanup_paths()
```

処理内容：
1. `cancel_all_path_following()` - パス追従停止
2. `clear_all_pending_paths()` - 保留パスクリア
3. パスモード中なら`cancel_path()` - パスモードキャンセル
4. `selection_manager.deselect_all()` - 選択解除

### クエリAPI

#### `has_map() -> bool`
マップがロードされているか確認する。

```gdscript
if map_manager.has_map():
    print("Current map: ", map_manager.current_map_id)
```

#### `get_map_size() -> Vector2`
現在のマップサイズを取得する。

```gdscript
var size = map_manager.get_map_size()
print("Map size: ", size)  # Vector2(50, 50)
```

#### `get_spawn_points(is_ct: bool) -> Array[Vector3]`
現在のマップからスポーン位置を取得する。

```gdscript
var ct_spawns = map_manager.get_spawn_points(true)
var t_spawns = map_manager.get_spawn_points(false)
```

## GameManager統合

MapManagerはGameManagerの子ノードとして動作する：

```gdscript
# GameManager内部
func _setup_map_manager() -> void:
    map_manager = MapManager.new()
    map_manager.name = "MapManager"
    add_child(map_manager)
    map_manager.setup(_map_container, self)
```

GameManagerはMapManagerへの委譲APIを提供：

```gdscript
# GameManager経由でのマップ操作
var map = game_manager.load_map("test_map")
game_manager.switch_map("warehouse")
game_manager.unload_map()

# 状態取得
if game_manager.has_map():
    var id = game_manager.get_current_map_id()
    var spawns = game_manager.get_spawn_points(true)
```

## 使用例

### マップ切り替え

```gdscript
func _on_map_button_pressed(map_id: String) -> void:
    # MapManagerが自動でクリーンアップ
    var map = game_manager.switch_map(map_id)
    if map:
        print("Switched to: ", map_id)
```

### シグナル購読

```gdscript
func _ready() -> void:
    game_manager.map_manager.map_will_load.connect(_on_map_will_load)
    game_manager.map_manager.map_loaded.connect(_on_map_loaded)
    game_manager.map_manager.map_will_unload.connect(_on_map_will_unload)
    game_manager.map_manager.map_unloaded.connect(_on_map_unloaded)

func _on_map_will_load(map_id: String) -> void:
    print("Loading map: ", map_id)
    show_loading_screen()

func _on_map_loaded(map_id: String, map_instance: Node3D) -> void:
    print("Map ready: ", map_id)
    hide_loading_screen()
    spawn_characters()

func _on_map_will_unload(map_id: String) -> void:
    print("Unloading map: ", map_id)
    save_game_state()

func _on_map_unloaded(map_id: String) -> void:
    print("Map unloaded: ", map_id)
```

### カスタムクリーンアップ

```gdscript
# 手動でクリーンアップ制御
game_manager.map_manager.cleanup_paths()  # パスのみクリア
game_manager.map_manager.cleanup_characters()  # キャラクターを削除
game_manager.map_manager.unload_map(false)  # マップのみアンロード（クリーンアップ済み）
```

## 関連クラス

- [MapRegistry](MapRegistry.md) - マッププリセット管理・インスタンス化
- [MapPreset](MapPreset.md) - マップ定義リソース
- [GameManager](GameManager.md) - MapManagerを内包、システム全体の統括
- [PathExecutionManager](PathExecutionManager.md) - パス実行管理
- [CharacterSelectionManager](CharacterSelectionManager.md) - キャラクター選択管理
