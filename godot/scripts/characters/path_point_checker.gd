class_name PathPointChecker
extends RefCounted

## パスポイント到達判定の共通ロジック
## Vision, Wait, Grenade, Door等のポイント到達判定を統一的に処理する
##
## 使用例:
## ```gdscript
## var checker := PathPointChecker.new()
## checker.setup(
##     PathPointChecker.CheckMode.DISTANCE,
##     _calculate_distance_traveled,
##     _calculate_anchor_distance
## )
##
## # ポイント追加（自動でソートとインデックス再計算）
## checker.add_point({"anchor": pos, "path_ratio": 0.5})
##
## # 到達判定（毎フレーム呼び出し）
## var current_dist := _calculate_distance_traveled()
## checker.check_all_reached(current_dist, func(idx, data):
##     point_reached.emit(idx, data)
## )
## ```
##
## 既存のPathFollowingControllerとの統合:
## - WaitPoint: _wait_points, _wait_index, _check_wait_points()
## - VisionPoint: _vision_points, _vision_index, _update_vision_direction()
## - これらを順次PathPointCheckerに移行可能

## 到達判定モード
enum CheckMode {
	RATIO,      ## path_ratioベースの判定（Clear, Grenade用）
	DISTANCE    ## path_distanceベースの判定（Vision, Wait用）
}

## ポイント配列
var points: Array = []

## 次にチェックするポイントのインデックス
var current_index: int = 0

## 判定モード
var check_mode: CheckMode = CheckMode.DISTANCE

## パス全長のキャッシュ（RATIOモード用）
var cached_total_length: float = 0.0

## 距離計算用コールバック
var calculate_distance_callback: Callable

## アンカー距離計算用コールバック
var calculate_anchor_distance_callback: Callable


## 初期化
## @param mode: 到達判定モード
## @param calc_distance: キャラクターの移動距離を計算するコールバック
## @param calc_anchor: アンカー位置の距離を計算するコールバック
func setup(mode: CheckMode, calc_distance: Callable, calc_anchor: Callable) -> void:
	check_mode = mode
	calculate_distance_callback = calc_distance
	calculate_anchor_distance_callback = calc_anchor


## ポイントを追加してソート、インデックスを再計算
## @param point_data: ポイントデータ（path_ratio, anchor等を含む）
func add_point(point_data: Dictionary) -> void:
	# path_distanceを計算（DISTANCEモードの場合）
	if check_mode == CheckMode.DISTANCE:
		if point_data.has("anchor") and not point_data.has("path_distance"):
			if calculate_anchor_distance_callback.is_valid():
				point_data["path_distance"] = calculate_anchor_distance_callback.call(point_data.anchor)

	points.append(point_data)
	_sort_points()
	_recalc_index()


## 延長パス用にポイントを追加（インデックス再計算なし）
## @param point_data: ポイントデータ
## @param path: 距離計算用のパス
## @param calc_on_path: パス上の距離計算コールバック
func add_point_for_extension(point_data: Dictionary, path: Array, calc_on_path: Callable) -> void:
	if point_data.has("anchor") and not point_data.has("path_distance"):
		if calc_on_path.is_valid():
			point_data["path_distance"] = calc_on_path.call(path, point_data.anchor)

	points.append(point_data)
	_sort_points()


## ポイントをソート
func _sort_points() -> void:
	if check_mode == CheckMode.DISTANCE:
		points.sort_custom(_compare_by_distance)
	else:
		points.sort_custom(_compare_by_ratio)


## path_distanceで比較
func _compare_by_distance(a: Dictionary, b: Dictionary) -> bool:
	var dist_a: float = a.get("path_distance", a.get("path_ratio", 0.0) * cached_total_length)
	var dist_b: float = b.get("path_distance", b.get("path_ratio", 0.0) * cached_total_length)
	return dist_a < dist_b


## path_ratioで比較
func _compare_by_ratio(a: Dictionary, b: Dictionary) -> bool:
	return a.get("path_ratio", 0.0) < b.get("path_ratio", 0.0)


## 現在位置に基づいてインデックスを再計算
func _recalc_index() -> void:
	if not calculate_distance_callback.is_valid():
		current_index = 0
		return

	var char_distance: float = calculate_distance_callback.call()
	var i := 0

	while i < points.size():
		var point_distance := _get_point_distance(points[i])
		if point_distance > char_distance:
			break
		i += 1

	current_index = i


