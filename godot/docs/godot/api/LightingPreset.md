# LightingPreset

ライティング設定を保持するリソース。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Resource` |
| ファイルパス | `scripts/resources/lighting_preset.gd` |
| プリセット配置 | `data/lighting/` |

## プロパティ

### Basic Info

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `id` | `String` | `""` | 一意の識別子 |
| `display_name` | `String` | `""` | UI表示名 |

### Directional Light

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `light_energy` | `float` | `0.3` | 光の強さ |
| `light_color` | `Color` | `(1, 0.98, 0.95)` | 光の色 |
| `shadow_enabled` | `bool` | `true` | 影を有効化 |
| `shadow_blur` | `float` | `0.7` | 影のぼかし |
| `light_pitch` | `float` | `-77.0` | 光の傾き（度） |
| `light_yaw` | `float` | `-33.0` | 光の回転（度） |

### Environment

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `ambient_energy` | `float` | `0.1` | アンビエント光の強さ |
| `ambient_color` | `Color` | `(0.6, 0.65, 0.7)` | アンビエント光の色 |
| `background_color` | `Color` | `(0.3, 0.35, 0.4)` | 背景色 |

### Mobile Optimization

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `shadow_distance` | `float` | `30.0` | 影の最大距離 |
| `shadow_size` | `int` | `2048` | 影の解像度 |

## 使用例

```gdscript
# プリセットをロード
var preset = load("res://data/lighting/default.tres") as LightingPreset

# LightingSetupに適用
lighting_setup.preset = preset
```

## プリセットファイル配置

```
data/lighting/
├── default.tres
├── indoor.tres
└── outdoor.tres
```
