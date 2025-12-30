extends Node3D

## パスマネージャー
## パス描画の管理とキャラクターへの指示を担当
## 各プレイヤーのパスを個別に保持

const PathRendererClass = preload("res://scripts/systems/path/path_renderer.gd")
const PathAnalyzerClass = preload("res://scripts/systems/path/path_analyzer.gd")

signal path_confirmed(waypoints: Array)  # Array of {position: Vector3, run: bool}
signal path_cleared
signal path_time_changed(current_time: float, max_time: float)  # UI通知用

@export var min_point_distance: float = 0.5  # ウェイポイント間の最小距離

# パス長制限
var max_path_time: float = 10.0  # デフォルト値（execution_timeから取得）
var current_path_time: float = 0.0

# 内部状態（現在選択中のプレイヤー用）
var current_path: Array[Vector3] = []
var run_flags: Array[bool] = []
var is_drawing: bool = false

# プレイヤーごとのパスデータ: { player_node: { path: Array, run_flags: Array, renderer: Node3D } }
var player_paths: Dictionary = {}

# 子コンポーネント
var analyzer: RefCounted = null

# プレイヤー参照
var player: Node3D = null


func _ready() -> void:
	analyzer = PathAnalyzerClass.new()

	# InputManagerに接続
	if has_node("/root/InputManager"):
		var input_manager = get_node("/root/InputManager")
		input_manager.draw_started.connect(_on_draw_started)
		input_manager.draw_moved.connect(_on_draw_moved)
		input_manager.draw_ended.connect(_on_draw_ended)

	# GameEventsに接続
	if has_node("/root/GameEvents"):
		var events = get_node("/root/GameEvents")
		events.round_started.connect(_on_round_started)
		events.strategy_phase_started.connect(_on_strategy_phase_started)
		events.execution_phase_started.connect(_on_execution_phase_started)

	# execution_timeを取得
	_update_max_path_time()


## 最大パス時間を更新（MatchManagerから取得）
func _update_max_path_time() -> void:
	if GameManager and GameManager.match_manager:
		var mm = GameManager.match_manager
		if mm.economy_rules:
			max_path_time = mm.economy_rules.execution_time


## ラウンド開始時に全パスをクリア
func _on_round_started(_round_number: int) -> void:
	clear_all_paths()


## 戦略フェーズ開始時に全パスをクリア（前ターンのパスを消す）
func _on_strategy_phase_started(_turn_number: int) -> void:
	clear_all_paths()


## 実行フェーズ開始時に描画中なら強制終了（確定）
func _on_execution_phase_started(_turn_number: int) -> void:
	if is_drawing:
		_on_draw_ended(Vector2.ZERO)


## 描画開始
func _on_draw_started(_screen_pos: Vector2, world_pos: Vector3) -> void:
	if world_pos == Vector3.INF:
		return

	# 戦略フェーズ以外では描画不可
	if not _can_draw():
		return

	# タップ位置に別のプレイヤーがいる場合はそのプレイヤーに切り替え（パス描画は続行）
	_check_and_switch_player(world_pos)

	is_drawing = true
	current_path.clear()
	run_flags.clear()
	current_path_time = 0.0

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
	_update_path_time()


## 描画中
func _on_draw_moved(_screen_pos: Vector2, world_pos: Vector3) -> void:
	if not is_drawing or world_pos == Vector3.INF:
		return

	if current_path.size() > 0:
		var last_pos := current_path[current_path.size() - 1]
		var distance := world_pos.distance_to(last_pos)
		if distance < min_point_distance:
			return

	# パス時間制限チェック
	if _would_exceed_time_limit(world_pos):
		# 制限に達している場合は追加しない
		return

	current_path.append(world_pos)
	_update_visual()
	_update_path_time()


## 描画終了
func _on_draw_ended(_screen_pos: Vector2) -> void:
	if not is_drawing:
		return

	is_drawing = false

	if current_path.size() >= 2 and player:
		# 最終的な解析
		run_flags = analyzer.analyze(current_path)

		# プレイヤーのパスデータを保存
		_save_player_path(player, current_path.duplicate(), run_flags.duplicate())
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


