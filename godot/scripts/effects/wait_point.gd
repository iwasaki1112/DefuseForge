class_name WaitPoint
extends ActionPoint

## Waitポイント（円形背景 + 砂時計アイコン）
## パス上でキャラクターが指定時間待機する位置を示す

## 待機時間（秒）
var _wait_duration: float = 1.0

## テキストラベル用
var _duration_label: Label3D = null


func _init() -> void:
	# デフォルト色を設定（黄色/琥珀系 - 待機を連想）
	circle_color = Color(0.8, 0.6, 0.1, 0.95)
	icon_color = Color(1.0, 1.0, 1.0, 1.0)


func get_action_point_type() -> PointType:
	return PointType.WAIT


## アイコン（砂時計）を構築
func _build_icon() -> void:
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()

	var y_offset = 0.02  # 円より少し上（Z-fighting防止）
	var icon_half_width = circle_radius * 0.35
	var icon_half_height = circle_radius * 0.45
	var neck_width = icon_half_width * 0.15  # くびれ部分

	# 上の台形（頂点が下を向く）
	var top_left = Vector3(-icon_half_width, y_offset, -icon_half_height)
	var top_right = Vector3(icon_half_width, y_offset, -icon_half_height)
	var top_bottom_left = Vector3(-neck_width, y_offset, 0)
	var top_bottom_right = Vector3(neck_width, y_offset, 0)

	# 下の台形（頂点が上を向く）
	var bottom_left = Vector3(-icon_half_width, y_offset, icon_half_height)
	var bottom_right = Vector3(icon_half_width, y_offset, icon_half_height)
	var bottom_top_left = Vector3(-neck_width, y_offset, 0)
	var bottom_top_right = Vector3(neck_width, y_offset, 0)

	# 頂点追加
	vertices.append(top_left)        # 0
	vertices.append(top_right)       # 1
	vertices.append(top_bottom_right) # 2
	vertices.append(top_bottom_left)  # 3
	vertices.append(bottom_top_left)  # 4
	vertices.append(bottom_top_right) # 5
	vertices.append(bottom_right)     # 6
	vertices.append(bottom_left)      # 7

	# 上の台形
	indices.append(0); indices.append(1); indices.append(2)
	indices.append(0); indices.append(2); indices.append(3)

	# 下の台形
	indices.append(4); indices.append(5); indices.append(6)
	indices.append(4); indices.append(6); indices.append(7)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_array_mesh.surface_set_material(1, _icon_material)


## 待機時間を設定
## @param duration: 待機時間（秒）
func set_wait_duration(duration: float) -> void:
	_wait_duration = duration
	_update_duration_label()


## 待機時間を取得
func get_wait_duration() -> float:
	return _wait_duration


## 持続時間ラベルを更新
func _update_duration_label() -> void:
	if not _duration_label:
		_duration_label = Label3D.new()
		_duration_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_duration_label.font_size = 32
		_duration_label.outline_size = 6
		_duration_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_duration_label.outline_modulate = Color(0, 0, 0, 0.8)
		_duration_label.position = Vector3(0, 0.1, 0)  # 地面近くに配置
		_duration_label.render_priority = 11
		add_child(_duration_label)

	# 同期ポイント（duration < 0）の場合は「W」を表示
	if _wait_duration < 0:
		_duration_label.text = "W"
	else:
		_duration_label.text = "%.1fs" % _wait_duration


## 色を変更（WaitPointは再構築が必要）
func set_colors(bg_color: Color, fg_color: Color) -> void:
	circle_color = bg_color
	icon_color = fg_color
	_build_mesh()
