class_name AnimatedButton
extends TextureButton

## 押下時にアニメーションするボタンの基底クラス
## TextureButtonを継承し、押下時に拡大→縮小アニメーションを自動的に再生する

## アニメーション設定
@export var press_scale: float = 1.15  ## 押下時の拡大率
@export var press_duration: float = 0.08  ## 拡大アニメーションの時間
@export var release_duration: float = 0.1  ## 縮小アニメーションの時間
@export var press_alpha: float = 0.7  ## 押下時の透明度
@export var animate_on_press: bool = true  ## 押下時にアニメーションするか

## 現在のTween
var _current_tween: Tween = null


func _ready() -> void:
	# ピボットを中央に設定
	pivot_offset = size / 2

	# サイズ変更時にピボットを更新
	resized.connect(_on_resized)

	# 押下シグナルに接続
	if animate_on_press:
		pressed.connect(_on_button_pressed)


func _on_resized() -> void:
	pivot_offset = size / 2


## ボタン押下時のコールバック
func _on_button_pressed() -> void:
	play_press_animation()


## 押下アニメーションを再生
func play_press_animation() -> void:
	# 既存のTweenをキャンセル
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()

	_current_tween = create_tween()
	_current_tween.set_parallel(true)

	# 拡大アニメーション
	_current_tween.tween_property(self, "scale", Vector2(press_scale, press_scale), press_duration).set_ease(Tween.EASE_OUT)

	# 透明度アニメーション
	modulate.a = press_alpha
	_current_tween.tween_property(self, "modulate:a", 1.0, press_duration).set_ease(Tween.EASE_OUT)

	# 縮小アニメーション（元に戻る）
	_current_tween.chain().tween_property(self, "scale", Vector2.ONE, release_duration).set_ease(Tween.EASE_IN_OUT)


## 外部からアニメーションを再生（自動アニメーションが無効の場合に使用）
func trigger_animation() -> void:
	play_press_animation()
