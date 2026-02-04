class_name GameHUD
extends Control
## ゲーム画面の操作パネルUI
##
## シーンファイル: res://scenes/ui/game_hud.tscn

signal execute_all_requested()
signal clear_paths_requested()
signal character_marker_pressed(character: Node)
signal point_edit_requested(action: String)
signal point_undo_requested()
signal point_cancel_requested()
signal sync_go_requested()  ## W解放ボタン押下

const TIMER_WARNING_THRESHOLD := 10.0
const TIMER_WARNING_COLOR := Color(1.0, 0.3, 0.3)
const TIMER_NORMAL_COLOR := Color.WHITE
const POINT_DEAD_ALPHA := 0.3

@onready var _pending_paths_label: Label = $ControlPanel/PendingPathsLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _money_label: Label = %MoneyLabel
@onready var _execute_button: TextureButton = %ExecuteButton
@onready var _sync_go_button: Button = %SyncGoButton
@warning_ignore("unused_private_class_variable")
@onready var _character_markers: HBoxContainer = %CharacterMarkers
@onready var _point_alpha: TextureButton = %MarkerAlpha
@onready var _point_bravo: TextureButton = %MarkerBravo
@onready var _point_ares: TextureButton = %MarkerAres
@onready var _point_brim: TextureButton = %MarkerBrim

## ポイントエディットパネル
@onready var _point_edit_panel: Control = %MarkerEditPanel
@onready var _vision_button: TextureButton = %VisionButton
@onready var _wait_button: TextureButton = %WaitButton

## アクティブボタンの色
const BUTTON_ACTIVE_COLOR := Color(0.5, 1.0, 0.5, 1.0)
const BUTTON_NORMAL_COLOR := Color(1.0, 1.0, 1.0, 1.0)

## アクション名とボタンのマッピング
var _action_to_button: Dictionary = {}
## 現在アクティブなアクション
var _active_action: String = ""

## マーカー名とキャラクターのマッピング
var _marker_to_character: Dictionary = {}
## マーカー名とマーカーボタンのマッピング
var _name_to_marker: Dictionary = {}


func setup() -> void:
	_setup_character_markers()
	_setup_point_edit_buttons()


func set_pending_paths(count: int) -> void:
	if _pending_paths_label:
		_pending_paths_label.text = "Pending: %d paths" % count


## 所持金表示を更新
func update_money(amount: int) -> void:
	if _money_label:
		_money_label.text = "$%s" % _format_with_commas(amount)


