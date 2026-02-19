# OccluderManager

Light2D用のLightOccluder2D管理システム。
3Dマップの壁、ドア、スモークエリアをSubViewport内の2Dオクルーダーに変換し、Fog of Warの遮蔽処理を行う。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/systems/occluder_manager.gd` |

## 概要

`FogOfWarSystem` によって使用されるコンポーネント。3Dワールドのジオメトリを解析し、FoW描画用の2Dポリゴンオクルーダーを生成・管理する。

## シグナル

| シグナル | 引数 | 説明 |
|---------|------|------|
| `occluder_updated` | なし | オクルーダーが更新された時に発火 |

## Public API

### セットアップ

#### `setup(viewport: SubViewport, map_size: Vector2, resolution: int) -> void`
マネージャーを初期化する。

**引数:**
- `viewport`: オクルーダーを追加するSubViewport
- `map_size`: マップのワールドサイズ
- `resolution`: テクスチャ解像度

### オクルーダー抽出

#### `extract_occluders_from_map(map_node: Node3D) -> void`
マップノードから壁やドアを探索し、オクルーダーを生成する。
ノード名が `wall_` または `door_` で始まる MeshInstance3D または CollisionShape3D を対象とする。

**引数:**
- `map_node`: マップのルートノード

### ドア制御

#### `set_door_occluder_enabled(door: Node3D, enabled: bool) -> void`
指定したドアのオクルーダーの有効/無効を切り替える。
ドアが開いたときは無効（`false`）、閉じたときは有効（`true`）にする。

**引数:**
- `door`: ドアのノード
- `enabled`: 有効にするかどうか

### ドアオクルーダーアニメーション

#### `start_door_occluder_animation(door: Node3D) -> void`
ドア開放アニメーション中にオクルーダーポリゴンをリアルタイム更新する。ドアのワールドコーナー座標をドアローカル座標に変換し、毎フレーム `door.global_transform` から2Dポリゴンを再計算する。

**引数:**
- `door`: アニメーション対象のドアノード

#### `stop_door_occluder_animation(door: Node3D) -> void`
ドアオクルーダーアニメーションを停止し、ドアの最終位置（回転後）でポリゴンを更新する。開いたドアパネルがFoW遮蔽を維持するため、オクルーダーは表示されたまま残る。

**引数:**
- `door`: アニメーション対象のドアノード

### スモーク制御

#### `add_smoke_occluder(smoke_area: Node3D) -> void`
スモークエリアに対応する円形オクルーダーを追加する。

**引数:**
- `smoke_area`: スモークエリアのノード（`get_current_radius()`メソッドが必要）

#### `remove_smoke_occluder(smoke_area: Node3D) -> void`
スモークエリアのオクルーダーを削除する。

#### `update_smoke_radius(smoke_area: Node3D) -> void`
スモークエリアの現在の半径に合わせてオクルーダーの形状を更新する。

### その他

#### `clear_all_occluders() -> void`
全てのオクルーダーを削除する。

#### `set_map_size(new_size: Vector2) -> void`
マップサイズを更新し、スケール係数を再計算する。

#### `set_texture_resolution(resolution: int) -> void`
テクスチャ解像度を更新し、スケール係数を再計算する。

## 内部動作

### オクルーダー生成ロジック

1.  **BoxShape3D**: 底面（XZ平面）の矩形ポリゴンを生成。
2.  **ConvexPolygonShape3D**: 頂点をXZ平面に投影し、凸包（Convex Hull）を計算してポリゴン化。
3.  **CylinderShape3D**: 円形ポリゴンを生成。
4.  **MeshInstance3D**: AABB（軸平行境界ボックス）の底面矩形を使用。

### 座標変換

ワールド座標（3D）からビューポート座標（2D）への変換は以下の式で行われる：

```gdscript
uv_x = (world_x + map_width / 2) / map_width
uv_y = (world_z + map_height / 2) / map_height
viewport_x = uv_x * resolution
viewport_y = uv_y * resolution
```
