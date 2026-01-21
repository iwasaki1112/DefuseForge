# LightingSetup

マップにライティングを適用するコンポーネント。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node3D` |
| ファイルパス | `scripts/systems/lighting_setup.gd` |

## エクスポートプロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `preset` | `LightingPreset` | ライティングプリセット |

## Public API

### get_directional_light() -> DirectionalLight3D
DirectionalLight3Dノードを取得。

### get_environment() -> Environment
Environmentリソースを取得。

### get_world_environment() -> WorldEnvironment
WorldEnvironmentノードを取得。

### set_preset(new_preset: LightingPreset) -> void
プリセットを動的に変更。

## 使用例

### マップへの追加

```gdscript
# シーンに追加
var lighting = LightingSetup.new()
lighting.preset = load("res://data/lighting/default.tres")
add_child(lighting)
```

### シーンファイルでの使用

```
[node name="LightingSetup" type="Node3D"]
script = ExtResource("lighting_setup_script")
preset = ExtResource("default_lighting_preset")
```

### 動的なパラメータ調整

```gdscript
# DirectionalLightを直接調整
var light = lighting_setup.get_directional_light()
light.light_energy = 0.5

# Environmentを直接調整
var env = lighting_setup.get_environment()
env.ambient_light_energy = 0.2
```

## 自動生成されるノード

LightingSetupは以下の子ノードを自動生成:

- `DirectionalLight` - メインライト
- `WorldEnvironment` - 環境設定

## モバイル最適化

以下のエフェクトは自動的に無効化:
- SSAO
- SSIL
- SDFGI
- Glow
- Fog
