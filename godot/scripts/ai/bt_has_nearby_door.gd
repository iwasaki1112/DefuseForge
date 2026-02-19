@tool
class_name BTHasNearbyDoor extends ConditionLeaf
## 近くに未開のドアがあるかチェック（検出範囲は広め、接近はBTOpenDoorが担当）

const DOOR_DETECT_DISTANCE := 3.5


func tick(actor: Node, blackboard: Blackboard) -> int:
	var anim_ctrl = actor.get_anim_controller()
	if anim_ctrl and anim_ctrl.is_opening_door():
		return FAILURE

	var doors := actor.get_tree().get_nodes_in_group("doors")
	var best_door: Node3D = null
	var best_dist := INF
	var char_pos: Vector3 = actor.global_position

	for door in doors:
		if not is_instance_valid(door):
			continue
		if not door is Node3D:
			continue
		# 既に開いているドアはスキップ
		if door.is_in_group("open_doors"):
			continue

		# パネル中心位置で距離判定（game_screen と同じ計算）
		var door_pos: Vector3 = door.global_position + door.global_transform.basis * Vector3(-0.5, 0.0, 0.0)
		var dist: float = char_pos.distance_to(door_pos)
		if dist > DOOR_DETECT_DISTANCE:
			continue

		# 壁越しチェック（パネル中心位置へレイキャスト）
		if _is_blocked_by_wall(actor, door, door_pos):
			continue

		if dist < best_dist:
			best_dist = dist
			best_door = door

	if best_door:
		blackboard.set_value("nearby_door", best_door)
		return SUCCESS

	return FAILURE


## ドアまでの間に壁があるかレイキャストでチェック（ドア自身のcolliderを除外）
func _is_blocked_by_wall(actor: Node, door: Node3D, door_pos: Vector3) -> bool:
	var space_state: PhysicsDirectSpaceState3D = actor.get_world_3d().direct_space_state
	if not space_state:
		return false

	var ray_from: Vector3 = actor.global_position + Vector3.UP * 0.5
	var ray_to: Vector3 = door_pos + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, MapBase.WALL_COLLISION_LAYER)

	# ドア自身のStaticBody3Dをレイキャストから除外（game_screen と同じ方式）
	var excludes: Array[RID] = []
	for child in door.get_children():
		if child is StaticBody3D:
			excludes.append((child as StaticBody3D).get_rid())
	if door is StaticBody3D:
		excludes.append((door as StaticBody3D).get_rid())
	query.exclude = excludes

	return not space_state.intersect_ray(query).is_empty()
