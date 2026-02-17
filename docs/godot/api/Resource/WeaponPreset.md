# WeaponPreset

武器プリセット定義リソース。武器ステータスを格納。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Resource` |
| ファイルパス | `scripts/resources/weapon_preset.gd` |

## Enum

### WeaponCategory
| 値 | 説明 |
|----|------|
| `RIFLE` (0) | アサルトライフル |
| `PISTOL` (1) | ピストル |
| `SMG` (2) | サブマシンガン |
| `SHOTGUN` (3) | ショットガン |
| `SNIPER` (4) | スナイパーライフル |

### FiringMode
| 値 | 説明 |
|----|------|
| `SINGLE` (0) | 単発射撃 |
| `BURST` (1) | バースト射撃（指定数発を連続発射） |
| `FULL_AUTO` (2) | フルオート射撃（連続発射） |

## Export Properties

### Basic Info
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `id` | `String` | `""` | 一意識別子（例: "m4a1", "glock"） |
| `display_name` | `String` | `""` | UI表示名 |
| `category` | `WeaponCategory` | `RIFLE` | 武器カテゴリー |

### Combat Stats
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `damage` | `float` | `30.0` | 1発あたりのダメージ |
| `fire_rate` | `float` | `0.1` | 発射間隔（秒） |

### Accuracy Curve（精度カーブ）

距離に応じた精度を定義する。最適距離帯（スイートスポット）を中心に、至近距離と遠距離で精度が変化する。

```
精度
  peak |         ___________
       |        /           \
       |       /             \
  far  |______/               \__________
       0   range_min  range_max  max_distance   距離(m)
            最適距離帯
