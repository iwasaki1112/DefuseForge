extends Node3D

## パスドロワーのテストシーン
## キャラクター選択 → コンテキストメニュー → パス描画 → 視線ポイント設定 → 実行
## Slice the Pie対応

const SelectionManagerScript = preload("res://scripts/managers/selection_manager.gd")
const ContextMenuScript = preload("res://scripts/ui/context_menu_component.gd")
const InputRotationScript = preload("res://scripts/characters/components/input_rotation_component.gd")
const InteractionManagerScript = preload("res://scripts/managers/character_interaction_manager.gd")
const ContextMenuItemScript = preload("res://scripts/resources/context_menu_item.gd")
const FogOfWarSystemScript = preload("res://scripts/systems/fog_of_war_system.gd")

## テスト状態
enum TestState { IDLE, DRAWING_MOVEMENT, SETTING_VISION, READY_TO_EXECUTE }

@onready var camera: Camera3D = $OrbitCamera
@onready var path_drawer: Node3D = $PathDrawer
@onready var execute_button: Button = $CanvasLayer/UI/ExecuteButton
@onready var point_count_label: Label = $CanvasLayer/UI/PointCountLabel
@onready var character: CharacterBody3D = $CharacterBody
@onready var canvas_layer: CanvasLayer = $CanvasLayer

var _selection_manager: Node
var _context_menu: Control
var _input_rotation: Node
var _interaction_manager: Node
var _selected_character: CharacterBody3D
var _current_state: TestState = TestState.IDLE

## 視線ポイント用UI
var _done_vision_button: Button
var _state_label: Label
var _vision_count_label: Label

## 動的メニュー項目（パス描画後に表示）
var _add_vision_item: Resource = null
var _clear_move_item: Resource = null

## Fog of War
var fog_of_war_system: Node3D = null


func _ready() -> void:
	# カメラを固定（入力無効化）
	camera.input_disabled = true

	# カメラのターゲットを設定
	if camera.has_method("set_target"):
		camera.set_target(character)

	# PathDrawerにカメラを設定
	path_drawer.setup(camera)

	# コンポーネント初期化を待つ
	await get_tree().process_frame

	# アウトラインカメラをセットアップ
	if character:
		character.setup_outline_camera(camera)
		if character.animation:
			character.animation.anim_tree.active = true
			character.animation.set_locomotion(0)

	# 選択システムをセットアップ
	_setup_selection_system()

	# 入力回転コンポーネントをセットアップ
	_setup_input_rotation()

	# コンテキストメニューをセットアップ
	_setup_context_menu()

	# インタラクションマネージャーをセットアップ
	_setup_interaction_manager()

	# 視線ポイント用UIをセットアップ
	_setup_vision_ui()

	# FoWシステムをセットアップ
	_setup_fog_of_war()

	# シグナル接続
	path_drawer.drawing_started.connect(_on_drawing_started)
	path_drawer.drawing_updated.connect(_on_drawing_updated)
	path_drawer.drawing_finished.connect(_on_drawing_finished)
	path_drawer.vision_point_added.connect(_on_vision_point_added)
	path_drawer.path_execution_completed.connect(_on_path_execution_completed)
	execute_button.pressed.connect(_on_execute_pressed)

	# シーンのClearButtonを非表示（コンテキストメニューに移動したため）
	var clear_btn = get_node_or_null("CanvasLayer/UI/ClearButton")
	if clear_btn:
		clear_btn.hide()

	print("[TestPathDrawer] Ready - Click character, select 'Move' from menu")


func _setup_selection_system() -> void:
	_selection_manager = SelectionManagerScript.new()
	_selection_manager.selection_changed.connect(_on_selection_changed)
	add_child(_selection_manager)


func _setup_input_rotation() -> void:
	_input_rotation = InputRotationScript.new()
	_input_rotation.require_menu_activation = true
	character.add_child(_input_rotation)
	_input_rotation.setup(camera)


func _setup_context_menu() -> void:
	_context_menu = ContextMenuScript.new()
	canvas_layer.add_child(_context_menu)
	_context_menu.setup_default_items()


func _setup_interaction_manager() -> void:
	_interaction_manager = InteractionManagerScript.new()
	add_child(_interaction_manager)

	_interaction_manager.setup(
		_selection_manager,
		_context_menu,
		_input_rotation,
		camera
	)

	_interaction_manager.action_started.connect(_on_action_started)


func _setup_vision_ui() -> void:
	var ui_container = $CanvasLayer/UI

	# 状態ラベル
	_state_label = Label.new()
	_state_label.name = "StateLabel"
	_state_label.text = "State: IDLE"
	_state_label.position = Vector2(10, 80)
	ui_container.add_child(_state_label)

	# 視線ポイント数ラベル
	_vision_count_label = Label.new()
	_vision_count_label.name = "VisionCountLabel"
	_vision_count_label.text = "Vision Points: 0"
	_vision_count_label.position = Vector2(10, 100)
	ui_container.add_child(_vision_count_label)

	# Done Vision ボタン（視線モード中に表示）
	_done_vision_button = Button.new()
	_done_vision_button.name = "DoneVisionButton"
	_done_vision_button.text = "Done"
	_done_vision_button.position = Vector2(10, 130)
	_done_vision_button.size = Vector2(80, 30)
	_done_vision_button.disabled = true
	_done_vision_button.pressed.connect(_on_done_vision_pressed)
	ui_container.add_child(_done_vision_button)


