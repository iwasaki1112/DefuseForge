class_name PointHandlerBase
extends RefCounted

## ポイントハンドラ基底クラス
## 各ポイント種別（Vision, Wait等）のハンドラの共通機能を提供


## ポイント追加シグナル（サブクラスで使用）
@warning_ignore("unused_signal")
signal point_added(point_data: Dictionary)

## ポイント削除シグナル（サブクラスで使用）
@warning_ignore("unused_signal")
signal point_removed(point_data: Dictionary)


## PathDrawerへの参照
var _path_drawer: Node3D = null

## カメラ参照
var _camera: Camera3D = null

## キャラクター色
var _character_color: Color = Color(1.0, 1.0, 1.0)


#region 共通状態（子クラスで使用）

## ポイントデータ配列
var _points: Array[Dictionary] = []

## ポイントメッシュ配列
var _meshes: Array[MeshInstance3D] = []

## 現在のアンカー位置
var _current_anchor: Vector3 = Vector3.ZERO

## 現在のパス上比率
var _current_ratio: float = 0.0

## 操作中フラグ（描画中、長押し中など）
var _is_active: bool = false

## ドラッグ開始位置（スクリーン座標）
var _drag_start_pos: Vector2 = Vector2.ZERO

## 最後のタッチ時刻（エミュレートマウスイベント対策）
var _last_touch_time: int = 0

## タッチイベントとマウスイベントの間隔閾値（ミリ秒）
const TOUCH_MOUSE_INTERVAL_MS: int = 100

#endregion


## 初期化
func setup(path_drawer: Node3D, camera: Camera3D) -> void:
	_path_drawer = path_drawer
	_camera = camera


## キャラクター色を設定
func set_character_color(color: Color) -> void:
	_character_color = color


#region 統一された入力処理テンプレート

## 入力処理（共通テンプレート）
## 子クラスでは_handle_press, _handle_release, _handle_motionをオーバーライド
func handle_input(event: InputEvent) -> bool:
	# タッチ入力
	if event is InputEventScreenTouch:
		_last_touch_time = Time.get_ticks_msec()
		if event.pressed:
			return _handle_press(event.position)
		else:
			return _handle_release(event.position)

	if event is InputEventScreenDrag:
		if _is_active:
			_handle_motion(event.position)
			return true
		return false

	# マウス入力（タッチ直後のエミュレートイベントはスキップ）
	if Time.get_ticks_msec() - _last_touch_time < TOUCH_MOUSE_INTERVAL_MS:
		return false

	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				return _handle_press(mouse_event.position)
			else:
				return _handle_release(mouse_event.position)

	if event is InputEventMouseMotion:
		if _is_active:
			_handle_motion(event.position)
			return true

	return false


## 押下処理（子クラスでオーバーライド）
func _handle_press(_screen_pos: Vector2) -> bool:
	return false


## 解放処理（子クラスでオーバーライド）
func _handle_release(_screen_pos: Vector2) -> bool:
	return false


## 移動処理（子クラスでオーバーライド）
func _handle_motion(_screen_pos: Vector2) -> void:
	pass

#endregion


#region 共通ポイント管理メソッド

## ポイントがあるか
func has_points() -> bool:
	return _points.size() > 0


## ポイント数を取得
func get_point_count() -> int:
	return _points.size()


## ポイントデータを取得
func get_points() -> Array[Dictionary]:
	return _points


## ポイントメッシュを取得して所有権を移譲
func take_points() -> Array[MeshInstance3D]:
	var points = _meshes.duplicate()
	_meshes.clear()
	return points


## メッシュを指定親ノードに転送し、データもクリア（所有権完全移譲）
## NOTE: 現在のUndoなし設計では_pointsもクリアする。
##       将来「ポイント編集」機能を再有効化する場合は、_pointsを残すか
##       「編集モード時は転送しない」などの分岐が必要になる可能性あり。
## @param parent: 転送先の親ノード
## @return: 転送されたメッシュの配列
func transfer_meshes_to(parent: Node3D) -> Array[MeshInstance3D]:
	var transferred: Array[MeshInstance3D] = []
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.reparent(parent)
			transferred.append(mesh)
	_meshes.clear()
	_points.clear()
	return transferred


## 最後のポイントをUndo
func undo_last() -> Dictionary:
	if _points.size() == 0:
		return {}

	var removed_data = _points.pop_back()
	if _meshes.size() > 0:
		var mesh = _meshes.pop_back()
		if is_instance_valid(mesh):
			mesh.queue_free()

	point_removed.emit(removed_data)
	return removed_data


