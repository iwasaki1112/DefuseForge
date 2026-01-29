class_name MarkerHandlerBase
extends RefCounted

## マーカーハンドラ基底クラス
## 各マーカー種別（Vision, Run, Clear等）のハンドラの共通機能を提供


## マーカー追加シグナル（サブクラスで使用）
@warning_ignore("unused_signal")
signal marker_added(marker_data: Dictionary)

## マーカー削除シグナル（サブクラスで使用）
@warning_ignore("unused_signal")
signal marker_removed(marker_data: Dictionary)


## PathDrawerへの参照
var _path_drawer: Node3D = null

## カメラ参照
var _camera: Camera3D = null

## キャラクター色
var _character_color: Color = Color(1.0, 1.0, 1.0)


## 初期化
func setup(path_drawer: Node3D, camera: Camera3D) -> void:
	_path_drawer = path_drawer
	_camera = camera


## キャラクター色を設定
func set_character_color(color: Color) -> void:
	_character_color = color


## 入力処理（子クラスでオーバーライド）
## @param event: 入力イベント
## @return: 入力を処理した場合true
func handle_input(_event: InputEvent) -> bool:
	return false


## マーカー作成（子クラスでオーバーライド）
## @param data: マーカーデータ
## @return: 作成したマーカーメッシュ
func create_marker(_data: Dictionary) -> MeshInstance3D:
	return null


## 最後のマーカーをUndo（子クラスでオーバーライド）
## @return: 削除したマーカーデータ（なければ空Dictionary）
func undo_last() -> Dictionary:
	return {}


## 全マーカーをクリア（子クラスでオーバーライド）
func clear_all() -> void:
	pass


## マーカーがあるか（子クラスでオーバーライド）
func has_markers() -> bool:
	return false


## マーカー数を取得（子クラスでオーバーライド）
func get_marker_count() -> int:
	return 0


## マーカーデータを取得（子クラスでオーバーライド）
func get_markers() -> Array[Dictionary]:
	return []


## マーカーメッシュを取得して所有権を移譲（子クラスでオーバーライド）
func take_markers() -> Array[MeshInstance3D]:
	return []


## 状態をリセット（子クラスでオーバーライド）
## 一時的な編集状態をクリアする
func reset_state() -> void:
	pass


## マーカーを復元（子クラスでオーバーライド）
## @param data: マーカーデータの配列
## @param meshes: マーカーメッシュノードの配列
func restore_markers(_data: Array, _meshes: Array) -> void:
	pass


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


## 保留中パスがあるか
func _has_pending_path() -> bool:
	if not _path_drawer:
		return false
	return _path_drawer.has_pending_path()


## PathDrawerに子ノードを追加
func _add_child_to_drawer(node: Node) -> void:
	if _path_drawer:
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

#endregion
