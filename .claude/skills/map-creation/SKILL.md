---
name: map-creation
description: Blenderでマップを作成し、Godotにインポートしてゲーム内で使用可能にする。マップ作成、命名規則、GLTF書き出し、Godot登録の全手順をガイドする。
argument-hint: [building-type]
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep
---

# マップ作成ガイド

Blenderでマップを作成し、Godotにインポートしてゲーム内で使用可能にするための完全ガイド。
引数 `$ARGUMENTS` でマップの種類を指定できる（例: `/map-creation office`）。

## 全体フロー

```
1. Blenderでモデル作成（命名規則に従う）
2. GLTFエクスポート → godot/scenes/maps/<map>.gltf
3. マップスクリプト作成 → godot/scripts/maps/<map>.gd
4. マップシーン作成 → godot/scenes/maps/<map>.tscn
5. マッププリセット作成 → godot/data/maps/<map>.tres
6. MapRegistryに登録 → godot/scripts/registries/map_registry.gd
```

## 命名規則（Critical）

### プレフィックスルール

MapBase.gd が自動検出してコリジョンレイヤーとFoWオクルーダーを設定する。

| プレフィックス | コリジョンレイヤー | FoWオクルーダー | 用途 |
|-------------|-------------------|----------------|------|
| `Ground_` | Layer 1（床） | マップサイズ計算に使用 | 床、地面 |
| `Wall_` | Layer 2（壁） | **視界を遮蔽する**（高さ≥1.2m） | 壁、家具、フェンス等のカバー |
| `Door_` | Layer 2 + doorsグループ | **視界を遮蔽する** | 開閉するドア |
| `Glass_` | デフォルト（Layer 1） | **遮蔽しない** | 窓ガラス（視界は通る、移動はブロック） |
| `Frame_` | デフォルト（Layer 1） | **遮蔽しない** | 窓上部の壁帯（構造材） |
| `Outdoor_` | 設定なし | **遮蔽しない** | 装飾（樹冠、花壇等） |
| `spawn_ct_*` | — | — | CTスポーン位置（Empty） |
| `spawn_t_*` | — | — | Tスポーン位置（Empty） |

### GLTFサフィックス（コリジョン自動生成）

| サフィックス | 生成されるコリジョン | 用途 |
|------------|---------------------|------|
| `-col` | ConvexPolygonShape3D | 壁、障害物（推奨） |
| `-colonly` | 同上（メッシュ非表示） | 不可視コリジョン |
| `-trimesh` | ConcavePolygonShape3D | 複雑な形状 |

### 命名例

```
Ground_Floor-col        # 建物内の床（コリジョン付き）
Ground_Garden-col       # 庭の地面（コリジョン付き）
Ground_Path_Main        # 歩道（装飾、コリジョン不要）
Wall_North-col          # 外壁（コリジョン+FoW遮蔽）
Wall_Desk_O1-col        # デスク（カバー用コリジョン+FoW遮蔽）
Wall_Hedge_South-col    # 生垣（カバー用、高さ0.8m→FoW遮蔽スキップ）
Wall_South_Pier0-col    # 窓間の柱（FoW遮蔽）
Glass_South_Win0-col    # 窓ガラス（視界透過、移動ブロック）
Frame_South_Header-col  # 窓上部の壁帯（FoW遮蔽なし）
Outdoor_Tree_Canopy     # 木の葉（装飾のみ）
spawn_ct_1              # CTスポーン（Empty）
spawn_t_1               # Tスポーン（Empty）
```

## 重要な教訓（Must Follow）

### 1. マップは必ず原点(0,0)中心に配置する

FoWシステムがマップを原点中心で計算するため、Ground_全体のバウンディングボックスの中心がBlenderの原点(0,0)になるようにする。
例: 24×24mのマップなら X[-12,12] × Y[-12,12] に収まるように配置。

### 2. 地面は必ず厚みのあるBoxにする

**NG**: `primitive_plane_add`（厚さ0） → コリジョン生成失敗 → キャラクター落下
**OK**: `primitive_cube_add` で厚さ0.1m程度のBoxを使用

### 3. 全歩行可能エリアにコリジョン付き地面が必要

- 建物内: `Ground_Floor-col`
- 庭全体: `Ground_Garden-col`（全エリアをカバーする大きなBox）
- 歩道やラインは装飾のみ（庭の地面のコリジョンがカバー）

### 4. ドア開口部にリンテル壁を置かない

FoWが2D投影（Y軸無視）のため、リンテルがドア開口を塞いで視界が通らない。
TopDown視点でドアの位置がわからなくなる。壁の上端まで完全に突き抜ける開口にすること。

