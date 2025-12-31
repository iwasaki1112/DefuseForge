extends Node3D

## アニメーションテストシーン
## 武器タイプ切り替えと移動アニメーションのテスト用

@onready var player: CharacterBase = $Player
@onready var status_label: Label = $UI/VBoxContainer/StatusLabel
@onready var camera: Camera3D = $Camera3D

# キャラクターシーンのプリロード
const PLAYER_SCENE = preload("res://scenes/player.tscn")
const ENEMY_SCENE = preload("res://scenes/enemy.tscn")

# 現在のキャラクタータイプ
enum CharacterType { GSG9, LEET }
var current_character_type: CharacterType = CharacterType.GSG9

# カメラ設定
var camera_distance := 3.5  # カメラ距離
var camera_yaw := 0.0  # 水平回転角度（ラジアン）
var camera_pitch := 30.0  # 垂直回転角度（度）
var camera_zoom_speed := 0.5
var camera_rotate_speed := 0.005
var camera_min_distance := 1.5
var camera_max_distance := 15.0
var camera_min_pitch := 5.0
var camera_max_pitch := 85.0
var is_dragging := false  # ドラッグ中フラグ
var is_paused := false  # 一時停止状態

@onready var btn_pause: Button = $UI/VBoxContainer/BtnPause


func _ready() -> void:
	# GameManagerの状態をPLAYINGに設定
	GameManager.current_state = GameManager.GameState.PLAYING
	_update_status()
	# iOSでの可視性問題を回避するため、遅延してキャラクターを強制表示
	_ensure_player_visible.call_deferred()


## プレイヤーの可視性を確保（iOS対策）
func _ensure_player_visible() -> void:
	await get_tree().create_timer(0.1).timeout
	if player:
		player.visible = true
		var model = player.get_node_or_null("CharacterModel")
		if model:
			model.visible = true
		print("[TestAnimation] Player visibility forced to true")


