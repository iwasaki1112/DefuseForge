class_name ActionPointPool
extends RefCounted

## ActionPointの汎用オブジェクトプール
## ポイント作成/破棄を削減し、GC圧力を軽減する
## NOTE: iOSビルド互換のためpreloadを使用せず、class_name参照を使用
## NOTE: PointRegistryと連携して動的にタイプを管理

## デフォルトのプール最大サイズ（タイプごと）
const DEFAULT_MAX_POOL_SIZE: int = 30

## プール状態監視用
var _total_created: Dictionary = {}  # { type_id: int }
var _total_recycled: Dictionary = {}  # { type_id: int }

## タイプ別の利用可能ポイントプール { type_id: Array[ActionPoint] }
var _pools: Dictionary = {}

## シングルトンインスタンス
static var _instance: ActionPointPool = null


## シングルトンを取得
static func get_instance() -> ActionPointPool:
	if _instance == null:
		_instance = ActionPointPool.new()
	return _instance


## 汎用: ポイントをプールから取得
static func acquire(type_id: int) -> ActionPoint:
	return get_instance()._acquire(type_id)


## VisionPointをプールから取得（後方互換）
static func acquire_vision_point() -> VisionPoint:
	return get_instance()._acquire(ActionPointData.Type.VISION) as VisionPoint


## WaitPointをプールから取得（後方互換）
static func acquire_wait_point() -> WaitPoint:
	return get_instance()._acquire(ActionPointData.Type.WAIT) as WaitPoint


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


## 汎用ポイント取得（内部実装）
func _acquire(type_id: int) -> ActionPoint:
	# プールが存在しなければ初期化
	if not _pools.has(type_id):
		_pools[type_id] = []

	var pool: Array = _pools[type_id]
	var point: ActionPoint

	if pool.size() > 0:
		point = pool.pop_back()
		_increment_recycled(type_id)
		# 状態リセット
		_reset_point(point, type_id)
	else:
		# PointRegistryから新規作成
		point = PointRegistry.create_point(type_id)
		if point == null:
			push_error("[ActionPointPool] Failed to create point for type_id: %d" % type_id)
			return null
		_increment_created(type_id)

	return point


## ポイントをプールに返却（内部実装）
func _release(point: MeshInstance3D) -> void:
	if not is_instance_valid(point):
		return

	# ActionPointでなければ破棄
	if not point is ActionPoint:
		point.queue_free()
		return

	var action_point := point as ActionPoint
	var type_id: int = action_point.get_action_point_type()

	# 親から削除
	if point.get_parent():
		point.get_parent().remove_child(point)

	# 非表示に
	point.visible = false

	# プールが存在しなければ初期化
	if not _pools.has(type_id):
		_pools[type_id] = []

	# プールサイズ制限を取得
	var max_size := _get_max_pool_size(type_id)

	# プールに追加または破棄
	if _pools[type_id].size() < max_size:
		_pools[type_id].append(action_point)
	else:
		point.queue_free()


## ポイントの状態リセット
func _reset_point(point: ActionPoint, type_id: int) -> void:
	point.visible = true
	point.rotation = Vector3.ZERO

	# タイプ固有のリセット処理
	match type_id:
		ActionPointData.Type.VISION:
			if point is VisionPoint:
				(point as VisionPoint).reset_for_pool()
		ActionPointData.Type.WAIT:
			# WaitPointには特別なリセットは不要
			pass
		ActionPointData.Type.SMOKE_GRENADE:
			# SmokeGrenadePointには特別なリセットは不要
			pass


## プールの最大サイズを取得
func _get_max_pool_size(type_id: int) -> int:
	var definition := PointRegistry.get_definition(type_id)
	if definition:
		return definition.max_pool_size
	return DEFAULT_MAX_POOL_SIZE


## 作成数インクリメント
func _increment_created(type_id: int) -> void:
	if not _total_created.has(type_id):
		_total_created[type_id] = 0
	_total_created[type_id] += 1


## リサイクル数インクリメント
func _increment_recycled(type_id: int) -> void:
	if not _total_recycled.has(type_id):
		_total_recycled[type_id] = 0
	_total_recycled[type_id] += 1


## プール統計を取得（デバッグ用）
func get_stats() -> Dictionary:
	var total_created := 0
	var total_recycled := 0
	for v in _total_created.values():
		total_created += v
	for v in _total_recycled.values():
		total_recycled += v

	var pool_sizes := {}
	for type_id in _pools:
		pool_sizes[type_id] = _pools[type_id].size()

	return {
		"pool_sizes": pool_sizes,
		"total_created": total_created,
		"total_recycled": total_recycled,
		"created_by_type": _total_created.duplicate(),
		"recycled_by_type": _total_recycled.duplicate(),
		"recycle_rate": float(total_recycled) / max(total_created, 1)
	}


## プールをクリア
func clear() -> void:
	for type_id in _pools:
		for point in _pools[type_id]:
			if is_instance_valid(point):
				point.queue_free()
		_pools[type_id].clear()
	_pools.clear()


## デストラクタ
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		clear()
