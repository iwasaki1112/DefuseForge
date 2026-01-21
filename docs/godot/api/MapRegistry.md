# MapRegistry

マッププリセット管理オートロード。プリセットの登録・検索・マップインスタンス化を行う。

## 基本情報

| 項目 | 内容 |
|------|------|
| スクリプト | `res://scripts/registries/map_registry.gd` |
| 基底クラス | Node |
| オートロード名 | `MapRegistry` |
| プリセットディレクトリ | `res://data/maps/` |

## 定数

| 定数 | 値 | 説明 |
|------|-----|------|
| `WALL_COLLISION_LAYER` | `2` | 壁のコリジョンレイヤービット |
| `PRESET_DIR` | `"res://data/maps/"` | プリセット格納ディレクトリ |

## API

### Query API

#### `get_preset(id: String) -> MapPreset`
IDでプリセットを取得。

```gdscript
var preset = MapRegistry.get_preset("test_map")
if preset:
    print(preset.display_name)
```

#### `has_preset(id: String) -> bool`
プリセットが存在するか確認。

```gdscript
if MapRegistry.has_preset("warehouse"):
    print("Warehouse map available")
```

#### `get_all() -> Array`
全プリセットを取得。

```gdscript
for preset in MapRegistry.get_all():
    print(preset.id, ": ", preset.display_name)
```

#### `get_all_ids() -> Array`
全プリセットIDを取得。

```gdscript
var map_ids = MapRegistry.get_all_ids()
print(map_ids)  # ["test_map", "warehouse", ...]
```

### Factory API

#### `instantiate_map(preset_id: String) -> Node3D`
プリセットIDからマップインスタンスを生成。

```gdscript
var map = MapRegistry.instantiate_map("test_map")
if map:
    get_tree().current_scene.add_child(map)
```

#### `instantiate_map_from_preset(preset: MapPreset) -> Node3D`
プリセットオブジェクトからマップインスタンスを生成。

```gdscript
var preset = MapRegistry.get_preset("test_map")
var map = MapRegistry.instantiate_map_from_preset(preset)
```

### Registration API

#### `register(preset: MapPreset) -> void`
プリセットを登録（通常は自動読み込み）。

```gdscript
var custom_preset = MapPreset.new()
custom_preset.id = "custom_map"
MapRegistry.register(custom_preset)
```

#### `unregister(id: String) -> void`
プリセットを登録解除。

```gdscript
MapRegistry.unregister("custom_map")
```

## 壁グループ自動設定

`instantiate_map()`で生成されたマップインスタンスは、collision_layer=2のノードが自動的に"walls"グループに追加される。

対象ノード:
- `CollisionObject3D`（StaticBody3D等）

これにより、VisionComponentの視界計算で壁として認識される。

## GameManager統合

GameManagerの`load_map()`メソッドでMapRegistryを使用:

```gdscript
# GameManagerでマップをロード
var map = game_manager.load_map("test_map")
if map:
    $MapContainer.add_child(map)

    # スポーン位置を取得
    var ct_spawns = game_manager.get_spawn_points("test_map", true)
    var t_spawns = game_manager.get_spawn_points("test_map", false)
```

GameManager.load_map()の処理:
1. MapRegistryからプリセット取得
2. マップインスタンス化
3. FogOfWarSystemのmap_size更新
4. VisionComponent.invalidate_wall_cache()呼び出し

## 起動時の動作

1. `_ready()`で`res://data/maps/`ディレクトリをスキャン
2. 全`.tres`ファイルをMapPresetとしてロード
3. コンソールに"MapRegistry: Loaded X presets"を出力

## 使用例

### マップ選択UI

```gdscript
func _populate_map_list():
    for preset in MapRegistry.get_all():
        var button = Button.new()
        button.text = preset.display_name
        button.pressed.connect(func(): _load_map(preset.id))
        map_list.add_child(button)

func _load_map(map_id: String):
    var map = game_manager.load_map(map_id)
    if map:
        _current_map = map
        add_child(map)
```

### キャラクタースポーン

```gdscript
func spawn_characters(map_id: String):
    var preset = MapRegistry.get_preset(map_id)

    # CTチームをスポーン
    for i in range(preset.spawn_points_ct.size()):
        var pos = preset.spawn_points_ct[i]
        var character = CharacterRegistry.create_character("ct_operator", pos)
        add_child(character)
        game_manager.register_character(character)

    # Tチームをスポーン
    for i in range(preset.spawn_points_t.size()):
        var pos = preset.spawn_points_t[i]
        var character = CharacterRegistry.create_character("t_operator", pos)
        add_child(character)
        game_manager.register_character(character)
```

## 関連クラス

- [MapPreset](MapPreset.md) - マッププリセットリソース
- [GameManager](GameManager.md) - load_map()でMapRegistry使用
- [CharacterRegistry](CharacterRegistry.md) - 同様のRegistryパターン
- [VisionComponent](VisionComponent.md) - "walls"グループを使用
