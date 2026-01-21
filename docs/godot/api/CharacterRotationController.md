# CharacterRotationController

キャラクターの回転モードを管理するコントローラークラス。視線方向をスムーズに変更し、確定/キャンセルをサポート。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/characters/character_rotation_controller.gd` |

## Export Properties

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `rotation_easing_speed` | `float` | `15.0` | 回転イージング速度 |

## Signals

### rotation_started(original_direction: Vector3)
回転モードが開始された時に発火。

**引数:**
- `original_direction` - 開始時の視線方向

### rotation_confirmed(final_direction: Vector3)
回転が確定された時に発火。

**引数:**
- `final_direction` - 確定された視線方向

### rotation_cancelled()
回転がキャンセルされた時に発火。

## Public API

### setup(character: CharacterBody3D, camera: Camera3D) -> void
コントローラーをセットアップする。

**引数:**
- `character` - 制御対象のキャラクター
- `camera` - スクリーン座標変換用カメラ

### start_rotation() -> void
回転モードを開始する。現在の視線方向を保存し、キャンセル時に復元できるようにする。

### confirm() -> void
現在の回転を確定する。`rotation_confirmed`シグナルを発火。

### cancel() -> void
回転をキャンセルし、元の向きに戻す。`rotation_cancelled`シグナルを発火。

### is_rotation_active() -> bool
回転モードがアクティブか確認する。

**戻り値:** アクティブなら`true`

### handle_input(screen_pos: Vector2) -> void
入力処理を行う。スクリーン座標からワールド座標を計算し、その方向を向くように設定。

**引数:**
- `screen_pos` - スクリーン座標（マウス/タッチ位置）

### process(delta: float) -> void
毎フレームの処理を実行する。`_physics_process`から呼び出す。

**引数:**
- `delta` - デルタタイム

## 使用例

```gdscript
# セットアップ
var rotation_ctrl = CharacterRotationController.new()
add_child(rotation_ctrl)
rotation_ctrl.rotation_confirmed.connect(_on_rotation_confirmed)
rotation_ctrl.rotation_cancelled.connect(_on_rotation_cancelled)

# 回転モード開始
rotation_ctrl.setup(character, camera)
rotation_ctrl.start_rotation()

# 入力処理
func _unhandled_input(event):
    if rotation_ctrl.is_rotation_active() and event is InputEventMouseButton:
        rotation_ctrl.handle_input(event.position)

# 毎フレーム処理
func _physics_process(delta):
    if rotation_ctrl.is_rotation_active():
        rotation_ctrl.process(delta)

# 確定/キャンセル
func _on_confirm_button_pressed():
    rotation_ctrl.confirm()

func _on_cancel_button_pressed():
    rotation_ctrl.cancel()
```

## 内部動作

- 開始時に現在の視線方向を保存（キャンセル時の復元用）
- `handle_input`でスクリーン座標をグラウンド平面との交点に変換
- キャラクターからその交点への方向を目標方向として設定
- `process`内で`CharacterAnimationController`を通じてスムーズに回転
- 確定時は`set_look_direction`で即座に方向を設定
- キャンセル時は元の方向に戻す
