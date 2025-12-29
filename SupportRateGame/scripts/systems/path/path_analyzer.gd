extends RefCounted

## パス解析ユーティリティ
## 直線判定、走り/歩き判定を担当

# 設定
var straight_angle_threshold: float = 15.0  # この角度（度）以下なら直線とみなす
var min_straight_distance: float = 2.0  # この距離以上の直線で走り判定
var end_walk_distance: float = 2.0  # 終点からこの距離内は必ず歩き


## パスを解析して走り/歩きフラグを生成
## 戻り値: Array[bool] 各セグメントが走りかどうか
func analyze(path: Array[Vector3]) -> Array[bool]:
	var flags: Array[bool] = []

	if path.size() < 2:
		return flags

	# 初期化：すべて歩き
	for i in range(path.size() - 1):
		flags.append(false)

	# 各セグメントの角度変化を計算
	var angle_changes: Array[float] = []
	for i in range(path.size() - 1):
		var angle := _get_angle_change_at(path, i)
		angle_changes.append(angle)

	# 連続した直線区間を検出してグループ化
	var i := 0
	while i < angle_changes.size():
		if angle_changes[i] <= straight_angle_threshold:
			var start_idx := i
			var cumulative_distance := 0.0

			# 連続した直線セグメントをまとめる
			while i < angle_changes.size() and angle_changes[i] <= straight_angle_threshold:
				var p1 := path[i]
				var p2 := path[i + 1]
				cumulative_distance += p1.distance_to(p2)
				i += 1

			# 累積距離が閾値以上なら走りに設定
			if cumulative_distance >= min_straight_distance:
				for j in range(start_idx, i):
					flags[j] = true
		else:
			i += 1

	# 終点付近は必ず歩きに設定
	_force_walk_near_end(path, flags)

	return flags


## 終点付近のセグメントを歩きに強制
func _force_walk_near_end(path: Array[Vector3], flags: Array[bool]) -> void:
	if path.size() < 2 or flags.size() == 0:
		return

	var cumulative_distance := 0.0

	for i in range(path.size() - 2, -1, -1):
		var p1 := path[i]
		var p2 := path[i + 1]
		cumulative_distance += p1.distance_to(p2)

		if cumulative_distance <= end_walk_distance:
			flags[i] = false
		else:
			break


## 指定インデックスでの角度変化を取得（度）
func _get_angle_change_at(path: Array[Vector3], segment_index: int) -> float:
	if path.size() < 3:
		return 0.0

	# 最初のセグメント
	if segment_index == 0:
		if path.size() < 3:
			return 0.0
		var dir_curr := (path[1] - path[0])
		var dir_next := (path[2] - path[1])
		dir_curr.y = 0
		dir_next.y = 0
		if dir_curr.length() < 0.01 or dir_next.length() < 0.01:
			return 0.0
		return rad_to_deg(acos(clamp(dir_curr.normalized().dot(dir_next.normalized()), -1.0, 1.0)))

	# 最後のセグメント
	if segment_index == path.size() - 2:
		var dir_prev := (path[segment_index] - path[segment_index - 1])
		var dir_curr := (path[segment_index + 1] - path[segment_index])
		dir_prev.y = 0
		dir_curr.y = 0
		if dir_prev.length() < 0.01 or dir_curr.length() < 0.01:
			return 0.0
		return rad_to_deg(acos(clamp(dir_prev.normalized().dot(dir_curr.normalized()), -1.0, 1.0)))

	# 中間セグメント
	var p0 := path[segment_index - 1]
	var p1 := path[segment_index]
	var p2 := path[segment_index + 1]

	var dir_prev := (p1 - p0)
	var dir_curr := (p2 - p1)
	dir_prev.y = 0
	dir_curr.y = 0

	if dir_prev.length() < 0.01 or dir_curr.length() < 0.01:
		return 0.0

	return rad_to_deg(acos(clamp(dir_prev.normalized().dot(dir_curr.normalized()), -1.0, 1.0)))


## Catmull-Romスプライン補間で滑らかなパスを生成
func generate_smooth_path(points: Array[Vector3], segments_per_point: int = 5) -> Array[Vector3]:
	if points.size() < 2:
		return points

	var smooth: Array[Vector3] = []

	for i in range(points.size() - 1):
		var p0 := points[max(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[min(i + 1, points.size() - 1)]
		var p3 := points[min(i + 2, points.size() - 1)]

		for j in range(segments_per_point):
			var t := float(j) / float(segments_per_point)
			var interpolated := _catmull_rom(p0, p1, p2, p3, t)
			smooth.append(interpolated)

	smooth.append(points[points.size() - 1])

	return smooth


## Catmull-Rom補間
func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t

	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)
