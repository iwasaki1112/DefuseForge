---
name: weapon-addition
description: 新しい武器をゲームに追加する。3Dモデルの準備、スケール調整、Godotプリセット作成、レジストリ登録の全手順をガイドする。
argument-hint: [weapon-name]
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep
---

# 武器追加ガイド

新しい武器をゲームに追加するための完全ガイド。
引数 `$ARGUMENTS` で武器名を指定できる（例: `/weapon-addition mark18`）。

## 全体フロー

```
1. 3Dモデル準備（GLBファイル + テクスチャ）
2. Blenderでスケール調整（実物サイズに合わせる）
3. GLBエクスポート → godot/assets/weapons/<weapon>/
4. シーンラッパー作成 → godot/assets/weapons/<weapon>/<weapon>.tscn
5. 武器プリセット作成 → godot/data/weapons/<weapon>.tres
6. WeaponRegistryに登録 → godot/scripts/registries/weapon_registry.gd
7. weapon_adjustment.gdにも追加（テスト用）
8. Godotで位置調整（weapon_adjustmentシーン使用）
```

## ファイル構成

```
godot/
├── assets/weapons/<weapon>/
│   ├── <weapon>.glb              # 3Dモデル（必須）
│   ├── <weapon>.tscn             # シーンラッパー（ライフル等の両手持ちは必須）
│   └── <weapon>_*.jpg/png        # テクスチャ（GLBから自動抽出）
├── data/weapons/
│   └── <weapon>.tres             # WeaponPreset（武器ステータス）
└── scripts/registries/
    └── weapon_registry.gd        # PRESET_FILESに登録
```

## Step 1: 3Dモデルの準備

### アセット配置

GLBファイルとテクスチャを `godot/assets/weapons/<weapon>/` に配置する。

### Blenderでスケール調整（実物サイズ）

武器モデルを実物のサイズに合わせる。既存武器と比較してスケール確認。

**参考サイズ（実物）:**

| 武器 | 全長 | 高さ | 幅 |
|------|------|------|-----|
| AK-47 | ~0.88m | ~0.26m | ~0.07m |
| MK18 (CQBR) | ~0.84m | ~0.24m | ~0.065m |
| Glock-18 | ~0.19m | ~0.13m | ~0.03m |
| M4A1 | ~0.84m | ~0.25m | ~0.065m |
| MP5 | ~0.68m | ~0.21m | ~0.05m |

**Blender MCPでのスケーリング手順:**

```python
import bpy, mathutils

obj = bpy.data.objects['<weapon>']

# 現在のバウンディングボックスから全長を計算
bb = [obj.matrix_world @ mathutils.Vector(corner) for corner in obj.bound_box]
current_length = max(v.y for v in bb) - min(v.y for v in bb)

# 目標全長に合わせてスケーリング
target_length = 0.84  # 実物のサイズ(m)
scale_factor = target_length / current_length
obj.scale *= scale_factor

# スケール適用
bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

# 原点をジオメトリ中心にリセット
bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='MEDIAN')
obj.location = (0, 0, 0)
```

### GLBエクスポート

```python
bpy.ops.export_scene.gltf(
    filepath="<godot_project_path>/assets/weapons/<weapon>/<weapon>.glb",
    export_format='GLB',
    use_selection=True,  # 選択オブジェクトのみ
    export_apply=True,
    export_yup=True,
    export_materials='EXPORT',
)
```

## Step 2: シーンラッパー作成（.tscn）

ライフル等の両手持ち武器は `.tscn` でラップし、`LeftHandGrip` ノードを追加する。
ピストル等の片手持ち武器は `.glb` を直接参照可能。

### ライフル用テンプレート

`godot/assets/weapons/<weapon>/<weapon>.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://assets/weapons/<weapon>/<weapon>.glb" id="1"]

[node name="<WeaponName>" type="Node3D"]

[node name="Model" parent="." instance=ExtResource("1")]

[node name="LeftHandGrip" type="Node3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.055, 0.101, 0.2)
```

**注意:** Godotで開くとUIDが自動付与される。初期値は仮の位置 — weapon_adjustmentシーンで実際に調整する。

## Step 3: 武器プリセット作成（.tres）

