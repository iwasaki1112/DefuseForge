class_name CharacterInteractionManager
extends Node

## キャラクター操作の状態管理とワークフロー制御
## SelectionManager, ContextMenuComponent, InputRotationComponent を連携させる

enum InteractionState {
	IDLE,       ## 待機状態
	MENU_OPEN,  ## メニュー表示中
	ROTATING,   ## 回転操作中
}

signal state_changed(old_state: InteractionState, new_state: InteractionState)
signal action_started(action_id: String, character: CharacterBody3D)
signal action_completed(action_id: String, character: CharacterBody3D)

var _state: InteractionState = InteractionState.IDLE
var _selection_manager: Node = null  # SelectionManager
var _context_menu: Control = null  # ContextMenuComponent
var _input_rotation: Node = null  # InputRotationComponent (current/active)
var _primary_input_rotation: Node = null  # InputRotationComponent (from setup, first character)
var _camera: Camera3D = null
var _current_action_character: CharacterBody3D = null


func get_current_state() -> InteractionState:
	return _state


## 初期設定
func setup(
	selection_manager: Node,
	context_menu: Control,
	input_rotation: Node,
	camera: Camera3D
) -> void:
	_selection_manager = selection_manager
	_context_menu = context_menu
	_input_rotation = input_rotation
	_primary_input_rotation = input_rotation  # Store for _on_character_clicked
	_camera = camera

	# シグナル接続（単一InputRotation用、後方互換性）
	if _input_rotation and _input_rotation.has_signal("clicked"):
		_input_rotation.clicked.connect(_on_character_clicked)
	if _input_rotation and _input_rotation.has_signal("clicked_empty"):
		_input_rotation.clicked_empty.connect(_on_empty_clicked)
	if _input_rotation and _input_rotation.has_signal("rotation_ended"):
		_input_rotation.rotation_ended.connect(_on_rotation_ended)

	if _context_menu.has_signal("item_selected"):
		_context_menu.item_selected.connect(_on_menu_item_selected)
	if _context_menu.has_signal("menu_closed"):
		_context_menu.menu_closed.connect(_on_menu_closed)


## 追加のInputRotationComponentを登録（複数キャラクター対応）
func register_input_rotation(input_rotation: Node, character: CharacterBody3D) -> void:
	if input_rotation.has_signal("clicked"):
		input_rotation.clicked.connect(_on_character_clicked_for.bind(character, input_rotation))
	if input_rotation.has_signal("clicked_empty"):
		input_rotation.clicked_empty.connect(_on_empty_clicked)
	if input_rotation.has_signal("rotation_ended"):
		input_rotation.rotation_ended.connect(_on_rotation_ended)


## 特定キャラクタークリック時（register_input_rotation経由）
func _on_character_clicked_for(character: CharacterBody3D, input_rotation: Node) -> void:
	# 敵チームは選択不可
	if character is CharacterBase and PlayerManager.is_enemy_team(character.team):
		return

	_input_rotation = input_rotation  # 現在のInputRotationを記録

	# 選択してメニューを表示
	if _selection_manager:
		_selection_manager.select(character)

	# 画面座標を計算
	var screen_pos = Vector2.ZERO
	if _camera:
		screen_pos = _camera.unproject_position(character.global_position)
		screen_pos += Vector2(20, -20)

	# メニューを開く
	_context_menu.open(screen_pos, character)
	_set_state(InteractionState.MENU_OPEN)


## 状態を変更
func _set_state(new_state: InteractionState) -> void:
	if _state == new_state:
		return
	var old_state = _state
	_state = new_state
	state_changed.emit(old_state, new_state)


## 現在のアクションをキャンセル
func cancel_current_action() -> void:
	match _state:
		InteractionState.MENU_OPEN:
			_context_menu.close()
		InteractionState.ROTATING:
			if _input_rotation.has_method("stop_rotation_mode"):
				_input_rotation.stop_rotation_mode()
			if _camera:
				_camera.input_disabled = false
			action_completed.emit("rotate", _current_action_character)
			_current_action_character = null

	_set_state(InteractionState.IDLE)


## キャラクタークリック時（setup()で登録されたプライマリキャラクター用）
func _on_character_clicked() -> void:
	var character: CharacterBody3D = null

	# プライマリInputRotationの親キャラクターを取得
	if _primary_input_rotation:
		var parent = _primary_input_rotation.get_parent()
		if parent is CharacterBody3D:
			character = parent

	if not character:
		return

	# 敵チームは選択不可
	if character is CharacterBase and PlayerManager.is_enemy_team(character.team):
		return

	# 現在のInputRotationを更新
	_input_rotation = _primary_input_rotation

	# 選択してメニューを表示
	if _selection_manager:
		_selection_manager.select(character)

	# 画面座標を計算（キャラクター位置から）
	var screen_pos = Vector2.ZERO
	if _camera:
		screen_pos = _camera.unproject_position(character.global_position)
		# 少し右下にオフセット
		screen_pos += Vector2(20, -20)

	# メニューを開く
	_context_menu.open(screen_pos, character)
	_set_state(InteractionState.MENU_OPEN)


## 空きエリアクリック時
func _on_empty_clicked() -> void:
	match _state:
		InteractionState.MENU_OPEN:
			_context_menu.close()
			# 選択も解除
			if _selection_manager:
				_selection_manager.deselect()
		InteractionState.ROTATING:
			# 回転中は何もしない（回転終了を待つ）
			pass
		InteractionState.IDLE:
			# 選択解除
			if _selection_manager:
				_selection_manager.deselect()


## メニュー項目選択時
func _on_menu_item_selected(action_id: String, character: CharacterBody3D) -> void:
	_current_action_character = character

	match action_id:
		"rotate":
			_start_rotation(character)
		_:
			# 未知のアクション
			action_started.emit(action_id, character)
			_set_state(InteractionState.IDLE)


## メニューが閉じられた時
func _on_menu_closed() -> void:
	if _state == InteractionState.MENU_OPEN:
		_set_state(InteractionState.IDLE)


## 回転操作を開始
func _start_rotation(character: CharacterBody3D) -> void:
	_set_state(InteractionState.ROTATING)
	action_started.emit("rotate", character)

	# カメラ入力を無効化
	if _camera:
		_camera.input_disabled = true

	# 回転モード開始
	if _input_rotation and _input_rotation.has_method("start_rotation_mode"):
		_input_rotation.start_rotation_mode()


## 回転終了時
func _on_rotation_ended() -> void:
	if _state == InteractionState.ROTATING:
		# カメラ入力を有効化
		if _camera:
			_camera.input_disabled = false

		action_completed.emit("rotate", _current_action_character)
		_current_action_character = null
		_set_state(InteractionState.IDLE)