```

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `accuracy_peak` | `float` | `0.85` | 最適距離での命中精度 |
| `accuracy_close` | `float` | `0.75` | 至近距離(0m)での命中精度 |
| `accuracy_far` | `float` | `0.15` | 最大距離以降の命中精度 |
| `accuracy_range_min` | `float` | `0.0` | 最適距離帯の開始(m) |
| `accuracy_range_max` | `float` | `15.0` | 最適距離帯の終了(m) |
| `accuracy_max_distance` | `float` | `40.0` | 精度最低到達距離(m) |

#### 距離別の精度計算

| 距離帯 | 計算 |
|--------|------|
| 0 〜 range_min | `lerp(accuracy_close, accuracy_peak, distance/range_min)` |
| range_min 〜 range_max | `accuracy_peak` 固定 |
| range_max 〜 max_distance | `lerp(accuracy_peak, accuracy_far, 正規化距離)` |
| max_distance以降 | `accuracy_far` 固定 |

### Movement Penalties（移動ペナルティ）

射手とターゲットの移動状態による精度への乗数。

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `shooter_walk_penalty` | `float` | `0.8` | 歩行時の精度乗数 |
| `shooter_sprint_penalty` | `float` | `0.4` | スプリント時の精度乗数 |
| `target_move_penalty` | `float` | `0.15` | ターゲット移動ペナルティ係数 |
| `target_speed_reference` | `float` | `6.0` | ターゲット速度基準値(m/s) |

#### 射手移動ペナルティの計算

| 速度 | 精度乗数 |
|------|----------|
| 0〜0.5 m/s | 1.0（静止） |
| 0.5〜4.0 m/s | `lerp(1.0, shooter_walk_penalty, 正規化)` |
| 4.0 m/s以上 | `shooter_sprint_penalty` |

#### ターゲット移動ペナルティの計算

```
multiplier = 1.0 - clamp(target_speed / target_speed_reference, 0, 1) * target_move_penalty
```

### Damage Falloff（ダメージ距離減衰）

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `damage_falloff_enabled` | `bool` | `false` | ダメージ距離減衰の有効化 |
| `damage_falloff_start` | `float` | `20.0` | 減衰開始距離(m) |
| `damage_falloff_min` | `float` | `0.5` | 最低ダメージ倍率 |
| `damage_falloff_end` | `float` | `50.0` | 最低ダメージ到達距離(m) |

### 武器カテゴリ別推奨値

| パラメータ | SMG | Rifle(AK) | Sniper | Pistol |
|-----------|-----|-----------|--------|--------|
| accuracy_peak | 0.80 | 0.85 | 0.95 | 0.80 |
| accuracy_close | 0.80 | 0.70 | 0.40 | 0.85 |
| accuracy_far | 0.05 | 0.10 | 0.30 | 0.08 |
| range_min(m) | 0 | 3 | 15 | 0 |
| range_max(m) | 8 | 20 | 40 | 10 |
| max_distance(m) | 25 | 45 | 60 | 25 |
| walk_penalty | 0.90 | 0.75 | 0.50 | 0.85 |
| sprint_penalty | 0.55 | 0.35 | 0.15 | 0.50 |
| target_move_penalty | 0.12 | 0.15 | 0.08 | 0.20 |

### Vision
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `vision_range` | `float` | `7.0` | 武器装備時の視界距離（メートル）。`equip_weapon()`で自動的にVisionComponentに適用される |

#### 武器カテゴリ別推奨視界距離

| カテゴリ | 推奨値 | 説明 |
|---------|--------|------|
| RIFLE | 7.0m | 標準視界 |
| PISTOL | 5.0m | 近距離戦向け |
| SMG | 6.0m | 中近距離戦向け |
| SHOTGUN | 5.0m | 近距離戦向け |
| SNIPER | 12.0m | 長距離索敵向け |

### Recoil
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `recoil_strength` | `float` | `0.08` | リコイルアニメーション強度 |
| `recoil_recovery` | `float` | `10.0` | リコイル回復速度 |

### Visual
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `model_scene` | `PackedScene` | - | 武器モデル（オプション） |
| `icon` | `Texture2D` | - | UI用武器アイコン |

### Attachment
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `attach_offset` | `Vector3` | `Vector3.ZERO` | 右手アタッチ時の位置オフセット（WeaponSocketに適用） |
| `attach_rotation` | `Vector3` | `Vector3.ZERO` | 右手アタッチ時の回転オフセット（度、WeaponSocketに適用） |

### Muzzle Flash
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `muzzle_flash_offset` | `Vector3` | `Vector3.ZERO` | マズルフラッシュ位置オフセット（WeaponSocket基準） |
| `muzzle_flash_scale` | `float` | `1.0` | マズルフラッシュのスケール倍率 |
| `muzzle_flash_rotation` | `Vector3` | `Vector3.ZERO` | マズルフラッシュの回転（度） |

### Auto Firing Mode（RIFLE/SMG専用）

距離に応じて射撃モードを自動切り替えするシステム。CQB（近距離）、Medium（中距離）、Long（長距離）の3レンジで異なる射撃パターンを使用。

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `auto_firing_mode_enabled` | `bool` | `false` | 距離ベース射撃モード切替の有効化 |

#### CQB Range（近距離）
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `cqb_max_distance` | `float` | `5.0` | CQBレンジの最大距離（メートル） |
| `cqb_firing_mode` | `FiringMode` | `FULL_AUTO` | CQBレンジの射撃モード |
| `cqb_shots_per_burst` | `int` | `0` | バースト発数（0=連続、FULL_AUTO用） |
| `cqb_burst_interval` | `float` | `0.08` | バースト内の発射間隔（秒） |
| `cqb_pause_after_burst` | `float` | `0.0` | バースト後の待機時間（秒） |
| `cqb_accuracy_modifier` | `float` | `0.85` | 精度倍率（1.0=標準） |
| `cqb_critical_rate` | `float` | `0.1` | クリティカルヒット確率（0.0-1.0） |

#### Medium Range（中距離）
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `medium_max_distance` | `float` | `15.0` | Mediumレンジの最大距離（メートル） |
| `medium_firing_mode` | `FiringMode` | `BURST` | Mediumレンジの射撃モード |
| `medium_shots_per_burst` | `int` | `3` | バースト発数 |
| `medium_burst_interval` | `float` | `0.10` | バースト内の発射間隔（秒） |
| `medium_pause_after_burst` | `float` | `0.40` | バースト後の待機時間（秒） |
| `medium_accuracy_modifier` | `float` | `1.0` | 精度倍率 |
| `medium_critical_rate` | `float` | `0.25` | クリティカルヒット確率 |

#### Long Range（長距離）
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `long_firing_mode` | `FiringMode` | `SINGLE` | Longレンジの射撃モード |
| `long_shots_per_burst` | `int` | `1` | バースト発数（SINGLEの場合1） |
| `long_burst_interval` | `float` | `0.0` | バースト内の発射間隔（SINGLE時未使用） |
| `long_pause_after_burst` | `float` | `0.60` | 射撃後の待機時間（秒） |
| `long_accuracy_modifier` | `float` | `1.15` | 精度倍率 |
| `long_critical_rate` | `float` | `0.5` | クリティカルヒット確率 |

#### 距離別推奨設定

| 距離 | モード | 動作 | 精度倍率 | クリ率 |
|------|--------|------|----------|--------|
| 0-5m (CQB) | フルオート | 高速連射、制圧用 | 0.85x | 10% |
| 5-15m (Medium) | バースト(3発) | 精度重視連射 | 1.0x | 25% |
| 15m+ (Long) | 単発 | 高精度シングル | 1.15x | 50% |

## 使用例

### GDScriptでの作成
```gdscript
var weapon = WeaponPreset.new()
weapon.id = "m4a1"
weapon.display_name = "M4A1"
weapon.category = WeaponPreset.WeaponCategory.RIFLE
weapon.damage = 33.0
weapon.fire_rate = 0.09
weapon.accuracy_peak = 0.85
weapon.accuracy_range_max = 20.0
weapon.recoil_strength = 0.08
```

### .tresファイル（エディタで作成）
`res://data/weapons/m4a1.tres`:
```
[gd_resource type="Resource" script_class="WeaponPreset" ...]

[resource]
id = "m4a1"
display_name = "M4A1"
category = 0
damage = 33.0
fire_rate = 0.09
accuracy_peak = 0.85
accuracy_close = 0.70
accuracy_far = 0.10
accuracy_range_min = 3.0
accuracy_range_max = 20.0
accuracy_max_distance = 45.0
shooter_walk_penalty = 0.75
shooter_sprint_penalty = 0.35
target_move_penalty = 0.15
recoil_strength = 0.08
```