## ポイントの距離を取得
func _get_point_distance(point: Dictionary) -> float:
	if check_mode == CheckMode.DISTANCE:
		if point.has("path_distance"):
			return point.path_distance
		elif point.has("anchor"):
			if calculate_anchor_distance_callback.is_valid():
				var dist = calculate_anchor_distance_callback.call(point.anchor)
				point["path_distance"] = dist
				return dist
		return point.get("path_ratio", 0.0) * cached_total_length
	else:
		return point.get("path_ratio", 0.0) * cached_total_length


## 到達したポイントを取得（1つずつ）
## @param current_position: 現在の位置（距離またはratio）
## @return: 到達したポイントまたはnull
func check_reached(current_position: float) -> Variant:
	if current_index >= points.size():
		return null

	var point = points[current_index]
	var point_position := _get_point_distance(point)

	if current_position >= point_position:
		current_index += 1
		return point

	return null


## 全ての到達したポイントをチェック（コールバック呼び出し）
## @param current_position: 現在の位置
## @param callback: 到達時に呼ばれるコールバック(index, point_data)
## @return: 到達したポイント数
func check_all_reached(current_position: float, callback: Callable) -> int:
	var count := 0

	while current_index < points.size():
		var point = points[current_index]
		var point_position := _get_point_distance(point)

		if current_position >= point_position:
			var reached_index = current_index
			current_index += 1
			count += 1

			if callback.is_valid():
				callback.call(reached_index, point)
		else:
			break

	return count


## リセット
func reset() -> void:
	points.clear()
	current_index = 0


## 状態を設定（延長パス切り替え時用）
func set_state(new_points: Array, new_index: int = 0) -> void:
	points = new_points.duplicate()
	current_index = new_index


## ポイント数を取得
func get_count() -> int:
	return points.size()


## 残りポイント数を取得
func get_remaining_count() -> int:
	return max(0, points.size() - current_index)


## ポイントがあるか
func has_points() -> bool:
	return points.size() > 0


## 配列からポイントを設定（start_path用）
## path_distanceを計算してソート
## @param new_points: 新しいポイント配列
## @param recalc_from_current_pos: キャラクターの現在位置からインデックスを再計算するか（デフォルトtrue）
func set_points(new_points: Array, recalc_from_current_pos: bool = true) -> void:
	points = new_points.duplicate()
	# path_distanceを計算
	for i in range(points.size()):
		var p = points[i]
		if p.has("anchor") and not p.has("path_distance"):
			if calculate_anchor_distance_callback.is_valid():
				points[i]["path_distance"] = calculate_anchor_distance_callback.call(p.anchor)
	_sort_points()

	# キャラクターの現在位置に基づいてインデックスを再計算
	# これにより、既に通過したポイントはスキップされる
	if recalc_from_current_pos:
		_recalc_index()
	else:
		current_index = 0


## 全ポイントのpath_distanceを再計算してソート
## パス切り替え時や延長パス伸長時に使用
func recalculate_distances() -> void:
	for i in range(points.size()):
		var p = points[i]
		if p.has("anchor"):
			if calculate_anchor_distance_callback.is_valid():
				points[i]["path_distance"] = calculate_anchor_distance_callback.call(p.anchor)
	_sort_points()


## path_distanceキャッシュをクリア
func clear_distance_cache() -> void:
	for p in points:
		if p.has("path_distance"):
			p.erase("path_distance")


## 延長用チェッカーを作成（同じ設定で新しいインスタンス）
func create_extension_checker() -> PathPointChecker:
	var checker := PathPointChecker.new()
	checker.check_mode = check_mode
	checker.cached_total_length = cached_total_length
	# コールバックは後で設定する必要がある（延長パス用）
	return checker


## 延長チェッカーからポイントを引き継ぎ（延長パス切り替え時）
func take_over_from(extension_checker: PathPointChecker) -> void:
	points = extension_checker.points.duplicate()
	current_index = 0
	# path_distanceを再計算（新しいパスでの距離）
	recalculate_distances()


## インデックスを取得
func get_current_index() -> int:
	return current_index


## インデックスを設定
func set_current_index(idx: int) -> void:
	current_index = idx


## 指定インデックスのポイントを取得
func get_point_at(idx: int) -> Dictionary:
	if idx >= 0 and idx < points.size():
		return points[idx]
	return {}


## 全ポイントを取得
func get_all_points() -> Array:
	return points


## ポイントをクリア
func clear() -> void:
	points.clear()
	current_index = 0
