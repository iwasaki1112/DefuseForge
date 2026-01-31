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
signal wait_point_added(path_ratio: float, wait_duration: float)

var path_drawer: PathDrawer = null
var selection_manager: CharacterSelectionManager = null
var path_execution_manager: PathExecutionManager = null
var path_mode_controller: PathModeController = null

## 継続モードフラグ（既存パスの終点からパスを継続する場合にtrue）
var _is_continuation_mode: bool = false
## 移動中パス継続フラグ（移動中キャラクターのパスを継続する場合にtrue）
var _is_moving_path_continuation: bool = false
## 移動中パス継続対象キャラクター
var _moving_continuation_character: Node = null


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
		path_drawer.wait_point_added.connect(_on_wait_point_added)
		path_drawer.path_undone.connect(_on_path_undone)
		path_drawer.off_path_tapped.connect(_on_off_path_tapped)
		# リアルタイム確定：パス開始時とポイント追加時に即座に反映
		path_drawer.path_started.connect(_on_path_started)
		path_drawer.path_point_added.connect(_on_path_point_added)

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

	# プライマリキャラクターの色を取得
	var primary = selection_manager.primary_character
	var char_color = CharacterColorManager.get_character_color(primary)

	# 既存の確定済みパスがある場合、削除して新規パスとして開始
	if path_execution_manager and path_execution_manager.has_pending_path_for_character(primary):
		path_execution_manager.clear_pending_path_for_character(primary)

	# パスモード開始（常に新規）
	var started := path_mode_controller.start(primary, char_color)
	if not started:
		return false

	# シングルキャラクターのみサポート
	path_drawer.set_active_edit_character(primary)

	return true


func start_path_mode(primary: Node, char_color: Color = Color.WHITE) -> bool:
	if not path_mode_controller:
		return false
	return path_mode_controller.start(primary, char_color)


## 特定の位置からパスモードを開始（パス継続用）
## @param character: 対象キャラクター
## @param start_point: 開始位置
## @param char_color: キャラクター色
## @param is_moving_path: 移動中パスの継続かどうか
func start_path_mode_from_point(character: Node, start_point: Vector3, char_color: Color = Color.WHITE, is_moving_path: bool = false) -> bool:
	if not path_mode_controller or not path_drawer:
		return false

	# 継続モードを有効化（既存パスを維持）
	_is_continuation_mode = true
	_is_moving_path_continuation = is_moving_path
	_moving_continuation_character = character if is_moving_path else null

	# キャラクターを選択状態にする
	if selection_manager:
		selection_manager.deselect_all()
		selection_manager.add_to_selection(character)
		selection_manager.capture_path_targets()

	# パスモードを有効化（開始点を指定）
	path_mode_controller.is_active = true
	path_mode_controller.editing_character = character
	path_drawer.enable_from_point(character as Node3D, start_point)
	path_drawer.set_character_color(char_color)
	path_drawer.set_active_edit_character(character)

	# 移動中パス継続モードの場合、PathDrawerのメッシュを非表示にする
	# （PathExecutionManagerのメッシュがリアルタイムで更新されるのでそちらを使う）
	if is_moving_path and path_drawer:
		path_drawer.hide_path_mesh()

	path_mode_controller.mode_started.emit(character)
	return true


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


func has_path() -> bool:
	return path_drawer and path_drawer.has_path()


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


func handle_click_to_confirm(clicked_character: Node) -> bool:
	if not path_mode_controller:
		return false
	return path_mode_controller.handle_click_to_confirm(clicked_character)


func is_point_mode() -> bool:
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


func start_wait_mode() -> void:
	if path_drawer:
		path_drawer.start_wait_mode()


func get_wait_point_count() -> int:
	return path_drawer.get_wait_point_count() if path_drawer else 0


## 最後に追加したポイントを削除（統一Undo）
func undo_last_point() -> void:
	if path_drawer:
		path_drawer.undo_last_point()


func get_vision_point_count() -> int:
	return path_drawer.get_vision_point_count() if path_drawer else 0


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
	_cleanup_moving_continuation()
	_is_continuation_mode = false
	_is_moving_path_continuation = false
	_moving_continuation_character = null
	mode_ended.emit()


func _on_path_mode_cancelled() -> void:
	_cleanup_moving_continuation(true)  # キャンセル時は元のメッシュを再表示
	_is_continuation_mode = false
	_is_moving_path_continuation = false
	_moving_continuation_character = null
	mode_cancelled.emit()


func _on_path_ready() -> void:
	# 新設計：パスはドラッグ終了時に自動確定されるため、
	# Visionモードへの自動移行は行わない
	# ユーザーが必要に応じて手動でVisionモードに入る
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


func _on_wait_point_added(path_ratio: float, wait_duration: float) -> void:
	wait_point_added.emit(path_ratio, wait_duration)


func _on_path_undone() -> void:
	# パスがUndoされたらパスモードは維持して再度パスを描けるようにする
	if path_drawer and selection_manager and selection_manager.has_selection():
		var primary = selection_manager.primary_character
		if primary:
			path_drawer.enable(primary)


func _on_off_path_tapped() -> void:
	# パス外タップでモードを終了（パスは既に確定済み）
	confirm_path()


## パス開始シグナルハンドラ（リアルタイム確定）
func _on_path_started(character: Node, start_point: Vector3) -> void:
	if not path_execution_manager:
		return

	# 移動中パス継続モードの場合は何もしない（パスは既にコントローラーに存在）
	if _is_moving_path_continuation:
		_is_continuation_mode = false  # フラグをリセット
		return

	# 継続モードの場合は既存パスを維持
	var is_continuation := _is_continuation_mode
	_is_continuation_mode = false  # フラグをリセット
	path_execution_manager.start_realtime_path(character, start_point, is_continuation)


## 移動中パス継続モードのクリーンアップ
func _cleanup_moving_continuation(_is_cancel: bool = false) -> void:
	# 特に何もしない（PathExecutionManagerのメッシュがそのまま使われる）
	pass


## パスポイント追加シグナルハンドラ（リアルタイム確定）
func _on_path_point_added(character: Node, point: Vector3) -> void:
	if not path_execution_manager:
		return

	# 移動中パス継続モードの場合は移動中パスに追加
	if _is_moving_path_continuation and _moving_continuation_character == character:
		path_execution_manager.add_point_to_moving_path(character, point)
	else:
		path_execution_manager.add_realtime_path_point(character, point)
