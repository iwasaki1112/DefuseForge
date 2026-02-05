class_name PointDefinition
extends Resource

## ポイントタイプの定義を保持するResourceクラス
## 各ポイントタイプ（Vision, Wait等）の設定を一元管理
## Type Object パターンにより、新規タイプ追加時の変更箇所を最小化

## ポイントタイプID（ActionPointData.Typeに対応）
@export var type_id: int = 0

## ポイントクラス名（class_name定義済みのクラスを文字列で指定）
## 例: "VisionPoint", "WaitPoint"
@export var point_class_name: String = ""

## ハンドラークラス名（class_name定義済みのクラスを文字列で指定）
## 例: "VisionPointHandler", "WaitPointHandler"
@export var handler_class_name: String = ""

## 背景色の乗算係数（キャラクター色から背景色を計算する際に使用）
@export var bg_color_multiplier: float = 0.3

## 背景色のアルファ値
@export var bg_color_alpha: float = 0.95

## アイコンのデフォルト色
@export var default_icon_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## プール最大サイズ
@export var max_pool_size: int = 30


## キャラクター色から背景色を計算
func calculate_bg_color(char_color: Color) -> Color:
	return Color(
		char_color.r * bg_color_multiplier,
		char_color.g * bg_color_multiplier,
		char_color.b * bg_color_multiplier,
		bg_color_alpha
	)


## プレビュー用の半透明色を計算
func calculate_preview_color(char_color: Color, alpha: float = 0.6) -> Color:
	return Color(char_color.r, char_color.g, char_color.b, alpha)


## ポイントインスタンスを作成
## NOTE: class_name定義済みのクラスのみ対応（iOS互換）
func create_point_instance() -> ActionPoint:
	match point_class_name:
		"VisionPoint":
			return VisionPoint.new()
		"WaitPoint":
			return WaitPoint.new()
		_:
			push_error("[PointDefinition] Unknown point class: %s" % point_class_name)
			return null


## ハンドラーインスタンスを作成
## NOTE: class_name定義済みのクラスのみ対応（iOS互換）
func create_handler_instance() -> PointHandlerBase:
	match handler_class_name:
		"VisionPointHandler":
			return VisionPointHandler.new()
		"WaitPointHandler":
			return WaitPointHandler.new()
		_:
			push_error("[PointDefinition] Unknown handler class: %s" % handler_class_name)
			return null
