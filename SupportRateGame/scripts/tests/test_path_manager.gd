extends "res://scripts/systems/path/path_manager.gd"
## テスト用PathManager
## SquadManager依存を排除し、単一プレイヤーで動作
## 障害物検出機能付き

## パス描画状態
enum PathState {
	DRAWING,   # 通常描画中
	BLOCKED,   # 障害物内を通過中（一時停止）
}

## テスト用：プレイヤー検出距離
var tap_detection_radius: float = 2.0

## 障害物検出
var path_state: PathState = PathState.DRAWING
var last_valid_point: Vector3 = Vector3.INF  # 最後の有効なポイント
var wall_hit_point: Vector3 = Vector3.INF  # 壁にヒットした位置（壁の表面）
var wall_normal: Vector3 = Vector3.ZERO  # 壁の法線ベクトル
var destination_point: Vector3 = Vector3.INF  # ユーザーが向かおうとしている目的地
var blocked_start_point: Vector3 = Vector3.INF  # ブロック開始位置（視覚フィードバック用）
const WALL_COLLISION_MASK: int = 6  # 壁(bit 2) + 地形(bit 1) を検出
const RAYCAST_HEIGHT_OFFSET: float = 0.5  # Raycastの高さオフセット（地面すれすれを避ける）
const WALL_SLIDE_STEP: float = 0.5  # 壁スライドのステップサイズ
const WALL_SLIDE_MAX_STEPS: int = 150  # 壁スライドの最大ステップ数（長い壁に対応）
const WALL_OFFSET: float = 0.8  # 壁からのオフセット距離（キャラクターの半径+余裕）
const CHARACTER_RADIUS: float = 0.5  # キャラクターの衝突半径
const PROXIMITY_CHECK_DIRECTIONS: int = 8  # 壁近接チェックの方向数


func _ready() -> void:
	# 親クラスの_ready()を呼ばずに、必要な初期化だけ行う
	# （親の_ready()はInputManagerシグナルを親メソッドに接続してしまうため）

	# アナライザーの初期化
	var PathAnalyzerClass = preload("res://scripts/systems/path/path_analyzer.gd")
	analyzer = PathAnalyzerClass.new()

	# InputManagerに接続（子クラスのメソッドに接続）
	if has_node("/root/InputManager"):
		var input_manager = get_node("/root/InputManager")
		input_manager.draw_started.connect(_on_draw_started)
		input_manager.draw_moved.connect(_on_draw_moved)
		input_manager.draw_ended.connect(_on_draw_ended)
		print("[TestPathManager] Connected to InputManager signals")
	else:
		push_warning("[TestPathManager] InputManager not found!")

	print("[TestPathManager] Ready")  # 検出範囲を広げる


## オーバーライド：位置にいるプレイヤーを取得
## SquadManagerなしで動作するようにシンプル化
func _get_player_at_position(world_pos: Vector3) -> Node3D:
	if not player:
		print("[TestPathManager] _get_player_at_position: player is null")
		return null

	# プレイヤーとの距離をチェック
	var player_pos := player.global_position
	player_pos.y = world_pos.y  # Y軸を揃えて比較
	var distance := player_pos.distance_to(world_pos)

	print("[TestPathManager] _get_player_at_position: world_pos=%s, player_pos=%s, distance=%.2f" % [world_pos, player_pos, distance])

	if distance <= tap_detection_radius:
		print("[TestPathManager] Player detected!")
		return player

	print("[TestPathManager] Player NOT detected (too far)")
	return null


## オーバーライド：プレイヤーを切り替え（テストでは不要）
func _switch_to_player(_new_player: Node3D) -> void:
	pass  # テストでは単一プレイヤーなので何もしない


## オーバーライド：選択解除（テストでは何もしない）
func _deselect_current_player() -> void:
	pass  # テストでは選択解除しない


## オーバーライド：パス描画可否（常に許可）
func _can_draw() -> bool:
	return true