## プレイヤーのパスデータを保存
func _save_player_path(p: Node3D, path: Array, flags: Array) -> void:
	if not p:
		return

	# 既存のレンダラーがあれば使用、なければ作成
	if not player_paths.has(p):
		var renderer = PathRendererClass.new()
		renderer.name = "PathRenderer_%s" % p.name
		add_child(renderer)

		# キャラクターカラーを設定
		_set_renderer_color_for_player(renderer, p)

		player_paths[p] = {
			"path": [],
			"run_flags": [],
			"renderer": renderer
		}

		# プレイヤーがシーンから削除されたらクリーンアップ
		if not p.tree_exiting.is_connected(_on_player_tree_exiting):
			p.tree_exiting.connect(_on_player_tree_exiting.bind(p))

	player_paths[p]["path"] = path
	player_paths[p]["run_flags"] = flags

	# レンダラーを更新
	var renderer = player_paths[p]["renderer"]
	var typed_path: Array[Vector3] = []
	for pos in path:
		typed_path.append(pos)
	var typed_flags: Array[bool] = []
	for flag in flags:
		typed_flags.append(flag)
	renderer.render(typed_path, typed_flags)


## ビジュアルを更新（現在描画中のパス）
func _update_visual() -> void:
	if not player:
		return

	# 描画中のパスをプレイヤーのレンダラーで表示
	if current_path.size() >= 2:
		run_flags = analyzer.analyze(current_path)

	if not player_paths.has(player):
		var renderer = PathRendererClass.new()
		renderer.name = "PathRenderer_%s" % player.name
		add_child(renderer)

		# キャラクターカラーを設定
		_set_renderer_color_for_player(renderer, player)

		player_paths[player] = {
			"path": [],
			"run_flags": [],
			"renderer": renderer
		}

	var renderer = player_paths[player]["renderer"]
	renderer.render(current_path, run_flags)


## 現在のプレイヤーのパスをクリア
func clear_path() -> void:
	current_path.clear()
	run_flags.clear()

	if player and player_paths.has(player):
		player_paths[player]["path"].clear()
		player_paths[player]["run_flags"].clear()
		player_paths[player]["renderer"].clear()

	path_cleared.emit()


## 全プレイヤーのパスをクリア
func clear_all_paths() -> void:
	current_path.clear()
	run_flags.clear()

	for p in player_paths.keys():
		if player_paths[p]["renderer"]:
			player_paths[p]["renderer"].clear()
		player_paths[p]["path"].clear()
		player_paths[p]["run_flags"].clear()

	path_cleared.emit()


## プレイヤーがシーンから削除されたときのクリーンアップ
func _on_player_tree_exiting(p: Node3D) -> void:
	if not player_paths.has(p):
		return

	# レンダラーを削除
	var renderer = player_paths[p]["renderer"]
	if renderer and is_instance_valid(renderer):
		renderer.queue_free()

	# Dictionaryからエントリを削除
	player_paths.erase(p)

	# 現在のプレイヤーだったらクリア
	if player == p:
		player = null
		current_path.clear()
		run_flags.clear()


## プレイヤー参照を設定
func set_player(p: Node3D) -> void:
	if player == p:
		return

	# 前のプレイヤーの描画中パスを保存
	if is_drawing and player:
		_save_player_path(player, current_path.duplicate(), run_flags.duplicate())
		is_drawing = false

	player = p

	# 新しいプレイヤーのパスを復元
	if player and player_paths.has(player):
		var data = player_paths[player]
		current_path.clear()
		for pos in data["path"]:
			current_path.append(pos)
		run_flags.clear()
		for flag in data["run_flags"]:
			run_flags.append(flag)
	else:
		current_path.clear()
		run_flags.clear()


## 描画中かどうか
func is_path_drawing() -> bool:
	return is_drawing


