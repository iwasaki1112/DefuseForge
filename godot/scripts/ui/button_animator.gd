class_name ButtonAnimator
extends RefCounted

## 既存のボタンに押下アニメーションを追加するヘルパークラス
## シーンファイルを変更せずに、コードからボタンにアニメーションを追加できる
##
## 使用例:
##   ButtonAnimator.setup(my_button)  # 自動アニメーション
##   ButtonAnimator.play(my_button)   # 手動でアニメーション再生

## デフォルトのアニメーション設定
const DEFAULT_PRESS_SCALE: float = 1.15
const DEFAULT_PRESS_DURATION: float = 0.08
const DEFAULT_RELEASE_DURATION: float = 0.1
const DEFAULT_PRESS_ALPHA: float = 0.7

## 設定済みボタンのTweenを保持
static var _active_tweens: Dictionary[int, Tween] = {}


## ボタンに自動アニメーションを設定
## @param button: アニメーションを追加するボタン
## @param press_scale: 押下時の拡大率
## @param auto_connect: pressedシグナルに自動接続するか
static func setup(
	button: Control,
	press_scale: float = DEFAULT_PRESS_SCALE,
	auto_connect: bool = true
) -> void:
	if not button:
		return

	# ピボットを中央に設定
	button.pivot_offset = button.size / 2

	# サイズ変更時にピボットを更新
	if not button.resized.is_connected(_on_button_resized.bind(button)):
		button.resized.connect(_on_button_resized.bind(button))

	# 押下シグナルに接続
	if auto_connect:
		var callback := func(): play(button, press_scale)
		if button is BaseButton:
			var base_button := button as BaseButton
			if not base_button.pressed.is_connected(callback):
				base_button.pressed.connect(callback)


## ボタンのリサイズ時コールバック
static func _on_button_resized(button: Control) -> void:
	if button:
		button.pivot_offset = button.size / 2


## アニメーションを再生
## @param button: アニメーションを再生するボタン
## @param press_scale: 押下時の拡大率
## @param press_duration: 拡大アニメーションの時間
## @param release_duration: 縮小アニメーションの時間
## @param press_alpha: 押下時の透明度
static func play(
	button: Control,
	press_scale: float = DEFAULT_PRESS_SCALE,
	press_duration: float = DEFAULT_PRESS_DURATION,
	release_duration: float = DEFAULT_RELEASE_DURATION,
	press_alpha: float = DEFAULT_PRESS_ALPHA
) -> void:
	if not button:
		return

	# ピボットを中央に設定
	button.pivot_offset = button.size / 2

	# 既存のTweenをキャンセル
	var button_id := button.get_instance_id()
	if _active_tweens.has(button_id):
		var old_tween: Tween = _active_tweens[button_id]
		if old_tween and old_tween.is_valid():
			old_tween.kill()

	var tween := button.create_tween()
	_active_tweens[button_id] = tween
	tween.set_parallel(true)

	# 拡大アニメーション
	tween.tween_property(button, "scale", Vector2(press_scale, press_scale), press_duration).set_ease(Tween.EASE_OUT)

	# 透明度アニメーション
	button.modulate.a = press_alpha
	tween.tween_property(button, "modulate:a", 1.0, press_duration).set_ease(Tween.EASE_OUT)

	# 縮小アニメーション（元に戻る）
	tween.chain().tween_property(button, "scale", Vector2.ONE, release_duration).set_ease(Tween.EASE_IN_OUT)

	# 完了後にTweenを削除
	tween.finished.connect(func(): _active_tweens.erase(button_id))


## 複数のボタンに一括で自動アニメーションを設定
## @param buttons: アニメーションを追加するボタンの配列
static func setup_all(buttons: Array) -> void:
	for button in buttons:
		if button is Control:
			setup(button)
