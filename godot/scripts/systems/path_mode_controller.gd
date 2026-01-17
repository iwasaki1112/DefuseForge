extends Node
class_name PathModeController
## パスモード制御
## パス描画モードの状態管理を担当

## パスモード開始時のシグナル
signal mode_started(character: Node)
## パスモード終了時のシグナル
signal mode_ended()
## パスモードキャンセル時のシグナル
signal mode_cancelled()
## パス描画完了時（確定可能状態）
signal path_ready()

## パス描画モード中
var is_active: bool = false
## 現在パスを編集中のキャラクター
var editing_character: Node = null
## PathDrawerへの参照
var path_drawer: Node3D = null
## CharacterSelectionManagerへの参照
var selection_manager: CharacterSelectionManager = null
## PathExecutionManagerへの参照
var path_execution_manager: PathExecutionManager = null


## セットアップ
func setup(
	drawer: Node3D,
	sel_manager: CharacterSelectionManager,
	exec_manager: PathExecutionManager
) -> void:
	path_drawer = drawer
	selection_manager = sel_manager
	path_execution_manager = exec_manager

	# PathDrawerのシグナルを接続
	if path_drawer:
		path_drawer.drawing_finished.connect(_on_drawing_finished)


## パスモード開始（選択中キャラクターを対象）
func start(character: Node, char_color: Color = Color.WHITE) -> bool:
	if not selection_manager or not selection_manager.has_selection():
		print("[PathMode] No characters selected")
		return false

	if not path_drawer:
		print("[PathMode] PathDrawer not set")
		return false

	# MOVEモード開始時に対象キャラクターを確定（スナップショット）
	selection_manager.capture_path_targets()

	var primary = selection_manager.primary_character
	var target_count = selection_manager.get_path_targets().size()

	# プライマリキャラクターを基準にパス描画
	is_active = true
	editing_character = primary
	path_drawer.enable(primary)
	path_drawer.set_character_color(char_color)

	mode_started.emit(primary)
	print("[PathMode] Started for %d characters (primary: %s)" % [target_count, primary.name])
	return true


## パスモードを確定して終了
func confirm() -> bool:
	if not is_active or not path_drawer.has_pending_path():
		cancel()
		return false

	var targets = selection_manager.get_path_targets()
	if targets.is_empty():
		print("[PathMode] No target characters for path")
		cancel()
		return false

	# PathExecutionManagerに委譲
	var primary = selection_manager.primary_character
	if path_execution_manager.confirm_path(targets, path_drawer, primary):
		_cleanup()
		mode_ended.emit()

		# パス確定後は選択を解除
		selection_manager.deselect_all()
		return true
	else:
		cancel()
		return false


## パスモードをキャンセル
func cancel() -> void:
	if not is_active:
		return

	_cleanup()
	mode_cancelled.emit()
	print("[PathMode] Cancelled")


## パスモード中かどうか
func is_path_mode() -> bool:
	return is_active


## パス描画後かどうか（確定可能状態）
func has_pending_path() -> bool:
	return is_active and path_drawer and path_drawer.has_pending_path()


## 編集中キャラクターを取得
func get_editing_character() -> Node:
	return editing_character


## 対象キャラクター数を取得
func get_target_count() -> int:
	if not selection_manager:
		return 0
	return selection_manager.get_path_targets().size()


## クリック・トゥ・キャンセル処理（キャラクター以外クリック時）
func handle_click_to_cancel(clicked_character: Node) -> bool:
	if not is_active:
		return false

	# パス描画後のみキャンセル判定
	if path_drawer.has_pending_path():
		if not clicked_character:
			cancel()
			return true

	return false


## パス描画完了時
func _on_drawing_finished(points: PackedVector3Array) -> void:
	if points.size() < 2:
		cancel()
		return

	print("[PathMode] Path drawn with %d points" % points.size())
	path_ready.emit()


## クリーンアップ処理
func _cleanup() -> void:
	is_active = false
	editing_character = null
	selection_manager.clear_path_targets()
	if path_drawer:
		path_drawer.clear()
		path_drawer.disable()
