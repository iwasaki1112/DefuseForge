# MapBase

**継承:** `Node3D`

マップの基底クラス。
壁やドアのコリジョン設定と、Fog of Warシステムへのオクルーダー抽出通知を自動化する。

## ファイル
`scripts/maps/map_base.gd`

## 機能

### 1. 自動コリジョン設定
`_ready()` 時にノードツリーを走査し、特定の命名規則に従ってコリジョンレイヤーを設定する。

- **対象**: `StaticBody3D`
- **ルール**:
    - ノード名または親ノード名が `wall_` または `door_` で始まる場合:
        - `collision_layer` を `2` (WALL_COLLISION_LAYER) に設定。
    - `door_` で始まる場合:
        - ノードを `doors` グループに追加（`GameManager` 等からの参照用）。

### 2. FoWオクルーダー抽出通知
`_ready()` 時に `GameScreen` -> `VisionService` -> `FogOfWarSystem` にアクセスし、自身 (`self`) を対象に `extract_occluders_from_map()` を呼び出すよう要求する。
FoWシステムの準備ができていない場合は、準備ができるまで（`process_frame`待機）遅延実行する。

## 使用方法

新しいマップスクリプトを作成する際は、このクラスを継承する。

```gdscript
extends MapBase

func _ready() -> void:
    _map_name = "MyMap" # ログ用
    super._ready()      # 必須
```

## コリジョンレイヤー

| 定数 | 値 | 説明 |
|------|-----|------|
| `GROUND_COLLISION_LAYER` | `1` | 床用の物理レイヤー |
| `WALL_COLLISION_LAYER` | `2` | 壁・ドア・窓柱用の物理レイヤー |
| `WINDOW_GLASS_COLLISION_LAYER` | `4` | 窓ガラス用の物理レイヤー（キャラ移動ブロック専用） |

### 窓タイルのコリジョン分離

窓タイル（`wall_window`等）は2つのStaticBody3Dを生成する:

| ボディ | レイヤー | シェイプ | 用途 |
|--------|---------|---------|------|
| `GridCol_*` | 2 (WALL) | MeshLibraryの柱シェイプ | 壁構造。グレネード・射撃・視線はここで判定 |
| `WindowGlass_*` | 4 (WINDOW_GLASS) | フルAABBボックス | キャラ移動ブロック専用。グレネード・視線は透過 |

**各エンティティのmask設定:**

| エンティティ | mask | 窓通過 |
|-------------|------|--------|
| キャラクター | `7` (1+2+4) | 不可（ガラスで阻止） |
| グレネード | `3` (1+2) | 可（ガラス無視、柱にはバウンス） |
| 視線/射撃 | `2` | 可（柱以外は通過） |

## 内部メソッド

- `_setup_collisions(node: Node)`: 再帰的にコリジョンを設定。
- `_notify_fow_system()`: FoWシステムへの通知を試みる。
- `_notify_fow_system_deferred()`: 遅延通知用。
