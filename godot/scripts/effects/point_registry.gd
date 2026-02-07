class_name PointRegistry
extends RefCounted

## ポイントタイプの定義を一元管理するレジストリ（シングルトン）
## 新規ポイントタイプ追加時は、ここに定義を登録するだけでOK

## シングルトンインスタンス
static var _instance: PointRegistry = null

## 登録されたポイント定義 { type_id: PointDefinition }
var _definitions: Dictionary = {}

## 初期化済みフラグ
var _initialized: bool = false


## シングルトンを取得
static func get_instance() -> PointRegistry:
	if _instance == null:
		_instance = PointRegistry.new()
		_instance._initialize_default_definitions()
	return _instance


## 静的アクセサ: 定義を取得
static func get_definition(type_id: int) -> PointDefinition:
	return get_instance()._get_definition(type_id)


## 静的アクセサ: 全定義を取得
static func get_all_definitions() -> Array[PointDefinition]:
	return get_instance()._get_all_definitions()


## 静的アクセサ: 登録されたタイプIDの一覧を取得
static func get_registered_type_ids() -> Array[int]:
	return get_instance()._get_registered_type_ids()


## 静的アクセサ: タイプIDが登録されているか確認
static func has_type(type_id: int) -> bool:
	return get_instance()._definitions.has(type_id)


## 静的アクセサ: 背景色を計算
static func calculate_bg_color(type_id: int, char_color: Color) -> Color:
	var definition = get_definition(type_id)
	if definition:
		return definition.calculate_bg_color(char_color)
	# デフォルト
	return Color(char_color.r * 0.3, char_color.g * 0.3, char_color.b * 0.3, 0.95)


## 静的アクセサ: プレビュー色を計算
static func calculate_preview_color(type_id: int, char_color: Color, alpha: float = 0.6) -> Color:
	var definition = get_definition(type_id)
	if definition:
		return definition.calculate_preview_color(char_color, alpha)
	return Color(char_color.r, char_color.g, char_color.b, alpha)


## 静的アクセサ: ポイントインスタンスを作成
static func create_point(type_id: int) -> ActionPoint:
	var definition = get_definition(type_id)
	if definition:
		return definition.create_point_instance()
	return null


## 静的アクセサ: ハンドラーインスタンスを作成
static func create_handler(type_id: int) -> PointHandlerBase:
	var definition = get_definition(type_id)
	if definition:
		return definition.create_handler_instance()
	return null


## デフォルトのポイント定義を初期化
func _initialize_default_definitions() -> void:
	if _initialized:
		return

	# Vision Point
	var vision_def = PointDefinition.new()
	vision_def.type_id = ActionPointData.Type.VISION
	vision_def.point_class_name = "VisionPoint"
	vision_def.handler_class_name = "VisionPointHandler"
	vision_def.bg_color_multiplier = 0.3
	vision_def.bg_color_alpha = 0.95
	vision_def.default_icon_color = Color(1.0, 1.0, 1.0, 1.0)
	vision_def.max_pool_size = 30
	_register(vision_def)

	# Wait Point
	var wait_def = PointDefinition.new()
	wait_def.type_id = ActionPointData.Type.WAIT
	wait_def.point_class_name = "WaitPoint"
	wait_def.handler_class_name = "WaitPointHandler"
	wait_def.bg_color_multiplier = 1.0  # WaitPointは元の色をそのまま使用
	wait_def.bg_color_alpha = 0.95
	wait_def.default_icon_color = Color(1.0, 1.0, 1.0, 1.0)
	wait_def.max_pool_size = 30
	_register(wait_def)

	# Smoke Grenade Point
	var smoke_def = PointDefinition.new()
	smoke_def.type_id = ActionPointData.Type.SMOKE_GRENADE
	smoke_def.point_class_name = "SmokeGrenadePoint"
	smoke_def.handler_class_name = ""  # ハンドラー不要
	smoke_def.bg_color_multiplier = 1.0
	smoke_def.bg_color_alpha = 0.95
	smoke_def.default_icon_color = Color(1.0, 1.0, 1.0, 1.0)
	smoke_def.max_pool_size = 20
	_register(smoke_def)

	_initialized = true


## 定義を登録
func _register(definition: PointDefinition) -> void:
	if _definitions.has(definition.type_id):
		push_warning("[PointRegistry] Overwriting definition for type_id: %d" % definition.type_id)
	_definitions[definition.type_id] = definition


## 定義を取得（内部実装）
func _get_definition(type_id: int) -> PointDefinition:
	return _definitions.get(type_id, null)


## 全定義を取得（内部実装）
func _get_all_definitions() -> Array[PointDefinition]:
	var result: Array[PointDefinition] = []
	for def in _definitions.values():
		result.append(def)
	return result


## 登録されたタイプIDの一覧を取得（内部実装）
func _get_registered_type_ids() -> Array[int]:
	var result: Array[int] = []
	for type_id in _definitions.keys():
		result.append(type_id)
	return result
