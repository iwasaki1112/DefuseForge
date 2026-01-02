extends Node3D

## グリッドテストシーン
## グリッドシステムとパス変換をテストするためのシーン

const PathGridConverterClass = preload("res://scripts/systems/grid/path_grid_converter.gd")
const LeetModel = preload("res://assets/characters/leet/leet.fbx")

@onready var grid_manager: Node = $GridManager
@onready var grid_visualizer: Node3D = $GridVisualizer
@onready var camera: Camera3D = $Camera3D
@onready var ui_label: Label = $UI/InfoLabel

# パス描画用
var _is_drawing: bool = false
var _freehand_points: Array[Vector3] = []
var _sprint_flags: Array[bool] = []  # 各ポイントがスプリントかどうか
var _path_converter = null  # PathGridConverter

# フリーハンドライン描画用
var _freehand_mesh_walk: MeshInstance3D = null
var _freehand_mesh_sprint: MeshInstance3D = null
var _freehand_material_walk: StandardMaterial3D = null
var _freehand_material_sprint: StandardMaterial3D = null

# カメラ操作
var _camera_target: Vector3 = Vector3(8, 0, 8)  # グリッド中央
var _camera_distance: float = 20.0
var _camera_angle: float = -60.0  # 俯瞰角度（度）
var _is_panning: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO

# テストキャラクター
var _character: Node3D = null
var _character_path: Array[Vector2i] = []
var _character_sprint_flags: Array[bool] = []  # 各セルがスプリントかどうか
var _character_path_index: int = 0
var _walk_speed: float = 3.0
var _sprint_speed: float = 5.0  # スプリント時は1.67倍速
var _character_moving: bool = false
var _anim_player: AnimationPlayer = null
var _current_anim_state: int = -1  # -1: uninitialized, 0: idle, 1: walking, 2: running
var _rotation_speed: float = 8.0  # 回転速度
var _use_2x2_character: bool = false  # 2x2キャラクターサイズを使用

# スプライン補間用
var _spline_points: Array[Vector3] = []  # スプライン上のポイント
var _spline_sprint_flags: Array[bool] = []  # 各スプラインポイントがスプリントかどうか
var _spline_index: int = 0
var _spline_t: float = 0.0  # 現在のセグメント内の位置（0-1）


func _ready() -> void:
	# フリーハンドライン描画用のメッシュを作成
	_create_freehand_mesh()

	# テストキャラクターを作成
	_create_test_character()

	# GridManagerの初期化を待つ
	if grid_manager.has_signal("grid_initialized"):
		if grid_manager._initialized:
			# 既に初期化済み
			_on_grid_initialized()
		else:
			grid_manager.grid_initialized.connect(_on_grid_initialized)

	_update_camera()
	_update_ui()


func _create_freehand_mesh() -> void:
	# 歩き用マテリアル（緑）
	_freehand_material_walk = StandardMaterial3D.new()
	_freehand_material_walk.albedo_color = Color(0.2, 0.8, 0.2, 1.0)
	_freehand_material_walk.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_freehand_material_walk.cull_mode = BaseMaterial3D.CULL_DISABLED

	# スプリント用マテリアル（オレンジ）
	_freehand_material_sprint = StandardMaterial3D.new()
	_freehand_material_sprint.albedo_color = Color(1.0, 0.5, 0.0, 1.0)
	_freehand_material_sprint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_freehand_material_sprint.cull_mode = BaseMaterial3D.CULL_DISABLED

	# 歩き用メッシュインスタンス
	_freehand_mesh_walk = MeshInstance3D.new()
	_freehand_mesh_walk.name = "FreehandLineWalk"
	_freehand_mesh_walk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_freehand_mesh_walk)

	# スプリント用メッシュインスタンス
	_freehand_mesh_sprint = MeshInstance3D.new()
	_freehand_mesh_sprint.name = "FreehandLineSprint"
	_freehand_mesh_sprint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_freehand_mesh_sprint)