## オーバーライド：描画開始（デバッグ用）
func _on_draw_started(screen_pos: Vector2, world_pos: Vector3) -> void:
	print("[TestPathManager] _on_draw_started: screen=%s, world=%s" % [screen_pos, world_pos])

	# 障害物検出状態をリセット
	path_state = PathState.DRAWING
	last_valid_point = Vector3.INF
	wall_hit_point = Vector3.INF
	wall_normal = Vector3.ZERO
	destination_point = Vector3.INF
	blocked_start_point = Vector3.INF

	# 親クラスのメソッドを呼び出し
	super._on_draw_started(screen_pos, world_pos)

	# 開始点を最後の有効ポイントとして記録
	if is_drawing and current_path.size() > 0:
		last_valid_point = current_path[current_path.size() - 1]

	print("[TestPathManager] After super._on_draw_started: is_drawing=%s, current_path.size=%d" % [is_drawing, current_path.size()])


## オーバーライド：描画中の処理
## フリーハンドでパスを描画（障害物検出付き）
func _on_draw_moved(_screen_pos: Vector2, world_pos: Vector3) -> void:
	if world_pos == Vector3.INF:
		return

	if not is_drawing:
		return

	# 最小距離チェック（最後の有効ポイントからの距離）
	var check_point := last_valid_point if last_valid_point != Vector3.INF else (current_path[current_path.size() - 1] if current_path.size() > 0 else Vector3.INF)
	if check_point != Vector3.INF:
		var distance := world_pos.distance_to(check_point)
		if distance < min_point_distance:
			return

	match path_state:
		PathState.DRAWING:
			_handle_drawing_state(world_pos)
		PathState.BLOCKED:
			_handle_blocked_state(world_pos)


## 通常描画状態の処理（後処理方式）
## すべてのポイントを記録し、壁チェックは視覚フィードバックのみ
func _handle_drawing_state(world_pos: Vector3) -> void:
	if last_valid_point == Vector3.INF:
		current_path.append(world_pos)
		last_valid_point = world_pos
		_update_visual()
		_update_path_time()
		return

	# Raycastで障害物チェック（視覚フィードバック用）
	var hit_result := _raycast_between_points(last_valid_point, world_pos)

	# ポイントは常に追加（後処理で壁スライドを挿入）
	current_path.append(world_pos)

	if hit_result.is_empty():
		# 障害物なし
		last_valid_point = world_pos
		_update_visual()
	else:
		# 障害物あり → 視覚フィードバック（赤い線）を表示
		wall_hit_point = hit_result["position"]
		wall_hit_point.y = last_valid_point.y
		wall_normal = hit_result.get("normal", Vector3.ZERO)
		blocked_start_point = world_pos
		path_state = PathState.BLOCKED
		_update_visual_with_blocked(world_pos)

	_update_path_time()


## ブロック状態の処理（後処理方式）
## ポイントは追加し、壁から抜けたらDRAWING状態に戻る
func _handle_blocked_state(world_pos: Vector3) -> void:
	var base_y := wall_hit_point.y

	# ポイントを追加（後処理で壁スライドを挿入）
	current_path.append(world_pos)

	# 最後の有効ポイントから新しいポイントへRaycast（壁から抜けたかチェック）
	var world_pos_normalized := Vector3(world_pos.x, base_y, world_pos.z)
	var hit_result := _raycast_between_points(last_valid_point, world_pos_normalized)

	if hit_result.is_empty():
		# 壁から抜けた！DRAWING状態に戻る
		last_valid_point = world_pos
		path_state = PathState.DRAWING
		_update_visual()
		_update_path_time()
		return

	# まだブロック中 → 視覚フィードバックのみ更新
	blocked_start_point = world_pos
	_update_visual_with_blocked(world_pos)


## DRAWING状態に復帰
func _resume_drawing(world_pos: Vector3) -> void:
	path_state = PathState.DRAWING
	blocked_start_point = Vector3.INF
	current_path.append(world_pos)
	last_valid_point = world_pos
	_update_visual()
	_update_path_time()


