class_name InputDeviceHandler
extends RefCounted
## 入力デバイスハンドラ基底クラス
##
## 責務:
## - デバイス固有の入力イベントを抽象化されたシグナルに変換
## - タップ/クリック、ドラッグ、ズーム等の共通インターフェースを提供
##
## 子クラス: MouseInputHandler, TouchInputHandler


#region シグナル

## プレス検出時（位置）
signal press_detected(position: Vector2)

## リリース検出時（位置、ドラッグ中だったか）
signal release_detected(position: Vector2, was_dragging: bool)

## ドラッグ検出時（位置、開始位置からの距離）
signal drag_detected(position: Vector2, distance_from_start: float)

## タップ検出時（位置）
signal tap_detected(position: Vector2)

## ズーム要求時（ズーム量: 正=ズームイン, 負=ズームアウト）
@warning_ignore("unused_signal")
signal zoom_requested(amount: float)

## ピンチ状態変更時（ピンチ中かどうか）
@warning_ignore("unused_signal")
signal pinch_state_changed(is_pinching: bool)

#endregion


#region 設定

## タップ判定の最大移動距離（ピクセル）
var tap_threshold: float = 40.0

## ドラッグ判定の最小移動距離（ピクセル）
var drag_threshold: float = 5.0

#endregion


#region 内部状態

## 入力押下中かどうか
var _is_pressed: bool = false

## 押下開始位置（スクリーン座標）
var _press_start_pos: Vector2 = Vector2.ZERO

## ドラッグ中かどうか
var _is_dragging: bool = false

## ドラッグ待機中かどうか（閾値チェック前）
var _is_pending_drag: bool = false

#endregion


#region 公開メソッド

## 入力イベントを処理
## @param _event: 入力イベント
## @return: イベントを消費した場合true
func handle_input(_event: InputEvent) -> bool:
	return false  # 子クラスでオーバーライド


## 押下中かどうかを取得
func is_pressed() -> bool:
	return _is_pressed


## ドラッグ中かどうかを取得
func is_dragging() -> bool:
	return _is_dragging


## ドラッグ待機中かどうかを取得
func is_pending_drag() -> bool:
	return _is_pending_drag


## 押下開始位置を取得
func get_press_start_position() -> Vector2:
	return _press_start_pos


## ピンチ中かどうかを取得（子クラスでオーバーライド）
func is_pinching() -> bool:
	return false


## タッチポイント数を取得（子クラスでオーバーライド）
func get_touch_count() -> int:
	return 0


## 状態をリセット
func reset_state() -> void:
	_is_pressed = false
	_is_dragging = false
	_is_pending_drag = false
	_press_start_pos = Vector2.ZERO

#endregion


#region ヘルパーメソッド

## タップかどうかを判定（ドラッグ距離に基づく）
func _is_tap(current_pos: Vector2) -> bool:
	return current_pos.distance_to(_press_start_pos) < tap_threshold


## ドラッグ閾値を超えたかどうかを判定
func _exceeded_drag_threshold(current_pos: Vector2) -> bool:
	return current_pos.distance_to(_press_start_pos) >= drag_threshold


## プレス処理の共通部分
func _on_press(position: Vector2) -> void:
	_is_pressed = true
	_press_start_pos = position
	_is_pending_drag = true
	press_detected.emit(position)


## リリース処理の共通部分
func _on_release(position: Vector2) -> void:
	var was_dragging := _is_dragging

	# タップ判定
	if not was_dragging and _is_tap(position):
		tap_detected.emit(position)

	release_detected.emit(position, was_dragging)

	# 状態をリセット
	_is_pressed = false
	_is_dragging = false
	_is_pending_drag = false


## ドラッグ処理の共通部分
func _on_drag(position: Vector2) -> void:
	var distance := position.distance_to(_press_start_pos)

	# ドラッグ待機中なら閾値チェック
	if _is_pending_drag and _exceeded_drag_threshold(position):
		_is_dragging = true
		_is_pending_drag = false

	drag_detected.emit(position, distance)

#endregion
