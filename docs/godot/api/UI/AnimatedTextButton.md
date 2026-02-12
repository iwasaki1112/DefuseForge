# AnimatedTextButton

押下時にアニメーションするButtonの基底クラス。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Button` |
| クラス名 | `AnimatedTextButton` |
| ファイルパス | `scripts/ui/animated_text_button.gd` |

## 概要

Buttonを継承し、押下時に拡大→縮小アニメーションを自動的に再生する。AnimatedButtonと同じアニメーション仕様だが、テキスト付きButton用。

## Export Properties

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `press_scale` | `float` | `1.15` | 押下時の拡大率 |
| `press_duration` | `float` | `0.08` | 拡大アニメーションの時間 |
| `release_duration` | `float` | `0.1` | 縮小アニメーションの時間 |
| `press_alpha` | `float` | `0.7` | 押下時の透明度 |
| `animate_on_press` | `bool` | `true` | 押下時にアニメーションするか |

## メソッド

### play_press_animation() -> void
押下アニメーションを再生する。既存のTweenはキャンセルされる。

### trigger_animation() -> void
外部からアニメーションを再生する（`animate_on_press`が無効の場合に使用）。

## 関連クラス

- [AnimatedButton](AnimatedButton.md) - TextureButton版
- [ButtonAnimator](ButtonAnimator.md) - 既存ボタンへのアニメーション追加ヘルパー

## APIリファレンス

### メソッド
- `play_press_animation() -> void`
- `trigger_animation() -> void`
