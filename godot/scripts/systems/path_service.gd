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

var path_drawer: PathDrawer = null
var selection_manager: CharacterSelectionManager = null
var path_execution_manager: PathExecutionManager = null
var path_mode_controller: PathModeController = null
var marker_edit_panel: MarkerEditPanel = null


func setup(
	drawer: PathDrawer,
	sel_manager: CharacterSelectionManager,
	exec_manager: PathExecutionManager,
	mode_controller: PathModeController,
	marker_panel: MarkerEditPanel
) -> void:
	path_drawer = drawer
	selection_manager = sel_manager
	path_execution_manager = exec_manager
	path_mode_controller = mode_controller
	marker_edit_panel = marker_panel

	if path_execution_manager:
		path_execution_manager.path_confirmed.connect(_on_path_confirmed)
		path_execution_manager.all_paths_completed.connect(_on_all_paths_completed)
		path_execution_manager.paths_cleared.connect(_on_paths_cleared)

	if path_drawer:
		path_drawer.mode_changed.connect(_on_path_mode_changed)
		path_drawer.vision_point_added.connect(_on_vision_point_added)
		path_drawer.run_segment_added.connect(_on_run_segment_added)

	if path_mode_controller:
		path_mode_controller.mode_started.connect(_on_path_mode_started)
		path_mode_controller.mode_ended.connect(_on_path_mode_ended)
		path_mode_controller.mode_cancelled.connect(_on_path_mode_cancelled)
		path_mode_controller.path_ready.connect(_on_path_ready)

	if marker_edit_panel:
		marker_edit_panel.character_selected.connect(_on_marker_panel_character_selected)
		marker_edit_panel.vision_add_requested.connect(_on_marker_panel_vision_add)
		marker_edit_panel.vision_undo_requested.connect(_on_marker_panel_vision_undo)
		marker_edit_panel.run_add_requested.connect(_on_marker_panel_run_add)
		marker_edit_panel.run_undo_requested.connect(_on_marker_panel_run_undo)
		marker_edit_panel.confirm_requested.connect(_on_marker_panel_confirm)
		marker_edit_panel.cancel_requested.connect(_on_marker_panel_cancel)


## ========================================
## パス操作API
## ========================================

func start_move_mode() -> bool:
	if not selection_manager or not selection_manager.has_selection():
		print("[PathService] No characters selected")
		return false

	if not path_drawer or not path_mode_controller:
		print("[PathService] PathDrawer or PathModeController not set")
		return false

	# 選択中のキャラクター配列を取得
	var selected_chars: Array[Node] = []
	for c in selection_manager.selected_characters:
		selected_chars.append(c)

	# プライマリキャラクターの色を取得
	var primary = selection_manager.primary_character
	var char_color = CharacterColorManager.get_character_color(primary)

	# パスモード開始
	if not path_mode_controller.start(primary, char_color):
		return false

	# マルチセレクトの場合
	if selected_chars.size() > 1:
		path_drawer.start_multi_character_mode(selected_chars)
		if marker_edit_panel:
			marker_edit_panel.setup(selected_chars, path_drawer)
	else:
		path_drawer.set_active_edit_character(primary)
		if marker_edit_panel:
			marker_edit_panel.setup(selected_chars, path_drawer)

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


func get_vision_point_count() -> int:
	return path_drawer.get_vision_point_count() if path_drawer else 0


func get_run_segment_count() -> int:
	return path_drawer.get_run_segment_count() if path_drawer else 0


func has_incomplete_run_start() -> bool:
	return path_drawer.has_incomplete_run_start() if path_drawer else false


func is_multi_character_mode() -> bool:
	return path_drawer.is_multi_character_mode() if path_drawer else false


func start_multi_character_mode(selected_chars: Array[Node]) -> void:
	if path_drawer:
		path_drawer.start_multi_character_mode(selected_chars)


func set_active_edit_character(character: Node) -> void:
	if path_drawer:
		path_drawer.set_active_edit_character(character)


func set_path_drawer_color(color: Color) -> void:
	if path_drawer:
		path_drawer.set_character_color(color)


## ========================================
## UI操作
## ========================================

func _show_marker_panel() -> void:
	if marker_edit_panel:
		marker_edit_panel.visible = true


func _hide_marker_panel() -> void:
	if marker_edit_panel:
		marker_edit_panel.visible = false
		marker_edit_panel.clear()


## ========================================
## シグナルハンドラ
## ========================================

func _on_path_mode_started(character: Node) -> void:
	mode_started.emit(character)


func _on_path_mode_ended() -> void:
	_hide_marker_panel()
	mode_ended.emit()


func _on_path_mode_cancelled() -> void:
	_hide_marker_panel()
	mode_cancelled.emit()


func _on_path_ready() -> void:
	# 視線ポイントモードへ移行
	if start_vision_mode():
		_show_marker_panel()
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
	if marker_edit_panel:
		marker_edit_panel.on_vision_point_added()
	vision_point_added.emit(anchor, direction)


func _on_run_segment_added(start_ratio: float, end_ratio: float) -> void:
	if marker_edit_panel:
		marker_edit_panel.on_run_segment_added()
	run_segment_added.emit(start_ratio, end_ratio)


func _on_marker_panel_character_selected(character: Node) -> void:
	var char_color = CharacterColorManager.get_character_color(character)
	set_path_drawer_color(char_color)


func _on_marker_panel_vision_add(_character: Node) -> void:
	if has_pending_path():
		start_vision_mode()


func _on_marker_panel_vision_undo(_character: Node) -> void:
	remove_last_vision_point()


func _on_marker_panel_run_add(_character: Node) -> void:
	if has_pending_path():
		start_run_mode()


func _on_marker_panel_run_undo(_character: Node) -> void:
	remove_last_run_segment()


func _on_marker_panel_confirm() -> void:
	confirm_path()


func _on_marker_panel_cancel() -> void:
	cancel_path()