## WeaponRegistryとの連携

1. `data/weapons/`に`.tres`ファイルを配置
2. `WeaponRegistry`が自動的に読み込み
3. `WeaponRegistry.get_preset("m4a1")`で使用

## GameCharacterとの連携

```gdscript
var weapon = WeaponRegistry.get_preset("m4a1")
character.equip_weapon(weapon)
```

## 武器モデルの装着に関する重要な注意点

### ARPキャラクターのスケルトンスケール

ARPリグのキャラクターモデルは、**スケルトンのスケールが1.0（等倍）**となっている。

これにより、`BoneAttachment3D`に配置したオブジェクトはそのままのスケールで描画される。旧Mixamoリグで必要だったスケール補正（*100）は不要。

#### 確認方法

```gdscript
# BoneAttachment3Dのglobal_transformを確認
print("Attachment global_transform: ", attachment.global_transform)
# 正常: X, Y, Zベクトルの長さが約1.0
```

### 武器モデルの調整

ARPリグではスケルトンスケールが等倍のため、武器モデルのスケール補正は不要：

| 項目 | 値 | 説明 |
|------|-----|------|
| `scale` | `Vector3.ONE` | スケール補正不要（ARPスケルトンが1.0のため） |
| `rotation_degrees` | 武器固有 | GLBモデルの向きにより調整 |
| `position` | 武器固有 | GLBモデルの原点位置により調整 |

※ 武器モデルが現実的なサイズ（メートル単位）であれば、スケールは全武器でVector3.ONEに統一可能

### 武器GLBモデルの推奨設定

Blenderでエクスポートする際：
- **原点**: グリップ位置に設定
- **銃口方向**: -Y方向を向くように配置
- **スケール**: **実寸（メートル単位）**で作成（例: AK47 = 0.87m, Glock = 0.2m）

## APIリファレンス

### シグナル
なし

### メソッド
なし
