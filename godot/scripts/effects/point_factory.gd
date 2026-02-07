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


## SmokeGrenadePointを作成
## @param anchor: パス上のアンカー位置
## @param target_pos: グレネードの着弾位置
## @param char_color: キャラクター色
## @param parent: 親ノード（nullの場合はadd_childしない）
## @return: 作成したSmokeGrenadePointメッシュ
static func create_smoke_grenade_point(
	anchor: Vector3,
	_target_pos: Vector3,
	char_color: Color,
	parent: Node = null
) -> MeshInstance3D:
	# プールから取得
	var point = ActionPointPool.acquire(PointType.SMOKE_GRENADE)

	if parent:
		parent.add_child(point)

	point.set_point_position(anchor)
	point.set_colors(char_color, Color(1.0, 1.0, 1.0, 1.0))

	return point


## SmokeGrenadePointを作成（Dictionaryから）
## @param data: { anchor, target_pos }
## @param char_color: キャラクター色
## @param parent: 親ノード（nullの場合はadd_childしない）
## @return: 作成したSmokeGrenadePointメッシュ
static func create_smoke_grenade_point_from_dict(
	data: Dictionary,
	char_color: Color,
	parent: Node = null
) -> MeshInstance3D:
	var anchor: Vector3 = data.get("anchor", Vector3.ZERO)
	var target_pos: Vector3 = data.get("target_pos", Vector3.ZERO)

	return create_smoke_grenade_point(anchor, target_pos, char_color, parent)


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
		PointType.SMOKE_GRENADE:
			return create_smoke_grenade_point_from_dict(data, char_color, parent)
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


## スモークグレネード着弾マーカーを作成（リング状）
## @param target_pos: 着弾位置
## @param char_color: キャラクター色
## @param parent: 親ノード
## @return: 作成したMeshInstance3D
static func create_smoke_grenade_target_marker(
	target_pos: Vector3,
	char_color: Color,
	parent: Node = null
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "SmokeGrenadeTarget"

	if parent:
		parent.add_child(mesh_instance)

	# ノード位置を着弾地点にセット
	mesh_instance.position = Vector3(target_pos.x, 0.15, target_pos.z)

	# リングメッシュを作成（ローカル座標: 原点中心）
	var ring_radius := 0.25
	var ring_thickness := 0.05
	var ring_segments := 24

	var array_mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()

	var inner_radius := ring_radius - ring_thickness

	for i in range(ring_segments):
		var angle := TAU * i / ring_segments
		var cos_a := cos(angle)
		var sin_a := sin(angle)
		vertices.append(Vector3(cos_a * inner_radius, 0.0, sin_a * inner_radius))
		vertices.append(Vector3(cos_a * ring_radius, 0.0, sin_a * ring_radius))

	for i in range(ring_segments):
		var ci := i * 2
		var co := i * 2 + 1
		var ni := ((i + 1) % ring_segments) * 2
		var no := ((i + 1) % ring_segments) * 2 + 1
		indices.append(ci)
		indices.append(co)
		indices.append(ni)
		indices.append(co)
		indices.append(no)
		indices.append(ni)

	if vertices.size() > 0:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_INDEX] = indices
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(char_color.r, char_color.g, char_color.b, 0.7)
		mat.emission_enabled = true
		mat.emission = char_color
		mat.emission_energy_multiplier = 1.2
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.render_priority = 2
		array_mesh.surface_set_material(0, mat)

	mesh_instance.mesh = array_mesh
	return mesh_instance