func _setup_fog_of_war() -> void:
	# FogOfWarSystemを作成
	fog_of_war_system = Node3D.new()
	fog_of_war_system.set_script(FogOfWarSystemScript)
	fog_of_war_system.name = "FogOfWarSystem"
	add_child(fog_of_war_system)

	# キャラクターの視界を登録（1フレーム待つ）
	await get_tree().process_frame
	if character and character.vision and PlayerManager.is_player_team(character.team):
		fog_of_war_system.register_vision(character.vision)
		print("[TestPathDrawer] Vision registered with FoW system")


func _set_state(new_state: TestState) -> void:
	_current_state = new_state
	var state_names = ["IDLE", "DRAWING_MOVEMENT", "SETTING_VISION", "READY_TO_EXECUTE"]
	_state_label.text = "State: %s" % state_names[new_state]
	_update_ui_for_state()


func _update_ui_for_state() -> void:
	match _current_state:
		TestState.IDLE:
			execute_button.disabled = true
			_done_vision_button.disabled = true
			_remove_add_vision_menu()
			_remove_clear_move_menu()
		TestState.DRAWING_MOVEMENT:
			execute_button.disabled = true
			_done_vision_button.disabled = true
			_remove_add_vision_menu()
			_remove_clear_move_menu()
		TestState.SETTING_VISION:
			execute_button.disabled = true
			_done_vision_button.disabled = false
			_remove_add_vision_menu()  # 視線モード中はメニューから削除
			_add_clear_move_menu()  # Clear Moveは表示
		TestState.READY_TO_EXECUTE:
			execute_button.disabled = false
			_done_vision_button.disabled = true
			_add_add_vision_menu()  # パス完了後にメニューに追加
			_add_clear_move_menu()  # Clear Moveも追加

	_update_vision_count()


func _update_vision_count() -> void:
	_vision_count_label.text = "Vision Points: %d" % path_drawer.get_vision_point_count()


## Add Visionメニュー項目を追加（Controlの直後に表示）
func _add_add_vision_menu() -> void:
	if _add_vision_item != null:
		return  # 既に追加済み
	# order=3でControlの直後に配置（Move=0, Rotate=1, Control=2）
	_add_vision_item = ContextMenuItemScript.create("add_vision", "Add Vision", 3)
	_context_menu.add_item(_add_vision_item)


## Add Visionメニュー項目を削除
func _remove_add_vision_menu() -> void:
	if _add_vision_item == null:
		return  # 未追加
	_context_menu.remove_item("add_vision")
	_add_vision_item = null


## Clear Moveメニュー項目を追加（Add Visionの直後に表示）
func _add_clear_move_menu() -> void:
	if _clear_move_item != null:
		return  # 既に追加済み
	# order=4でAdd Visionの直後に配置
	_clear_move_item = ContextMenuItemScript.create("clear_move", "Clear Move", 4)
	_context_menu.add_item(_clear_move_item)


## Clear Moveメニュー項目を削除
func _remove_clear_move_menu() -> void:
	if _clear_move_item == null:
		return  # 未追加
	_context_menu.remove_item("clear_move")
	_clear_move_item = null


func _on_selection_changed(selected: CharacterBody3D) -> void:
	_selected_character = selected
	if selected:
		print("[TestPathDrawer] Character selected")
	else:
		print("[TestPathDrawer] Selection cleared")


func _on_action_started(action_id: String, action_character: CharacterBody3D) -> void:
	match action_id:
		"move":
			path_drawer.enable(action_character)
			_set_state(TestState.DRAWING_MOVEMENT)
			print("[TestPathDrawer] Move selected - draw a movement path")
		"add_vision":
			_on_add_vision_selected()
		"clear_move":
			_on_clear_move_selected()


func _on_drawing_started() -> void:
	point_count_label.text = "Path: 1"


func _on_drawing_updated(points: PackedVector3Array) -> void:
	point_count_label.text = "Path: %d" % points.size()


func _on_drawing_finished(points: PackedVector3Array) -> void:
	print("[TestPathDrawer] Movement path completed with %d points" % points.size())
	path_drawer.disable()

	if path_drawer.has_pending_path():
		_set_state(TestState.READY_TO_EXECUTE)
		print("[TestPathDrawer] Path ready. Click 'Add Vision' to set look directions, or 'Execute' to start.")


func _on_vision_point_added(_anchor: Vector3, _direction: Vector3) -> void:
	_update_vision_count()
	print("[TestPathDrawer] Vision point added. Total: %d" % path_drawer.get_vision_point_count())


func _on_add_vision_selected() -> void:
	if path_drawer.start_vision_mode():
		_set_state(TestState.SETTING_VISION)
		print("[TestPathDrawer] Click on path and drag to set look direction")


func _on_done_vision_pressed() -> void:
	path_drawer.disable()
	_set_state(TestState.READY_TO_EXECUTE)
	print("[TestPathDrawer] Vision setup done. Press Execute to start.")


func _on_clear_move_selected() -> void:
	path_drawer.clear()
	path_drawer.clear_pending()
	point_count_label.text = "Path: 0"
	_set_state(TestState.IDLE)
	print("[TestPathDrawer] Move path cleared")


func _on_execute_pressed() -> void:
	if path_drawer.execute_with_vision(false):
		_set_state(TestState.IDLE)
		var vision_count = path_drawer.get_vision_point_count()
		print("[TestPathDrawer] Movement started with %d vision points" % vision_count)


func _on_path_execution_completed(_completed_character: CharacterBody3D) -> void:
	_set_state(TestState.IDLE)
	print("[TestPathDrawer] Movement completed")