### 5. FoWオクルーダーの高さフィルター

`Wall_`プレフィックスのオブジェクトをXZ平面に投影して2D LightOccluder2Dとして登録する。
**高さ1.2m未満の障害物はFoW遮蔽をスキップ**（`MIN_OCCLUSION_HEIGHT = 1.2`）。
これにより低い障害物（0.8mの生垣等）は3Dレイキャストと同様にFoWでも視界が通る。
装飾用の高所オブジェクトに`Wall_`プレフィックスを使わないこと。

### 6. 天井（屋根）は不要

TopDownゲームのため、建物に天井を付けない。

### 7. スポーンポイントの向き

BlenderではZ軸回転でヨー設定。GLTF Y-up exportでGodot Y軸回転に自動変換される。

```python
# BlenderでZ軸回転 = Godot Y軸回転
empty.rotation_euler = (0, 0, math.radians(180))  # 建物方向を向く
```

### 8. ライト・カメラはマップに含めない

GameScreenの`EnvironmentSetup`が自動適用するため不要。

## Blenderでの作成手順

### Step 1: 地面作成（厚みのあるBox）

```python
GROUND_THICKNESS = 0.1

# 建物内の床
bpy.ops.mesh.primitive_cube_add(size=1, location=(cx, cy, -GROUND_THICKNESS/2))
floor = bpy.context.active_object
floor.name = "Ground_Floor-col"
floor.scale = (width, depth, GROUND_THICKNESS)
bpy.ops.object.transform_apply(scale=True)

# 庭全体
bpy.ops.mesh.primitive_cube_add(size=1, location=(gcx, gcy, -0.01 - GROUND_THICKNESS/2))
garden = bpy.context.active_object
garden.name = "Ground_Garden-col"
garden.scale = (garden_w, garden_d, GROUND_THICKNESS)
bpy.ops.object.transform_apply(scale=True)
```

### Step 2: 壁作成

```python
WALL_THICKNESS = 0.15
WALL_HEIGHT = 2.5

def create_wall(name, x, y, width, depth, height=WALL_HEIGHT):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(
        x + width/2, y + depth/2, height/2
    ))
    wall = bpy.context.active_object
    wall.name = name  # 例: "Wall_North-col"
    wall.scale = (width, depth, height)
    bpy.ops.object.transform_apply(scale=True)
    return wall
```

### Step 3: ドア開口部（壁を分割、リンテルなし）

```python
# 壁の左側
create_wall("Wall_South_Left-col", 0, 0, door_x, WALL_THICKNESS)
# 壁の右側
create_wall("Wall_South_Right-col", door_x + DOOR_WIDTH, 0, remaining, WALL_THICKNESS)
# リンテルは作らない！
```

### Step 4: 窓の追加（任意）

外壁に窓を追加する場合、壁を分割して窓構造を作成する。

**窓の構成要素:**
- `Wall_*_Sill-col` — 窓台（Z: 0→0.8m）。高さフィルターでFoW遮蔽スキップ
- `Wall_*_Pier*-col` — 窓間の柱（Z: 0.8→2.0m）。FoW遮蔽あり
- `Frame_*_Header-col` — 窓上部の壁帯（Z: 2.0→2.5m）。`Frame_`プレフィックスでFoW遮蔽なし
- `Glass_*_Win*-col` — ガラス面（薄いBox 0.02m厚）。`Glass_`プレフィックスでFoW遮蔽なし

**窓サイズの目安:** 幅1.5m × 高1.2m、窓台高0.8m

**重要ポイント:**
- Header（窓上壁帯）は `Wall_` ではなく `Frame_` プレフィックス。全幅に渡るため `Wall_` だと窓部分もFoWで遮蔽されてしまう
- Sill（窓台）は `Wall_` プレフィックスでOK。高さ0.8m < 1.2m なので高さフィルターでスキップされる
- Glass は `-col` サフィックスで移動ブロック。`Glass_` プレフィックスでFoW/3D視界は透過

```python
# 窓付き壁の作成例（南壁）
# 1. 元の壁を削除
# 2. 窓台（全幅、Wall_プレフィックス）
create_box("Wall_South_Sill-col", (0,0,0), (9.5, 0.15, 0.8))
# 3. 窓上壁帯（全幅、Frame_プレフィックス）
create_box("Frame_South_Header-col", (0,0,2.0), (9.5, 0.15, 2.5))
# 4. 柱（窓間、Wall_プレフィックス）
create_box("Wall_South_Pier0-col", (0,0,0.8), (0.75, 0.15, 2.0))
# 5. ガラス（薄いBox、Glass_プレフィックス）
create_box("Glass_South_Win0-col", (0.75, 0.065, 0.8), (2.25, 0.085, 2.0))
```