`godot/data/weapons/<weapon>.tres` を作成する。

### テンプレート（ライフル）

```
[gd_resource type="Resource" script_class="WeaponPreset" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/resources/weapon_preset.gd" id="1"]
[ext_resource type="PackedScene" path="res://assets/weapons/<weapon>/<weapon>.tscn" id="2"]

[resource]
script = ExtResource("1")
id = "<weapon>"
display_name = "<Display Name>"
category = 0
damage = 18.0
fire_rate = 0.1
accuracy_peak = 0.70
accuracy_close = 0.55
accuracy_far = 0.08
accuracy_range_min = 3.0
accuracy_range_max = 20.0
accuracy_max_distance = 45.0
shooter_walk_penalty = 0.75
shooter_sprint_penalty = 0.35
target_move_penalty = 0.15
target_speed_reference = 6.0
recoil_strength = 0.15
recoil_recovery = 8.0
model_scene = ExtResource("2")
attach_offset = Vector3(0.05, 0.09, -0.02)
attach_rotation = Vector3(-66.5, 77.0, 24.0)
muzzle_flash_offset = Vector3(0.0, 0.15, 0.8)
muzzle_flash_scale = 0.59
muzzle_flash_rotation = Vector3(88.0, -162.0, 22.5)
left_hand_grip_enabled = true
left_hand_grip_offset = Vector3(0.024, 0.04, 0.2)
auto_firing_mode_enabled = true
cqb_max_distance = 2.0
cqb_firing_mode = 2
cqb_shots_per_burst = 0
cqb_burst_interval = 0.08
cqb_pause_after_burst = 0.0
cqb_accuracy_modifier = 0.80
cqb_critical_rate = 0.05
medium_max_distance = 15.0
medium_firing_mode = 1
medium_shots_per_burst = 3
medium_burst_interval = 0.1
medium_pause_after_burst = 0.4
medium_accuracy_modifier = 0.9
medium_critical_rate = 0.1
long_firing_mode = 0
long_shots_per_burst = 1
long_burst_interval = 0.0
long_pause_after_burst = 0.6
long_accuracy_modifier = 1.0
long_critical_rate = 0.2
```

### テンプレート（ピストル）

```
[gd_resource type="Resource" script_class="WeaponPreset" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/resources/weapon_preset.gd" id="1"]
[ext_resource type="PackedScene" path="res://assets/weapons/<weapon>/<weapon>.glb" id="2"]

[resource]
script = ExtResource("1")
id = "<weapon>"
display_name = "<Display Name>"
category = 1
damage = 16.0
fire_rate = 0.15
accuracy_peak = 0.65
accuracy_close = 0.70
accuracy_far = 0.05
accuracy_range_min = 0.0
accuracy_range_max = 10.0
accuracy_max_distance = 25.0
shooter_walk_penalty = 0.85
shooter_sprint_penalty = 0.5
target_move_penalty = 0.2
target_speed_reference = 6.0
recoil_strength = 0.18
recoil_recovery = 12.0
model_scene = ExtResource("2")
attach_offset = Vector3(-0.001, 0.094, 0.029)
attach_rotation = Vector3(-90, -81.5, 0)
muzzle_flash_offset = Vector3(0.012, 0.07, 0.26)
muzzle_flash_scale = 0.59
muzzle_flash_rotation = Vector3(88.0, -162.0, 22.5)
```

## Step 4: レジストリ登録

### WeaponRegistry（必須）

`godot/scripts/registries/weapon_registry.gd` の `PRESET_FILES` に追加:

```gdscript
const PRESET_FILES := [
    "res://data/weapons/ak47.tres",
    "res://data/weapons/glock.tres",
    "res://data/weapons/<weapon>.tres",  # ← 追加
]
```

### weapon_adjustment.gd（テスト用）

`godot/scripts/tests/weapon_adjustment.gd` の `_load_data()` 内の `weapon_paths` に追加:

```gdscript
var weapon_paths = [
    "res://data/weapons/ak47.tres",
    "res://data/weapons/glock.tres",
    "res://data/weapons/<weapon>.tres",  # ← 追加
]
```

## Step 5: Godotで位置調整

