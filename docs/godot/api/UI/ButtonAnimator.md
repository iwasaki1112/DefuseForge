# ButtonAnimator

既存のボタンに押下アニメーションを追加するヘルパークラス。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `RefCounted` |
| クラス名 | `ButtonAnimator` |
| ファイルパス | `scripts/ui/button_animator.gd` |

## 概要

シーンファイルを変更せずに、コードからボタンにアニメーションを追加できるstaticヘルパー。`setup()`で自動アニメーション、`play()`で手動アニメーション再生が可能。

## 定数

| 定数 | 値 | 説明 |
|------|-----|------|
| `DEFAULT_PRESS_SCALE` | `1.15` | デフォルトの押下時拡大率 |
| `DEFAULT_PRESS_DURATION` | `0.08` | デフォルトの拡大アニメーション時間 |
| `DEFAULT_RELEASE_DURATION` | `0.1` | デフォルトの縮小アニメーション時間 |
| `DEFAULT_PRESS_ALPHA` | `0.7` | デフォルトの押下時透明度 |

## Static メソッド

### setup(button: Control, press_scale: float, auto_connect: bool) -> void
ボタンに自動アニメーションを設定する。ピボットを中央に設定し、`pressed`シグナルに自動接続する。

### play(button: Control, press_scale: float, press_duration: float, release_duration: float, press_alpha: float) -> void
アニメーションを手動で再生する。既存のTweenはキャンセルされる。

### setup_all(buttons: Array) -> void
複数のボタンに一括で自動アニメーションを設定する。

## 使用例

```gdscript
# 単一ボタンに自動アニメーションを設定
ButtonAnimator.setup(my_button)

# カスタム拡大率で設定
ButtonAnimator.setup(my_button, 1.2)

# 手動でアニメーション再生
ButtonAnimator.play(my_button)

# 複数ボタンに一括設定
ButtonAnimator.setup_all([btn1, btn2, btn3])
```

## 関連クラス

- [AnimatedButton](AnimatedButton.md) - TextureButton版（継承方式）
- [AnimatedTextButton](AnimatedTextButton.md) - Button版（継承方式）

## APIリファレンス

### Static メソッド
- `setup(button: Control, press_scale: float = 1.15, auto_connect: bool = true) -> void`
- `play(button: Control, press_scale: float = 1.15, press_duration: float = 0.08, release_duration: float = 0.1, press_alpha: float = 0.7) -> void`
- `setup_all(buttons: Array) -> void`
