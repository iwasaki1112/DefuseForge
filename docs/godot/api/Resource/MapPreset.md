# MapPreset

マッププリセットリソース。マップのメタデータ、シーン参照、スポーン位置を定義する。

## 基本情報

| 項目 | 内容 |
|------|------|
| スクリプト | `res://scripts/resources/map_preset.gd` |
| 基底クラス | Resource |

## マップ定義方式

マッププリセットは `.tscn` マップシーン内の `MapBase` @export から自動生成される。MapRegistryが `scenes/maps/` の `.tscn` をスキャンし、`map_id` 付きシーンからプリセットを自動作成する。

個別の `.tres` ファイルは不要。

## プロパティ

### Basic Info

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `id` | String | `""` | ユニークID（例: "home"） |
| `display_name` | String | `""` | UI表示用の名前 |
| `description` | String | `""` | マップの説明文 |

### Scene

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `map_scene` | PackedScene | `null` | マップシーン（.tscn） |

### Map Settings

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `map_size` | Vector2 | `(50, 50)` | FogOfWarSystem用のマップサイズ |

### Spawn Points

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `spawn_points_ct` | Array[Vector3] | `[]` | Counter-Terroristスポーン位置 |
| `spawn_points_t` | Array[Vector3] | `[]` | Terroristスポーン位置 |
| `spawn_rotations_ct` | Array[float] | `[]` | CTスポーン向き（Y回転ラジアン） |
| `spawn_rotations_t` | Array[float] | `[]` | Tスポーン向き（Y回転ラジアン） |

### UI

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `thumbnail` | Texture2D | `null` | マップ選択UI用サムネイル |

## マップシーン構造（GridMapタイルシステム）

マップは GridMap + MapBase 方式で構築する。

```
MapRoot (Node3D) [script: MapBase]
├── GridMap (GridMap)
│   ├── Layer 0: 床タイル（floor*, ground*）
│   └── Layer 1: 壁タイル（wall*, glass*, door*）
├── SpawnCT1 (Marker3D) ← CTスポーン位置
├── SpawnCT2 (Marker3D)
├── SpawnT1 (Marker3D) ← Tスポーン位置
└── SpawnT2 (Marker3D)
```

MapBase の @export プロパティでメタデータを埋め込む:

```gdscript
@export var map_id: String = ""
@export var display_name: String = ""
@export var map_description: String = ""
```

### GridMapタイル分類

| タイル名パターン | Layer | 用途 |
|-----------------|-------|------|
| `floor*`, `ground*` | 0（床） | 床面 |
| `wall*`, `glass*` | 1（壁） | 壁・障害物 |
| `door*` | 1（壁） + `doors` グループ | ドア |

### グリッドサイズ

`cell_size = Vector3(2, 2, 2)` — 2m x 2m x 2m グリッド

## マップの作成方法

1. CLIでテンプレート生成: `godot --headless --script res://scripts/editor/new_gridmap_map.gd -- <map_id>`
2. Godotエディタでタイル配置
3. `scenes/maps/` に保存 → MapRegistryが自動検出・登録

## ランタイム処理

`MapBase._ready()` が GridMap セルから `StaticBody3D` を自動生成（GridMap built-in コリジョンは無効化）。

**重要: 環境設定について**

マップシーンにDirectionalLight3DやWorldEnvironmentを含めないこと。
環境設定（ライティング・影・レンダリング品質）はGameScreenの`EnvironmentSetup`が自動的に適用する。
詳細は [EnvironmentSetup](EnvironmentSetup.md) を参照。

## コリジョンレイヤー

| Layer | Bit | 用途 |
|-------|-----|------|
| 1 | `1` | キャラクター、床 |
| 2 | `2` | 壁・障害物（VisionComponent用） |

壁（collision_layer=2）はVisionComponentの視界計算で遮蔽物として検出される。

## 関連クラス

- [MapRegistry](MapRegistry.md) - プリセット管理・マップインスタンス化
- [GameManager](GameManager.md) - load_map()でマップロード
- [VisionComponent](VisionComponent.md) - 壁グループを使用した視界計算
- [FogOfWarSystem](FogOfWarSystem.md) - map_sizeを使用
- [EnvironmentSetup](EnvironmentSetup.md) - 環境設定の自動適用

## APIリファレンス

### シグナル
なし

### メソッド
なし
