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

## 定数

| 定数 | 値 | 説明 |
|------|-----|------|
| `WALL_COLLISION_LAYER` | `2` | 壁・ドア用の物理レイヤー |

## 内部メソッド

- `_setup_collisions(node: Node)`: 再帰的にコリジョンを設定。
- `_notify_fow_system()`: FoWシステムへの通知を試みる。
- `_notify_fow_system_deferred()`: 遅延通知用。
