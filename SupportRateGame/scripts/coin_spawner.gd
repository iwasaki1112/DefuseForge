extends Node3D

## マップ上にコインを配置するスポナー

@export_group("スポーン設定")
@export var coin_scene: PackedScene
@export var number_of_coins: int = 20
@export var spawn_area_width: float = 20.0
@export var spawn_area_length: float = 20.0
@export var spawn_height: float = 1.0
@export var min_distance_between_coins: float = 2.0

var spawned_positions: Array[Vector3] = []


func _ready() -> void:
	spawn_coins()


func spawn_coins() -> void:
	if coin_scene == null:
		push_error("Coin Sceneが設定されていません！")
		return

	var spawned: int = 0
	var max_attempts: int = number_of_coins * 10
	var attempts: int = 0

	while spawned < number_of_coins and attempts < max_attempts:
		var random_position := _get_random_position()

		if _is_valid_position(random_position):
			var coin := coin_scene.instantiate() as Node3D
			add_child(coin)
			coin.global_position = random_position
			spawned_positions.append(random_position)
			spawned += 1

		attempts += 1

	print("%d個のコインをスポーンしました" % spawned)


func _get_random_position() -> Vector3:
	var x := randf_range(-spawn_area_width / 2, spawn_area_width / 2) + global_position.x
	var z := randf_range(-spawn_area_length / 2, spawn_area_length / 2) + global_position.z

	# 地面の高さを取得（レイキャストで）
	var y := spawn_height
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x, 100.0, z),
		Vector3(x, -100.0, z)
	)
	var result := space_state.intersect_ray(query)
	if result:
		y = result.position.y + spawn_height

	return Vector3(x, y, z)


func _is_valid_position(pos: Vector3) -> bool:
	# 他のコインとの距離をチェック
	for existing_pos in spawned_positions:
		if pos.distance_to(existing_pos) < min_distance_between_coins:
			return false

	# プレイヤーのスポーン位置（原点）から離れているかチェック
	if pos.distance_to(Vector3.ZERO) < 3.0:
		return false

	return true
