extends Node
class_name PathModeController
## パスモード制御
## パス描画モードの状態管理を担当

## デバッグログ出力フラグ（運用時はfalseに設定）
const DEBUG_PATH: bool = false

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
func start(_character: Node, char_color: Color = Color.WHITE) -> bool:
	if not selection_manager or not selection_manager.has_selection():
		return false

	if not path_drawer:
		return false

	# MOVEモード開始時に対象キャラクターを確定（スナップショット）
	selection_manager.capture_path_targets()

	var primary = selection_manager.primary_character
	var _target_count = selection_manager.get_path_targets().size()

	# プライマリキャラクターを基準にパス描画
	is_active = true
	editing_character = primary
	path_drawer.enable(primary)
	path_drawer.set_character_color(char_color)

	mode_started.emit(primary)
	return true


## パスモードを終了（パスはリアルタイムで確定済み）
## このメソッドはモードの終了処理のみを行う
func confirm() -> bool:
	if not is_active:
		if DEBUG_PATH:
			if Debug.enabled: print("[PointDebug] PathModeController.confirm: not active")
		return false

	if DEBUG_PATH:
		# スタックトレースを出力して呼び出し元を特定
		var stack = get_stack()
		if Debug.enabled: print("[PointDebug] PathModeController.confirm: ending mode, called from:")
		for i in range(min(stack.size(), 5)):
			var frame = stack[i]
			if Debug.enabled: print("  [%d] %s:%d in %s" % [i, frame.source, frame.line, frame.function])
	_cleanup()
	mode_ended.emit()

	# モード終了後は選択を解除
	if selection_manager:
		selection_manager.deselect_all()
	return true


## パスモードをキャンセル
func cancel() -> void:
	if not is_active:
		if DEBUG_PATH:
			if Debug.enabled: print("[PointDebug] PathModeController.cancel: not active")
		return

	if DEBUG_PATH:
		if Debug.enabled: print("[PointDebug] PathModeController.cancel: cancelling")
	_cleanup()
	mode_cancelled.emit()

	# キャンセル時も選択を解除
	if selection_manager:
		selection_manager.deselect_all()


## パスモード中かどうか
func is_path_mode() -> bool:
	return is_active


## パスがあるかどうか
func has_path() -> bool:
	return is_active and path_drawer and path_drawer.has_path()


## 編集中キャラクターを取得
func get_editing_character() -> Node:
	return editing_character


## 対象キャラクター数を取得
func get_target_count() -> int:
	if not selection_manager:
		return 0
	return selection_manager.get_path_targets().size()


## クリック・トゥ・コンファーム処理（パス外クリック時にモード終了）
func handle_click_to_confirm(clicked_character: Node) -> bool:
	if not is_active:
		return false

	# パスがある場合のみモード終了判定
	if path_drawer.has_path():
		if not clicked_character:
			# パス外タップでモード終了
			confirm()
			return true

	return false


## パス描画完了時
func _on_drawing_finished(points: PackedVector3Array) -> void:
	if points.size() < 2:
		cancel()
		return

	path_ready.emit()


## クリーンアップ処理
func _cleanup() -> void:
	is_active = false
	editing_character = null
	if selection_manager:
		selection_manager.clear_path_targets()
	if path_drawer:
		path_drawer.clear()
		path_drawer.disable()
