class_name TimelineCalculator
extends RefCounted
## タイムライン時間計算ユーティリティ
## パスデータから時間情報を計算する静的クラス

## 移動速度定数
const WALK_SPEED: float = 2.0  ## 歩行速度 (m/s)
const RUN_SPEED: float = 5.0  ## 走行速度 (m/s)
const DOOR_DURATION: float = 2.2  ## ドアキック固定時間 (秒) - 66フレーム/30fps

## セグメントタイプ
enum SegmentType {
	WALK,
	RUN,
	WAIT,
	DOOR
}

## 瞬間マーカータイプ（時間を消費しないマーカー）
enum MarkerType {
	VISION,
	CLEAR,
	GRENADE
}

## タイムラインセグメント
## 各セグメントは開始時間、終了時間、タイプを持つ
class TimelineSegment:
	var start_time: float = 0.0
	var end_time: float = 0.0
	var type: int = SegmentType.WALK
	var start_ratio: float = 0.0
	var end_ratio: float = 0.0

	func _init(p_start_time: float = 0.0, p_end_time: float = 0.0, p_type: int = SegmentType.WALK, p_start_ratio: float = 0.0, p_end_ratio: float = 0.0) -> void:
		start_time = p_start_time
		end_time = p_end_time
		type = p_type
		start_ratio = p_start_ratio
		end_ratio = p_end_ratio

	func get_duration() -> float:
		return end_time - start_time


## 瞬間マーカーポイント（時間を消費しないアクション）
class MarkerPoint:
	var time: float = 0.0  ## タイムライン上の時間位置
	var ratio: float = 0.0  ## パス上の位置(0.0-1.0)
	var type: int = MarkerType.VISION

	func _init(p_time: float = 0.0, p_ratio: float = 0.0, p_type: int = MarkerType.VISION) -> void:
		time = p_time
		ratio = p_ratio
		type = p_type


## タイムラインデータ
## パス全体の時間情報とセグメントリストを保持
class TimelineData:
	var total_duration: float = 0.0
	var segments: Array[TimelineSegment] = []
	var markers: Array[MarkerPoint] = []  ## 瞬間マーカー
	var path_length: float = 0.0

	func add_segment(segment: TimelineSegment) -> void:
		segments.append(segment)
		if segment.end_time > total_duration:
			total_duration = segment.end_time

	func add_marker(marker: MarkerPoint) -> void:
		markers.append(marker)

	func get_time_at_ratio(ratio: float) -> float:
		if segments.is_empty():
			return 0.0

		for segment in segments:
			if ratio >= segment.start_ratio and ratio <= segment.end_ratio:
				# セグメント内での補間
				var segment_progress = 0.0
				if segment.end_ratio > segment.start_ratio:
					segment_progress = (ratio - segment.start_ratio) / (segment.end_ratio - segment.start_ratio)
				return segment.start_time + segment_progress * segment.get_duration()

		# ratio が最後のセグメントを超えている場合
		return total_duration

	func get_ratio_at_time(time: float) -> float:
		if segments.is_empty() or total_duration < 0.001:
			return 0.0

		for segment in segments:
			if time >= segment.start_time and time <= segment.end_time:
				# セグメント内での補間
				var segment_progress = 0.0
				var segment_duration = segment.get_duration()
				if segment_duration > 0.001:
					segment_progress = (time - segment.start_time) / segment_duration
				return segment.start_ratio + segment_progress * (segment.end_ratio - segment.start_ratio)

		# time が最後を超えている場合
		return 1.0