## 2点間のRaycast（障害物検出）
func _raycast_between_points(from: Vector3, to: Vector3) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return {}

	# 高さオフセットを適用（地面すれすれのRaycastを避ける）
	var from_elevated := from + Vector3(0, RAYCAST_HEIGHT_OFFSET, 0)
	var to_elevated := to + Vector3(0, RAYCAST_HEIGHT_OFFSET, 0)

	var query := PhysicsRayQueryParameters3D.create(from_elevated, to_elevated)
	query.collision_mask = WALL_COLLISION_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result := space_state.intersect_ray(query)
	return result


## ポイントが壁から十分離れているかチェック
## 8方向にレイキャストを行い、どれかがキャラクター半径内に壁があれば壁に近すぎる
func _check_wall_proximity(point: Vector3) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return {}

	var elevated := point + Vector3(0, RAYCAST_HEIGHT_OFFSET, 0)

	# 8方向にレイキャスト
	for i in range(PROXIMITY_CHECK_DIRECTIONS):
		var angle := float(i) * TAU / float(PROXIMITY_CHECK_DIRECTIONS)
		var direction := Vector3(cos(angle), 0, sin(angle))
		var end_pos := elevated + direction * CHARACTER_RADIUS

		var query := PhysicsRayQueryParameters3D.create(elevated, end_pos)
		query.collision_mask = WALL_COLLISION_MASK
		query.collide_with_areas = false
		query.collide_with_bodies = true

		var result := space_state.intersect_ray(query)
		if not result.is_empty():
			# 壁が見つかった → このポイントは壁に近すぎる
			return result

	return {}  # 壁なし


## ポイントを壁から離れた位置に調整
func _adjust_point_away_from_wall(point: Vector3, wall_normal: Vector3) -> Vector3:
	var normal_xz := Vector3(wall_normal.x, 0, wall_normal.z).normalized()
	if normal_xz.length() < 0.01:
		return point
	# 壁の法線方向にオフセット
	return point + normal_xz * CHARACTER_RADIUS


## 壁スライドで迂回ポイントを計算
## 壁沿いにスライドして、目的地が直接見える位置を探す
func _calculate_wall_slide(hit_point: Vector3, dest: Vector3, normal: Vector3, base_y: float) -> Array[Vector3]:
	var hit_xz := Vector3(hit_point.x, base_y, hit_point.z)
	var dest_xz := Vector3(dest.x, base_y, dest.z)

	print("[WallSlide] Starting: hit=%s, dest=%s, normal=%s" % [hit_xz, dest_xz, normal])

	if normal == Vector3.ZERO:
		print("[WallSlide] FAILED: normal is zero")
		return []

	var normal_xz := Vector3(normal.x, 0, normal.z).normalized()
	if normal_xz == Vector3.ZERO:
		print("[WallSlide] FAILED: normal_xz is zero")
		return []

	# 壁から少しオフセットした開始位置
	var start_pos := hit_xz + normal_xz * WALL_OFFSET

	# 両方向を試す
	for direction_sign: float in [1.0, -1.0]:
		var result := _wall_follow_until_visible(start_pos, dest_xz, normal_xz, direction_sign, base_y)
		if result.size() > 0:
			return result

	print("[WallSlide] FAILED: could not find path after trying both directions")
	return []