func _create_test_character() -> void:
	# leetモデルを使用
	_character = Node3D.new()
	_character.name = "TestCharacter"

	# leetモデルをインスタンス化
	var leet_instance: Node3D = LeetModel.instantiate()
	leet_instance.name = "LeetModel"
	leet_instance.scale = Vector3(1.5, 1.5, 1.5)  # スケール調整
	_character.add_child(leet_instance)

	# マテリアルとテクスチャを設定
	CharacterSetup.setup_materials(leet_instance, "TestLeet")

	# Skeletonを取得してYオフセットを計算
	var skeleton = CharacterSetup.find_skeleton(leet_instance)
	if skeleton:
		var model_scale: float = leet_instance.scale.y
		var y_offset = CharacterSetup.calculate_y_offset_from_skeleton(skeleton, model_scale, "TestLeet")
		if y_offset > 0:
			leet_instance.position.y = y_offset

	# AnimationPlayerを取得してアニメーションをロード
	_anim_player = CharacterSetup.find_animation_player(leet_instance)
	if _anim_player:
		CharacterSetup.load_animations(_anim_player, leet_instance, "TestLeet")
		# 初期アニメーションを再生
		var idle_anim = CharacterSetup.get_animation_name("idle", CharacterSetup.WeaponType.RIFLE)
		if _anim_player.has_animation(idle_anim):
			_anim_player.play(idle_anim)
			print("[GridTest] Playing animation: %s" % idle_anim)

	# 初期位置（グリッドの左下付近、2x2の場合は1セル内側）
	if _use_2x2_character:
		_character.position = Vector3(1.0, 0, 1.0)  # 2x2エリアの中心
	else:
		_character.position = Vector3(0.5, 0, 0.5)

	add_child(_character)


func _on_grid_initialized() -> void:
	_path_converter = PathGridConverterClass.new(grid_manager)
	print("[GridTest] Grid initialized")

	# ブロックされているセルをデバッグ出力
	var blocked_cells: Array[Vector2i] = []
	for y in range(grid_manager.grid_height):
		for x in range(grid_manager.grid_width):
			var cell := Vector2i(x, y)
			if not grid_manager.is_walkable(cell):
				blocked_cells.append(cell)

	if blocked_cells.size() > 0:
		print("[GridTest] Blocked cells:")
		for cell in blocked_cells:
			var world_pos: Vector3 = grid_manager.cell_to_world(cell)
			print("  - Cell (%d, %d) -> World (%.1f, %.1f)" % [cell.x, cell.y, world_pos.x, world_pos.z])

	_update_ui()


func _process(delta: float) -> void:
	# キャラクター移動
	if _character_moving and _character_path.size() > 0:
		_move_character(delta)

	# キーボードカメラ移動
	var move_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move_dir.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move_dir.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move_dir.x += 1

	if move_dir != Vector3.ZERO:
		_camera_target += move_dir.normalized() * 10.0 * delta
		_update_camera()


func _move_character(delta: float) -> void:
	if _spline_points.size() < 2:
		_character_moving = false
		_update_character_animation(false)
		print("[GridTest] Character reached destination")
		return

	# 現在のセグメントがスプリントかどうか
	var is_sprinting := false
	if _spline_index < _spline_sprint_flags.size():
		is_sprinting = _spline_sprint_flags[_spline_index]

	# スプリント状態に応じた速度
	var current_speed := _sprint_speed if is_sprinting else _walk_speed

	# スプライン上を移動
	var segment_length := _spline_points[_spline_index].distance_to(_spline_points[_spline_index + 1])
	var move_distance := current_speed * delta
	_spline_t += move_distance / segment_length if segment_length > 0.01 else 1.0

	# セグメント終了チェック
	while _spline_t >= 1.0 and _spline_index < _spline_points.size() - 2:
		_spline_t -= 1.0
		_spline_index += 1
		segment_length = _spline_points[_spline_index].distance_to(_spline_points[_spline_index + 1])
		if segment_length < 0.01:
			_spline_t = 1.0
		# スプリント状態を更新
		if _spline_index < _spline_sprint_flags.size():
			is_sprinting = _spline_sprint_flags[_spline_index]

	# 終点到達
	if _spline_index >= _spline_points.size() - 2 and _spline_t >= 1.0:
		_character.position = _spline_points[_spline_points.size() - 1]
		_character_moving = false
		_update_character_animation(false)
		print("[GridTest] Character reached destination")
		return

	# 現在位置を補間
	var p0 := _spline_points[_spline_index]
	var p1 := _spline_points[_spline_index + 1]
	var new_pos := p0.lerp(p1, _spline_t)
	new_pos.y = 0

	# 進行方向を計算
	var direction := (new_pos - _character.position)
	direction.y = 0

	# 位置を更新
	_character.position = new_pos

	# 進行方向を滑らかに向く
	if direction.length() > 0.01:
		var target_rotation := atan2(direction.x, direction.z)
		_character.rotation.y = lerp_angle(_character.rotation.y, target_rotation, _rotation_speed * delta)

	# アニメーション更新
	_update_character_animation(is_sprinting)


