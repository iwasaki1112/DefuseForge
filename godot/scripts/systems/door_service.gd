extends Node
class_name DoorService

## ドア管理サービス
## ドアID管理・キック処理・ネットワーク同期を一元管理
## GameManagerから抽出されたコンポーネント

## ドアキックネットワークイベント（マルチプレイヤー同期用）
signal door_kick_network_event(door_id: int, character_network_id: int)
## ドア開けネットワークイベント（マルチプレイヤー同期用）
signal door_open_network_event(door_id: int, character_network_id: int)
## ドア開閉完了シグナル
signal door_opened(door: Node3D, character: Node)

## ドアID管理（マルチプレイヤー同期用）
var _next_door_id: int = 1
var _door_id_map: Dictionary[Node3D, int] = {}  ## door_node -> door_id
var _id_to_door: Dictionary[int, Node3D] = {}   ## door_id -> door_node

## 外部参照
var _character_manager: CharacterManagerService = null
var _is_multiplayer_mode: bool = false

## 視界更新コールバック（ドア開閉時）
var _on_vision_update_callback: Callable = Callable()


## セットアップ
func setup(character_manager: CharacterManagerService = null) -> void:
	_character_manager = character_manager


## マルチプレイヤーモードを設定
func set_multiplayer_mode(enabled: bool) -> void:
	_is_multiplayer_mode = enabled


## 視界更新コールバックを設定
func set_vision_update_callback(callback: Callable) -> void:
	_on_vision_update_callback = callback


## ドアを登録し、一意のIDを割り当て
## Returns: 割り当てられたドアID
func register_door(door: Node3D) -> int:
	if _door_id_map.has(door):
		return _door_id_map[door]

	var door_id := _next_door_id
	_next_door_id += 1

	_door_id_map[door] = door_id
	_id_to_door[door_id] = door

	return door_id


## ドアIDからドアノードを取得
func get_door_by_id(door_id: int) -> Node3D:
	if _id_to_door.has(door_id):
		var door: Node3D = _id_to_door[door_id]
		if is_instance_valid(door):
			return door
		else:
			_id_to_door.erase(door_id)
	return null


## ドアノードからドアIDを取得
func get_door_id(door: Node3D) -> int:
	if _door_id_map.has(door):
		return _door_id_map[door]
	return 0


## 全ドアを登録解除
func clear_door_registry() -> void:
	_door_id_map.clear()
	_id_to_door.clear()
	_next_door_id = 1


## マップ内の全ドアを登録（"doors"グループから取得）
func register_all_doors_in_map() -> void:
	var doors := get_tree().get_nodes_in_group("doors")
	for door in doors:
		if door is Node3D:
			register_door(door)


## ドアキックインパクト時（フレーム36/66）
## character: ドアをキックしたキャラクター（位置から回転方向を計算）
func on_door_kick_done(door: Node3D, character: CharacterBody3D) -> void:
	if not is_instance_valid(door) or not is_instance_valid(character):
		return

	# ローカルキャラクターのキックのみネットワークイベントを送信
	var game_char := character as GameCharacter
	if game_char and game_char.is_local() and _is_multiplayer_mode:
		var door_id := get_door_id(door)
		if door_id > 0:
			door_kick_network_event.emit(door_id, game_char.network_id)

	# ドアを開く処理を実行
	open_door(door, character)


## ドアを開く処理（ローカル・リモート共通）
func open_door(door: Node3D, character: CharacterBody3D) -> void:
	if not is_instance_valid(door) or not is_instance_valid(character):
		return

	# ドアからキャラクターへの方向ベクトル
	var door_to_char := (character.global_position - door.global_position)
	door_to_char.y = 0.0
	door_to_char = door_to_char.normalized()

	# ドアの壁面法線（Z軸 = 壁の厚み方向、キャラクターが壁のどちら側にいるかを判定）
	var door_normal := door.global_transform.basis.z.normalized()
	door_normal.y = 0.0
	door_normal = door_normal.normalized()

	# キャラクターがドアのどちら側にいるかを判定
	var side_dot := door_normal.dot(door_to_char)

	# ドアはキャラクターから離れる方向に開く
	# side_dot > 0: キャラクターは壁の+Z側 → +Y回転（パネルが-Z方向へ）
	# side_dot < 0: キャラクターは壁の-Z側 → -Y回転（パネルが+Z方向へ）
	var rotation_amount := 170.0 if side_dot > 0 else -170.0

	# ヒンジを壁法線方向にシフト（パネルの壁フレームめり込み防止）
	# 開く方向と逆側（キャラクターから遠い側）にずらす
	var shift_dir := door_normal * (-1.0 if side_dot > 0 else 1.0)
	var hinge_shift := shift_dir * 0.1

	# ドアを「open_doors」グループに追加（他のキャラクターが通過可能になる）
	if not door.is_in_group("open_doors"):
		door.add_to_group("open_doors")

	# Tweenでドア回転+ヒンジシフトを並行実行
	var tween := create_tween()
	tween.set_parallel(true)
	var current_y := door.rotation_degrees.y

	# ヒンジ位置シフト（回転と同じ速度で同時進行）
	tween.tween_property(door, "global_position", door.global_position + hinge_shift, 0.4) \
		.set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_BACK)

	# ドアをY軸で回転（蝶番を軸に横開き）
	tween.tween_property(door, "rotation_degrees:y", current_y + rotation_amount, 0.4) \
		.set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_BACK)

	# ドアが開いた後に視界を強制更新（並行Tween完了後に順次実行）
	if _on_vision_update_callback.is_valid():
		tween.chain().tween_callback(_on_vision_update_callback)

	# シグナル発火
	door_opened.emit(door, character)