## 壁沿いにスライドして、目的地が見える位置まで進む
func _wall_follow_until_visible(start: Vector3, dest: Vector3, initial_normal: Vector3, direction_sign: float, base_y: float) -> Array[Vector3]:
	var slide_points: Array[Vector3] = []
	var current_pos := start
	var current_normal := initial_normal

	# スライド方向（壁に平行）
	var slide_dir := current_normal.cross(Vector3.UP) * direction_sign
	if slide_dir.length() < 0.01:
		slide_dir = Vector3.RIGHT * direction_sign
	slide_dir = slide_dir.normalized()

	var total_steps := 0

	while total_steps < WALL_SLIDE_MAX_STEPS:
		# 現在位置から目的地が見えるかチェック
		var dest_check := _raycast_between_points(current_pos, dest)
		if dest_check.is_empty():
			# 目的地が見えた！
			if slide_points.size() == 0:
				slide_points.append(current_pos)
			slide_points.append(dest)
			print("[WallSlide] Found visible path with %d points after %d steps" % [slide_points.size(), total_steps])
			return slide_points

		# 次の位置を計算
		var next_pos := current_pos + slide_dir * WALL_SLIDE_STEP

		# 次の位置に壁があるかチェック
		var wall_check := _raycast_between_points(current_pos, next_pos)
		if wall_check.is_empty():
			# 壁なし → 進める
			slide_points.append(next_pos)
			current_pos = next_pos
		else:
			# 角に当たった → 角を回り込む
			var corner_pos: Vector3 = wall_check["position"]
			corner_pos.y = base_y
			var corner_normal: Vector3 = wall_check.get("normal", Vector3.ZERO)

			if corner_normal == Vector3.ZERO:
				break

			var corner_normal_xz := Vector3(corner_normal.x, 0, corner_normal.z).normalized()
			if corner_normal_xz == Vector3.ZERO:
				break

			# 角のオフセット位置
			var corner_offset := corner_pos + corner_normal_xz * WALL_OFFSET
			corner_offset.y = base_y

			# 角の位置から目的地が見えるかチェック
			var corner_dest_check := _raycast_between_points(corner_offset, dest)
			if corner_dest_check.is_empty():
				# 角から目的地が見える！
				slide_points.append(corner_offset)
				slide_points.append(dest)
				print("[WallSlide] Found visible path at corner with %d points" % slide_points.size())
				return slide_points

			slide_points.append(corner_offset)
			current_pos = corner_offset
			current_normal = corner_normal_xz

			# 新しいスライド方向
			slide_dir = current_normal.cross(Vector3.UP) * direction_sign
			if slide_dir.length() < 0.01:
				slide_dir = Vector3.RIGHT * direction_sign
			slide_dir = slide_dir.normalized()

		total_steps += 1

	return []


## パスを後処理：壁を通過するセグメントに壁スライドポイントを挿入
func _post_process_path_for_walls(path: Array[Vector3]) -> Array[Vector3]:
	if path.size() < 2:
		return path

	var base_y := path[0].y  # 基準Y座標
	var result: Array[Vector3] = []
	result.append(path[0])

	var i := 0
	while i < path.size() - 1:
		var from := result[result.size() - 1]  # 最後に追加したポイント
		var to := path[i + 1]
		to.y = base_y  # Y座標を正規化

		# このセグメントが壁を通過するかチェック
		var hit := _raycast_between_points(from, to)

		if hit.is_empty():
			# 壁なし → そのまま追加
			result.append(to)
			i += 1
		else:
			# 壁あり
			var wall_pos: Vector3 = hit["position"]
			wall_pos.y = base_y
			var wall_norm: Vector3 = hit.get("normal", Vector3.ZERO)
			var offset_pos := wall_pos + Vector3(wall_norm.x, 0, wall_norm.z).normalized() * WALL_OFFSET
			offset_pos.y = base_y

			print("[PostProcess] Wall hit at %s between points %d and %d" % [wall_pos, i, i + 1])

			# 先読み：到達可能なポイントを探す
			var found_exit := false
			for j in range(i + 1, path.size()):
				var target := path[j]
				target.y = base_y

				# まずオフセット位置から直接見えるかチェック
				var direct_check := _raycast_between_points(offset_pos, target)
				if direct_check.is_empty():
					# 直接見える！
					result.append(offset_pos)
					result.append(target)
					i = j
					found_exit = true
					print("[PostProcess] Direct path from offset to point %d" % j)
					break

				# 壁スライドを試す
				var slide_points := _calculate_wall_slide(wall_pos, target, wall_norm, base_y)
				if slide_points.size() > 0:
					# 壁スライド成功
					for p in slide_points:
						result.append(p)
					i = j
					found_exit = true
					print("[PostProcess] Wall slide success to point %d with %d slides" % [j, slide_points.size()])
					break

			if not found_exit:
				# どのポイントにも到達できない → 最後の有効ポイントでパスを終了
				# 新しいポイントは追加せず、既存の有効なパスを維持
				print("[PostProcess] Wall slide failed, path ends at last valid point")
				print("[PostProcess] No reachable exit found, path ends with %d points" % result.size())
				break  # パスを終了

	# 最終バリデーション：各ポイントが壁から十分離れているかチェック
	result = _validate_path_clearance(result)

	return result