## 線形パスを生成（壁を貫通しない）
func _generate_linear_path(waypoints: Array[Vector3], samples_per_segment: int = 4) -> Array[Vector3]:
	if waypoints.size() < 2:
		return waypoints

	var result: Array[Vector3] = []

	# 各セグメントをサンプリング
	for i in range(waypoints.size() - 1):
		var p0 := waypoints[i]
		var p1 := waypoints[i + 1]

		for j in range(samples_per_segment):
			var t := float(j) / float(samples_per_segment)
			var point := p0.lerp(p1, t)
			result.append(point)

	# 最後のポイントを追加
	result.append(waypoints[waypoints.size() - 1])

	return result


## Catmull-Romスプラインを生成
func _generate_spline_path(waypoints: Array[Vector3], samples_per_segment: int = 5) -> Array[Vector3]:
	if waypoints.size() < 2:
		return waypoints

	var result: Array[Vector3] = []

	# 端点を複製してスプラインの端を滑らかに
	var extended: Array[Vector3] = []
	extended.append(waypoints[0])  # 最初のポイントを複製
	for wp in waypoints:
		extended.append(wp)
	extended.append(waypoints[waypoints.size() - 1])  # 最後のポイントを複製

	# 各セグメントをサンプリング
	for i in range(1, extended.size() - 2):
		var p0 := extended[i - 1]
		var p1 := extended[i]
		var p2 := extended[i + 1]
		var p3 := extended[i + 2]

		for j in range(samples_per_segment):
			var t := float(j) / float(samples_per_segment)
			var point := _catmull_rom(p0, p1, p2, p3, t)
			result.append(point)

	# 最後のポイントを追加
	result.append(waypoints[waypoints.size() - 1])

	return result


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


func _update_character_animation(is_sprinting: bool = false) -> void:
	if _anim_player == null:
		return

	# 0: idle, 1: walking, 2: running
	var new_state: int = 0
	if _character_moving:
		new_state = 2 if is_sprinting else 1

	if new_state != _current_anim_state:
		_current_anim_state = new_state
		var anim_name: String
		match new_state:
			0:
				anim_name = CharacterSetup.get_animation_name("idle", CharacterSetup.WeaponType.RIFLE)
			1:
				anim_name = CharacterSetup.get_animation_name("walking", CharacterSetup.WeaponType.RIFLE)
			2:
				anim_name = CharacterSetup.get_animation_name("running", CharacterSetup.WeaponType.RIFLE)

		if _anim_player.has_animation(anim_name):
			_anim_player.play(anim_name, 0.3)