## ドア開けインパクト時（アニメーション途中、静かに開く）
## character: ドアを開けたキャラクター（位置から回転方向を計算）
func on_door_open_done(door: Node3D, character: CharacterBody3D) -> void:
	if not is_instance_valid(door) or not is_instance_valid(character):
		return

	# ローカルキャラクターの開けのみネットワークイベントを送信
	var game_char := character as GameCharacter
	if game_char and game_char.is_local() and _is_multiplayer_mode:
		var door_id := get_door_id(door)
		if door_id > 0:
			door_open_network_event.emit(door_id, game_char.network_id)

	# ドアを静かに開く処理を実行
	open_door_quietly(door, character)


## ドアを静かに開く処理（キックより穏やか: 160°回転、0.8秒、イーズイン/アウト）
func open_door_quietly(door: Node3D, character: CharacterBody3D) -> void:
	if not is_instance_valid(door) or not is_instance_valid(character):
		return

	# ドアからキャラクターへの方向ベクトル
	var door_to_char := (character.global_position - door.global_position)
	door_to_char.y = 0.0
	door_to_char = door_to_char.normalized()

	# ドアの壁面法線（Z軸 = 壁の厚み方向、キャラクターが壁のどちら側にいるかを判定）
	var door_normal := door.global_transform.basis.z.normalized()
	door_normal.y = 0.0
	door_normal = door_normal.normalized()

	# キャラクターがドアのどちら側にいるかを判定
	var side_dot := door_normal.dot(door_to_char)

	# ドアはキャラクターから離れる方向に開く（160°で大きく開放）
	var rotation_amount := 160.0 if side_dot > 0 else -160.0

	# ヒンジを壁法線方向にシフト（パネルの壁フレームめり込み防止）
	# 開く方向と逆側（キャラクターから遠い側）にずらす
	var shift_dir := door_normal * (-1.0 if side_dot > 0 else 1.0)
	var hinge_shift := shift_dir * 0.1

	# ドアを「open_doors」グループに追加（他のキャラクターが通過可能になる）
	if not door.is_in_group("open_doors"):
		door.add_to_group("open_doors")

	# Tweenでドア回転+ヒンジシフトを並行実行
	var tween := create_tween()
	tween.set_parallel(true)
	var current_y := door.rotation_degrees.y

	# ヒンジ位置シフト（回転と同じ速度で同時進行）
	tween.tween_property(door, "global_position", door.global_position + hinge_shift, 0.8) \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_CUBIC)

	# ドアをY軸で回転（キックより穏やかに: 0.8秒、EASE_IN_OUT）
	tween.tween_property(door, "rotation_degrees:y", current_y + rotation_amount, 0.8) \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_CUBIC)

	# ドアが開いた後に視界を強制更新（並行Tween完了後に順次実行）
	if _on_vision_update_callback.is_valid():
		tween.chain().tween_callback(_on_vision_update_callback)

	# シグナル発火
	door_opened.emit(door, character)


## ネットワークからのドア開けイベントを適用（リモート側用）
func apply_door_open_from_network(door_id: int, character_network_id: int) -> void:
	var door := get_door_by_id(door_id)
	if not door:
		push_warning("[DoorService] Door not found for network open: ", door_id)
		return

	# 既に開いているドアは無視
	if door.is_in_group("open_doors"):
		return

	if not _character_manager:
		push_warning("[DoorService] CharacterManager not set")
		return

	var character := _character_manager.find_character_by_network_id(character_network_id)
	if not character:
		push_warning("[DoorService] Character not found for door open: ", character_network_id)
		return

	# ローカルキャラクターのイベントは無視（二重処理防止）
	if character.is_local():
		return

	# ドアを静かに開く処理を実行
	open_door_quietly(door, character)


## ネットワークからのドアキックイベントを適用（リモート側用）
func apply_door_kick_from_network(door_id: int, character_network_id: int) -> void:
	var door := get_door_by_id(door_id)
	if not door:
		push_warning("[DoorService] Door not found for network kick: ", door_id)
		return

	# 既に開いているドアは無視
	if door.is_in_group("open_doors"):
		return

	if not _character_manager:
		push_warning("[DoorService] CharacterManager not set")
		return

	var character := _character_manager.find_character_by_network_id(character_network_id)
	if not character:
		push_warning("[DoorService] Character not found for door kick: ", character_network_id)
		return

	# ローカルキャラクターのイベントは無視（二重処理防止）
	if character.is_local():
		return

	# ドアを開く処理を実行
	open_door(door, character)


## 登録されているドア数を取得
func get_registered_door_count() -> int:
	return _door_id_map.size()


## ドアが開いているか確認
func is_door_open(door: Node3D) -> bool:
	return door.is_in_group("open_doors")
