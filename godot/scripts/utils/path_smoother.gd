class_name PathSmoother
extends RefCounted

## 手描きパスのスムージングユーティリティ
## Ramer-Douglas-Peucker法（間引き）+ Catmull-Rom曲線（補間）の2段階処理

## デフォルトのRDP法許容誤差（メートル）
const DEFAULT_RDP_EPSILON: float = 0.15

## デフォルトの曲線補間分割数
const DEFAULT_SEGMENTS: int = 4


## パスをスムージングする（RDP間引き + Catmull-Rom補間）
## @param path: 元のパスポイント配列
## @param epsilon: RDP法の許容誤差（大きいほど間引きが強い）
## @param segments: Catmull-Rom曲線の各区間の分割数
## @return: スムージング後のパスポイント配列
static func smooth_path(path: PackedVector3Array, epsilon: float = DEFAULT_RDP_EPSILON, segments: int = DEFAULT_SEGMENTS) -> PackedVector3Array:
	if path.size() < 3:
		return path.duplicate()

	# Step 1: RDP法で不要ポイントを間引き
	var simplified = simplify_rdp(path, epsilon)

	# 間引き後のポイントが2点以下なら補間不要
	if simplified.size() < 3:
		return simplified

	# Step 2: Catmull-Rom曲線で補間
	var interpolated = interpolate_catmull_rom(simplified, segments)

	return interpolated


## Ramer-Douglas-Peucker法でパスを間引く
## @param path: 元のパスポイント配列
## @param epsilon: 許容誤差（この距離以下のポイントは削除）
## @return: 間引き後のパスポイント配列
static func simplify_rdp(path: PackedVector3Array, epsilon: float = DEFAULT_RDP_EPSILON) -> PackedVector3Array:
	if path.size() < 3:
		return path.duplicate()

	var result = PackedVector3Array()
	var keep_flags: Array[bool] = []
	keep_flags.resize(path.size())

	# 最初と最後は常に保持
	keep_flags[0] = true
	keep_flags[path.size() - 1] = true

	# 再帰的に間引き処理
	_rdp_recursive(path, 0, path.size() - 1, epsilon, keep_flags)

	# 保持フラグが立っているポイントのみ抽出
	for i in range(path.size()):
		if keep_flags[i]:
			result.append(path[i])

	return result


## RDP法の再帰処理
static func _rdp_recursive(path: PackedVector3Array, start_idx: int, end_idx: int, epsilon: float, keep_flags: Array[bool]) -> void:
	if end_idx - start_idx <= 1:
		return

	var start_point = path[start_idx]
	var end_point = path[end_idx]

	var max_distance: float = 0.0
	var max_index: int = start_idx

	# 始点-終点間の直線からの最大距離を持つポイントを探す
	for i in range(start_idx + 1, end_idx):
		var distance = _point_to_line_distance(path[i], start_point, end_point)
		if distance > max_distance:
			max_distance = distance
			max_index = i

	# 最大距離がepsilonを超えていたら、そのポイントを保持して再帰
	if max_distance > epsilon:
		keep_flags[max_index] = true
		_rdp_recursive(path, start_idx, max_index, epsilon, keep_flags)
		_rdp_recursive(path, max_index, end_idx, epsilon, keep_flags)


## 点から線分への垂直距離を計算
static func _point_to_line_distance(point: Vector3, line_start: Vector3, line_end: Vector3) -> float:
	var line = line_end - line_start
	var line_length_sq = line.length_squared()

	# 線分が点の場合
	if line_length_sq < 0.0001:
		return point.distance_to(line_start)

	# 線分上の最近点を求めるためのパラメータt
	var t = maxf(0.0, minf(1.0, (point - line_start).dot(line) / line_length_sq))
	var projection = line_start + line * t

	return point.distance_to(projection)


## Catmull-Rom曲線でパスを補間
## @param path: 間引き後のパスポイント配列（制御点）
## @param segments: 各区間の分割数
## @return: 補間後のパスポイント配列
static func interpolate_catmull_rom(path: PackedVector3Array, segments: int = DEFAULT_SEGMENTS) -> PackedVector3Array:
	if path.size() < 2:
		return path.duplicate()

	if path.size() == 2:
		# 2点のみの場合は線形補間
		return path.duplicate()

	var result = PackedVector3Array()

	# Catmull-Romスプラインの計算
	# 端点処理のため、仮想的な制御点を追加
	for i in range(path.size() - 1):
		# 4つの制御点を取得（端点は繰り返し）
		var p0 = path[maxi(0, i - 1)]
		var p1 = path[i]
		var p2 = path[i + 1]
		var p3 = path[mini(path.size() - 1, i + 2)]

		# 最初の区間では始点を追加
		if i == 0:
			result.append(p1)

		# 区間内を分割してサンプリング
		for j in range(1, segments + 1):
			var t = float(j) / float(segments)
			var point = _catmull_rom_point(p0, p1, p2, p3, t)
			result.append(point)

	return result


## Catmull-Romスプラインの1点を計算
## @param p0, p1, p2, p3: 4つの制御点（p1-p2間を補間）
## @param t: 補間パラメータ (0.0 - 1.0)
## @return: 補間された点
static func _catmull_rom_point(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 = t * t
	var t3 = t2 * t

	# Catmull-Romスプライン係数（標準的な0.5のテンション）
	var a = -0.5 * t3 + t2 - 0.5 * t
	var b = 1.5 * t3 - 2.5 * t2 + 1.0
	var c = -1.5 * t3 + 2.0 * t2 + 0.5 * t
	var d = 0.5 * t3 - 0.5 * t2

	return p0 * a + p1 * b + p2 * c + p3 * d
