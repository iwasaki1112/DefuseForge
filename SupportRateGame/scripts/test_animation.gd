extends Node3D

## アニメーションテストシーン
## 武器タイプ切り替えと移動アニメーションのテスト用

@onready var player: CharacterBase = $Player
@onready var status_label: Label = $UI/VBoxContainer/StatusLabel
@onready var camera: Camera3D = $Camera3D

var walk_target := Vector3(3, 0, 0)
var run_target := Vector3(-3, 0, 0)

# カメラオフセット（60度アングル）
var camera_offset := Vector3(0, 4, 2.5)


func _ready() -> void:
	# GameManagerの状態をPLAYINGに設定
	GameManager.current_state = GameManager.GameState.PLAYING
	_update_status()

	# 初期配置後にプレイヤー位置を修正
	await get_tree().create_timer(0.1).timeout
	player.global_position.y = -1.15


func _process(_delta: float) -> void:
	_update_status()
	_update_camera()


func _update_camera() -> void:
	if camera and player:
		camera.global_position = player.global_position + camera_offset


func _update_status() -> void:
	if player and status_label:
		var weapon = player.get_weapon_type_name()
		var state = "idle"
		if player.is_moving:
			state = "running" if player.is_running else "walking"

		var anim = "---"
		if player.anim_player:
			anim = player.anim_player.current_animation

		status_label.text = "武器: %s\n状態: %s\nアニメ: %s" % [weapon, state, anim]


func _on_btn_none_pressed() -> void:
	player.set_weapon_type(CharacterSetup.WeaponType.NONE)
	print("[Test] Weapon changed to NONE")


func _on_btn_rifle_pressed() -> void:
	player.set_weapon_type(CharacterSetup.WeaponType.RIFLE)
	print("[Test] Weapon changed to RIFLE")


func _on_btn_pistol_pressed() -> void:
	player.set_weapon_type(CharacterSetup.WeaponType.PISTOL)
	print("[Test] Weapon changed to PISTOL")


func _on_btn_walk_pressed() -> void:
	# 現在位置から反対方向に歩く
	var target = walk_target if player.global_position.x < 0 else -walk_target
	player.move_to(target, false)  # run=false で歩き
	print("[Test] Walking to %s" % target)


func _on_btn_run_pressed() -> void:
	# 現在位置から反対方向に走る
	var target = run_target if player.global_position.x > 0 else -run_target
	player.move_to(target, true)  # run=true で走り
	print("[Test] Running to %s" % target)


func _on_btn_stop_pressed() -> void:
	player.stop()
	print("[Test] Stopped")