## パス描画が可能かどうか
func _can_draw() -> bool:
	if GameManager and GameManager.match_manager:
		return GameManager.match_manager.can_draw_path()
	return true  # MatchManagerがなければ許可


## タップ位置に別のプレイヤーがいるかチェックし、いれば選択を切り替える
## 切り替え後もパス描画を続行する（タップ&ドラッグで即座にパスを描けるように）
const PLAYER_TAP_RADIUS: float = 1.5

func _check_and_switch_player(world_pos: Vector3) -> void:
	if not GameManager or not GameManager.squad_manager:
		return

	var sm = GameManager.squad_manager
	var closest_player: Node3D = null
	var closest_distance: float = PLAYER_TAP_RADIUS

	for data in sm.squad:
		if not data.is_alive or not data.player_node:
			continue
		var dist := world_pos.distance_to(data.player_node.global_position)
		if dist < closest_distance:
			closest_distance = dist
			closest_player = data.player_node

	# 別のプレイヤーをタップした場合、そのプレイヤーを選択してパス描画を続行
	if closest_player and closest_player != player:
		var new_index := -1
		for i in range(sm.squad.size()):
			if sm.squad[i].player_node == closest_player:
				new_index = i
				break
		if new_index >= 0:
			sm.select_player(new_index)
			# playerを直接更新（シグナル経由の更新を待たずにパス描画を開始）
			player = closest_player


## プレイヤーのパスデータを取得
func get_player_path(p: Node3D) -> Dictionary:
	if player_paths.has(p):
		return player_paths[p]
	return {}


## プレイヤーにパスが設定されているか
func has_player_path(p: Node3D) -> bool:
	return player_paths.has(p) and player_paths[p]["path"].size() >= 2


## プレイヤーの速度を取得
func _get_player_speeds() -> Dictionary:
	var walk_speed := 3.0  # デフォルト値
	var run_speed := 6.0   # デフォルト値

	if player:
		if "walk_speed" in player:
			walk_speed = player.walk_speed
		if "run_speed" in player:
			run_speed = player.run_speed

	return {"walk": walk_speed, "run": run_speed}


## パス時間を更新してシグナルを発行
func _update_path_time() -> void:
	var speeds := _get_player_speeds()
	current_path_time = PathAnalyzerClass.calculate_path_time(
		current_path, run_flags, speeds["walk"], speeds["run"]
	)
	path_time_changed.emit(current_path_time, max_path_time)


## 新しい点を追加したら時間制限を超えるかチェック
func _would_exceed_time_limit(new_pos: Vector3) -> bool:
	if current_path.size() == 0:
		return false

	var speeds := _get_player_speeds()

	# 仮のパスを作成して時間を計算
	var test_path: Array[Vector3] = current_path.duplicate()
	test_path.append(new_pos)

	# 仮のrun_flagsを作成（解析して走り判定）
	var test_flags: Array[bool] = analyzer.analyze(test_path)

	var test_time: float = PathAnalyzerClass.calculate_path_time(
		test_path, test_flags, speeds["walk"], speeds["run"]
	)

	return test_time > max_path_time


## 残り時間を取得
func get_remaining_time() -> float:
	return max(0.0, max_path_time - current_path_time)


## 最大パス時間を取得
func get_max_path_time() -> float:
	return max_path_time


## プレイヤーノードからキャラクターカラーを取得してレンダラーに設定
func _set_renderer_color_for_player(renderer: Node, p: Node3D) -> void:
	if not renderer or not p:
		return

	# プレイヤーノードからPlayerDataを取得
	var color := Color.GREEN  # デフォルト色

	if p.has_method("get") and p.get("player_data"):
		var player_data = p.player_data
		if player_data and "character_color" in player_data:
			color = player_data.character_color
	elif GameManager and GameManager.squad_manager:
		# SquadManager経由でPlayerDataを取得
		var player_data = GameManager.squad_manager.get_player_data_by_node(p)
		if player_data and "character_color" in player_data:
			color = player_data.character_color

	# レンダラーに色を設定
	if renderer.has_method("set_character_color"):
		renderer.set_character_color(color)
