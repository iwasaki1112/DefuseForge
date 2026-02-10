# TPSPlayerController

TPS操作の再利用可能なプレイヤー制御コントローラー。ツインスティック（左: 移動、右: 向き/エイム）+ WASD + マウス操作をサポートする。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/controllers/tps_player_controller.gd` |

## 概要

GameScreenで使用するTPS操作の中核コンポーネント。左スティック/WASDで移動しつつ、右スティック/マウスで任意の方向を向ける。CombatAwarenessComponentと連携し、敵検知時は自動で敵方向を向く。

## 設定可能パラメータ

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `camera_height` | `float` | `20.0` | カメラの高さ |
| `camera_pitch_deg` | `float` | `-90.0` | カメラのピッチ角度（度） |
| `enable_aim_stick` | `bool` | `true` | 右エイムスティックを有効にするか |

これらは`setup()`のconfigパラメータで上書き可能。

## Constants

| 定数 | 値 | 説明 |
|------|-----|------|
| `CAMERA_FOV` | `30.0` | カメラのFOV |
| `CAMERA_SMOOTH` | `8.0` | カメラ追従のlerp速度 |
| `GROUND_Y` | `0.0` | 地面のY座標 |
| `STICK_RADIUS` | `80.0` | 移動スティックの半径 |
| `STICK_DEADZONE` | `0.15` | スティックのデッドゾーン |

## Public API

### setup(character: GameCharacter, cam: Camera3D, canvas: CanvasLayer, config: Dictionary = {}) -> void
コントローラーを初期化する。

**引数:**
- `character` - 操作対象のGameCharacter
- `cam` - シーンのCamera3D
- `canvas` - UIを追加するCanvasLayer
- `config` - オプション設定
  - `"camera_height"`: カメラ高さ（デフォルト20.0）
  - `"camera_pitch_deg"`: カメラピッチ（デフォルト-90.0）
  - `"enable_aim_stick"`: 右スティック有効化（デフォルトtrue）

**処理内容:**
1. カメラをTPS用に設定（FOV、ピッチ、初期位置）
2. 移動ジョイスティックUI作成（左半分）
3. エイムジョイスティックUI作成（右半分、enable_aim_stick時のみ）

### process(delta: float) -> void
毎フレーム処理。`_physics_process`から呼び出す。

**実行順序:**
1. CombatAwareness処理（敵検知）
2. エイム方向更新
3. 移動+アニメーション更新
4. カメラ追従

### handle_input(event: InputEvent) -> void
入力処理。`_input`から呼び出す。タッチ入力（モバイルジョイスティック）を処理する。

### get_character() -> GameCharacter
操作対象のキャラクターを返す。

## エイム優先順位

1. **CombatAwareness** - 敵検知時は自動で敵方向を向く
2. **右スティック** - エイム方向を直接指定（デッドゾーン超過時）
3. **マウス** - 地面レイキャストでカーソル位置方向を向く（PC）
4. **移動方向** - フォールバック: 移動方向 = 向き

## カメラ制御

固定追従カメラ方式:
- ピッチ角度とカメラ高さから自動計算されるオフセットで追従
- lerpによる滑らかな追従（`CAMERA_SMOOTH = 8.0`）
- 軌道回転なし（固定角度）

## ジョイスティック（モバイル）

**移動スティック（左半分）:**
- タッチ位置に出現、離すと消える
- デッドゾーン内の入力は無視

**エイムスティック（右半分）:**
- タッチ位置に出現、離すと消える
- スティックの2D入力をワールド3D方向に変換

## 使用例

```gdscript
# GameScreenでの基本的な使用
var tps_controller: TPSPlayerController

func _ready():
    tps_controller = TPSPlayerController.new()
    tps_controller.name = "TPSPlayerController"
    add_child(tps_controller)
    tps_controller.setup(player_character, camera, ui_layer)

func _physics_process(delta):
    tps_controller.process(delta)

func _input(event):
    tps_controller.handle_input(event)

# カスタム設定での使用
tps_controller.setup(character, camera, ui_layer, {
    "camera_height": 10.0,
    "camera_pitch_deg": -50.0,
    "enable_aim_stick": false,
})
```

## 関連クラス
- [GameScreen](../Screen/GameScreen.md) - 主な使用場所
- [GameCharacter](../Character/GameCharacter.md) - 操作対象
- [CombatAwarenessComponent](../Character/CombatAwarenessComponent.md) - 自動エイム連携
- [CharacterAnimationController](../Animation/CharacterAnimationController.md) - アニメーション更新