`weapon_adjustment.tscn` シーンを実行して以下を調整:

1. **attach_offset / attach_rotation** — 右手への取り付け位置・角度
2. **muzzle_flash_offset / scale / rotation** — マズルフラッシュの位置（銃口先端）
3. **LeftHandGrip位置** — 左手IKターゲット（ハンドガード位置）

調整後、表示される `Preset:` の値を `.tres` ファイルにコピーする。

## WeaponPreset プロパティリファレンス

### カテゴリ

| 値 | enum | 用途 |
|----|------|------|
| 0 | RIFLE | ライフル（AK-47, MK18, M4A1等） |
| 1 | PISTOL | ピストル（Glock等） |
| 2 | SMG | サブマシンガン |
| 3 | SHOTGUN | ショットガン |
| 4 | SNIPER | スナイパーライフル |

### 射撃モード（Auto Firing Mode）

ライフル/SMG向け。距離に応じて射撃モードを自動切替。

| 距離帯 | 設定 | 説明 |
|--------|------|------|
| CQB | `cqb_max_distance` まで | 近距離（フルオート推奨） |
| Medium | `medium_max_distance` まで | 中距離（バースト推奨） |
| Long | それ以降 | 遠距離（セミオート推奨） |

FiringMode enum: `0` = SINGLE, `1` = BURST, `2` = FULL_AUTO

### アニメーション連動

`WeaponCategory` によって使用アニメーションが自動選択される:
- **RIFLE** (0): `game_rifle_idle`, `game_rifle_walk_*`, `game_rifle_sprint`
- **PISTOL** (1): `game_pistol_idle`, `game_pistol_walk_*`, `game_pistol_sprint`

`_switch_weapon_animations()` が `equip_weapon()` 内で自動的に呼ばれる。

## 既存武器のステータス比較

| プロパティ | AK-47 | Glock-18 | 説明 |
|-----------|-------|----------|------|
| category | RIFLE (0) | PISTOL (1) | |
| damage | 18.0 | 16.0 | 一発あたりダメージ |
| fire_rate | 0.1s | 0.15s | 射撃間隔（小さい=速い） |
| accuracy_peak | 0.70 | 0.65 | 最適距離での命中精度 |
| recoil_strength | 0.15 | 0.18 | リコイル強度 |
| recoil_recovery | 8.0 | 12.0 | リコイル回復速度 |
| left_hand_grip | Enabled | Disabled | 両手持ちIK |
| auto_firing_mode | Enabled | Disabled | 距離別射撃モード |

## トラブルシューティング

| 症状 | 原因 | 修正 |
|------|------|------|
| 武器がゲームに表示されない | PRESET_FILESに未登録 | weapon_registry.gdに追加 |
| weapon_adjustmentに出ない | weapon_adjustment.gdのweapon_pathsに未登録 | パスを追加 |
| 武器の向き/位置がおかしい | attach_offset/rotationが未調整 | weapon_adjustmentシーンで調整 |
| 左手が浮いている | LeftHandGrip位置がモデルに合っていない | weapon_adjustmentのGripスライダーで調整 |
| マズルフラッシュが変な位置 | muzzle_flash_offsetが未調整 | weapon_adjustmentシーンで調整 |
| 武器が大きすぎ/小さすぎ | Blenderでスケール未調整 | Blenderで実物サイズにスケーリング |
| テクスチャ抽出エラー（Godot import） | GLBに不要なテクスチャが埋め込まれている | .importファイルで `gltf/embedded_image_handling = 0` に設定 |

## 関連ファイル

| ファイル | 責務 |
|---------|------|
| `scripts/resources/weapon_preset.gd` | WeaponPresetリソース定義（全プロパティ） |
| `scripts/registries/weapon_registry.gd` | 武器登録・検索（Autoload singleton） |
| `scripts/characters/game_character.gd` | `equip_weapon()` — 武器装着・モデルアタッチ |
| `scripts/animation/character_animation_controller.gd` | 武器カテゴリ別アニメーション切替 |
| `scripts/tests/weapon_adjustment.gd` | 武器位置調整テストツール |
| `scripts/utils/game_constants.gd` | `NODE_LEFT_HAND_GRIP` 等の定数 |
