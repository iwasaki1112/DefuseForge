class_name PointFactory
extends RefCounted

## ポイントメッシュ作成ファクトリ
## VisionPoint/WaitPointの作成を一元化し、重複コードを削減
## NOTE: iOSビルド互換のためpreloadを使用せず、class_name参照を使用
## NOTE: オブジェクトプールを使用してGC圧力を軽減
## NOTE: PointRegistryと連携してカラー計算を共通化

## ポイントタイプのエイリアス（ActionPointDataはclass_name定義済み）
const PointType = ActionPointData.Type


#region カラー計算ヘルパー

## 背景色を計算（キャラクター色から暗めの背景色を生成）
## @param char_color: キャラクター色
## @param type_id: ポイントタイプ（省略時はVISION）
## @return: 計算された背景色
static func calculate_bg_color(char_color: Color, type_id: int = PointType.VISION) -> Color:
	return PointRegistry.calculate_bg_color(type_id, char_color)


## プレビュー用の半透明色を計算
## @param char_color: キャラクター色
## @param alpha: アルファ値（デフォルト0.6）
## @return: 計算されたプレビュー色
static func calculate_preview_color(char_color: Color, alpha: float = 0.6) -> Color:
	return Color(char_color.r, char_color.g, char_color.b, alpha)


## ターゲットライン色を計算
## @param char_color: キャラクター色
## @return: ターゲットライン色
static func calculate_target_line_color(char_color: Color) -> Color:
	return Color(char_color.r, char_color.g * 0.7, char_color.b * 0.5, 0.8)

#endregion


## VisionPointを作成
## @param anchor: パス上のアンカー位置
## @param target_point: ターゲット地点（null/ZEROの場合はdirectionを使用）
## @param direction: 視線方向（target_pointがない場合に使用）
## @param char_color: キャラクター色
## @param parent: 親ノード（nullの場合はadd_childしない）
## @return: 作成したVisionPointメッシュ
static func create_vision_point(
	anchor: Vector3,
	target_point: Variant,
	direction: Vector3,
	char_color: Color,
	parent: Node = null
) -> MeshInstance3D:
	# プールから取得
	var point = ActionPointPool.acquire_vision_point()

	if parent:
		parent.add_child(point)

	# 背景色を計算（ヘルパー使用）
	var bg_color = calculate_bg_color(char_color, PointType.VISION)

	# ターゲットポイントモードか固定方向モードか判定
	var has_target = target_point != null and target_point is Vector3 and (target_point as Vector3).length_squared() > 0.001

	if has_target:
		point.set_position_and_target(anchor, target_point as Vector3)
		point.set_target_line_color(calculate_target_line_color(char_color))
	else:
		point.set_position_and_direction(anchor, direction)

	point.set_colors(bg_color, char_color)

	return point


## VisionPointを作成（Dictionaryから）
## @param data: { anchor, target_point?, direction? }
## @param char_color: キャラクター色
## @param parent: 親ノード（nullの場合はadd_childしない）
## @return: 作成したVisionPointメッシュ
static func create_vision_point_from_dict(
	data: Dictionary,
	char_color: Color,
	parent: Node = null
) -> MeshInstance3D:
	var anchor: Vector3 = data.get("anchor", Vector3.ZERO)
	var target_point = data.get("target_point", null)
	var direction: Vector3 = data.get("direction", Vector3.FORWARD)

	return create_vision_point(anchor, target_point, direction, char_color, parent)


## WaitPointを作成
## @param anchor: パス上のアンカー位置
## @param duration: 待機時間（-1で同期ポイント）
## @param char_color: キャラクター色
## @param parent: 親ノード（nullの場合はadd_childしない）
## @return: 作成したWaitPointメッシュ
static func create_wait_point(
	anchor: Vector3,
	duration: float,
	char_color: Color,
	parent: Node = null
) -> MeshInstance3D:
	# プールから取得
	var point = ActionPointPool.acquire_wait_point()

	if parent:
		parent.add_child(point)

	point.set_point_position(anchor)
	point.set_wait_duration(duration)
	point.set_colors(char_color, Color(1.0, 1.0, 1.0, 1.0))

	return point


## WaitPointを作成（Dictionaryから）
## @param data: { anchor, wait_duration }
## @param char_color: キャラクター色
## @param parent: 親ノード（nullの場合はadd_childしない）
## @return: 作成したWaitPointメッシュ
static func create_wait_point_from_dict(
	data: Dictionary,
	char_color: Color,
	parent: Node = null
) -> MeshInstance3D:
	var anchor: Vector3 = data.get("anchor", Vector3.ZERO)
	var duration: float = data.get("wait_duration", 1.0)

	return create_wait_point(anchor, duration, char_color, parent)


## ポイントタイプに応じてポイントを作成
## @param point_type: PointType
## @param data: ポイントデータのDictionary
## @param char_color: キャラクター色
## @param parent: 親ノード（nullの場合はadd_childしない）
## @return: 作成したポイントメッシュ
static func create_point_by_type(
	point_type: int,
	data: Dictionary,
	char_color: Color,
	parent: Node = null
) -> MeshInstance3D:
	match point_type:
		PointType.VISION:
			return create_vision_point_from_dict(data, char_color, parent)
		PointType.WAIT:
			return create_wait_point_from_dict(data, char_color, parent)
		_:
			push_warning("[PointFactory] Unknown point type: %d" % point_type)
			return null


## ポイントメッシュのリストを解放（プールに返却）
## @param meshes: 解放するメッシュの配列
static func free_point_meshes(meshes: Array) -> void:
	ActionPointPool.release_all(meshes)


## プレビュー用VisionPointを作成（半透明）
## @param anchor: パス上のアンカー位置
## @param target_point: ターゲット地点
## @param char_color: キャラクター色
## @param parent: 親ノード
## @return: 作成したプレビュー用メッシュ
static func create_vision_point_preview(
	anchor: Vector3,
	target_point: Vector3,
	char_color: Color,
	parent: Node = null
) -> MeshInstance3D:
	var preview_color = calculate_preview_color(char_color)
	return create_vision_point(anchor, target_point, Vector3.ZERO, preview_color, parent)


## プレビュー用WaitPointを作成（半透明）
## @param anchor: パス上のアンカー位置
## @param duration: 待機時間
## @param char_color: キャラクター色
## @param parent: 親ノード
## @return: 作成したプレビュー用メッシュ
static func create_wait_point_preview(
	anchor: Vector3,
	duration: float,
	char_color: Color,
	parent: Node = null
) -> MeshInstance3D:
	# プールから取得
	var point = ActionPointPool.acquire_wait_point()

	if parent:
		parent.add_child(point)

	point.set_point_position(anchor)
	point.set_wait_duration(duration)

	# プレビュー用の半透明色（ヘルパー使用）
	var bg_color = calculate_preview_color(char_color)
	var fg_color = Color(1.0, 1.0, 1.0, 0.8)
	point.set_colors(bg_color, fg_color)

	return point
