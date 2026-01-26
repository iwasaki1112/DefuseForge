class_name PathInputHandler
extends RefCounted

## パス入力ハンドラ
## PathDrawerの入力処理を統括し、適切なマーカーハンドラに委譲する


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


## PathDrawerへの参照
var _path_drawer: Node3D = null

## マーカーハンドラ辞書
var _handlers: Dictionary = {}


## 初期化
func setup(path_drawer: Node3D, camera: Camera3D) -> void:
	_path_drawer = path_drawer

	# 各マーカーハンドラを初期化
	_handlers[DrawingMode.VISION_POINT] = VisionMarkerHandler.new()
	_handlers[DrawingMode.RUN_MARKER] = RunMarkerHandler.new()
	_handlers[DrawingMode.CLEAR_MARKER] = ClearMarkerHandler.new()
	_handlers[DrawingMode.GRENADE_MARKER] = GrenadeMarkerHandler.new()
	_handlers[DrawingMode.SMOKE_GRENADE_MARKER] = SmokeGrenadeMarkerHandler.new()
	_handlers[DrawingMode.DOOR_MARKER] = DoorMarkerHandler.new()
	_handlers[DrawingMode.WAIT_MARKER] = WaitMarkerHandler.new()

	# 各ハンドラをセットアップ
	for handler in _handlers.values():
		handler.setup(path_drawer, camera)


## キャラクター色を全ハンドラに設定
func set_character_color(color: Color) -> void:
	for handler in _handlers.values():
		handler.set_character_color(color)


## 指定モードのハンドラを取得
func get_handler(mode: DrawingMode) -> MarkerHandlerBase:
	return _handlers.get(mode, null)


## 指定モードの入力を処理
## @return: 入力を処理した場合true
func handle_input(event: InputEvent, mode: DrawingMode) -> bool:
	var handler = get_handler(mode)
	if handler:
		return handler.handle_input(event)
	return false


## 全ハンドラをクリア
func clear_all() -> void:
	for handler in _handlers.values():
		handler.clear_all()


## 全ハンドラの状態をリセット
func reset_all_states() -> void:
	for handler in _handlers.values():
		handler.reset_state()


#region マーカー取得API

## 視線ポイントがあるか
func has_vision_points() -> bool:
	var handler = get_handler(DrawingMode.VISION_POINT)
	return handler and handler.has_markers()


## 視線ポイントを取得
func get_vision_points() -> Array[Dictionary]:
	var handler = get_handler(DrawingMode.VISION_POINT)
	if handler:
		return handler.get_markers()
	return []


## 視線マーカーを移譲
func take_vision_markers() -> Array[MeshInstance3D]:
	var handler = get_handler(DrawingMode.VISION_POINT)
	if handler:
		return handler.take_markers()
	return []


## Run区間があるか
func has_run_segments() -> bool:
	var handler = get_handler(DrawingMode.RUN_MARKER)
	return handler and handler.has_markers()


## Run区間を取得
func get_run_segments() -> Array[Dictionary]:
	var handler = get_handler(DrawingMode.RUN_MARKER)
	if handler:
		return handler.get_markers()
	return []


## Runマーカーを移譲
func take_run_markers() -> Array[MeshInstance3D]:
	var handler = get_handler(DrawingMode.RUN_MARKER)
	if handler:
		return handler.take_markers()
	return []


## Clearポイントがあるか
func has_clear_points() -> bool:
	var handler = get_handler(DrawingMode.CLEAR_MARKER)
	return handler and handler.has_markers()


## Clearポイントを取得
func get_clear_points() -> Array[Dictionary]:
	var handler = get_handler(DrawingMode.CLEAR_MARKER)
	if handler:
		return handler.get_markers()
	return []


## Clearマーカーを移譲
func take_clear_markers() -> Array[MeshInstance3D]:
	var handler = get_handler(DrawingMode.CLEAR_MARKER)
	if handler:
		return handler.take_markers()
	return []


## グレネードマーカーがあるか
func has_grenade_markers() -> bool:
	var handler = get_handler(DrawingMode.GRENADE_MARKER)
	return handler and handler.has_markers()


## グレネードマーカーを取得
func get_grenade_markers() -> Array[Dictionary]:
	var handler = get_handler(DrawingMode.GRENADE_MARKER)
	if handler:
		return handler.get_markers()
	return []


## グレネードマーカーを移譲
func take_grenade_markers() -> Array[MeshInstance3D]:
	var handler = get_handler(DrawingMode.GRENADE_MARKER)
	if handler:
		return handler.take_markers()
	return []


## スモークグレネードマーカーがあるか
func has_smoke_grenade_markers() -> bool:
	var handler = get_handler(DrawingMode.SMOKE_GRENADE_MARKER)
	return handler and handler.has_markers()


## スモークグレネードマーカーを取得
func get_smoke_grenade_markers() -> Array[Dictionary]:
	var handler = get_handler(DrawingMode.SMOKE_GRENADE_MARKER)
	if handler:
		return handler.get_markers()
	return []


## スモークグレネードマーカーを移譲
func take_smoke_grenade_markers() -> Array[MeshInstance3D]:
	var handler = get_handler(DrawingMode.SMOKE_GRENADE_MARKER)
	if handler:
		return handler.take_markers()
	return []


## ドアマーカーがあるか
func has_door_markers() -> bool:
	var handler = get_handler(DrawingMode.DOOR_MARKER)
	return handler and handler.has_markers()


## ドアマーカーを取得
func get_door_markers() -> Array[Dictionary]:
	var handler = get_handler(DrawingMode.DOOR_MARKER)
	if handler:
		return handler.get_markers()
	return []


## ドアマーカーを移譲
func take_door_markers() -> Array[MeshInstance3D]:
	var handler = get_handler(DrawingMode.DOOR_MARKER)
	if handler:
		return handler.take_markers()
	return []


## Waitマーカーがあるか
func has_wait_markers() -> bool:
	var handler = get_handler(DrawingMode.WAIT_MARKER)
	return handler and handler.has_markers()


## Waitマーカーを取得
func get_wait_markers() -> Array[Dictionary]:
	var handler = get_handler(DrawingMode.WAIT_MARKER)
	if handler:
		return handler.get_markers()
	return []


## Waitマーカーを移譲
func take_wait_markers() -> Array[MeshInstance3D]:
	var handler = get_handler(DrawingMode.WAIT_MARKER)
	if handler:
		return handler.take_markers()
	return []

#endregion
