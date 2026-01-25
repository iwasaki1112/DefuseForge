class_name ActionMarkerData
extends RefCounted

## アクションマーカーデータの基底クラス
## 各マーカー種別のデータを統一的に扱うためのデータ構造

## マーカータイプ（ActionMarker.MarkerTypeと同じ）
enum Type {
	VISION,
	CLEAR,
	RUN,
	DOOR,
	GRENADE,
	WAIT,
	SMOKE_GRENADE
}

## マーカータイプ
var type: Type = Type.VISION

## パス上の位置比率 (0.0 ~ 1.0)
var path_ratio: float = 0.0

## アンカー位置（マーカーの配置位置）
var anchor: Vector3 = Vector3.ZERO


## 比率を接続線を考慮して調整
func adjust_ratio_for_connection(connect_length: float, base_length: float) -> void:
	if connect_length < 0.01 or base_length < 0.01:
		return
	var new_length = connect_length + base_length
	path_ratio = (connect_length + path_ratio * base_length) / new_length


## Dictionaryに変換（シリアライズ用）
func to_dict() -> Dictionary:
	return {
		"type": type,
		"path_ratio": path_ratio,
		"anchor": anchor
	}


## Dictionaryから復元（デシリアライズ用）
func from_dict(data: Dictionary) -> void:
	if data.has("type"):
		type = data.type
	if data.has("path_ratio"):
		path_ratio = data.path_ratio
	if data.has("anchor"):
		anchor = data.anchor


## マーカーノードを作成（子クラスでオーバーライド）
func create_marker_node() -> Node3D:
	return null


## ファクトリメソッド: タイプに応じたデータクラスを作成
static func create(marker_type: Type) -> ActionMarkerData:
	match marker_type:
		Type.VISION:
			return VisionMarkerData.new()
		Type.CLEAR:
			return ClearMarkerData.new()
		Type.RUN:
			return RunMarkerData.new()
		Type.DOOR:
			return DoorMarkerData.new()
		Type.GRENADE:
			return GrenadeMarkerData.new()
		Type.WAIT:
			return WaitMarkerData.new()
		Type.SMOKE_GRENADE:
			return SmokeGrenadeMarkerData.new()
		_:
			return ActionMarkerData.new()


## ファクトリメソッド: Dictionaryからデータクラスを作成
static func from_dictionary(data: Dictionary) -> ActionMarkerData:
	var marker_type: Type = data.get("type", Type.VISION)
	var marker_data = create(marker_type)
	marker_data.from_dict(data)
	return marker_data


#region Vision Marker Data
class VisionMarkerData extends ActionMarkerData:
	## ターゲット地点（キャラクターが見続ける位置）
	var target_point: Vector3 = Vector3.ZERO
	## 視線方向（後方互換用）
	var direction: Vector3 = Vector3.ZERO
	## ターゲットポイントモードかどうか
	var has_target: bool = false

	func _init() -> void:
		type = Type.VISION

	func to_dict() -> Dictionary:
		var data = super.to_dict()
		if has_target:
			data["target_point"] = target_point
		else:
			data["direction"] = direction
		return data

	func from_dict(data: Dictionary) -> void:
		super.from_dict(data)
		if data.has("target_point"):
			target_point = data.target_point
			has_target = true
		elif data.has("direction"):
			direction = data.direction
			has_target = false

	func create_marker_node() -> Node3D:
		var marker = MeshInstance3D.new()
		marker.set_script(preload("res://scripts/effects/vision_marker.gd"))
		return marker
#endregion


#region Clear Marker Data
class ClearMarkerData extends ActionMarkerData:
	func _init() -> void:
		type = Type.CLEAR

	func create_marker_node() -> Node3D:
		var marker = MeshInstance3D.new()
		marker.set_script(preload("res://scripts/effects/clear_marker.gd"))
		return marker
#endregion


#region Run Marker Data
class RunMarkerData extends ActionMarkerData:
	## Run区間の開始比率
	var start_ratio: float = 0.0
	## Run区間の終了比率
	var end_ratio: float = 0.0

	func _init() -> void:
		type = Type.RUN

	func adjust_ratio_for_connection(connect_length: float, base_length: float) -> void:
		if connect_length < 0.01 or base_length < 0.01:
			return
		var new_length = connect_length + base_length
		start_ratio = (connect_length + start_ratio * base_length) / new_length
		end_ratio = (connect_length + end_ratio * base_length) / new_length

	func to_dict() -> Dictionary:
		return {
			"type": type,
			"start_ratio": start_ratio,
			"end_ratio": end_ratio
		}

	func from_dict(data: Dictionary) -> void:
		super.from_dict(data)
		if data.has("start_ratio"):
			start_ratio = data.start_ratio
		if data.has("end_ratio"):
			end_ratio = data.end_ratio

	func create_marker_node() -> Node3D:
		var marker = MeshInstance3D.new()
		marker.set_script(preload("res://scripts/effects/run_marker.gd"))
		return marker
