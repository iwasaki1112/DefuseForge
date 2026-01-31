class_name WaitPointHandler
extends PointHandlerBase

## Waitポイントハンドラ
## パス上の待機ポイント（長押しで待機時間を設定）を管理するポイントの入力・管理を担当


## 最小待機時間（秒）
const WAIT_MIN_DURATION: float = 0.0
## 最大待機時間（秒）
const WAIT_MAX_DURATION: float = 10.0
## 最小押下時間（秒）- これ未満はタップとみなしキャンセル
const MIN_PRESS_DURATION: float = 0.15

## 長押し開始時刻
var _press_start_time: float = 0.0

## プレビューポイント
var _preview_point: MeshInstance3D = null


## 押下処理
func _handle_press(screen_pos: Vector2) -> bool:
	# 既に操作中の場合は無視（重複イベント対策）
	if _is_active:
		return true

	var click_result = _check_path_click(screen_pos)
	if not click_result.success:
		return false

	_current_anchor = click_result.anchor
	_current_ratio = click_result.ratio
	_press_start_time = Time.get_ticks_msec() / 1000.0
	_is_active = true

	_create_preview_point()
	return true


## 解放処理
func _handle_release(_screen_pos: Vector2) -> bool:
	if not _is_active:
		return false

	var current_time = Time.get_ticks_msec() / 1000.0
	var duration = current_time - _press_start_time
	_is_active = false

	# 最小押下時間未満はタップとみなしキャンセル
	if duration < MIN_PRESS_DURATION:
		_remove_preview_point()
		return true

	# 最小待機時間未満はキャンセル
	if duration < WAIT_MIN_DURATION:
		_remove_preview_point()
		return true

	# 最大時間で制限
	duration = clampf(duration, WAIT_MIN_DURATION, WAIT_MAX_DURATION)

	_remove_preview_point()

	# Waitポイントデータを作成
	var new_point = {
		"path_ratio": _current_ratio,
		"anchor": _current_anchor,
		"wait_duration": duration
	}

	# ポイントメッシュを作成（親ノードを渡してツリーに追加してから設定）
	var mesh = PointFactory.create_wait_point(
		_current_anchor,
		duration,
		_character_color,
		_path_drawer
	)

	# 共通の追加処理
	_add_point(new_point, mesh)
	return true


## 移動処理（長押し中はプレビュー更新）
func _handle_motion(_screen_pos: Vector2) -> void:
	update_preview()


## プレビューポイント作成
func _create_preview_point() -> void:
	_remove_preview_point()

	_preview_point = PointFactory.create_wait_point_preview(
		_current_anchor,
		WAIT_MIN_DURATION,
		_character_color,
		_path_drawer
	)


## プレビューポイント削除
func _remove_preview_point() -> void:
	if _preview_point:
		_preview_point.queue_free()
		_preview_point = null


## プレビュー更新
func update_preview() -> void:
	if not _is_active or not _preview_point:
		return

	var current_time = Time.get_ticks_msec() / 1000.0
	var duration = clampf(current_time - _press_start_time, WAIT_MIN_DURATION, WAIT_MAX_DURATION)
	_preview_point.set_wait_duration(duration)


## プレビュー中の待機時間を取得
func get_preview_duration() -> float:
	if not _is_active:
		return 0.0
	var current_time = Time.get_ticks_msec() / 1000.0
	return clampf(current_time - _press_start_time, WAIT_MIN_DURATION, WAIT_MAX_DURATION)


## 長押し中かどうか
func is_pressing() -> bool:
	return _is_active


## get_points オーバーライド（プレビュー中のポイントを含める）
func get_points() -> Array[Dictionary]:
	var result: Array[Dictionary] = _points.duplicate()
	# プレビュー中のポイントがあれば追加
	if _is_active and _preview_point:
		result.append({
			"path_ratio": _current_ratio,
			"anchor": _current_anchor,
			"wait_duration": get_preview_duration()
		})
	return result


## clear_all オーバーライド
func clear_all() -> void:
	super.clear_all()
	_remove_preview_point()
	_press_start_time = 0.0


## 状態リセット（オーバーライド）
func reset_state() -> void:
	super.reset_state()
	_remove_preview_point()
	_press_start_time = 0.0


## 同期Waitポイントを追加（コンテキストメニューから呼ばれる）
## wait_duration = -1 は同期ポイント（Wボタンで解放されるまで待機）を示す
## @param path_ratio: パス上の位置（0.0〜1.0）
## @param anchor: ポイントの3D位置
func add_sync_point(path_ratio: float, anchor: Vector3) -> void:
	var new_point = {
		"path_ratio": path_ratio,
		"anchor": anchor,
		"wait_duration": -1.0  # 同期ポイント（無期限待機）
	}

	# ポイントメッシュを作成（"W"表示）
	var mesh = PointFactory.create_wait_point(
		anchor,
		-1.0,
		_character_color,
		_path_drawer
	)

	# 共通の追加処理
	_add_point(new_point, mesh)
