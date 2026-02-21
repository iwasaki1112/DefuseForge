# EnvironmentSetup

マップ環境をセットアップするコンポーネント。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node3D` |
| ファイルパス | `scripts/systems/environment_setup.gd` |

## エクスポートプロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `preset` | `EnvironmentPreset` | 環境プリセット |

## Public API

### get_directional_light() -> DirectionalLight3D
メインDirectionalLight3Dノードを取得。

### get_outdoor_light() -> DirectionalLight3D
屋外DirectionalLight3Dノードを取得。斜め光で屋外エリアに影を生成する。

### get_environment() -> Environment
Environmentリソースを取得。

### get_world_environment() -> WorldEnvironment
WorldEnvironmentノードを取得。

### set_preset(new_preset: EnvironmentPreset) -> void
プリセットを動的に変更。

## 使用例

### マップへの追加

```gdscript
# シーンに追加
var env_setup = EnvironmentSetup.new()
env_setup.preset = load("res://data/environment/default.tres")
add_child(env_setup)
```

### シーンファイルでの使用

```
[node name="EnvironmentSetup" type="Node3D"]
script = ExtResource("environment_setup_script")
preset = ExtResource("default_environment_preset")
```

### 動的なパラメータ調整

```gdscript
# DirectionalLightを直接調整
var light = env_setup.get_directional_light()
light.light_energy = 0.5

# Environmentを直接調整
var env = env_setup.get_environment()
env.ambient_light_energy = 0.2
```

## 自動生成されるノード

EnvironmentSetupは以下の子ノードを自動生成:

- `DirectionalLight` - メインライト（真上からの均一照明）
- `OutdoorLight` - 屋外ライト（斜め光、影あり。建物上のルーフオクルーダーで屋内遮蔽）
- `WorldEnvironment` - 環境設定

## 適用される設定

### Lighting
- DirectionalLight3D（メイン）の位置・エネルギー・色・角度
- OutdoorLight（屋外）の有効化・エネルギー・色・角度

### Shadow
- 影の有効化・ぼかし・バイアス・距離
- 影の解像度（RenderingServer経由で適用）

### Ambient
- アンビエント光のエネルギー・色
- 背景色

### Rendering Quality
- 内部解像度スケール（Viewport.scaling_3d_scale）
- FSRアップスケーリング（Viewport.scaling_3d_mode）

### Post-processing
- SSAO、SSIL、SDFGI、Glow、Fog

## 重要な注意事項

**マップシーンに環境設定を含めないこと**

EnvironmentSetupはGameScreenで自動的に追加される。
マップシーン（.tscn）に以下を含めると二重適用になり、意図しない見た目になる：
- DirectionalLight3D
- WorldEnvironment

マップシーンはジオメトリ（床、壁）とスポーンポイントのみを含める。

**屋外ライトの遮蔽（ルーフオクルーダー）**

建物内に屋外ライトの光が届かないようにするには、`GridMapRoof` レイヤーでルーフタイルを配置する：
- `tile_library_roof.tres` のタイルを建物の屋内セルに配置（エディタで半透明の青タイルとして表示）
- ランタイムでMapBaseが自動的にSHADOWS_ONLYメッシュに変換（GridMapは非表示）
- これにより屋外ライトの影だけが屋内に落ち、屋内は均一照明のまま保たれる

**カメラの投影方式**

gl_compatibilityレンダラーでは、直交投影（Orthogonal）カメラで影が表示されない。
透視投影（Perspective）カメラを使用すること。

## 関連クラス

- `EnvironmentPreset` - 環境設定のプリセット定義
- `GameScreen` - EnvironmentSetupを使用してマップ環境を設定

## APIリファレンス

### シグナル
なし

### メソッド
- `set_preset(new_preset: EnvironmentPreset) -> void`
- `get_directional_light() -> DirectionalLight3D`
- `get_outdoor_light() -> DirectionalLight3D`
- `get_environment() -> Environment`
- `get_world_environment() -> WorldEnvironment`
