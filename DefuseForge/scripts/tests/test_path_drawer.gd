extends Node3D

## パスドロワーのテストシーン

@onready var camera: Camera3D = $OrbitCamera
@onready var path_drawer: Node3D = $PathDrawer
@onready var clear_button: Button = $CanvasLayer/UI/ClearButton
@onready var point_count_label: Label = $CanvasLayer/UI/PointCountLabel
@onready var character: Node3D = $Character


func _ready() -> void:
	# カメラを固定（入力無効化）
	camera.input_disabled = true

	# PathDrawerにカメラとキャラクターを設定
	path_drawer.setup(camera, character)

	# アニメーション再生（Idle）
	_play_idle_animation()

	# シグナル接続
	path_drawer.drawing_started.connect(_on_drawing_started)
	path_drawer.drawing_updated.connect(_on_drawing_updated)
	path_drawer.drawing_finished.connect(_on_drawing_finished)
	clear_button.pressed.connect(_on_clear_pressed)

	print("[TestPathDrawer] Ready - Left-click and drag to draw a path")


func _on_drawing_started() -> void:
	point_count_label.text = "Points: 1"


func _on_drawing_updated(points: PackedVector3Array) -> void:
	point_count_label.text = "Points: %d" % points.size()


func _on_drawing_finished(points: PackedVector3Array) -> void:
	print("[TestPathDrawer] Path completed with %d points" % points.size())


func _on_clear_pressed() -> void:
	path_drawer.clear()
	point_count_label.text = "Points: 0"
	print("[TestPathDrawer] Path cleared")


func _play_idle_animation() -> void:
	var anim_player = character.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player:
		# Idleアニメーションを探して再生
		for anim_name in anim_player.get_animation_list():
			if "idle" in anim_name.to_lower():
				anim_player.play(anim_name)
				print("[TestPathDrawer] Playing animation: %s" % anim_name)
				return
		# 見つからなければ最初のアニメーションを再生
		if anim_player.get_animation_list().size() > 0:
			var first_anim = anim_player.get_animation_list()[0]
			anim_player.play(first_anim)
			print("[TestPathDrawer] Playing first animation: %s" % first_anim)
	else:
		print("[TestPathDrawer] AnimationPlayer not found")
