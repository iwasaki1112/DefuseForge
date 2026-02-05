extends RefCounted
class_name MovingPathVisionService

## 移動中パスVisionポイント管理サービス
## パス実行中のVisionポイントの追加・表示・非表示を管理
## GameManagerから抽出されたコンポーネント

## VisionPointスクリプト（遅延ロード）
var VisionPointScript = null

## 外部参照
var _mesh_parent: Node3D = null
var _path_execution_manager = null  # PathExecutionManager

## 移動中パスVisionプレビュー用
var _preview: MeshInstance3D = null
## 現在プレビュー中のpath_ratio
var _preview_ratio: float = 0.0
## 移動中パスに追加されたVisionポイント（キャラクターIDをキーとした配列）
## { char_id: Array[{ "point": MeshInstance3D, "path_ratio": float, "anchor": Vector3, "target_point": Vector3 }] }
var _vision_points: Dictionary = {}


## セットアップ
func setup(mesh_parent: Node3D, path_execution_manager) -> void:
	_mesh_parent = mesh_parent
	_path_execution_manager = path_execution_manager
	VisionPointScript = load("res://scripts/effects/vision_point.gd")


## Visionポイントを移動中パスに追加
## @return: 成功した場合true
func add_vision_point(character: Node, path_ratio: float, anchor: Vector3, target_point: Vector3) -> bool:
	if not _path_execution_manager:
		return false
	var result = _path_execution_manager.add_vision_point_to_moving_path(character, path_ratio, anchor, target_point)
	if result and _preview:
		# プレビューを永続ポイントとして保持
		var char_id = character.get_instance_id()
		if not _vision_points.has(char_id):
			_vision_points[char_id] = []
		_vision_points[char_id].append({
			"point": _preview,
			"path_ratio": path_ratio,
			"anchor": anchor,
			"target_point": target_point
		})
		# プレビュー参照をクリア（ノードは保持）
		_preview = null
		_preview_ratio = 0.0
	return result


## プレビューを更新
func update_preview(character: Node, anchor: Vector3, target_point: Vector3, path_ratio: float = 0.0) -> void:
	var char_color := CharacterColorManager.get_character_color(character) if character else Color.WHITE

	if not _preview:
		if not VisionPointScript:
			VisionPointScript = load("res://scripts/effects/vision_point.gd")
		_preview = MeshInstance3D.new()
		_preview.set_script(VisionPointScript)
		if _mesh_parent:
			_mesh_parent.add_child(_preview)

	_preview.set_position_and_target(anchor, target_point)
	_preview.set_colors(char_color, Color.WHITE)
	_preview.set_target_line_color(Color(char_color.r, char_color.g * 0.7, char_color.b * 0.5, 0.8))
	_preview_ratio = path_ratio


## プレビューをクリア
func clear_preview() -> void:
	if _preview and is_instance_valid(_preview):
		_preview.queue_free()
		_preview = null


## キャラクターのVisionポイントをクリア
func clear_for_character(character: Node) -> void:
	if not character:
		return
	var char_id = character.get_instance_id()
	if _vision_points.has(char_id):
		for point_data in _vision_points[char_id]:
			var point = point_data.get("point")
			if is_instance_valid(point):
				point.queue_free()
		_vision_points.erase(char_id)


## 全Visionポイントをクリア
func clear_all() -> void:
	for char_id in _vision_points:
		for point_data in _vision_points[char_id]:
			var point = point_data.get("point")
			if is_instance_valid(point):
				point.queue_free()
	_vision_points.clear()


## 進行状況に応じてVisionポイントを非表示
func hide_passed_points(character: Node, _current_ratio: float) -> void:
	if not character:
		return
	var char_id = character.get_instance_id()
	if not _vision_points.has(char_id):
		return

	# キャラクターの現在位置を取得（Y座標は無視）
	var char_pos = character.global_position
	char_pos.y = 0.0

	for point_data in _vision_points[char_id]:
		var point = point_data.get("point")
		if not is_instance_valid(point):
			continue

		# 既に非表示なら処理しない
		if not point.visible:
			continue

		var anchor = point_data.get("anchor", Vector3.ZERO)
		if anchor == Vector3.ZERO:
			continue

		# ポイント位置との距離で判定（Y座標は無視）
		var anchor_flat = Vector3(anchor.x, 0.0, anchor.z)
		var distance = char_pos.distance_to(anchor_flat)

		# キャラクターがポイント位置に十分近い（1.0ユニット以内）なら非表示
		if distance < 1.0:
			point.visible = false


## キャラクターのVisionポイント有無を確認
func has_points_for_character(character: Node) -> bool:
	if not character:
		return false
	return _vision_points.has(character.get_instance_id())


## キャラクターのVisionポイントを取得
func get_points_for_character(character: Node) -> Array:
	if not character:
		return []
	var char_id = character.get_instance_id()
	if not _vision_points.has(char_id):
		return []
	return _vision_points[char_id]


## パス拡張時にVisionポイントの比率を再計算
## @param character: 対象キャラクター
## @param full_path: 完全な残りパス配列
## @param ratio_calculator: 比率計算関数 (path: Array[Vector3], position: Vector3) -> float
func recalculate_ratios_on_scale(character: Node, full_path: Array[Vector3], ratio_calculator: Callable) -> void:
	if not character:
		return
	var char_id = character.get_instance_id()
	if not _vision_points.has(char_id):
		return

	if full_path.size() < 2:
		return

	for point_data in _vision_points[char_id]:
		var anchor = point_data.get("anchor", Vector3.ZERO)
		if anchor != Vector3.ZERO:
			# アンカー位置からパス上の比率を再計算
			var new_ratio = ratio_calculator.call(full_path, anchor)
			point_data["path_ratio"] = new_ratio

		# 視覚的なポイント位置を維持
		var point = point_data.get("point")
		var target_point = point_data.get("target_point", Vector3.ZERO)
		if is_instance_valid(point) and anchor != Vector3.ZERO:
			point.set_position_and_target(anchor, target_point)
