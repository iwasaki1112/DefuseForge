# EnvironmentPreset

マップ環境設定のプリセット定義リソース。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Resource` |
| ファイルパス | `scripts/resources/environment_preset.gd` |

## エクスポートプロパティ

### Basic Info

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|---------|------|
| `id` | `String` | `""` | 一意の識別子 |
| `display_name` | `String` | `""` | UI表示名 |

### Directional Light

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|---------|------|
| `light_energy` | `float` | `0.3` | 光の強さ |
| `light_color` | `Color` | `(1.0, 0.98, 0.95, 1.0)` | 光の色 |
| `light_pitch` | `float` | `-77.0` | 光の傾き（度） |
| `light_yaw` | `float` | `-33.0` | 光の回転（度） |

### Shadow

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|---------|------|
| `shadow_enabled` | `bool` | `true` | 影を有効化 |
| `shadow_blur` | `float` | `0.7` | 影のぼかし |
| `shadow_bias` | `float` | `0.1` | 影のバイアス |
| `shadow_distance` | `float` | `30.0` | 影の最大距離 |
| `shadow_size` | `int` | `2` | 影の解像度（0=512, 1=1024, 2=2048, 3=4096） |

### Ambient Light

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|---------|------|
| `ambient_energy` | `float` | `0.1` | アンビエント光の強さ |
| `ambient_color` | `Color` | `(0.6, 0.65, 0.7, 1.0)` | アンビエント光の色 |
| `background_color` | `Color` | `(0.3, 0.35, 0.4, 1.0)` | 背景色 |

### Rendering Quality

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|---------|------|
| `resolution_scale` | `float` | `0.75` | 内部解像度スケール（0.5-1.0） |
| `use_fsr` | `bool` | `true` | FSRアップスケーリング |

### Post-processing

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|---------|------|
| `ssao_enabled` | `bool` | `false` | SSAO |
| `ssil_enabled` | `bool` | `false` | SSIL |
| `sdfgi_enabled` | `bool` | `false` | SDFGI |
| `glow_enabled` | `bool` | `false` | Glow |
| `fog_enabled` | `bool` | `false` | Fog |

## Public API

### get_shadow_size_value() -> int
影の解像度を数値で取得。

## 使用例

### プリセットファイルの作成

```
[gd_resource type="Resource" script_class="EnvironmentPreset" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/environment_preset.gd" id="1_preset"]

[resource]
script = ExtResource("1_preset")
id = "default"
display_name = "Default"
light_energy = 0.3
light_color = Color(1, 0.98, 0.95, 1)
light_pitch = -77.0
light_yaw = -33.0
shadow_enabled = true
shadow_blur = 0.7
shadow_bias = 0.1
shadow_distance = 30.0
shadow_size = 2
ambient_energy = 0.1
ambient_color = Color(0.6, 0.65, 0.7, 1)
background_color = Color(0.3, 0.35, 0.4, 1)
resolution_scale = 0.75
use_fsr = true
ssao_enabled = false
ssil_enabled = false
sdfgi_enabled = false
glow_enabled = false
fog_enabled = false
```

### GDScriptでの使用

```gdscript
# プリセットをロード
var preset := load("res://data/environment/default.tres") as EnvironmentPreset

# 設定を取得
print(preset.light_energy)
print(preset.get_shadow_size_value())  # 2048
```

## プリセットの保存場所

`data/environment/` ディレクトリに `.tres` 形式で保存。

- `data/environment/default.tres` - デフォルトプリセット

## モバイル最適化

デフォルトプリセットはモバイル向けに最適化されている:

- 解像度スケール: 0.75（75%レンダリング）
- FSRアップスケーリング: 有効
- 重いポストプロセス（SSAO, SSIL, SDFGI, Glow, Fog）: 無効

## 関連クラス

- `EnvironmentSetup` - プリセットを適用するコンポーネント

## APIリファレンス

### シグナル
なし

### メソッド
- `get_shadow_size_value() -> int`
