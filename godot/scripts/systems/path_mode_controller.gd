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
## 延長モード用のキャラクター（選択マネージャーをバイパス）
var _extension_mode_character: Node = null


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


## 既存パスを読み込んで編集モード開始
## @param path_data: PathExecutionManagerから取得したパスデータ
## @param char_color: キャラクター色
func start_with_existing_path(path_data: Dictionary, char_color: Color = Color.WHITE) -> bool:
	if not selection_manager or not selection_manager.has_selection():
		return false

	if not path_drawer:
		return false

	if path_data.is_empty():
		return false

	# MOVEモード開始時に対象キャラクターを確定（スナップショット）
	selection_manager.capture_path_targets()

	var primary = selection_manager.primary_character
	var _target_count = selection_manager.get_path_targets().size()

	# 既存パスを復元してパス描画モードに入る
	is_active = true
	editing_character = primary
	if not path_drawer.restore_pending_path(primary, path_data):
		# 復元に失敗した場合は通常のenableにフォールバック
		path_drawer.enable(primary)
	path_drawer.set_character_color(char_color)

	mode_started.emit(primary)
	return true


## 延長モード開始（選択マネージャーをバイパス、一時的な選択リングを表示）
func start_extension_mode(character: Node, path_data: Dictionary, char_color: Color = Color.WHITE) -> bool:
	if not character or not path_drawer:
		return false
	if path_data.is_empty():
		return false

	_extension_mode_character = character

	# 一時的な選択リングを表示
	_show_temporary_outline(character)

	# パスモード開始
	is_active = true
	editing_character = character
	if not path_drawer.restore_pending_path(character, path_data):
		# 復元に失敗した場合は通常のenableにフォールバック
		path_drawer.enable(character)
	path_drawer.set_character_color(char_color)

	mode_started.emit(character)
	return true


## 一時的なアウトライン表示
func _show_temporary_outline(character: Node) -> void:
	if character.has_method("show_outline"):
		character.show_outline(true)


## 一時的なアウトラインを非表示
func _hide_temporary_outline() -> void:
	if _extension_mode_character and is_instance_valid(_extension_mode_character):
		if _extension_mode_character.has_method("show_outline"):
			_extension_mode_character.show_outline(false)


## パスモードを確定して終了
func confirm() -> bool:
	if not is_active or not path_drawer.has_pending_path():
		cancel()
		return false

	# 延長モードの場合は _extension_mode_character を使用
	var targets: Array[Node] = []
	var primary: Node = null
	if _extension_mode_character:
		targets = [_extension_mode_character]
		primary = _extension_mode_character
	else:
		targets = selection_manager.get_path_targets()
		primary = selection_manager.primary_character

	if targets.is_empty():
		cancel()
		return false

	# PathExecutionManagerに委譲
	if path_execution_manager.confirm_path(targets, path_drawer, primary):
		# 延長モードでなければ選択を解除
		var should_deselect := _extension_mode_character == null
		_cleanup()
		mode_ended.emit()

		# パス確定後は選択を解除
		if should_deselect and selection_manager:
			selection_manager.deselect_all()
		return true
	else:
		cancel()
		return false


## パスモードをキャンセル
func cancel() -> void:
	if not is_active:
		return

	# 延長モードでなければ選択を解除
	var should_deselect := _extension_mode_character == null
	_cleanup()
	mode_cancelled.emit()

	# キャンセル時も選択を解除
	if should_deselect and selection_manager:
		selection_manager.deselect_all()


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


## クリック・トゥ・コンファーム処理（パス外クリック時に確定）
func handle_click_to_confirm(clicked_character: Node) -> bool:
	if not is_active:
		return false

	# パス描画後のみ確定判定
	if path_drawer.has_pending_path():
		if not clicked_character:
			# パス外タップで確定
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
	_hide_temporary_outline()
	_extension_mode_character = null
	if selection_manager:
		selection_manager.clear_path_targets()
	if path_drawer:
		path_drawer.clear()
		path_drawer.disable()
