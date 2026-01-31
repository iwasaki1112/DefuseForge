class_name PointFactory
extends RefCounted

## ポイントメッシュ作成ファクトリ
## VisionPoint/WaitPointの作成を一元化し、重複コードを削減


const VisionPointScript = preload("res://scripts/effects/vision_point.gd")
const WaitPointScript = preload("res://scripts/effects/wait_point.gd")
const ActionPointDataScript = preload("res://scripts/effects/action_point_data.gd")

## ポイントタイプのエイリアス
const PointType = ActionPointDataScript.Type


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
	var point = MeshInstance3D.new()
	point.set_script(VisionPointScript)

	if parent:
		parent.add_child(point)

	# 背景色を計算（暗めのキャラクター色）
	var bg_color = Color(char_color.r * 0.3, char_color.g * 0.3, char_color.b * 0.3, 0.95)

	# ターゲットポイントモードか固定方向モードか判定
	var has_target = target_point != null and target_point is Vector3 and (target_point as Vector3).length_squared() > 0.001

	if has_target:
		point.set_position_and_target(anchor, target_point as Vector3)
		point.set_target_line_color(Color(char_color.r, char_color.g * 0.7, char_color.b * 0.5, 0.8))
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
	var point = MeshInstance3D.new()
	point.set_script(WaitPointScript)

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


## ポイントメッシュのリストを解放
## @param meshes: 解放するメッシュの配列
static func free_point_meshes(meshes: Array) -> void:
	for mesh in meshes:
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()


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
	var preview_color = Color(char_color.r, char_color.g, char_color.b, 0.6)
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
	var point = MeshInstance3D.new()
	point.set_script(WaitPointScript)

	if parent:
		parent.add_child(point)

	point.set_point_position(anchor)
	point.set_wait_duration(duration)

	# プレビュー用の半透明色
	var bg_color = Color(char_color.r, char_color.g, char_color.b, 0.6)
	var fg_color = Color(1.0, 1.0, 1.0, 0.8)
	point.set_colors(bg_color, fg_color)

	return point