## パス内の各ポイントが壁から十分離れているかチェックし、近すぎる場合は調整または削除
func _validate_path_clearance(path: Array[Vector3]) -> Array[Vector3]:
	if path.size() < 2:
		return path

	var base_y := path[0].y
	var validated: Array[Vector3] = []
	validated.append(path[0])  # 開始点は常に保持

	for idx in range(1, path.size()):
		var point := path[idx]
		point.y = base_y

		# 壁近接チェック
		var proximity := _check_wall_proximity(point)

		if proximity.is_empty():
			# 壁から十分離れている → そのまま追加
			validated.append(point)
		else:
			# 壁に近すぎる → 調整を試みる
			var wall_normal: Vector3 = proximity.get("normal", Vector3.ZERO)
			var adjusted := _adjust_point_away_from_wall(point, wall_normal)
			adjusted.y = base_y

			# 調整後のポイントもチェック
			var adjusted_proximity := _check_wall_proximity(adjusted)
			if adjusted_proximity.is_empty():
				# 調整成功 → 調整後のポイントを追加
				# ただし、前のポイントから到達可能かチェック
				var prev := validated[validated.size() - 1]
				var reach_check := _raycast_between_points(prev, adjusted)
				if reach_check.is_empty():
					validated.append(adjusted)
					print("[Validate] Adjusted point %d away from wall" % idx)
				else:
					print("[Validate] Skipped point %d (adjusted but unreachable)" % idx)
			else:
				# 調整しても壁に近い → スキップ
				print("[Validate] Skipped point %d (too close to wall)" % idx)

	print("[Validate] Path validated: %d -> %d points" % [path.size(), validated.size()])
	return validated


## ブロック中の視覚フィードバック
func _update_visual_with_blocked(current_blocked_pos: Vector3) -> void:
	if not player:
		return

	# 通常のパスを更新
	if current_path.size() >= 2:
		run_flags = analyzer.analyze(current_path)

	if not player_paths.has(player):
		var PathRendererClass = preload("res://scripts/systems/path/path_renderer.gd")
		var renderer = PathRendererClass.new()
		renderer.name = "PathRenderer_%s" % player.name
		add_child(renderer)
		player_paths[player] = {
			"path": [],
			"run_flags": [],
			"renderer": renderer
		}

	var renderer = player_paths[player]["renderer"]

	# ブロック中は壁ヒット位置から現在位置までの「無効ライン」を表示
	# （renderメソッドが対応していれば赤い点線で表示）
	if renderer.has_method("render_with_blocked"):
		renderer.render_with_blocked(current_path, run_flags, wall_hit_point, current_blocked_pos)
	else:
		# フォールバック：通常表示 + デバッグ出力
		renderer.render(current_path, run_flags)


## オーバーライド：描画終了
## グリッドシステムを完全にバイパスしてフリーハンドパスを使用
func _on_draw_ended(_screen_pos: Vector2) -> void:
	print("[TestPathManager] _on_draw_ended: is_drawing=%s, current_path.size=%d, path_state=%s" % [is_drawing, current_path.size(), PathState.keys()[path_state]])

	if not is_drawing:
		return

	is_drawing = false

	# 障害物検出状態をリセット
	path_state = PathState.DRAWING
	last_valid_point = Vector3.INF
	wall_hit_point = Vector3.INF
	wall_normal = Vector3.ZERO
	destination_point = Vector3.INF
	blocked_start_point = Vector3.INF

	if current_path.size() >= 2 and player:
		# 後処理：壁を通過するセグメントに壁スライドポイントを挿入
		var processed_path := _post_process_path_for_walls(current_path)
		print("[TestPathManager] Path processed: %d -> %d points" % [current_path.size(), processed_path.size()])
		current_path = processed_path

		# 走り判定（グリッドなし、アナライザー使用）
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

	print("[TestPathManager] After _on_draw_ended: is_drawing=%s" % is_drawing)
