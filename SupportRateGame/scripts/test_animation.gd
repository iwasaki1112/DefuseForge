extends Node3D

## アニメーションテストシーン
## 武器タイプ切り替えと移動アニメーションのテスト用
## その場でアニメーションをループ再生

@onready var player: CharacterBase = $Player
@onready var status_label: Label = $UI/VBoxContainer/StatusLabel
@onready var camera: Camera3D = $Camera3D

# カメラオフセット（60度アングル）
var camera_offset := Vector3(0, 4, 2.5)

# 現在のアニメーション状態
var current_anim_state: String = "idle"  # idle, walking, running


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

		var anim = "---"
		if player.anim_player:
			anim = player.anim_player.current_animation

		status_label.text = "武器: %s\n状態: %s\nアニメ: %s" % [weapon, current_anim_state, anim]


func _on_btn_none_pressed() -> void:
	player.set_weapon_type(CharacterSetup.WeaponType.NONE)
	_play_animation(current_anim_state)
	print("[Test] Weapon changed to NONE")


func _on_btn_rifle_pressed() -> void:
	player.set_weapon_type(CharacterSetup.WeaponType.RIFLE)
	_play_animation(current_anim_state)
	print("[Test] Weapon changed to RIFLE")


func _on_btn_pistol_pressed() -> void:
	player.set_weapon_type(CharacterSetup.WeaponType.PISTOL)
	_play_animation(current_anim_state)
	print("[Test] Weapon changed to PISTOL")


func _on_btn_walk_pressed() -> void:
	current_anim_state = "walking"
	_play_animation("walking")
	print("[Test] Playing walking animation (in place)")


func _on_btn_run_pressed() -> void:
	current_anim_state = "running"
	_play_animation("running")
	print("[Test] Playing running animation (in place)")


func _on_btn_stop_pressed() -> void:
	current_anim_state = "idle"
	_play_animation("idle")
	print("[Test] Stopped - playing idle animation")


## 指定したアニメーションをその場で再生
func _play_animation(anim_type: String) -> void:
	if player.anim_player == null:
		return

	var anim_name = CharacterSetup.get_animation_name(anim_type, player.current_weapon_type)

	# 武器タイプ別アニメーションがない場合はNONEにフォールバック
	if not player.anim_player.has_animation(anim_name):
		anim_name = CharacterSetup.get_animation_name(anim_type, CharacterSetup.WeaponType.NONE)

	if player.anim_player.has_animation(anim_name):
		player.anim_player.play(anim_name, 0.3)
		print("[Test] Playing animation: %s" % anim_name)