## パスデータからタイムラインを計算
## @param path: パスポイント配列
## @param run_segments: Run区間配列 [{ start_ratio, end_ratio }]
## @param wait_markers: Waitマーカー配列 [{ path_ratio, wait_duration }]
## @param door_markers: Doorマーカー配列 [{ path_ratio }]
## @param vision_markers: Visionマーカー配列 [{ path_ratio }]
## @param clear_markers: Clearマーカー配列 [{ path_ratio }]
## @param grenade_markers: Grenadeマーカー配列 [{ path_ratio }]
## @return: TimelineData
static func calculate_timeline(
	path: Array[Vector3],
	run_segments: Array[Dictionary] = [],
	wait_markers: Array[Dictionary] = [],
	door_markers: Array[Dictionary] = [],
	vision_markers: Array[Dictionary] = [],
	clear_markers: Array[Dictionary] = [],
	grenade_markers: Array[Dictionary] = []
) -> TimelineData:
	var timeline = TimelineData.new()

	if path.size() < 2:
		return timeline

	# パスの総距離を計算
	var total_length = _calculate_path_length(path)
	timeline.path_length = total_length

	if total_length < 0.001:
		return timeline

	# マーカーとRun区間を統合してイベントリストを作成
	var events: Array[Dictionary] = []

	# Run区間の開始・終了をイベントとして追加
	for seg in run_segments:
		events.append({ "ratio": seg.get("start_ratio", 0.0), "type": "run_start" })
		events.append({ "ratio": seg.get("end_ratio", 0.0), "type": "run_end" })

	# Waitマーカーをイベントとして追加
	for wm in wait_markers:
		var duration = wm.get("wait_duration", 1.0)
		events.append({ "ratio": wm.get("path_ratio", 0.0), "type": "wait", "duration": duration })

	# Doorマーカーをイベントとして追加
	for dm in door_markers:
		events.append({ "ratio": dm.get("path_ratio", 0.0), "type": "door" })

	# ratio順にソート
	events.sort_custom(func(a, b): return a.ratio < b.ratio)

	# イベントを処理してセグメントを生成
	var current_time: float = 0.0
	var current_ratio: float = 0.0
	var is_running: bool = false

	for event in events:
		var event_ratio: float = event.ratio

		# 現在位置からイベント位置までの移動セグメントを追加
		if event_ratio > current_ratio:
			var distance = (event_ratio - current_ratio) * total_length
			var speed = RUN_SPEED if is_running else WALK_SPEED
			var move_duration = distance / speed

			var segment = TimelineSegment.new(
				current_time,
				current_time + move_duration,
				SegmentType.RUN if is_running else SegmentType.WALK,
				current_ratio,
				event_ratio
			)
			timeline.add_segment(segment)
			current_time += move_duration
			current_ratio = event_ratio

		# イベントを処理
		match event.type:
			"run_start":
				is_running = true
			"run_end":
				is_running = false
			"wait":
				var wait_duration: float = event.get("duration", 1.0)
				var segment = TimelineSegment.new(
					current_time,
					current_time + wait_duration,
					SegmentType.WAIT,
					event_ratio,
					event_ratio
				)
				timeline.add_segment(segment)
				current_time += wait_duration
			"door":
				var segment = TimelineSegment.new(
					current_time,
					current_time + DOOR_DURATION,
					SegmentType.DOOR,
					event_ratio,
					event_ratio
				)
				timeline.add_segment(segment)
				current_time += DOOR_DURATION

	# 残りの移動区間を追加（最後のイベントからパス終端まで）
	if current_ratio < 1.0:
		var distance = (1.0 - current_ratio) * total_length
		var speed = RUN_SPEED if is_running else WALK_SPEED
		var move_duration = distance / speed

		var segment = TimelineSegment.new(
			current_time,
			current_time + move_duration,
			SegmentType.RUN if is_running else SegmentType.WALK,
			current_ratio,
			1.0
		)
		timeline.add_segment(segment)

	# 瞬間マーカーを追加（時間位置を計算）
	for vm in vision_markers:
		var ratio = vm.get("path_ratio", 0.0)
		var time = timeline.get_time_at_ratio(ratio)
		timeline.add_marker(MarkerPoint.new(time, ratio, MarkerType.VISION))

	for cm in clear_markers:
		var ratio = cm.get("path_ratio", 0.0)
		var time = timeline.get_time_at_ratio(ratio)
		timeline.add_marker(MarkerPoint.new(time, ratio, MarkerType.CLEAR))

	for gm in grenade_markers:
		var ratio = gm.get("path_ratio", 0.0)
		var time = timeline.get_time_at_ratio(ratio)
		timeline.add_marker(MarkerPoint.new(time, ratio, MarkerType.GRENADE))

	return timeline


## パスの総距離を計算
static func _calculate_path_length(path: Array[Vector3]) -> float:
	var length: float = 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length


## 距離から時間を計算（単純計算）
static func calculate_time_for_distance(distance: float, is_running: bool = false) -> float:
	var speed = RUN_SPEED if is_running else WALK_SPEED
	return distance / speed if speed > 0 else 0.0


## パスの合計時間を計算（簡易版、マーカーなし）
static func calculate_simple_duration(path: Array[Vector3], is_running: bool = false) -> float:
	var distance = _calculate_path_length(path)
	return calculate_time_for_distance(distance, is_running)
