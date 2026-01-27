class_name PathService
extends Node
## パス描画・編集・実行の統合サービス

signal mode_started(character: Node)
signal mode_ended()
signal mode_cancelled()
signal path_ready()
signal path_confirmed(count: int)
signal all_paths_completed()
signal paths_cleared()
signal mode_changed(mode: int)
signal vision_point_added(anchor: Vector3, direction: Vector3)
signal run_segment_added(start_ratio: float, end_ratio: float)
signal clear_point_added(path_ratio: float)
signal grenade_marker_added(path_ratio: float, target_pos: Vector3)
signal smoke_grenade_marker_added(path_ratio: float, target_pos: Vector3)
signal door_marker_added(path_ratio: float, door: Node3D)
signal wait_marker_added(path_ratio: float, wait_duration: float)

var path_drawer: PathDrawer = null
var selection_manager: CharacterSelectionManager = null
var path_execution_manager: PathExecutionManager = null
var path_mode_controller: PathModeController = null


func setup(
	drawer: PathDrawer,
	sel_manager: CharacterSelectionManager,
	exec_manager: PathExecutionManager,
	mode_controller: PathModeController
) -> void:
	path_drawer = drawer
	selection_manager = sel_manager
	path_execution_manager = exec_manager
	path_mode_controller = mode_controller

	if path_execution_manager:
		path_execution_manager.path_confirmed.connect(_on_path_confirmed)
		path_execution_manager.all_paths_completed.connect(_on_all_paths_completed)
		path_execution_manager.paths_cleared.connect(_on_paths_cleared)

	if path_drawer:
		path_drawer.mode_changed.connect(_on_path_mode_changed)
		path_drawer.vision_point_added.connect(_on_vision_point_added)
		path_drawer.run_segment_added.connect(_on_run_segment_added)
		path_drawer.clear_point_added.connect(_on_clear_point_added)
		path_drawer.grenade_marker_added.connect(_on_grenade_marker_added)
		path_drawer.smoke_grenade_marker_added.connect(_on_smoke_grenade_marker_added)
		path_drawer.door_marker_added.connect(_on_door_marker_added)
		path_drawer.wait_marker_added.connect(_on_wait_marker_added)
		path_drawer.path_undone.connect(_on_path_undone)

	if path_mode_controller:
		path_mode_controller.mode_started.connect(_on_path_mode_started)
		path_mode_controller.mode_ended.connect(_on_path_mode_ended)
		path_mode_controller.mode_cancelled.connect(_on_path_mode_cancelled)
		path_mode_controller.path_ready.connect(_on_path_ready)


## ========================================
## パス操作API
## ========================================

func start_move_mode() -> bool:
	if not selection_manager or not selection_manager.has_selection():
		return false

	if not path_drawer or not path_mode_controller:
		push_warning("[PathService] PathDrawer or PathModeController not set")
		return false

	# 選択中のキャラクター配列を取得
	var selected_chars: Array[Node] = []
	for c in selection_manager.selected_characters:
		selected_chars.append(c)

	# プライマリキャラクターの色を取得
	var primary = selection_manager.primary_character
	var char_color = CharacterColorManager.get_character_color(primary)

	# 既存の確定済みパスがあるかチェック
	var existing_path_data: Dictionary = {}
	if path_execution_manager and path_execution_manager.has_pending_path_for_character(primary):
		# 既存パスを編集用に取り出す（pending_pathsから削除される）
		existing_path_data = path_execution_manager.take_pending_path_for_editing(primary)

	# パスモード開始（既存パスがあれば復元、なければ新規）
	var started: bool
	if not existing_path_data.is_empty():
		started = path_mode_controller.start_with_existing_path(existing_path_data, char_color)
	else:
		started = path_mode_controller.start(primary, char_color)

	if not started:
		return false

	# シングルキャラクターのみサポート
	path_drawer.set_active_edit_character(primary)

	return true


func start_path_mode(primary: Node, char_color: Color = Color.WHITE) -> bool:
	if not path_mode_controller:
		return false
	return path_mode_controller.start(primary, char_color)


func confirm_path() -> void:
	if path_mode_controller:
		path_mode_controller.confirm()


func cancel_path() -> void:
	if path_mode_controller:
		path_mode_controller.cancel()


func execute_all_paths(run: bool) -> int:
	if not path_execution_manager:
		return 0
	return path_execution_manager.execute_all_paths(run)


func clear_all_pending_paths() -> void:
	if path_execution_manager:
		path_execution_manager.clear_all_pending_paths()


func cancel_all_path_following() -> void:
	if path_execution_manager:
		path_execution_manager.cancel_all_path_following()


func cancel_path_following(character: Node, clear_pending: bool = true) -> void:
	if path_execution_manager:
		path_execution_manager.cancel_path_following(character, clear_pending)


func process_controllers(delta: float) -> void:
	if path_execution_manager:
		path_execution_manager.process_controllers(delta)


func is_path_mode() -> bool:
	return path_mode_controller and path_mode_controller.is_path_mode()


func has_pending_path() -> bool:
	return path_drawer and path_drawer.has_pending_path()


