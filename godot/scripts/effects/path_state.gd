class_name PathState
extends RefCounted

## パス状態管理クラス
## PathDrawerの状態変数を一元管理する


## 描画状態
enum State {
	IDLE,            ## 待機状態
	DRAWING,         ## パス描画中
	EXTENDING,       ## パス継続描画中
	MARKER_EDIT      ## マーカー編集中（Vision等）
}


## 描画モード（PathDrawer.DrawingModeと同等）
enum DrawingMode {
	MOVEMENT,
	VISION_POINT,
	RUN_MARKER,
	CLEAR_MARKER,
	GRENADE_MARKER,
	DOOR_MARKER,
	WAIT_MARKER,
	SMOKE_GRENADE_MARKER
}


## 現在の状態
var state: State = State.IDLE

## 描画モード
var drawing_mode: DrawingMode = DrawingMode.MOVEMENT

## 有効状態
var is_enabled: bool = false

## 描画中フラグ
var is_drawing: bool = false

## 継続描画中フラグ
var is_extending_path: bool = false

## Vision描画中フラグ
var is_drawing_vision: bool = false

## アクティブキャラクター
var active_character: Node3D = null

## 編集対象キャラクター
var active_edit_character: Node = null

## 保留中パス
var pending_path: PackedVector3Array = PackedVector3Array()

## 保留中キャラクター
var pending_character: CharacterBody3D = null

## 実行中キャラクター
var executing_character: CharacterBody3D = null

## キャラクター色
var character_color: Color = Color(1.0, 1.0, 1.0)


## 状態をリセット
func reset() -> void:
	state = State.IDLE
	drawing_mode = DrawingMode.MOVEMENT
	is_enabled = false
	is_drawing = false
	is_extending_path = false
	is_drawing_vision = false
	pending_path.clear()
	pending_character = null
	executing_character = null


## 描画開始
func start_drawing() -> void:
	state = State.DRAWING
	is_drawing = true


## 描画終了
func finish_drawing() -> void:
	state = State.IDLE if drawing_mode == DrawingMode.MOVEMENT else State.MARKER_EDIT
	is_drawing = false


## 継続描画開始
func start_extending() -> void:
	state = State.EXTENDING
	is_extending_path = true


## 継続描画終了
func finish_extending() -> void:
	state = State.IDLE if drawing_mode == DrawingMode.MOVEMENT else State.MARKER_EDIT
	is_extending_path = false


## Vision描画開始
func start_vision_drawing() -> void:
	state = State.MARKER_EDIT
	is_drawing_vision = true


## Vision描画終了
func finish_vision_drawing() -> void:
	is_drawing_vision = false


## マーカーモードに切り替え
func set_marker_mode(mode: DrawingMode) -> void:
	drawing_mode = mode
	if mode != DrawingMode.MOVEMENT:
		state = State.MARKER_EDIT


## 移動モードに戻す
func set_movement_mode() -> void:
	drawing_mode = DrawingMode.MOVEMENT
	state = State.IDLE


## 何らかの描画中か
func is_any_drawing() -> bool:
	return is_drawing or is_drawing_vision or is_extending_path


## マーカーモードか
func is_marker_mode() -> bool:
	return drawing_mode != DrawingMode.MOVEMENT


## 保留中パスがあるか
func has_pending_path() -> bool:
	return pending_path.size() >= 2 and pending_character != null


## プレビュー用パスがあるか（描画中/拡張中/確定済みを含む）
func has_preview_path() -> bool:
	if is_drawing or is_extending_path:
		return active_character != null
	return has_pending_path()
