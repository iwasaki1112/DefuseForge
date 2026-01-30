class_name SmokeGrenadePoint
extends GrenadePoint

## スモークグレネードポイント（灰色/白の爆発アイコン + 軌道線）
## GrenadePointを継承し、色のみを変更

func _init() -> void:
	super._init()
	# スモークグレネード用の色設定（灰色/白）
	circle_color = Color(0.2, 0.2, 0.2, 0.95)  # 暗灰色
	icon_color = Color(0.9, 0.9, 0.9, 1.0)  # 白


func get_action_point_type() -> PointType:
	return PointType.SMOKE_GRENADE


func _setup_mesh() -> void:
	super._setup_mesh()
	# 軌道線の色も灰色に変更
	set_trajectory_color(Color(0.7, 0.7, 0.7, 0.8))