## 数値をカンマ区切りでフォーマット
func _format_with_commas(value: int) -> String:
	var str_value := str(absi(value))
	var result := ""
	var count := 0
	for i in range(str_value.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_value[i] + result
		count += 1
	return "-" + result if value < 0 else result


## タイマーを更新
func update_timer(remaining: float) -> void:
	if not _timer_label:
		return
	var total_seconds := int(remaining)
	@warning_ignore("integer_division")
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	_timer_label.text = "%d:%02d" % [minutes, seconds]

	if remaining <= TIMER_WARNING_THRESHOLD:
		_timer_label.add_theme_color_override("font_color", TIMER_WARNING_COLOR)
	else:
		_timer_label.add_theme_color_override("font_color", TIMER_NORMAL_COLOR)


func _on_execute_pressed() -> void:
	_play_button_press_animation()
	execute_all_requested.emit()


## ボタン押下時のアニメーション演出
func _play_button_press_animation() -> void:
	if not _execute_button:
		return

	# 既存のTweenをキャンセル
	var tween := create_tween()
	tween.set_parallel(true)

	# 拡大→縮小アニメーション
	_execute_button.pivot_offset = _execute_button.size / 2
	tween.tween_property(_execute_button, "scale", Vector2(1.15, 1.15), 0.08).set_ease(Tween.EASE_OUT)

	# 透明度アニメーション（少し透明→不透明）
	_execute_button.modulate.a = 0.7
	tween.tween_property(_execute_button, "modulate:a", 1.0, 0.08).set_ease(Tween.EASE_OUT)

	# 縮小アニメーション（元に戻る）
	tween.chain().tween_property(_execute_button, "scale", Vector2(1.0, 1.0), 0.1).set_ease(Tween.EASE_IN_OUT)


func _on_clear_pressed() -> void:
	clear_paths_requested.emit()


## ========================================
## キャラクターポイントAPI
## ========================================

## ポイントの初期設定
func _setup_character_markers() -> void:
	_name_to_marker = {
		"alpha": _point_alpha,
		"bravo": _point_bravo,
		"ares": _point_ares,
		"brim": _point_brim,
	}
	# 全ポイントを初期状態でリセット（登録時に表示される）
	for point in _name_to_marker.values():
		if point:
			point.visible = false
			point.modulate.a = 1.0
	if Debug.enabled: print("[GameHUD] Character points setup complete")


## キャラクターをポイントに登録（marker_nameで指定）
func register_character_marker(character: GameCharacter) -> void:
	if not character or character.marker_name.is_empty():
		if Debug.enabled: print("[GameHUD] register_character_marker: skipped (no character or empty marker_name)")
		return

	var point_name := character.marker_name
	if Debug.enabled: print("[GameHUD] Registering point: %s" % point_name)
	if not _name_to_marker.has(point_name):
		push_warning("[GameHUD] Unknown point name: %s" % point_name)
		return

	var point: TextureButton = _name_to_marker[point_name]
	if not point:
		return

	# マッピングを保存
	_marker_to_character[point_name] = character

	# ポイントを表示
	point.visible = true
	point.modulate.a = 1.0

	# キャラクターの死亡シグナルを接続
	if not character.died.is_connected(_on_character_died):
		character.died.connect(_on_character_died)


## 全キャラクターのポイントをクリア
func clear_character_points() -> void:
	_marker_to_character.clear()
	for point_name in _name_to_marker.keys():
		var point: TextureButton = _name_to_marker[point_name]
		if point:
			point.visible = false
			point.modulate.a = 1.0


## キャラクター死亡時のコールバック
func _on_character_died(character: GameCharacter) -> void:
	# 該当するポイントを探して透明化
	for point_name in _marker_to_character.keys():
		if _marker_to_character[point_name] == character:
			var point: TextureButton = _name_to_marker.get(point_name)
			if point:
				_animate_point_death(point)
			break


## ポイント死亡アニメーション
func _animate_point_death(point: TextureButton) -> void:
	var tween := create_tween()
	tween.tween_property(point, "modulate:a", POINT_DEAD_ALPHA, 0.3).set_ease(Tween.EASE_OUT)


## ポイントクリック時のコールバック
func _on_marker_pressed(point_name: String) -> void:
	if _marker_to_character.has(point_name):
		var character: Node = _marker_to_character[point_name]
		if is_instance_valid(character):
			character_marker_pressed.emit(character)


## ========================================
## ポイントエディットパネルAPI
## ========================================

## ポイントエディットボタンの初期設定
func _setup_point_edit_buttons() -> void:
	_action_to_button = {
		"vision": _vision_button,
		"wait": _wait_button,
	}


## ポイントエディットパネルを表示
## NOTE: 一時的に無効化（入力の邪魔になっている可能性のため）
func show_point_edit_panel() -> void:
	pass  # 一時的に無効化
	#if _point_edit_panel:
	#	_point_edit_panel.visible = true
	#	_reset_point_edit_buttons()


## ポイントエディットパネルを非表示
func hide_point_edit_panel() -> void:
	if _point_edit_panel:
		_point_edit_panel.visible = false
		_reset_point_edit_buttons()


## ポイントエディットパネルの表示状態を取得
func is_point_edit_panel_visible() -> bool:
	return _point_edit_panel and _point_edit_panel.visible


## ポイントエディットボタン押下時のコールバック
func _on_point_edit_pressed(action: String) -> void:
	_set_active_point_edit_button(action)
	point_edit_requested.emit(action)


## アクティブなボタンを設定
func _set_active_point_edit_button(action: String) -> void:
	# 前のアクティブボタンをリセット
	if _active_action != "" and _action_to_button.has(_active_action):
		var prev_button: TextureButton = _action_to_button[_active_action]
		if prev_button:
			prev_button.modulate = BUTTON_NORMAL_COLOR

	# 新しいアクティブボタンを設定
	_active_action = action
	if _action_to_button.has(action):
		var button: TextureButton = _action_to_button[action]
		if button:
			button.modulate = BUTTON_ACTIVE_COLOR


## 全ポイントエディットボタンをリセット
func _reset_point_edit_buttons() -> void:
	_active_action = ""
	for button in _action_to_button.values():
		if button:
			button.modulate = BUTTON_NORMAL_COLOR


## Undoボタン押下時のコールバック
func _on_point_undo_pressed() -> void:
	point_undo_requested.emit()


## Cancelボタン押下時のコールバック
func _on_point_cancel_pressed() -> void:
	point_cancel_requested.emit()


## ========================================
## 同期待機解放ボタンAPI
## ========================================

## W解放ボタン押下時のコールバック
func _on_sync_go_pressed() -> void:
	sync_go_requested.emit()


## W解放ボタンを表示
func show_sync_go_button() -> void:
	if _sync_go_button:
		_sync_go_button.visible = true


## W解放ボタンを非表示
func hide_sync_go_button() -> void:
	if _sync_go_button:
		_sync_go_button.visible = false


## W解放ボタンの表示状態を設定
## @param has_waiting: 同期待機中のキャラクターがいるか
func update_sync_go_button_visibility(has_waiting: bool) -> void:
	if _sync_go_button:
		_sync_go_button.visible = has_waiting
