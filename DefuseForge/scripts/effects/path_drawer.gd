class_name PathDrawer
extends Node3D

## 地面にパスを描画するコンポーネント
## マウスドラッグでパスを描き、将来キャラクター移動に使用

signal drawing_started()
signal drawing_updated(points: PackedVector3Array)
signal drawing_finished(points: PackedVector3Array)

@export var min_point_distance: float = 0.2  # ポイント間の最小距離
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.9)  # 白
@export var line_width: float = 0.04
@export var ground_plane_height: float = 0.0
@export var max_points: int = 500

const PathLineMeshScript = preload("res://scripts/effects/path_line_mesh.gd")

var _camera: Camera3D
var _character: Node3D
var _ground_plane: Plane
var _is_drawing: bool = false
var _path_points: PackedVector3Array = PackedVector3Array()
var _path_mesh: MeshInstance3D


func _ready() -> void:
	_ground_plane = Plane(Vector3.UP, ground_plane_height)
	_setup_mesh()


func _setup_mesh() -> void:
	_path_mesh = MeshInstance3D.new()
	_path_mesh.set_script(PathLineMeshScript)
	_path_mesh.line_color = line_color
	_path_mesh.line_width = line_width
	add_child(_path_mesh)


## カメラとキャラクターを設定
func setup(camera: Camera3D, character: Node3D = null) -> void:
	_camera = camera
	_character = character


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null:
		return

	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# キャラクターの足元からスタート
				var start_pos: Vector3
				if _character:
					start_pos = Vector3(_character.global_position.x, 0, _character.global_position.z)
				else:
					var ground_pos = _get_ground_position(mouse_event.position)
					if ground_pos == null:
						return
					start_pos = ground_pos
				_start_drawing(start_pos)
			else:
				if _is_drawing:
					_finish_drawing()

	if event is InputEventMouseMotion:
		if _is_drawing:
			var ground_pos = _get_ground_position(event.position)
			if ground_pos != null:
				_add_point(ground_pos)


## マウス位置から地面上の座標を取得
func _get_ground_position(screen_pos: Vector2) -> Variant:
	var ray_origin = _camera.project_ray_origin(screen_pos)
	var ray_direction = _camera.project_ray_normal(screen_pos)

	var intersection = _ground_plane.intersects_ray(ray_origin, ray_direction)
	if intersection:
		return intersection as Vector3
	return null


## 描画開始
func _start_drawing(start_pos: Vector3) -> void:
	_is_drawing = true
	_path_points.clear()
	_path_points.append(start_pos)
	_path_mesh.update_from_points(_path_points)
	drawing_started.emit()


## ポイントを追加
func _add_point(pos: Vector3) -> void:
	if _path_points.size() >= max_points:
		return

	# 最後のポイントとの距離チェック
	var last_point = _path_points[_path_points.size() - 1]
	if pos.distance_to(last_point) < min_point_distance:
		return

	_path_points.append(pos)
	_path_mesh.update_from_points(_path_points)
	drawing_updated.emit(_path_points)


## 描画終了
func _finish_drawing() -> void:
	_is_drawing = false
	drawing_finished.emit(_path_points)
	print("[PathDrawer] Drawing finished with %d points" % _path_points.size())


## パスをクリア
func clear() -> void:
	_path_points.clear()
	_path_mesh.clear()
	_is_drawing = false


## 現在のパスを取得
func get_drawn_path() -> PackedVector3Array:
	return _path_points


## 描画中かどうか
func is_drawing() -> bool:
	return _is_drawing


## 線の色を変更
func set_line_color(color: Color) -> void:
	line_color = color
	if _path_mesh:
		_path_mesh.set_line_color(color)