### Step 5: スポーンポイント（旧Step 4）

```python
import math

def create_spawn(name, x, y, z=0, yaw_degrees=0):
    bpy.ops.object.empty_add(type='ARROWS', location=(x, y, z))
    sp = bpy.context.active_object
    sp.name = name
    sp.empty_display_size = 0.5
    sp.rotation_euler = (0, 0, math.radians(yaw_degrees))
    return sp

# CT: 建物外（建物方向=180度）
create_spawn("spawn_ct_1", 10, -5, 0, 180)
# T: 建物内（CT方向=0度）
create_spawn("spawn_t_1", 3, 3, 0, 0)
```

### Step 6: GLTFエクスポート

```python
bpy.ops.export_scene.gltf(
    filepath="/path/to/godot/scenes/maps/<map_name>.gltf",
    export_format='GLTF_SEPARATE',
    use_selection=False,
    export_apply=True,
    export_yup=True,
    export_extras=True,
    export_cameras=False,
    export_lights=False,
    export_materials='EXPORT',
)
```

## Godotファイル作成

### マップスクリプト: `godot/scripts/maps/<map>.gd`

```gdscript
extends MapBase

func _ready() -> void:
	_map_name = "<MAP_NAME>"
	super._ready()
```

### マップシーン: `godot/scenes/maps/<map>.tscn`

```
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/maps/<map>.gltf" id="1_gltf"]
[ext_resource type="Script" path="res://scripts/maps/<map>.gd" id="2_script"]

[node name="<MapName>" instance=ExtResource("1_gltf")]
script = ExtResource("2_script")
```

### マッププリセット: `godot/data/maps/<map>.tres`

```
[gd_resource type="Resource" script_class="MapPreset" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/resources/map_preset.gd" id="1_script"]
[ext_resource type="PackedScene" path="res://scenes/maps/<map>.tscn" id="2_scene"]

[resource]
script = ExtResource("1_script")
id = "<map>"
display_name = "<Display Name>"
description = "<Map description>"
map_scene = ExtResource("2_scene")
map_size = Vector2(<width>, <depth>)
spawn_points_ct = Array[Vector3]([])
spawn_points_t = Array[Vector3]([])
spawn_rotations_ct = Array[float]([])
spawn_rotations_t = Array[float]([])
```

### MapRegistryに登録

`godot/scripts/registries/map_registry.gd` の `PRESET_FILES` に追加:

```gdscript
const PRESET_FILES := [
	"res://data/maps/home.tres",
	"res://data/maps/<map>.tres",  # ← 追加
]
```

## トラブルシューティング

| 症状 | 原因 | 修正 |
|------|------|------|
| キャラクターが地面を突き抜ける | 地面がPlane（厚さ0）、`-col`欠落 | 厚さ0.1mのBoxに変更、`-col`付加 |
| 部屋間で視界が通らない | ドア上のリンテル壁が`Wall_`プレフィックス | リンテル壁を削除 |
| 庭で落下する | `Ground_Garden`に`-col`がない | `Ground_Garden-col`にリネーム |
| マップ選択に表示されない | MapRegistryのPRESET_FILESに未登録 | パスを追加 |
| FoWのマップサイズがおかしい | `Ground_`プレフィックスの地面が不足 | 全歩行エリアに`Ground_`付きBoxを配置 |
| スポーンの向きが逆 | BlenderのZ回転が未設定 | Z回転180度=建物方向を向く |
| FoWの範囲がマップとズレている | マップが原点中心に配置されていない | Blenderで全オブジェクトを原点中心に移動 |
| 窓越しにFoW視界が通らない | Header が `Wall_` プレフィックス | `Frame_` にリネーム |
| 低い障害物がFoWで見えない | 高さ < 1.2m だが `Wall_` が付いている | 正常動作。高さフィルターでスキップされる |

## 関連ファイル

| ファイル | 責務 |
|---------|------|
| `scripts/maps/map_base.gd` | マップ基底クラス（コリジョン自動設定、FoW通知） |
| `scripts/resources/map_preset.gd` | MapPresetリソース定義 |
| `scripts/registries/map_registry.gd` | マップ登録・インスタンス化 |
| `scripts/systems/occluder_manager.gd` | FoWオクルーダー抽出（XZ平面投影） |
