class_name VisionPointHandler
extends PointHandlerBase

## 視線ポイントハンドラ
## パス上の任意の点から視線方向を設定するポイントの入力・管理を担当


## 最小ドラッグ距離（これ以上動かさないとドラッグとみなさない）
## モバイルでの誤検出を防ぐため大きめの値を設定
const MIN_DRAG_DISTANCE: float = 40.0

## 一時プレビューポイント
var _temp_mesh: MeshInstance3D = null


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
	_drag_start_pos = screen_pos
	_is_active = true
	return true


## 解放処理
func _handle_release(screen_pos: Vector2) -> bool:
	if not _is_active:
		return false

	# ドラッグ距離が閾値未満の場合（タップ）はポイントを作成しない
	if not _is_tap(screen_pos, MIN_DRAG_DISTANCE):
		var ground_pos = _get_ground_position(screen_pos)
		if ground_pos != null:
			_finish_vision_point(ground_pos)
	else:
		_remove_temp_point()

	_is_active = false
	return true


## 移動処理
func _handle_motion(screen_pos: Vector2) -> void:
	var ground_pos = _get_ground_position(screen_pos)
	if ground_pos != null:
		_update_temp_point(_current_anchor, ground_pos)


## 視線ポイント設定完了
func _finish_vision_point(end_pos: Vector3) -> void:
	var target_point = end_pos
	target_point.y = 0

	var direction = (target_point - _current_anchor)
	direction.y = 0

	if direction.length_squared() < 0.001:
		_remove_temp_point()
		return

	_remove_temp_point()

	# 視線ポイントデータを作成
	var new_point = {
		"path_ratio": _current_ratio,
		"anchor": _current_anchor,
		"target_point": target_point
	}

	# ポイントメッシュを作成（親ノードを渡してツリーに追加してから設定）
	var mesh = PointFactory.create_vision_point(
		_current_anchor,
		target_point,
		Vector3.ZERO,
		_character_color,
		_path_drawer
	)

	# 共通の追加処理
	_add_point(new_point, mesh)


## 一時ポイント更新
func _update_temp_point(anchor: Vector3, target_point: Vector3) -> void:
	if _temp_mesh:
		_temp_mesh.set_position_and_target(anchor, target_point)
	else:
		_temp_mesh = PointFactory.create_vision_point_preview(
			anchor,
			target_point,
			_character_color,
			_path_drawer
		)


## 一時ポイント削除
func _remove_temp_point() -> void:
	if _temp_mesh:
		_temp_mesh.queue_free()
		_temp_mesh = null


## 状態リセット（オーバーライド）
func reset_state() -> void:
	super.reset_state()
	_remove_temp_point()