func _process(_delta: float) -> void:
	_update_status()
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	# マウスボタン
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = max(camera_min_distance, camera_distance - camera_zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = min(camera_max_distance, camera_distance + camera_zoom_speed)

	# マウスドラッグで回転
	if event is InputEventMouseMotion and is_dragging:
		camera_yaw -= event.relative.x * camera_rotate_speed
		camera_pitch -= event.relative.y * camera_rotate_speed * 50.0
		camera_pitch = clamp(camera_pitch, camera_min_pitch, camera_max_pitch)

	# Macトラックパッド: ピンチでズーム
	if event is InputEventMagnifyGesture:
		var zoom_amount: float = (event.factor - 1.0) * 2.0
		camera_distance = clamp(camera_distance - zoom_amount, camera_min_distance, camera_max_distance)

	# Macトラックパッド: 2本指スクロールでズーム
	if event is InputEventPanGesture:
		camera_distance = clamp(camera_distance + event.delta.y * 0.1, camera_min_distance, camera_max_distance)


func _update_camera() -> void:
	if camera and player:
		# キャラクターの中心位置（少し上にオフセット）
		var target_pos := player.global_position + Vector3(0, 1.0, 0)

		# 球面座標からカメラ位置を計算
		var pitch_rad := deg_to_rad(camera_pitch)
		var offset := Vector3(
			sin(camera_yaw) * cos(pitch_rad) * camera_distance,
			sin(pitch_rad) * camera_distance,
			cos(camera_yaw) * cos(pitch_rad) * camera_distance
		)

		camera.global_position = target_pos + offset
		camera.look_at(target_pos, Vector3.UP)


func _update_status() -> void:
	if player and status_label:
		var character_name = "GSG9" if current_character_type == CharacterType.GSG9 else "LEET"
		var weapon_type = player.get_weapon_type_name()
		var weapon_data = player.get_weapon_data()
		var weapon_name = weapon_data.name if weapon_data else "None"
		var state = "idle"
		if player.is_moving:
			state = "running" if player.is_running else "walking"

		var anim = "---"
		if player.anim_player:
			anim = player.anim_player.current_animation

		status_label.text = "キャラ: %s\n武器タイプ: %s\n装備: %s\n状態: %s\nアニメ: %s\n距離: %.1f\n---\nドラッグ: 回転\nホイール: ズーム" % [character_name, weapon_type, weapon_name, state, anim, camera_distance]


func _on_btn_none_pressed() -> void:
	player.set_weapon_type(CharacterSetup.WeaponType.NONE)
	print("[Test] Weapon changed to NONE")


func _on_btn_rifle_pressed() -> void:
	player.set_weapon_type(CharacterSetup.WeaponType.RIFLE)
	print("[Test] Weapon changed to RIFLE")


func _on_btn_pistol_pressed() -> void:
	player.set_weapon_type(CharacterSetup.WeaponType.PISTOL)
	print("[Test] Weapon changed to PISTOL")


func _on_btn_ak47_pressed() -> void:
	player.set_weapon(CharacterSetup.WeaponId.AK47)
	print("[Test] Weapon equipped: AK-47")


func _on_btn_remove_weapon_pressed() -> void:
	player.set_weapon(CharacterSetup.WeaponId.NONE)
	print("[Test] Weapon removed")


func _on_btn_walk_pressed() -> void:
	# 移動せずに歩きアニメーションをその場で再生
	player.is_moving = true
	player.is_running = false
	print("[Test] Walking animation started")


func _on_btn_run_pressed() -> void:
	# 移動せずに走りアニメーションをその場で再生
	player.is_moving = true
	player.is_running = true
	print("[Test] Running animation started")


func _on_btn_stop_pressed() -> void:
	# アニメーションを停止（idle状態に）
	player.is_moving = false
	player.is_running = false
	player.velocity = Vector3.ZERO
	player.waypoints.clear()
	player.current_waypoint_index = 0
	print("[Test] Stopped")


func _on_btn_dying_pressed() -> void:
	# 死亡アニメーションを再生
	player.is_moving = false
	player.is_running = false
	player.play_dying_animation()
	print("[Test] Dying animation started")


func _on_btn_pause_pressed() -> void:
	# 一時停止/再開を切り替え
	is_paused = !is_paused
	if player and player.anim_player:
		if is_paused:
			player.anim_player.pause()
			btn_pause.text = "再開"
			print("[Test] Animation paused")
		else:
			player.anim_player.play()
			btn_pause.text = "一時停止"
			print("[Test] Animation resumed")


func _on_btn_gsg9_pressed() -> void:
	_switch_character(CharacterType.GSG9)


func _on_btn_leet_pressed() -> void:
	_switch_character(CharacterType.LEET)


## キャラクター切り替え
func _switch_character(new_type: CharacterType) -> void:
	if current_character_type == new_type:
		return

	# 現在のキャラクターの状態を保存
	var was_moving := player.is_moving
	var was_running := player.is_running
	var weapon_type := player.current_weapon_type
	var weapon_id := player.current_weapon_id
	var old_pos := player.global_position

	# 古いキャラクターを削除
	player.queue_free()

	# 新しいキャラクターをインスタンス化
	var new_player: CharacterBase
	if new_type == CharacterType.GSG9:
		new_player = PLAYER_SCENE.instantiate()
		new_player.name = "Player"
	else:
		new_player = ENEMY_SCENE.instantiate()
		new_player.name = "Player"  # 参照名は同じにする

	# シーンに追加
	add_child(new_player)
	new_player.global_position = old_pos

	# 参照を更新
	player = new_player
	current_character_type = new_type

	# 状態を復元（1フレーム待ってから）
	await get_tree().process_frame
	# 武器IDがある場合は武器を装着、なければ武器タイプのみ設定
	if weapon_id != CharacterSetup.WeaponId.NONE:
		player.set_weapon(weapon_id)
	else:
		player.set_weapon_type(weapon_type)
	player.is_moving = was_moving
	player.is_running = was_running

	# iOS対策: 可視性を強制設定
	await get_tree().create_timer(0.1).timeout
	if player:
		player.visible = true
		var model = player.get_node_or_null("CharacterModel")
		if model:
			model.visible = true

	var type_name = "GSG9" if new_type == CharacterType.GSG9 else "LEET"
	print("[Test] Character changed to: %s" % type_name)
