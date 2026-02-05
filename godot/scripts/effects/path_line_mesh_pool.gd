class_name PathLineMeshPool
extends RefCounted

## PathLineMeshのオブジェクトプール
## メッシュの作成/破棄を削減し、GC圧力を軽減する
## NOTE: iOSビルド互換のためpreloadを使用せず、class_name参照を使用

## プールの最大サイズ（これ以上は破棄）
const MAX_POOL_SIZE: int = 20

## プール状態監視用
var _total_created: int = 0
var _total_recycled: int = 0

## 利用可能なメッシュのプール
var _available_meshes: Array[PathLineMesh] = []

## シングルトンインスタンス
static var _instance: PathLineMeshPool = null


## シングルトンを取得
static func get_instance() -> PathLineMeshPool:
	if _instance == null:
		_instance = PathLineMeshPool.new()
	return _instance


## プールからメッシュを取得、またはなければ新規作成
## @param parent: 親ノード
## @param color: 線の色
## @param width: 線の幅
## @return: PathLineMeshインスタンス
static func acquire(parent: Node3D, color: Color, width: float) -> PathLineMesh:
	return get_instance()._acquire(parent, color, width)


## メッシュをプールに返却
## @param mesh: 返却するメッシュ
static func release(mesh: PathLineMesh) -> void:
	if mesh:
		get_instance()._release(mesh)


## プールからメッシュを取得（内部実装）
func _acquire(parent: Node3D, color: Color, width: float) -> PathLineMesh:
	var mesh: PathLineMesh

	if _available_meshes.size() > 0:
		# プールから取得
		mesh = _available_meshes.pop_back()
		_total_recycled += 1

		# 親を設定
		if mesh.get_parent():
			mesh.get_parent().remove_child(mesh)
		parent.add_child(mesh)

		# 状態をリセット
		mesh.visible = true
		mesh.set_line_color(color)
		mesh.line_width = width
	else:
		# 新規作成
		mesh = PathLineMesh.new()
		mesh.line_color = color
		mesh.line_width = width
		parent.add_child(mesh)
		_total_created += 1

	return mesh


## メッシュをプールに返却（内部実装）
func _release(mesh: PathLineMesh) -> void:
	if not is_instance_valid(mesh):
		return

	# メッシュをクリア
	mesh.clear()
	mesh.visible = false

	# 親から削除
	if mesh.get_parent():
		mesh.get_parent().remove_child(mesh)

	# プールサイズ制限
	if _available_meshes.size() < MAX_POOL_SIZE:
		_available_meshes.append(mesh)
	else:
		# プールが満杯なら破棄
		mesh.queue_free()


## プール統計を取得（デバッグ用）
func get_stats() -> Dictionary:
	return {
		"pool_size": _available_meshes.size(),
		"total_created": _total_created,
		"total_recycled": _total_recycled,
		"recycle_rate": float(_total_recycled) / max(_total_created, 1)
	}


## プールをクリア
func clear() -> void:
	for mesh in _available_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_available_meshes.clear()


## デストラクタ
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		clear()
