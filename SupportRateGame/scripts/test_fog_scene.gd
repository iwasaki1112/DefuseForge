extends Node3D

## Fog of Warテスト用シーン
## WASD/矢印キーでキャラクターを移動
## カメラはキャラクターを追従

const FogOfWarManagerScene = preload("res://scenes/systems/fog_of_war_manager.tscn")
const FogOfWarRendererScene = preload("res://scenes/systems/fog_of_war_renderer.tscn")

@onready var player: CharacterBody3D = $Player
@onready var camera: Camera3D = $Camera3D

var fog_of_war_manager: Node = null
var fog_renderer: Node3D = null

var move_speed: float = 5.0
var rotation_speed: float = 10.0
var camera_height: float = 15.0
var camera_distance: float = 10.0


func _ready() -> void:
	# FogOfWarシステムを初期化
	_setup_fog_of_war_manager()
	_setup_fog_of_war_renderer()

	# カメラ初期位置
	_update_camera()

	print("[TestFog] Scene ready - Use WASD to move")


func _exit_tree() -> void:
	GameManager.unregister_fog_of_war_manager()


func _setup_fog_of_war_manager() -> void:
	fog_of_war_manager = FogOfWarManagerScene.instantiate()
	add_child(fog_of_war_manager)
	GameManager.register_fog_of_war_manager(fog_of_war_manager)
	print("[TestFog] FogOfWarManager initialized")


func _setup_fog_of_war_renderer() -> void:
	fog_renderer = FogOfWarRendererScene.instantiate()
	add_child(fog_renderer)
	fog_renderer.set_map_bounds(Vector3.ZERO, Vector2(100, 100))
	print("[TestFog] FogOfWarRenderer initialized")


func _physics_process(delta: float) -> void:
	# カメラ更新も物理フレームで行う（物理補間と連携）
	_update_camera()
	if not player:
		return

	# WASD/矢印キーで移動
	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1

	input_dir = input_dir.normalized()

	# 移動方向をワールド座標に変換（トップダウンビュー）
	var direction := Vector3(input_dir.x, 0, input_dir.y)
	var is_moving := direction.length() > 0.1

	# プレイヤーのis_movingフラグを設定（アニメーション用）
	if "is_moving" in player:
		player.is_moving = is_moving

	# 移動中はキャラクターを移動方向に向ける
	if is_moving:
		# character_base.gdと同じ向き計算を使用
		var target_rotation := atan2(direction.x, direction.z)
		player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)

	# 速度設定
	var velocity := direction * move_speed

	# 重力
	if not player.is_on_floor():
		velocity.y = player.velocity.y - 9.8 * delta
	else:
		velocity.y = 0

	player.velocity = velocity
	player.move_and_slide()


func _update_camera() -> void:
	if not camera or not player:
		return

	# カメラをプレイヤーの上に配置してlookAt
	camera.global_position = player.global_position + Vector3(0, camera_height, camera_distance)
	camera.look_at(player.global_position, Vector3.UP)
	# 物理補間をリセット（直接位置設定後に必要）
	camera.reset_physics_interpolation()
