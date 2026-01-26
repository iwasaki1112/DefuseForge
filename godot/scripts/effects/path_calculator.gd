class_name PathCalculator
extends RefCounted

## パス計算ユーティリティクラス
## パス上の最近点検索、オフセット計算、距離計算などの静的メソッドを提供


## パス上で最も近い点を見つける
## @param path: パスポイント配列
## @param pos: 検索位置
## @return: { "point": Vector3, "distance": float, "ratio": float }
static func find_closest_point_on_path(path: PackedVector3Array, pos: Vector3) -> Dictionary:
	if path.size() < 2:
		return { "point": Vector3.ZERO, "distance": INF, "ratio": 0.0 }

	var closest_point: Vector3 = path[0]
	var closest_distance: float = INF
	var closest_ratio: float = 0.0

	var total_length: float = 0.0
	var lengths: Array[float] = [0.0]

	# パスの総距離を計算
	for i in range(1, path.size()):
		var segment_length = path[i - 1].distance_to(path[i])
		total_length += segment_length
		lengths.append(total_length)

	# 各セグメントで最も近い点を探す
	for i in range(1, path.size()):
		var p1 = path[i - 1]
		var p2 = path[i]

		# セグメント上の最近点を計算
		var segment = p2 - p1
		var segment_length = segment.length()
		if segment_length < 0.001:
			continue

		var t = clampf((pos - p1).dot(segment) / (segment_length * segment_length), 0.0, 1.0)
		var point_on_segment = p1 + segment * t

		var distance = pos.distance_to(point_on_segment)
		if distance < closest_distance:
			closest_distance = distance
			closest_point = point_on_segment
			# このセグメント上での進行率を計算
			var distance_to_point = lengths[i - 1] + segment_length * t
			closest_ratio = distance_to_point / total_length if total_length > 0 else 0.0

	return { "point": closest_point, "distance": closest_distance, "ratio": closest_ratio }


## パス上の指定された比率から距離オフセットした点を探す
## @param path: パスポイント配列
## @param base_ratio: 基準となるパス上の比率 (0.0-1.0)
## @param offset_distance: オフセット距離（負の値で開始方向へ）
## @return: { "point": Vector3, "ratio": float }
static func find_offset_point_on_path(path: PackedVector3Array, base_ratio: float, offset_distance: float) -> Dictionary:
	if path.size() < 2:
		return { "point": Vector3.ZERO, "ratio": 0.0 }

	# パスの総距離を計算
	var total_length: float = 0.0
	var lengths: Array[float] = [0.0]
	for i in range(1, path.size()):
		var segment_length = path[i - 1].distance_to(path[i])
		total_length += segment_length
		lengths.append(total_length)

	if total_length < 0.001:
		return { "point": path[0], "ratio": 0.0 }

	# 基準点の距離を計算
	var base_distance = base_ratio * total_length

	# オフセットを適用した距離を計算
	var target_distance = clampf(base_distance + offset_distance, 0.0, total_length)

	# 目標距離に対応するパス上の点を探す
	var target_ratio = target_distance / total_length

	for i in range(1, path.size()):
		if lengths[i] >= target_distance:
			var p1 = path[i - 1]
			var p2 = path[i]
			var segment_start_dist = lengths[i - 1]
			var segment_length = lengths[i] - segment_start_dist

			if segment_length < 0.001:
				return { "point": p1, "ratio": target_ratio }

			var t = (target_distance - segment_start_dist) / segment_length
			var point = p1 + (p2 - p1) * t
			return { "point": point, "ratio": target_ratio }

	# パスの終点を返す
	return { "point": path[path.size() - 1], "ratio": 1.0 }


## パスの総距離を計算
## @param path: パスポイント配列
## @return: パスの総距離
static func calculate_path_length(path: PackedVector3Array) -> float:
	if path.size() < 2:
		return 0.0

	var total_length: float = 0.0
	for i in range(1, path.size()):
		total_length += path[i - 1].distance_to(path[i])
	return total_length


## 指定比率のパス上の位置を取得
## @param path: パスポイント配列
## @param ratio: パス上の比率 (0.0-1.0)
## @return: パス上の位置
static func get_point_at_ratio(path: PackedVector3Array, ratio: float) -> Vector3:
	if path.size() < 2:
		return Vector3.ZERO if path.is_empty() else path[0]

	var total_length = calculate_path_length(path)
	if total_length < 0.001:
		return path[0]

	var target_distance = ratio * total_length
	var current_distance: float = 0.0

	for i in range(1, path.size()):
		var segment_length = path[i - 1].distance_to(path[i])
		if current_distance + segment_length >= target_distance:
			var t = (target_distance - current_distance) / segment_length if segment_length > 0 else 0.0
			return path[i - 1] + (path[i] - path[i - 1]) * t
		current_distance += segment_length

	return path[path.size() - 1]


## パスの終点を取得
## @param path: パスポイント配列
## @return: パスの終点位置
static func get_path_endpoint(path: PackedVector3Array) -> Vector3:
	if path.size() < 1:
		return Vector3.ZERO
	return path[path.size() - 1]


## 指定位置がパス終点付近かどうか判定
## @param path: パスポイント配列
## @param ground_pos: 検索位置
## @param threshold: 判定距離
## @return: パス終点付近かどうか
static func is_near_path_endpoint(path: PackedVector3Array, ground_pos: Vector3, threshold: float) -> bool:
	if path.size() < 2:
		return false
	var endpoint = get_path_endpoint(path)
	var distance = Vector2(ground_pos.x - endpoint.x, ground_pos.z - endpoint.z).length()
	return distance <= threshold
