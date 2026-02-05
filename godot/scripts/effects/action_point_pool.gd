class_name ActionPointPool
extends RefCounted

## ActionPoint (VisionPoint/WaitPoint)のオブジェクトプール
## ポイント作成/破棄を削減し、GC圧力を軽減する
## NOTE: iOSビルド互換のためpreloadを使用せず、class_name参照を使用

## プールの最大サイズ（タイプごと）
const MAX_POOL_SIZE_PER_TYPE: int = 30

## プール状態監視用
var _total_created: Dictionary = {}  # { type: int }
var _total_recycled: Dictionary = {}  # { type: int }

## タイプ別の利用可能ポイントプール
var _available_vision_points: Array[VisionPoint] = []
var _available_wait_points: Array[WaitPoint] = []

## シングルトンインスタンス
static var _instance: ActionPointPool = null


## シングルトンを取得
static func get_instance() -> ActionPointPool:
	if _instance == null:
		_instance = ActionPointPool.new()
	return _instance


## VisionPointをプールから取得
static func acquire_vision_point() -> VisionPoint:
	return get_instance()._acquire_vision_point()


## WaitPointをプールから取得
static func acquire_wait_point() -> WaitPoint:
	return get_instance()._acquire_wait_point()


## ポイントをプールに返却
static func release(point: MeshInstance3D) -> void:
	if point:
		get_instance()._release(point)


## 複数ポイントをプールに返却
static func release_all(points: Array) -> void:
	var pool := get_instance()
	for point in points:
		if point and is_instance_valid(point):
			pool._release(point)


## VisionPointを取得（内部実装）
func _acquire_vision_point() -> VisionPoint:
	var point: VisionPoint

	if _available_vision_points.size() > 0:
		point = _available_vision_points.pop_back()
		_increment_recycled("vision")
		# 状態リセット
		_reset_vision_point(point)
	else:
		point = VisionPoint.new()
		_increment_created("vision")

	return point


## WaitPointを取得（内部実装）
func _acquire_wait_point() -> WaitPoint:
	var point: WaitPoint

	if _available_wait_points.size() > 0:
		point = _available_wait_points.pop_back()
		_increment_recycled("wait")
		# 状態リセット
		_reset_wait_point(point)
	else:
		point = WaitPoint.new()
		_increment_created("wait")

	return point


## ポイントをプールに返却（内部実装）
func _release(point: MeshInstance3D) -> void:
	if not is_instance_valid(point):
		return

	# 親から削除
	if point.get_parent():
		point.get_parent().remove_child(point)

	# 非表示に
	point.visible = false

	# タイプに応じてプールに追加
	if point is VisionPoint:
		if _available_vision_points.size() < MAX_POOL_SIZE_PER_TYPE:
			_available_vision_points.append(point as VisionPoint)
		else:
			point.queue_free()
	elif point is WaitPoint:
		if _available_wait_points.size() < MAX_POOL_SIZE_PER_TYPE:
			_available_wait_points.append(point as WaitPoint)
		else:
			point.queue_free()
	else:
		# 不明なタイプは破棄
		point.queue_free()


## VisionPointの状態リセット
func _reset_vision_point(point: VisionPoint) -> void:
	point.visible = true
	point.rotation = Vector3.ZERO
	# ターゲット線のクリーンアップはset_position_and_*で行われる


## WaitPointの状態リセット
func _reset_wait_point(point: WaitPoint) -> void:
	point.visible = true
	point.rotation = Vector3.ZERO


## 作成数インクリメント
func _increment_created(point_type: String) -> void:
	if not _total_created.has(point_type):
		_total_created[point_type] = 0
	_total_created[point_type] += 1


## リサイクル数インクリメント
func _increment_recycled(point_type: String) -> void:
	if not _total_recycled.has(point_type):
		_total_recycled[point_type] = 0
	_total_recycled[point_type] += 1


## プール統計を取得（デバッグ用）
func get_stats() -> Dictionary:
	var total_created := 0
	var total_recycled := 0
	for v in _total_created.values():
		total_created += v
	for v in _total_recycled.values():
		total_recycled += v

	return {
		"vision_pool_size": _available_vision_points.size(),
		"wait_pool_size": _available_wait_points.size(),
		"total_created": total_created,
		"total_recycled": total_recycled,
		"created_by_type": _total_created.duplicate(),
		"recycled_by_type": _total_recycled.duplicate(),
		"recycle_rate": float(total_recycled) / max(total_created, 1)
	}


## プールをクリア
func clear() -> void:
	for point in _available_vision_points:
		if is_instance_valid(point):
			point.queue_free()
	_available_vision_points.clear()

	for point in _available_wait_points:
		if is_instance_valid(point):
			point.queue_free()
	_available_wait_points.clear()


## デストラクタ
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		clear()
