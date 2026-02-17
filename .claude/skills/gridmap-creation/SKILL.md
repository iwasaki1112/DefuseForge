---
name: gridmap-creation
description: GridMapタイルシステムでマップを作成する。CLIでテンプレート生成、エディタでタイル配置、保存して即プレイ。1ファイル完結。
argument-hint: [map_id]
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep
---

# GridMapタイルマップ作成ガイド

GridMapタイルシステムでマップを作成する完全ガイド。
引数 `$ARGUMENTS` でmap_idを指定できる（例: `/gridmap-creation warehouse`）。

## 全体フロー（1ファイル完結）

```
1. CLIでテンプレート.tscn生成
2. Godotエディタで開いてタイルを配置
3. スポーンポイント位置を調整
4. 保存 → マップ選択画面に自動表示
```

**Blender方式との違い**: .gd、.tres不要。.tscn 1ファイルで完結。

## Step 1: テンプレート生成

```bash
cd godot
godot --headless --script res://scripts/editor/new_gridmap_map.gd -- <map_id>
```

生成されるファイル:
- `scenes/maps/<map_id>.tscn` — GridMapシーン（MapBase直接方式）

## Step 2: エディタでタイル配置

1. Godotエディタで `scenes/maps/<map_id>.tscn` を開く
2. **GridMapノードを選択**
3. 画面上部のタイルパレットからタイルを選択:
   - `floor_concrete` — 床（GROUND_COLLISION_LAYER）
   - `wall_exterior` — 外壁（WALL_COLLISION_LAYER + FoWオクルーダー）
   - `wall_interior` — 内壁（WALL_COLLISION_LAYER + FoWオクルーダー）
   - `door_frame` — ドア枠（WALL_COLLISION_LAYER + doorsグループ）
4. クリックでタイルを配置
5. 回転: GridMapツールバーの回転ボタン

## Step 3: スポーンポイント調整

テンプレートにデフォルトのスポーンMarker3Dが配置済み:
- `spawn_ct_0`, `spawn_ct_1` — CTスポーン
- `spawn_t_0`, `spawn_t_1` — Tスポーン

エディタで位置と回転を調整する。

## Step 4: 保存して完了

保存するだけでマップ選択画面に自動表示される。
MapRegistryが `scenes/maps/` を自動スキャンし、`map_id` @exportが設定された.tscnを検出する。

## アーキテクチャ

### .tscn構造（MapBase直接方式）

```
[node name="MapName" type="Node3D"]
script = map_base.gd        ← MapBase直接（サブクラス不要）
map_id = "map_name"          ← @export: MapRegistryが自動検出
display_name = "MapName"     ← @export: マップ選択画面の表示名
map_description = ""         ← @export: 説明文（任意）

  [node name="GridMapGround" type="GridMap"]
  mesh_library = tile_library_floor.tres
  cell_size = Vector3(1, 2, 1)     ← 床: 1m×1m
  cell_center_y = false

  [node name="GridMapWall" type="GridMap"]
  mesh_library = tile_library_wall.tres
  cell_size = Vector3(2, 2, 2)     ← 壁: 2m×2m
  cell_center_y = false

  [node name="spawn_ct_0" type="Marker3D"]
  [node name="spawn_t_0" type="Marker3D"]
```

### ランタイム処理（MapBase._ready()）

1. **GridMap検出** → `_setup_gridmap_collisions()`
2. GridMap内蔵コリジョンを無効化（collision_layer = 0）
3. 各セルのアイテム名でカテゴリ判定:
   - `floor*` / `ground*` → StaticBody3D + GROUND_COLLISION_LAYER (1)
   - `wall*` / `glass*` → StaticBody3D + WALL_COLLISION_LAYER (2)
   - `door*` → StaticBody3D + WALL_COLLISION_LAYER (2) + doorsグループ
4. **FoW通知** → OccluderManagerがGridMapセルから壁/ドアのオクルーダーを抽出