func _input(event: InputEvent) -> void:
	# マウスボタン
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drawing(event.position)
			else:
				_finish_drawing()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# 右クリックでカメラパン
			_is_panning = event.pressed
			_last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			# 中クリックでもカメラパン
			_is_panning = event.pressed
			_last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = max(5.0, _camera_distance - 2.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = min(50.0, _camera_distance + 2.0)
			_update_camera()

	# マウス移動
	if event is InputEventMouseMotion:
		if _is_drawing:
			_add_drawing_point(event.position)
		elif _is_panning:
			# カメラパン
			var delta_mouse: Vector2 = event.position - _last_mouse_pos
			_last_mouse_pos = event.position

			var pan_speed: float = _camera_distance * 0.002
			_camera_target.x -= delta_mouse.x * pan_speed
			_camera_target.z -= delta_mouse.y * pan_speed
			_update_camera()

	# キーボード
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_R:
				_clear_path()
			KEY_G:
				grid_visualizer.show_grid_lines = not grid_visualizer.show_grid_lines
				grid_visualizer.update_visibility()
			KEY_C:
				grid_visualizer.show_cells = not grid_visualizer.show_cells
				grid_visualizer.update_visibility()
			KEY_SPACE:
				# スペースでキャラクター移動開始
				_start_character_movement()


func _start_drawing(screen_pos: Vector2) -> void:
	_is_drawing = true
	_freehand_points.clear()
	_sprint_flags.clear()
	grid_visualizer.clear_path()
	_add_drawing_point(screen_pos)


func _add_drawing_point(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world(screen_pos)
	if world_pos != Vector3.INF:
		# 障害物の上には描画しない
		if grid_manager:
			var cell = grid_manager.world_to_cell(world_pos)
			if _use_2x2_character:
				# 2x2キャラクターの場合、セルを左下として2x2エリアをチェック
				var cell_2x2 = Vector2i(cell.x - 1, cell.y - 1)  # 中心を基準にするため調整
				if not grid_manager.is_walkable_2x2(cell_2x2):
					return
			else:
				if not grid_manager.is_walkable(cell):
					return

		# 前のポイントから一定距離離れていれば追加（斜めグリッドを得やすくするため間隔を広げる）
		var min_distance: float = grid_manager.cell_size * 0.7 if grid_manager else 0.7
		if _freehand_points.is_empty() or _freehand_points[_freehand_points.size() - 1].distance_to(world_pos) > min_distance:
			_freehand_points.append(world_pos)
			_update_freehand_line()
			_update_ui()


func _finish_drawing() -> void:
	_is_drawing = false

	if _freehand_points.size() >= 2 and _path_converter:
		# パスをグリッドに変換（A*パスファインディングで障害物回避）
		var grid_cells = _path_converter.convert_with_pathfinding(_freehand_points)

		# 表示用に最適化（方向が変わる点のみ）
		var optimized_cells = _path_converter.optimize_path(grid_cells)
		grid_visualizer.show_path(optimized_cells)

		# キャラクター用のパスは全セル（スムーズな移動のため）
		_character_path = grid_cells.duplicate()
		_character_path_index = 0

		# 直線が続く区間を自動でスプリントに判定
		_character_sprint_flags.clear()
		_detect_auto_sprint(grid_cells)

		# フリーハンドラインの色を更新（スプリント判定結果を反映）
		_update_freehand_line_with_sprint()

		var sprint_count := 0
		for flag in _character_sprint_flags:
			if flag:
				sprint_count += 1

		print("[GridTest] Path converted (A* pathfinding):")
		print("  - Original points: %d" % _freehand_points.size())
		print("  - Grid cells: %d" % grid_cells.size())
		print("  - Sprint cells: %d (auto-detected)" % sprint_count)
		print("  - Press SPACE to move character")

		_update_ui()

	# フリーハンドラインは残す（ユーザーリクエスト）


## 直線区間を自動でスプリントに判定
func _detect_auto_sprint(cells: Array[Vector2i]) -> void:
	if cells.size() < 2:
		for i in range(cells.size()):
			_character_sprint_flags.append(false)
		return

	# 各セルの方向を計算
	var directions: Array[Vector2i] = []
	for i in range(cells.size() - 1):
		var dir := cells[i + 1] - cells[i]
		directions.append(dir)
	directions.append(directions[directions.size() - 1])  # 最後は前のと同じ

	# 直線（同じまたは類似の方向が続く）区間を検出
	# 最低3セル以上同じ方向ならスプリント
	var min_straight_length := 3

	for i in range(cells.size()):
		var current_dir := directions[i]

		# 前後で類似方向が続いているかチェック
		var straight_count := 1

		# 前方向をチェック
		for j in range(i + 1, cells.size()):
			if _is_similar_direction(directions[j], current_dir):
				straight_count += 1
			else:
				break

		# 後ろ方向をチェック
		for j in range(i - 1, -1, -1):
			if _is_similar_direction(directions[j], current_dir):
				straight_count += 1
			else:
				break

		# 直線が続いていればスプリント
		var is_sprint := straight_count >= min_straight_length
		_character_sprint_flags.append(is_sprint)


## 2つの方向ベクトルが同じかチェック（厳格モード）
## 完全一致のみスプリント判定
func _is_similar_direction(dir1: Vector2i, dir2: Vector2i) -> bool:
	# 完全一致のみ許容
	return dir1 == dir2


func _start_character_movement() -> void:
	if _character_path.size() > 0:
		# グリッドセルをワールド座標に変換
		var waypoints: Array[Vector3] = []
		for cell in _character_path:
			var pos: Vector3
			if _use_2x2_character:
				pos = Vector3(
					grid_manager.grid_origin.x + (float(cell.x) + 1.0) * grid_manager.cell_size,
					0,
					grid_manager.grid_origin.z + (float(cell.y) + 1.0) * grid_manager.cell_size
				)
			else:
				pos = grid_manager.cell_to_world(cell)
				pos.y = 0
			waypoints.append(pos)

		# 線形パスを生成（壁を貫通しないようスプラインを使わない）
		_spline_points = _generate_linear_path(waypoints)
		_spline_index = 0
		_spline_t = 0.0

		# スプラインポイントごとのスプリントフラグを生成
		_spline_sprint_flags.clear()
		var samples_per_segment := 4  # 線形補間でも同じサンプル数
		for i in range(_spline_points.size()):
			# ポイントがどのウェイポイントセグメントに属するか計算
			var waypoint_idx: int = mini(i / samples_per_segment, _character_sprint_flags.size() - 1)
			var is_sprint := _character_sprint_flags[waypoint_idx] if waypoint_idx < _character_sprint_flags.size() else false
			_spline_sprint_flags.append(is_sprint)

		# キャラクターをパスの開始位置に移動
		if _spline_points.size() > 0:
			_character.position = _spline_points[0]

		_character_path_index = 0
		_character_moving = true
		print("[GridTest] Character started moving (spline points: %d)" % _spline_points.size())


func _clear_path() -> void:
	_freehand_points.clear()
	_sprint_flags.clear()
	_character_sprint_flags.clear()
	_spline_sprint_flags.clear()
	grid_visualizer.clear_path()
	_clear_freehand_line()
	_character_path.clear()
	_character_moving = false
	_update_ui()


func _update_freehand_line() -> void:
	# 描画中は緑色の線で表示（スプリント判定は描画完了後）
	if _freehand_points.size() < 2:
		_freehand_mesh_walk.mesh = null
		_freehand_mesh_sprint.mesh = null
		return

	var st_walk := SurfaceTool.new()
	st_walk.begin(Mesh.PRIMITIVE_LINE_STRIP)
	st_walk.set_material(_freehand_material_walk)

	var y_offset: float = 0.1

	for point in _freehand_points:
		st_walk.add_vertex(Vector3(point.x, point.y + y_offset, point.z))

	_freehand_mesh_walk.mesh = st_walk.commit()
	_freehand_mesh_sprint.mesh = null


## スプリント判定結果を反映してフリーハンドラインを更新
func _update_freehand_line_with_sprint() -> void:
	if _freehand_points.size() < 2 or _character_path.size() < 2:
		return

	var st_walk := SurfaceTool.new()
	var st_sprint := SurfaceTool.new()
	st_walk.begin(Mesh.PRIMITIVE_LINES)
	st_walk.set_material(_freehand_material_walk)
	st_sprint.begin(Mesh.PRIMITIVE_LINES)
	st_sprint.set_material(_freehand_material_sprint)

	var y_offset: float = 0.1
	var has_walk := false
	var has_sprint := false

	# 各フリーハンドポイントを最も近いグリッドセルに関連付けてスプリント状態を取得
	for i in range(_freehand_points.size() - 1):
		var p1 := _freehand_points[i]
		var p2 := _freehand_points[i + 1]

		# p1に最も近いグリッドセルを見つける
		var nearest_cell_idx := _find_nearest_cell_index(p1)
		var is_sprint := _character_sprint_flags[nearest_cell_idx] if nearest_cell_idx < _character_sprint_flags.size() else false

		var v1 := Vector3(p1.x, p1.y + y_offset, p1.z)
		var v2 := Vector3(p2.x, p2.y + y_offset, p2.z)

		if is_sprint:
			st_sprint.add_vertex(v1)
			st_sprint.add_vertex(v2)
			has_sprint = true
		else:
			st_walk.add_vertex(v1)
			st_walk.add_vertex(v2)
			has_walk = true

	_freehand_mesh_walk.mesh = st_walk.commit() if has_walk else null
	_freehand_mesh_sprint.mesh = st_sprint.commit() if has_sprint else null


## ワールド座標に最も近いグリッドセルのインデックスを返す
func _find_nearest_cell_index(world_pos: Vector3) -> int:
	var nearest_idx := 0
	var nearest_dist := INF

	for i in range(_character_path.size()):
		var cell_world: Vector3 = grid_manager.cell_to_world(_character_path[i])
		var dist: float = world_pos.distance_to(cell_world)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_idx = i

	return nearest_idx


func _clear_freehand_line() -> void:
	if _freehand_mesh_walk:
		_freehand_mesh_walk.mesh = null
	if _freehand_mesh_sprint:
		_freehand_mesh_sprint.mesh = null


func _screen_to_world(screen_pos: Vector2) -> Vector3:
	# スクリーン座標をワールド座標に変換（Y=0平面との交点）
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)

	# Y=0平面との交点を計算
	if abs(dir.y) < 0.001:
		return Vector3.INF

	var t := -from.y / dir.y
	if t < 0:
		return Vector3.INF

	return from + dir * t


func _update_camera() -> void:
	var angle_rad := deg_to_rad(_camera_angle)
	camera.position = _camera_target + Vector3(
		0,
		_camera_distance * sin(-angle_rad),
		_camera_distance * cos(-angle_rad)
	)
	camera.look_at(_camera_target, Vector3.UP)


func _update_ui() -> void:
	if not ui_label:
		return

	var info = grid_manager.get_debug_info() if grid_manager else {}
	var char_status: String = "Moving" if _character_moving else "Idle"

	# スプリントセル数をカウント（自動判定後）
	var sprint_count := 0
	for flag in _character_sprint_flags:
		if flag:
			sprint_count += 1

	var text := """Grid Test Scene
================
Grid: %dx%d (cell: %.1fm)
Walkable: %d / Blocked: %d

Drawing: %d points
Path cells: %d (Sprint: %d)
Character: %s

Controls:
- Left drag: Draw path
- Right drag: Pan camera
- WASD/Arrows: Move camera
- Mouse wheel: Zoom
- SPACE: Move character
- R: Clear path
- G: Toggle grid lines
- C: Toggle cell colors
- ESC: Quit

Sprint: Auto (straight lines)""" % [
		info.get("grid_size", Vector2i.ZERO).x,
		info.get("grid_size", Vector2i.ZERO).y,
		info.get("cell_size", 1.0),
		info.get("walkable_cells", 0),
		info.get("blocked_cells", 0),
		_freehand_points.size(),
		grid_visualizer._current_path.size() if grid_visualizer else 0,
		sprint_count,
		char_status
	]

	ui_label.text = text
