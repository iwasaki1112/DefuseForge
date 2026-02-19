# MapRegistry

マッププリセット管理オートロード。マップシーンの自動検出・登録・インスタンス化を行う。

## 基本情報

| 項目 | 内容 |
|------|------|
| スクリプト | `res://scripts/registries/map_registry.gd` |
| 基底クラス | Node |
| オートロード名 | `MapRegistry` |
| マップシーンディレクトリ | `res://scenes/maps/` |

## 定数

| 定数 | 値 | 説明 |
|------|-----|------|
| `WALL_COLLISION_LAYER` | `2` | 壁のコリジョンレイヤービット |
| `SCENE_DIR` | `"res://scenes/maps/"` | マップシーン格納ディレクトリ |
| `PRESET_FILES` | `[...]` | エクスポート用静的リスト（フォールバック） |

## マップ検出方式

1. **エディタ実行時**: `scenes/maps/` の `.tscn` をスキャンし、`map_id` @export が設定された MapBase シーンを自動検出
2. **エクスポート時**: `DirAccess` が使えない場合、`PRESET_FILES` 静的リストにフォールバック

### 起動時の動作

```
_ready()
├─ _load_presets_from_scenes()  ← scenes/maps/*.tscn をスキャン
│   └─ _create_preset_from_scene()  ← SceneState から map_id/display_name/map_description を読み取り
│       └─ register()  ← MapPreset を生成して登録
└─ （スキャン失敗時）_load_presets_from_list()  ← PRESET_FILES の静的リストからロード
```

`_create_preset_from_scene()` は `PackedScene.get_state()` を使い、シーンをインスタンス化せずにルートノードの @export プロパティ（`map_id`, `display_name`, `map_description`）を読み取る。`map_id` が未設定のシーンはスキップされる。

## API

### Query API

#### `get_preset(id: String) -> MapPreset`
IDでプリセットを取得。

```gdscript
var preset = MapRegistry.get_preset("home")
if preset:
    print(preset.display_name)
```

#### `has_preset(id: String) -> bool`
プリセットが存在するか確認。

#### `get_all() -> Array`
全プリセットを取得。

```gdscript
for preset in MapRegistry.get_all():
    print(preset.id, ": ", preset.display_name)
```

#### `get_all_ids() -> Array`
全プリセットIDを取得。

### Factory API

#### `instantiate_map(preset_id: String) -> Node3D`
プリセットIDからマップインスタンスを生成。壁グループの自動設定とスポーンポイント抽出も実行される。

```gdscript
var map = MapRegistry.instantiate_map("home")
if map:
    get_tree().current_scene.add_child(map)
```

#### `instantiate_map_from_preset(preset: MapPreset) -> Node3D`
プリセットオブジェクトからマップインスタンスを生成。

### Registration API

#### `register(preset: MapPreset) -> void`
プリセットを登録（通常は自動検出で登録される）。

#### `unregister(id: String) -> void`
プリセットを登録解除。

## 壁グループ自動設定

`instantiate_map()` で生成されたマップインスタンスは、`collision_layer` に `WALL_COLLISION_LAYER` ビットが含まれる `CollisionObject3D` が自動的に `"walls"` グループに追加される。

## スポーンポイント抽出

マップインスタンス化時に、シーン内のマーカーノードからスポーンポイントと向きを自動抽出してプリセットに設定する。

**マーカー命名規則:**
- CT: `spawn_ct_1`, `spawn_ct_2`, ... または `SpawnCT1`, `SpawnCT2`, ...
- T: `spawn_t_1`, `spawn_t_2`, ... または `SpawnT1`, `SpawnT2`, ...

マーカーの `position` がスポーン位置、`rotation.y` がスポーン向きとして使用される。

## GameManager統合

GameManagerの`load_map()`メソッドでMapRegistryを使用:

```gdscript
var map = game_manager.load_map("home")
```

GameManager.load_map()の処理:
1. MapRegistryからプリセット取得
2. マップインスタンス化
3. FogOfWarSystemのmap_size更新

## 使用例

### マップ選択UI

```gdscript
func _populate_map_list():
    for preset in MapRegistry.get_all():
        var button = Button.new()
        button.text = preset.display_name
        button.pressed.connect(func(): _load_map(preset.id))
        map_list.add_child(button)
```

## 関連クラス

- [MapPreset](MapPreset.md) - マッププリセットリソース
- [GameManager](GameManager.md) - load_map()でMapRegistry使用
- [CharacterRegistry](CharacterRegistry.md) - 同様のRegistryパターン
- [VisionComponent](VisionComponent.md) - "walls"グループを使用

## APIリファレンス

### シグナル
なし

### メソッド
- `register(preset: MapPreset) -> void`
- `unregister(id: String) -> void`
- `get_preset(id: String) -> MapPreset`
- `has_preset(id: String) -> bool`
- `get_all() -> Array`
- `get_all_ids() -> Array`
- `instantiate_map(preset_id: String) -> Node3D`
- `instantiate_map_from_preset(preset: MapPreset) -> Node3D`
