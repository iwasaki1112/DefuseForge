class_name ActionPointData
extends RefCounted

## アクションポイントデータの基底クラス
## 各ポイント種別のデータを統一的に扱うためのデータ構造

## ポイントタイプ
enum Type {
	VISION,
	WAIT
}

## ポイントタイプ
var type: Type = Type.VISION

## パス上の位置比率 (0.0 ~ 1.0)
var path_ratio: float = 0.0

## アンカー位置（ポイントの配置位置）
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


## ポイントノードを作成（子クラスでオーバーライド）
func create_point_node() -> Node3D:
	return null


## ファクトリメソッド: タイプに応じたデータクラスを作成
static func create(point_type: Type) -> ActionPointData:
	match point_type:
		Type.VISION:
			return VisionPointData.new()
		Type.WAIT:
			return WaitPointData.new()
		_:
			return ActionPointData.new()


## ファクトリメソッド: Dictionaryからデータクラスを作成
static func from_dictionary(data: Dictionary) -> ActionPointData:
	var point_type: Type = data.get("type", Type.VISION)
	var point_data = create(point_type)
	point_data.from_dict(data)
	return point_data


## 発火結果を取得（子クラスでオーバーライド）
## @return: 発火結果のDictionary
func get_reached_result() -> Dictionary:
	return {
		"type": type,
		"path_ratio": path_ratio,
		"anchor": anchor
	}


## 発火時の処理を実行（子クラスでオーバーライド）
## @param controller: PathFollowingControllerへの参照
## @param point_index: 発火したポイントのインデックス
## @return: 処理が実行されたらtrue
func apply_reached_effect(controller: Node, point_index: int) -> bool:
	return false


## 静的メソッド: Dictionaryデータから発火結果を処理
## @param data: ポイントデータのDictionary
## @param controller: PathFollowingControllerへの参照
## @param point_index: 発火したポイントのインデックス
## @param point_type: ポイントタイプ（省略時はdataから判断、なければVISION）
## @return: 処理が実行されたらtrue
static func process_point_reached(data: Dictionary, controller: Node, point_index: int, point_type: Type = Type.VISION) -> bool:
	# dataにtypeがなければ引数から設定
	var data_with_type := data.duplicate()
	if not data_with_type.has("type"):
		data_with_type["type"] = point_type
	var point_data = from_dictionary(data_with_type)
	return point_data.apply_reached_effect(controller, point_index)


#region Vision Point Data
class VisionPointData extends ActionPointData:
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

	func create_point_node() -> Node3D:
		var point = MeshInstance3D.new()
		point.set_script(preload("res://scripts/effects/vision_point.gd"))
		return point

	func get_reached_result() -> Dictionary:
		var result = super.get_reached_result()
		result["has_target"] = has_target
		if has_target:
			result["target_point"] = target_point
		else:
			result["direction"] = direction
		return result

	func apply_reached_effect(controller: Node, point_index: int) -> bool:
		# PathFollowingControllerのpublicメソッドを使用
		var target := target_point if has_target else Vector3.ZERO
		var dir := direction if not has_target else Vector3.ZERO
		controller.apply_vision_effect(point_index, target, dir)
		return true
#endregion


#region Wait Point Data
class WaitPointData extends ActionPointData:
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

	func create_point_node() -> Node3D:
		var point = MeshInstance3D.new()
		point.set_script(preload("res://scripts/effects/wait_point.gd"))
		return point

	func get_reached_result() -> Dictionary:
		var result = super.get_reached_result()
		result["wait_duration"] = wait_duration
		result["is_sync"] = wait_duration < 0
		return result

	func apply_reached_effect(controller: Node, point_index: int) -> bool:
		# PathFollowingControllerのpublicメソッドを使用
		controller.apply_wait_effect(point_index, to_dict(), wait_duration)
		return true
#endregion