### MapRegistry検出フロー

```
1. scenes/maps/*.tscn スキャン → SceneStateからmap_id読取 → MapPreset生成
2. data/maps/*.tres スキャン → レガシーMapPreset読取
3. フォールバック: PRESET_FILES静的リスト（iOSエクスポート用）
```

## タイルアセット管理

### MeshLibrary生成

```bash
cd godot
godot --headless --script res://scripts/editor/generate_tile_library_cli.gd
```

タイルソース: `blender/tiles/tile_library.blend` → GLBエクスポート → `godot/scenes/tiles/*.glb`

### 新タイル追加手順

1. Blenderで `tile_library.blend` にコレクション追加（コレクション名 = タイル名）
2. 一括エクスポート: `exec(open("blender/tiles/export_tiles.py").read())` (Blender MCP経由)
   または: `blender tile_library.blend --background --python export_tiles.py`
3. CLI実行で `tile_library.tres` 更新（GLBは自動スキャン、手動登録不要）

### タイルアイテム名とコリジョン分類

| アイテム名パターン | コリジョンレイヤー | FoWオクルーダー |
|-------------------|-------------------|----------------|
| `floor*`, `ground*` | Layer 1（床） | なし |
| `wall*` | Layer 2（壁） | あり（高さ≥1.2m） |
| `glass*` | Layer 2（壁） | なし |
| `door*` | Layer 2 + doorsグループ | あり |

## iOSデプロイ

エクスポート前にPRESET_FILESを同期:

```bash
cd godot
godot --headless --script res://scripts/editor/sync_map_presets.gd
```

## GridMap設定

床と壁で異なるグリッドサイズを使用:

| GridMapノード | cell_size | MeshLibrary | 用途 |
|--------------|-----------|-------------|------|
| GridMapGround | Vector3(1, 2, 1) | tile_library_floor.tres | 床/地面タイル（1m×1m） |
| GridMapWall | Vector3(2, 2, 2) | tile_library_wall.tres | 壁/ドア/ガラスタイル（2m×2m） |

| 共通設定 | 値 | 理由 |
|---------|-----|------|
| cell_center_x | true（デフォルト） | セル中心にメッシュ配置 |
| cell_center_y | false | 床がY=0に配置される |
| cell_center_z | true（デフォルト） | セル中心にメッシュ配置 |

## トラブルシューティング

| 症状 | 原因 | 修正 |
|------|------|------|
| マップ選択に表示されない | map_idが未設定 | .tscnルートノードのインスペクタでmap_idを設定 |
| キャラクターが落下する | floor_concreteタイル未配置 | 全歩行エリアにfloor_concreteを配置 |
| FoW壁が効かない | wall_exteriorの高さ < 1.2m | タイルメッシュの高さを確認 |
| コリジョンが効かない | MeshLibraryにシェイプ未登録 | generate_tile_library_cli.gdを再実行 |
| タイルパレットが空 | tile_library.tres未生成 | generate_tile_library_cli.gdを実行 |

## 関連ファイル

| ファイル | 責務 |
|---------|------|
| `scripts/maps/map_base.gd` | MapBase基底クラス（GridMap自動処理 + @exportメタデータ） |
| `scripts/registries/map_registry.gd` | マップ検出（.tscn自動スキャン + .tresレガシー） |
| `scripts/systems/occluder_manager.gd` | FoWオクルーダー抽出（GridMap対応） |
| `data/tiles/tile_library.tres` | MeshLibrary（タイルメッシュ+コリジョン） |
| `scripts/editor/new_gridmap_map.gd` | CLIテンプレート生成 |
| `scripts/editor/generate_tile_library_cli.gd` | MeshLibrary生成CLI |
| `scripts/editor/sync_map_presets.gd` | PRESET_FILES同期CLI |
| `blender/tiles/tile_library.blend` | タイルアセットソース |
