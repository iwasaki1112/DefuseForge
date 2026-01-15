class_name PathDrawer
extends Node3D

## 地面にパスを描画するコンポーネント
## マウスドラッグでパスを描き、キャラクター移動に使用

signal drawing_started()
signal drawing_updated(points: PackedVector3Array)
signal drawing_finished(points: PackedVector3Array)
signal path_execution_started(character: CharacterBody3D)
signal path_execution_completed(character: CharacterBody3D)

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
var _is_enabled: bool = false  # パス描画が有効かどうか
var _path_points: PackedVector3Array = PackedVector3Array()
var _path_mesh: MeshInstance3D

## パス実行管理
var _pending_path: PackedVector3Array = PackedVector3Array()
var _pending_character: CharacterBody3D = null
var _executing_character: CharacterBody3D = null


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
	if _camera == null or not _is_enabled:
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
				get_viewport().set_input_as_handled()
			else:
				if _is_drawing:
					_finish_drawing()
					get_viewport().set_input_as_handled()

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

	# パスを保存
	if _path_points.size() >= 2 and _character:
		_pending_path = _path_points.duplicate()
		_pending_character = _character as CharacterBody3D

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


## パス描画を有効化（キャラクターを指定）
func enable(character: Node3D) -> void:
	_character = character
	_is_enabled = true
	clear()
	print("[PathDrawer] Enabled for character")


## パス描画を無効化
func disable() -> void:
	_is_enabled = false
	_is_drawing = false
	print("[PathDrawer] Disabled")


## 有効かどうか
func is_enabled() -> bool:
	return _is_enabled


## ========================================
## パス実行 API
## ========================================

## 保存されたパスを実行（キャラクター移動開始）
## @param run: 走るかどうか
## @return: 実行開始できたらtrue
func execute(run: bool = false) -> bool:
	if _pending_path.size() < 2 or _pending_character == null:
		return false

	# パスに沿って移動開始
	var path_array: Array[Vector3] = []
	for point in _pending_path:
		path_array.append(point)
	_pending_character.set_path(path_array, run)

	# 実行中キャラクターを記録
	_executing_character = _pending_character

	# path_completedシグナルを接続
	if not _executing_character.path_completed.is_connected(_on_path_completed):
		_executing_character.path_completed.connect(_on_path_completed)

	path_execution_started.emit(_executing_character)

	# 保留パスをクリア
	_pending_path.clear()
	_pending_character = null

	print("[PathDrawer] Path execution started")
	return true


## 保留中のパスがあるか
func has_pending_path() -> bool:
	return _pending_path.size() >= 2 and _pending_character != null


## 保留中のパスをクリア
func clear_pending() -> void:
	_pending_path.clear()
	_pending_character = null


## パス完了時のコールバック
func _on_path_completed() -> void:
	if _executing_character:
		# シグナルを切断
		if _executing_character.path_completed.is_connected(_on_path_completed):
			_executing_character.path_completed.disconnect(_on_path_completed)

		path_execution_completed.emit(_executing_character)
		_executing_character = null

	# パス描画をクリア
	clear()
	print("[PathDrawer] Path execution completed")