#endregion


#region Door Marker Data
class DoorMarkerData extends ActionMarkerData:
	## 対象ドアノード
	var door_node: Node3D = null

	func _init() -> void:
		type = Type.DOOR

	func to_dict() -> Dictionary:
		var data = super.to_dict()
		data["door_node"] = door_node
		return data

	func from_dict(data: Dictionary) -> void:
		super.from_dict(data)
		if data.has("door_node"):
			door_node = data.door_node
		elif data.has("door"):
			door_node = data.door

	func create_marker_node() -> Node3D:
		var marker = MeshInstance3D.new()
		marker.set_script(preload("res://scripts/effects/door_marker.gd"))
		return marker
#endregion


#region Grenade Marker Data
class GrenadeMarkerData extends ActionMarkerData:
	## 投擲目標位置
	var target_pos: Vector3 = Vector3.ZERO
	## バウンスポイント（壁に当たる位置）
	var bounce_point: Vector3 = Vector3.ZERO
	## バウンス法線
	var bounce_normal: Vector3 = Vector3.ZERO
	## バウンスがあるか
	var has_bounce: bool = false

	func _init() -> void:
		type = Type.GRENADE

	func to_dict() -> Dictionary:
		var data = super.to_dict()
		data["target_pos"] = target_pos
		if has_bounce:
			data["bounce_point"] = bounce_point
			data["bounce_normal"] = bounce_normal
		return data

	func from_dict(data: Dictionary) -> void:
		super.from_dict(data)
		if data.has("target_pos"):
			target_pos = data.target_pos
		if data.has("bounce_point"):
			bounce_point = data.bounce_point
			has_bounce = true
		if data.has("bounce_normal"):
			bounce_normal = data.bounce_normal

	func create_marker_node() -> Node3D:
		var marker = MeshInstance3D.new()
		marker.set_script(preload("res://scripts/effects/grenade_marker.gd"))
		return marker
#endregion


#region Wait Marker Data
class WaitMarkerData extends ActionMarkerData:
	## 待機時間（秒）
	var wait_duration: float = 1.0

	func _init() -> void:
		type = Type.WAIT

	func to_dict() -> Dictionary:
		var data = super.to_dict()
		data["wait_duration"] = wait_duration
		return data

	func from_dict(data: Dictionary) -> void:
		super.from_dict(data)
		if data.has("wait_duration"):
			wait_duration = data.wait_duration

	func create_marker_node() -> Node3D:
		var marker = MeshInstance3D.new()
		marker.set_script(preload("res://scripts/effects/wait_marker.gd"))
		return marker
#endregion


#region Smoke Grenade Marker Data
class SmokeGrenadeMarkerData extends ActionMarkerData:
	## 投擲目標位置
	var target_pos: Vector3 = Vector3.ZERO
	## バウンスポイント（壁に当たる位置）
	var bounce_point: Vector3 = Vector3.ZERO
	## バウンス法線
	var bounce_normal: Vector3 = Vector3.ZERO
	## バウンスがあるか
	var has_bounce: bool = false

	func _init() -> void:
		type = Type.SMOKE_GRENADE

	func to_dict() -> Dictionary:
		var data = super.to_dict()
		data["target_pos"] = target_pos
		if has_bounce:
			data["bounce_point"] = bounce_point
			data["bounce_normal"] = bounce_normal
		return data

	func from_dict(data: Dictionary) -> void:
		super.from_dict(data)
		if data.has("target_pos"):
			target_pos = data.target_pos
		if data.has("bounce_point"):
			bounce_point = data.bounce_point
			has_bounce = true
		if data.has("bounce_normal"):
			bounce_normal = data.bounce_normal

	func create_marker_node() -> Node3D:
		var marker = MeshInstance3D.new()
		marker.set_script(preload("res://scripts/effects/smoke_grenade_marker.gd"))
		return marker
#endregion