func get_pending_path_count() -> int:
	return path_execution_manager.get_pending_path_count() if path_execution_manager else 0


func get_path_target_count() -> int:
	if not selection_manager:
		return 0
	return selection_manager.get_path_targets().size()


func is_any_path_following_active() -> bool:
	return path_execution_manager and path_execution_manager.is_any_path_following_active()


func is_character_following_path(character: Node) -> bool:
	return path_execution_manager and path_execution_manager.is_character_following_path(character)


func handle_click_to_cancel(clicked_character: Node) -> bool:
	if not path_mode_controller:
		return false
	return path_mode_controller.handle_click_to_cancel(clicked_character)


func is_marker_mode() -> bool:
	if not path_drawer:
		return false
	return path_drawer.get_drawing_mode() != PathDrawer.DrawingMode.MOVEMENT


## ========================================
## PathDrawer委譲API
## ========================================

func start_vision_mode() -> bool:
	return path_drawer.start_vision_mode() if path_drawer else false


func remove_last_vision_point() -> void:
	if path_drawer:
		path_drawer.remove_last_vision_point()


func start_run_mode() -> void:
	if path_drawer:
		path_drawer.start_run_mode()


func remove_last_run_segment() -> void:
	if path_drawer:
		path_drawer.remove_last_run_segment()


func start_clear_mode() -> void:
	if path_drawer:
		path_drawer.start_clear_mode()


func remove_last_clear_point() -> void:
	if path_drawer:
		path_drawer.remove_last_clear_point()


func start_grenade_mode() -> void:
	if path_drawer:
		path_drawer.start_grenade_mode()


func start_smoke_grenade_mode() -> void:
	if path_drawer:
		path_drawer.start_smoke_grenade_mode()


func start_door_mode() -> void:
	if path_drawer:
		path_drawer.start_door_mode()


func start_wait_mode() -> void:
	if path_drawer:
		path_drawer.start_wait_mode()


func get_grenade_marker_count() -> int:
	return path_drawer.get_grenade_marker_count() if path_drawer else 0


func get_door_marker_count() -> int:
	return path_drawer.get_door_marker_count() if path_drawer else 0


func get_wait_marker_count() -> int:
	return path_drawer.get_wait_marker_count() if path_drawer else 0


## 最後に追加したマーカーを削除（統一Undo）
func undo_last_marker() -> void:
	if path_drawer:
		path_drawer.undo_last_marker()


func get_vision_point_count() -> int:
	return path_drawer.get_vision_point_count() if path_drawer else 0


func get_run_segment_count() -> int:
	return path_drawer.get_run_segment_count() if path_drawer else 0


func get_clear_point_count() -> int:
	return path_drawer.get_clear_point_count() if path_drawer else 0


func has_incomplete_run_start() -> bool:
	return path_drawer.has_incomplete_run_start() if path_drawer else false


func set_active_edit_character(character: Node) -> void:
	if path_drawer:
		path_drawer.set_active_edit_character(character)


func set_path_drawer_color(color: Color) -> void:
	if path_drawer:
		path_drawer.set_character_color(color)


## ========================================
## シグナルハンドラ
## ========================================

func _on_path_mode_started(character: Node) -> void:
	mode_started.emit(character)


func _on_path_mode_ended() -> void:
	mode_ended.emit()


func _on_path_mode_cancelled() -> void:
	mode_cancelled.emit()


func _on_path_ready() -> void:
	# 視線ポイントモードへ移行
	# パス終点付近にVisionマーカーを追加すると、その方向で最終向きが固定される
	start_vision_mode()
	path_ready.emit()


func _on_path_confirmed(count: int) -> void:
	path_confirmed.emit(count)


func _on_all_paths_completed() -> void:
	all_paths_completed.emit()


func _on_paths_cleared() -> void:
	paths_cleared.emit()


func _on_path_mode_changed(mode: int) -> void:
	mode_changed.emit(mode)


func _on_vision_point_added(anchor: Vector3, direction: Vector3) -> void:
	vision_point_added.emit(anchor, direction)


func _on_run_segment_added(start_ratio: float, end_ratio: float) -> void:
	run_segment_added.emit(start_ratio, end_ratio)


func _on_clear_point_added(path_ratio: float) -> void:
	clear_point_added.emit(path_ratio)


func _on_grenade_marker_added(path_ratio: float, target_pos: Vector3) -> void:
	grenade_marker_added.emit(path_ratio, target_pos)


func _on_smoke_grenade_marker_added(path_ratio: float, target_pos: Vector3) -> void:
	smoke_grenade_marker_added.emit(path_ratio, target_pos)


func _on_door_marker_added(path_ratio: float, door: Node3D) -> void:
	door_marker_added.emit(path_ratio, door)


func _on_wait_marker_added(path_ratio: float, wait_duration: float) -> void:
	wait_marker_added.emit(path_ratio, wait_duration)


func _on_path_undone() -> void:
	# パスがUndoされたらパスモードは維持して再度パスを描けるようにする
	if path_drawer and selection_manager and selection_manager.has_selection():
		var primary = selection_manager.primary_character
		if primary:
			path_drawer.enable(primary)
