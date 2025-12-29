extends Node3D

## パスマネージャー
## パス描画の管理とキャラクターへの指示を担当

const PathRendererClass = preload("res://scripts/systems/path/path_renderer.gd")
const PathAnalyzerClass = preload("res://scripts/systems/path/path_analyzer.gd")

signal path_confirmed(waypoints: Array)  # Array of {position: Vector3, run: bool}
signal path_cleared

@export var min_point_distance: float = 0.5  # ウェイポイント間の最小距離

# 内部状態
var current_path: Array[Vector3] = []
var run_flags: Array[bool] = []
var is_drawing: bool = false

# 子コンポーネント
var renderer: Node3D = null
var analyzer: RefCounted = null

# プレイヤー参照
var player: Node3D = null


func _ready() -> void:
	analyzer = PathAnalyzerClass.new()

	# レンダラーを作成
	renderer = PathRendererClass.new()
	renderer.name = "PathRenderer"
	add_child(renderer)

	# InputManagerに接続
	if has_node("/root/InputManager"):
		var input_manager = get_node("/root/InputManager")
		input_manager.draw_started.connect(_on_draw_started)
		input_manager.draw_moved.connect(_on_draw_moved)
		input_manager.draw_ended.connect(_on_draw_ended)


## 描画開始
func _on_draw_started(_screen_pos: Vector2, world_pos: Vector3) -> void:
	if world_pos == Vector3.INF:
		return

	is_drawing = true
	current_path.clear()
	run_flags.clear()

	# プレイヤーを停止
	if player and player.has_method("stop"):
		player.stop()

	# プレイヤーの足元からパスを開始
	if player:
		var player_pos := player.global_position
		player_pos.y = world_pos.y
		current_path.append(player_pos)

	current_path.append(world_pos)
	_update_visual()


## 描画中
func _on_draw_moved(_screen_pos: Vector2, world_pos: Vector3) -> void:
	if not is_drawing or world_pos == Vector3.INF:
		return

	if current_path.size() > 0:
		var last_pos := current_path[current_path.size() - 1]
		var distance := world_pos.distance_to(last_pos)
		if distance < min_point_distance:
			return

	current_path.append(world_pos)
	_update_visual()


## 描画終了
func _on_draw_ended(_screen_pos: Vector2) -> void:
	if not is_drawing:
		return

	is_drawing = false

	if current_path.size() >= 2:
		# 最終的な解析
		run_flags = analyzer.analyze(current_path)
		_update_visual()

		# waypointsを生成
		var waypoints: Array = []
		for i in range(current_path.size()):
			var run := false
			if i > 0 and i - 1 < run_flags.size():
				run = run_flags[i - 1]
			waypoints.append({
				"position": current_path[i],
				"run": run
			})

		path_confirmed.emit(waypoints)


## ビジュアルを更新
func _update_visual() -> void:
	if current_path.size() >= 2:
		run_flags = analyzer.analyze(current_path)
	renderer.render(current_path, run_flags)


## パスをクリア
func clear_path() -> void:
	current_path.clear()
	run_flags.clear()
	renderer.clear()
	path_cleared.emit()


## プレイヤー参照を設定
func set_player(p: Node3D) -> void:
	player = p


## 描画中かどうか
func is_path_drawing() -> bool:
	return is_drawing