## 全ポイントをクリア
func clear_all() -> void:
	_points.clear()
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_meshes.clear()
	reset_state()


## 状態をリセット
## 一時的な編集状態をクリアする（子クラスでオーバーライド可能）
func reset_state() -> void:
	_is_active = false
	_drag_start_pos = Vector2.ZERO
	_current_anchor = Vector3.ZERO
	_current_ratio = 0.0


## ポイントを復元
## @param data: ポイントデータの配列
## @param meshes: ポイントメッシュノードの配列
func restore_points(data: Array, meshes: Array) -> void:
	for d in data:
		_points.append(d)
	for m in meshes:
		if is_instance_valid(m):
			_add_child_to_drawer(m)
			_meshes.append(m)


## ポイントを追加（共通処理）
## @param point_data: ポイントデータ
## @param mesh: ポイントメッシュ
func _add_point(point_data: Dictionary, mesh: MeshInstance3D) -> void:
	# path_ratio順に挿入位置を決定
	var insert_idx = 0
	for i in range(_points.size()):
		if _points[i].get("path_ratio", 0.0) > point_data.get("path_ratio", 0.0):
			break
		insert_idx = i + 1

	_points.insert(insert_idx, point_data)
	_meshes.insert(insert_idx, mesh)

	if Debug.enabled: print("[PointDebug] _add_point: ratio=%.3f, total=%d, mesh_valid=%s" % [
		point_data.get("path_ratio", 0.0),
		_points.size(),
		str(is_instance_valid(mesh))
	])

	point_added.emit(point_data)


## ポイント作成（子クラスでオーバーライド）
## @param data: ポイントデータ
## @return: 作成したポイントメッシュ
func create_point(_data: Dictionary) -> MeshInstance3D:
	return null

#endregion


#region ヘルパーメソッド

## 地面位置を取得
func _get_ground_position(screen_pos: Vector2) -> Variant:
	if not _path_drawer:
		return null
	return _path_drawer._get_ground_position(screen_pos)


## パス上の最近点を検索
func _find_closest_point_on_path(pos: Vector3) -> Dictionary:
	if not _path_drawer:
		return { "point": Vector3.ZERO, "distance": INF, "ratio": 0.0 }
	return _path_drawer._find_closest_point_on_path(pos)


## パス上の指定比率からオフセットした点を検索
func _find_offset_point_on_path(base_ratio: float, offset_distance: float) -> Dictionary:
	if not _path_drawer:
		return { "point": Vector3.ZERO, "ratio": 0.0 }
	return _path_drawer._find_offset_point_on_path(base_ratio, offset_distance)


## パスクリック判定距離を取得
func _get_path_click_threshold() -> float:
	if not _path_drawer:
		return 0.5
	return _path_drawer.path_click_threshold


## パスがあるか
func _has_path() -> bool:
	if not _path_drawer:
		return false
	return _path_drawer.has_path()


## PathDrawerに子ノードを追加
func _add_child_to_drawer(node: Node) -> void:
	if _path_drawer and node:
		# 既に親がある場合は再ペアレント
		if node.get_parent():
			node.reparent(_path_drawer)
		else:
			_path_drawer.add_child(node)


## 壁または床へのレイキャスト
func _raycast_wall_or_floor(screen_pos: Vector2) -> Dictionary:
	if not _path_drawer:
		return {}
	return _path_drawer._raycast_wall_or_floor(screen_pos)


## ドアへのレイキャスト
func _raycast_door(screen_pos: Vector2) -> Node3D:
	if not _path_drawer:
		return null
	return _path_drawer._raycast_door(screen_pos)


## タップかどうかを判定（ドラッグ距離に基づく）
func _is_tap(current_pos: Vector2, threshold: float = 40.0) -> bool:
	return current_pos.distance_to(_drag_start_pos) < threshold


## パス上クリック判定（共通処理）
## @return: { success: bool, anchor: Vector3, ratio: float }
func _check_path_click(screen_pos: Vector2) -> Dictionary:
	var ground_pos = _get_ground_position(screen_pos)
	if ground_pos == null:
		return { "success": false }

	var result = _find_closest_point_on_path(ground_pos)
	if result.distance > _get_path_click_threshold():
		return { "success": false }

	return {
		"success": true,
		"anchor": result.point,
		"ratio": result.ratio
	}

#endregion
