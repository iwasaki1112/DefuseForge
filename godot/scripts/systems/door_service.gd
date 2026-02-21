extends Node
class_name DoorService

## ドア管理サービス
## ドアID管理・ネットワーク同期を一元管理
## GameManagerから抽出されたコンポーネント

## ドア開けネットワークイベント（マルチプレイヤー同期用）
signal door_open_network_event(door_id: int, character_network_id: int)
## ドアキックネットワークイベント（マルチプレイヤー同期用）
signal door_kick_network_event(door_id: int, character_network_id: int)
## キックダメージ発生（マルチプレイヤーダメージ同期用）
signal kick_damage_dealt(attacker_network_id: int, target_network_id: int, damage: float)
## ドア開閉完了シグナル
signal door_opened(door: Node3D, character: Node)
## ドア閉めネットワークイベント（マルチプレイヤー同期用）
signal door_close_network_event(door_id: int, character_network_id: int)
## ドア閉め完了シグナル（FoW更新用）
signal door_closed(door: Node3D)
## ドア開放アニメーション開始シグナル（FoWリアルタイム更新用）
signal door_opening_started(door: Node3D)
## ドア開放アニメーション完了シグナル（FoWリアルタイム更新用）
signal door_opening_finished(door: Node3D)

## ドアスイープテスト定数
const _SWEEP_STEP_DEG := 10.0  ## スイープの角度ステップ（度）
const _SWEEP_MARGIN_DEG := 3.0  ## 衝突マージン（度）
const _DOOR_PANEL_SIZE := Vector3(1.2, 2.0, 0.154)  ## ドアパネルのコリジョンサイズ（実寸1.0m + マージン0.1m×2）
const _DOOR_PANEL_CENTER := Vector3(-0.6, 1.0, 0.0)  ## パネル中心（ヒンジからのオフセット）

## ドアの元のTransform保存（ドア閉め用）
var _door_original_transforms: Dictionary = {}  ## door_node -> Transform3D

## ドアID管理（マルチプレイヤー同期用）
var _next_door_id: int = 1
var _door_id_map: Dictionary[Node3D, int] = {}  ## door_node -> door_id
var _id_to_door: Dictionary[int, Node3D] = {}   ## door_id -> door_node

## 外部参照
var _character_manager: CharacterManagerService = null
var _is_multiplayer_mode: bool = false

## 視界更新コールバック（ドア開閉時）
var _on_vision_update_callback: Callable = Callable()

## チーム別可視性システム（敵チームのドア開放をFoW確認まで保留）
var _pending_enemy_doors: Dictionary = {}  ## door -> { rotation_amount, hinge_shift, is_kick }
var _fow_system = null  ## FogOfWarSystem参照
var _fow_check_counter: int = 0
const _FOW_CHECK_INTERVAL: int = 15  ## ~4Hz at 60fps
const _FOW_CHECK_OFFSET := 1.0  ## FoWチェック位置のオフセット（ヒンジ周辺4方向をチェック）
const _ANIMATION_GRACE_FRAMES: int = 30  ## 保留後この frame 数以内に可視→アニメーション再生（~500ms at 60fps）
const _DOOR_VIS_NEAR_DISTANCE := 2.0  ## この距離以内なら方向不問で可視
const _DOOR_VIS_MAX_RANGE := 8.0  ## LOS チェックの最大距離
const _DOOR_VIS_FOV_MARGIN_DEG := 10.0  ## 視野角マージン（度）


func _ready() -> void:
	set_process(false)


## セットアップ
func setup(character_manager: CharacterManagerService = null) -> void:
	_character_manager = character_manager


## マルチプレイヤーモードを設定
func set_multiplayer_mode(enabled: bool) -> void:
	_is_multiplayer_mode = enabled


## 視界更新コールバックを設定
func set_vision_update_callback(callback: Callable) -> void:
	_on_vision_update_callback = callback


## FogOfWarSystemの参照を設定（GameManagerから呼ばれる）
func set_fow_system(fow) -> void:
	_fow_system = fow


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
	_pending_enemy_doors.clear()
	_door_original_transforms.clear()
	set_process(false)


## マップ内の全ドアを登録（"doors"グループから取得）
func register_all_doors_in_map() -> void:
	var doors := get_tree().get_nodes_in_group("doors")
	for door in doors:
		if door is Node3D:
			register_door(door)


## ドアを開く処理（ローカル・リモート共通）
func open_door(door: Node3D, character: CharacterBody3D) -> void:
	if not is_instance_valid(door) or not is_instance_valid(character):
		return

	# 保留中の敵ドアをクリア（プレイヤーが先に開けた場合）
	_pending_enemy_doors.erase(door)

	var params := _calculate_door_open_params(door, character, true)
	if params.is_empty():
		return

	_execute_door_open(door, params)
	door_opened.emit(door, character)


## ドア開けインパクト時（アニメーション途中、静かに開く）
## character: ドアを開けたキャラクター（位置から回転方向を計算）
func on_door_open_done(door: Node3D, character: CharacterBody3D) -> void:
	if not is_instance_valid(door) or not is_instance_valid(character):
		return

	# 保留中の敵ドアをクリア（プレイヤーが先に開けた場合）
	_pending_enemy_doors.erase(door)

	# ローカルキャラクターの開けのみネットワークイベントを送信
	var game_char := character as GameCharacter
	if game_char and game_char.is_local() and _is_multiplayer_mode:
		var door_id := get_door_id(door)
		if door_id > 0:
			door_open_network_event.emit(door_id, game_char.network_id)

	# 敵チームのCPUキャラクターがドアを開けた場合、FoWで可視になるまで保留
	if _fow_system and game_char and game_char.team != PlayerState.get_player_team():
		var params := _calculate_door_open_params(door, character, false)
		if not params.is_empty():
			_defer_enemy_door_open(door, params)
		return

	# 味方チーム or FoWなし → 即座に開く
	open_door_quietly(door, character)


## ドアを静かに開く処理（キックより穏やか: 160°回転、0.8秒、イーズイン/アウト）
func open_door_quietly(door: Node3D, character: CharacterBody3D) -> void:
	if not is_instance_valid(door) or not is_instance_valid(character):
		return

	# 保留中の敵ドアをクリア（プレイヤーが先に開けた場合）
	_pending_enemy_doors.erase(door)

	var params := _calculate_door_open_params(door, character, false)
	if params.is_empty():
		return

	_execute_door_open(door, params)
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

	# 既に保留中のドアは無視
	if _pending_enemy_doors.has(door):
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

	# チーム判定：敵チームのドア開けはバッファに保留（次フレームでFoWチェック）
	if _fow_system and character.team != PlayerState.get_player_team():
		var params := _calculate_door_open_params(door, character, false)
		if not params.is_empty():
			_defer_enemy_door_open(door, params)
		return

	# 味方チーム or FoWなし → 即座に開く
	open_door_quietly(door, character)


## 登録されているドア数を取得
func get_registered_door_count() -> int:
	return _door_id_map.size()


## ドアが開いているか確認
func is_door_open(door: Node3D) -> bool:
	return door.is_in_group("open_doors")


## ========================================
## チーム別可視性システム
## ========================================

## ドア開きパラメータを計算（open_door / open_door_quietly 共通ロジック）
## is_kick: true=キック（170°, 0.4s, BACK）、false=静かに開く（160°, 0.8s, CUBIC）
func _calculate_door_open_params(door: Node3D, character: CharacterBody3D, is_kick: bool) -> Dictionary:
	# ドアからキャラクターへの方向ベクトル
	var door_to_char := (character.global_position - door.global_position)
	door_to_char.y = 0.0
	door_to_char = door_to_char.normalized()

	# ドアの壁面法線（Z軸 = 壁の厚み方向）
	var door_normal := door.global_transform.basis.z.normalized()
	door_normal.y = 0.0
	door_normal = door_normal.normalized()

	# キャラクターがドアのどちら側にいるかを判定
	var side_dot := door_normal.dot(door_to_char)

	# 回転量（キック: 170°、静かに: 160°）
	var base_angle := 170.0 if is_kick else 160.0
	var rotation_amount := -base_angle if side_dot > 0 else base_angle

	# 壁との衝突を考慮して最大開角度を制限
	rotation_amount = _calculate_max_opening_angle(door, rotation_amount)
	if is_zero_approx(rotation_amount):
		return {}  # 完全にブロックされている

	# ヒンジシフト（パネルの壁フレームめり込み防止）
	var shift_dir := door_normal * (-1.0 if side_dot > 0 else 1.0)
	var hinge_shift := shift_dir * 0.1

	return {
		"rotation_amount": rotation_amount,
		"hinge_shift": hinge_shift,
		"is_kick": is_kick,
	}


## ドアを開くTweenを実行（パラメータに基づいてアニメーション再生）
## instant: trueの場合アニメーションなしで即座に開いた状態にする
func _execute_door_open(door: Node3D, params: Dictionary, instant: bool = false) -> void:
	# 開く前のTransformを保存（閉める際に使用、まだ保存されていない場合のみ）
	if not _door_original_transforms.has(door):
		_door_original_transforms[door] = door.global_transform

	# ドアを「open_doors」グループに追加（他のキャラクターが通過可能になる）
	if not door.is_in_group("open_doors"):
		door.add_to_group("open_doors")

	var rotation_amount: float = params["rotation_amount"]
	var hinge_shift: Vector3 = params["hinge_shift"]

	if instant:
		# 即座に開いた状態にする（保留ドアがFoW可視になった場合）
		door.global_position += hinge_shift
		door.rotation_degrees.y += rotation_amount
		door_opening_finished.emit(door)
		if _on_vision_update_callback.is_valid():
			_on_vision_update_callback.call()
		return

	var is_kick: bool = params["is_kick"]

	# FoWオクルーダーのリアルタイム更新を開始
	door_opening_started.emit(door)

	# Tween設定（キック: 0.4s BACK, 静かに: 0.8s CUBIC）
	var duration := 0.4 if is_kick else 0.8
	var ease_type := Tween.EASE_OUT if is_kick else Tween.EASE_IN_OUT
	var trans_type := Tween.TRANS_BACK if is_kick else Tween.TRANS_CUBIC

	var tween := create_tween()
	tween.set_parallel(true)
	var current_y := door.rotation_degrees.y

	# ヒンジ位置シフト
	tween.tween_property(door, "global_position", door.global_position + hinge_shift, duration) \
		.set_ease(ease_type) \
		.set_trans(trans_type)

	# ドアをY軸で回転（蝶番を軸に横開き）
	tween.tween_property(door, "rotation_degrees:y", current_y + rotation_amount, duration) \
		.set_ease(ease_type) \
		.set_trans(trans_type)

	# ドアが開いた後にFoWオクルーダーアニメーション停止＋視界を強制更新
	tween.chain().tween_callback(func():
		door_opening_finished.emit(door)
		if _on_vision_update_callback.is_valid():
			_on_vision_update_callback.call()
	)


## 敵チームのドア開放をバッファに保留（FoW確認まで開かない）
func _defer_enemy_door_open(door: Node3D, params: Dictionary) -> void:
	params["deferred_frame"] = Engine.get_physics_frames()
	_pending_enemy_doors[door] = params
	# 次フレームで即座にFoWチェックを実行させる
	_fow_check_counter = _FOW_CHECK_INTERVAL - 1
	set_process(true)


## 保留中のドアを公開（FoWで可視になった時点で呼ばれる）
func _reveal_deferred_door(door: Node3D) -> void:
	var params: Dictionary = _pending_enemy_doors.get(door, {})
	_pending_enemy_doors.erase(door)

	if not is_instance_valid(door) or params.is_empty():
		if _pending_enemy_doors.is_empty():
			set_process(false)
		return

	# 保留から短時間ならアニメーション再生（目の前で開いた場合）
	# 長時間経過なら即座に開いた状態にする（既に開いていたドアを後から見た場合）
	var deferred_frame: int = params.get("deferred_frame", 0)
	var is_recent := (Engine.get_physics_frames() - deferred_frame) < _ANIMATION_GRACE_FRAMES
	if params.get("is_fall", false):
		_execute_door_fall(door, params, not is_recent)
	else:
		_execute_door_open(door, params, not is_recent)
	door_opened.emit(door, null)

	if _pending_enemy_doors.is_empty():
		set_process(false)


## 保留中のドアのFoW可視性を定期チェック
func _process(_delta: float) -> void:
	if _pending_enemy_doors.is_empty():
		set_process(false)
		return

	_fow_check_counter += 1
	if _fow_check_counter < _FOW_CHECK_INTERVAL:
		return
	_fow_check_counter = 0

	# バッファ内のドアを可視性チェック（イテレーション中の変更を避けるため先に収集）
	var doors_to_reveal: Array = []
	for door: Node3D in _pending_enemy_doors:
		if not is_instance_valid(door):
			doors_to_reveal.append(door)
			continue
		if _is_door_visible_to_local_team(door):
			doors_to_reveal.append(door)

	for door in doors_to_reveal:
		_reveal_deferred_door(door)


## ドアがローカルチームから可視かどうか判定
## 1) FoWチェック（高速パス）
## 2) Raycast LOSチェック（FoWオクルーダー循環依存の回避）
func _is_door_visible_to_local_team(door: Node3D) -> bool:
	# FoWチェック（高速パス — オクルーダー問題がなければこれで検出できる）
	if _fow_system:
		var door_basis := door.global_transform.basis
		var door_normal := door_basis.z
		door_normal.y = 0.0
		door_normal = door_normal.normalized()
		var door_right := door_basis.x
		door_right.y = 0.0
		door_right = door_right.normalized()
		var pos := door.global_position
		if _fow_system.is_position_visible_in_fow(pos + door_normal * _FOW_CHECK_OFFSET):
			return true
		if _fow_system.is_position_visible_in_fow(pos - door_normal * _FOW_CHECK_OFFSET):
			return true
		if _fow_system.is_position_visible_in_fow(pos + door_right * _FOW_CHECK_OFFSET):
			return true
		if _fow_system.is_position_visible_in_fow(pos - door_right * _FOW_CHECK_OFFSET):
			return true

	# Raycast LOSチェック（FoWオクルーダー循環依存の回避）
	if not _character_manager:
		return false
	var panel_center := door.global_position + door.global_transform.basis * _DOOR_PANEL_CENTER
	for node in _character_manager.get_local_friendly_characters():
		var character := node as GameCharacter
		if not is_instance_valid(character) or not character.is_alive:
			continue
		if _can_character_see_door(character, door, panel_center):
			return true
	return false


## キャラクターがドアを視認できるか判定（距離 + 視野角 + LOS raycast）
func _can_character_see_door(character: GameCharacter, door: Node3D, panel_center: Vector3) -> bool:
	var to_door := panel_center - character.global_position
	to_door.y = 0.0
	var dist := to_door.length()

	# 近距離: 方向不問で可視（ドアのすぐ前に立っている場合）
	if dist < _DOOR_VIS_NEAR_DISTANCE:
		return true

	# 距離チェック
	if dist > _DOOR_VIS_MAX_RANGE:
		return false

	# 方向チェック（視野角内か）
	var facing := character.get_facing_direction()
	facing.y = 0.0
	if facing.length_squared() > 0.001 and to_door.length_squared() > 0.001:
		var half_fov := 37.5  # デフォルト 75° / 2
		if character.vision:
			half_fov = character.vision.fov_degrees * 0.5
		var angle := rad_to_deg(facing.normalized().angle_to(to_door.normalized()))
		if angle > half_fov + _DOOR_VIS_FOV_MARGIN_DEG:
			return false

	# LOS raycast（壁のみチェック、ドア自身のヒットは許可）
	var space := character.get_world_3d().direct_space_state
	if not space:
		return false
	var eye_height := 1.5
	if character.vision:
		eye_height = character.vision.eye_height
	var eye_pos := character.global_position + Vector3.UP * eye_height
	var target := Vector3(panel_center.x, eye_pos.y, panel_center.z)
	var query := PhysicsRayQueryParameters3D.create(eye_pos, target, MapBase.WALL_COLLISION_LAYER)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true  # 壁なし → 可視
	# ヒットしたのがドア自身なら可視（ドアパネルのコリジョン）
	var collider = hit.get("collider")
	if collider is Node:
		if collider == door or door.is_ancestor_of(collider as Node):
			return true
	return false


## ========================================
## スイープテスト
## ========================================

## ドアが壁と衝突せずに開ける最大角度を計算（スイープテスト）
## 10°刻みでドアパネルのコリジョンを回転させ、壁との衝突を検出
func _calculate_max_opening_angle(door: Node3D, target_angle: float) -> float:
	var space_state := door.get_world_3d().direct_space_state
	if not space_state:
		return target_angle

	var exclude_rids: Array[RID] = _collect_door_exclude_rids(door)

	var test_shape := BoxShape3D.new()
	test_shape.size = _DOOR_PANEL_SIZE

	var angle_sign := signf(target_angle)
	var abs_target := absf(target_angle)

	var angle := _SWEEP_STEP_DEG
	while angle <= abs_target:
		var test_rad := deg_to_rad(angle * angle_sign)
		var rotated_basis := door.global_transform.basis * Basis(Vector3.UP, test_rad)
		var panel_center_world := door.global_position + rotated_basis * _DOOR_PANEL_CENTER

		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = test_shape
		query.transform = Transform3D(rotated_basis, panel_center_world)
		query.collision_mask = MapBase.WALL_COLLISION_LAYER
		query.exclude = exclude_rids

		var results := space_state.intersect_shape(query, 1)
		if results.size() > 0:
			# 衝突検出 — 前のステップの角度からマージンを引いた値を返す
			var safe_angle := angle - _SWEEP_STEP_DEG - _SWEEP_MARGIN_DEG
			if safe_angle <= 0.0:
				return 0.0
			return safe_angle * angle_sign

		angle += _SWEEP_STEP_DEG

	return target_angle


## ドアの除外RIDを収集（パネル自身のコリジョン＋ドアフレーム）
func _collect_door_exclude_rids(door: Node3D) -> Array[RID]:
	var rids: Array[RID] = []

	# ドアパネル自身のコリジョンボディ（PanelCollision）
	for child in door.get_children():
		if child is StaticBody3D:
			rids.append(child.get_rid())

	# ドアフレームのコリジョンボディ（同じGridMap内の近隣door系StaticBody3D）
	var parent := door.get_parent()
	if parent:
		for sibling in parent.get_children():
			if sibling is StaticBody3D and "door" in sibling.name.to_lower():
				if sibling.global_position.distance_to(door.global_position) < 3.0:
					rids.append(sibling.get_rid())

	return rids


## ========================================
## ドアキック処理
## ========================================

## ドアキックインパクト時（DoorServiceに委譲される）
## ネットワークイベント発火 → ドア倒壊 → キックダメージ適用
func on_door_kick_done(door: Node3D, character: CharacterBody3D) -> void:
	if not is_instance_valid(door) or not is_instance_valid(character):
		return

	# 保留中の敵ドアをクリア
	_pending_enemy_doors.erase(door)

	# ローカルキャラクターのキックのみネットワークイベントを送信
	var game_char := character as GameCharacter
	if game_char and game_char.is_local() and _is_multiplayer_mode:
		var door_id := get_door_id(door)
		if door_id > 0:
			door_kick_network_event.emit(door_id, game_char.network_id)

	# ドアを倒す（開くのではなく蹴り倒す）
	var params := _calculate_door_fall_params(door, character)
	_execute_door_fall(door, params)
	door_opened.emit(door, character)

	# キックダメージを適用（キッカーの反対側の敵にダメージ）
	_apply_kick_damage(door, character)


## ドア倒壊パラメータを計算（キッカーの反対側に倒れる）
func _calculate_door_fall_params(door: Node3D, character: CharacterBody3D) -> Dictionary:
	var door_to_char := (character.global_position - door.global_position)
	door_to_char.y = 0.0
	door_to_char = door_to_char.normalized()

	var door_normal := door.global_transform.basis.z.normalized()
	door_normal.y = 0.0
	door_normal = door_normal.normalized()

	var side_dot := door_normal.dot(door_to_char)
	# キッカーの反対側に倒れる（+Z側にいる→-Z方向に倒れる）
	# ローカルX軸正回転=上端が+Z方向へ倒れるので、+Z側キッカーなら負回転
	var fall_angle := -90.0 if side_dot > 0 else 90.0
	var fall_dir := -door_normal if side_dot > 0 else door_normal

	return {
		"fall_angle": fall_angle,
		"fall_dir": fall_dir,
		"is_fall": true,
	}


## ドア倒壊Tweenを実行（キックで蹴り倒す）
## ドアのローカルX軸を支点に90°回転させて倒す
func _execute_door_fall(door: Node3D, params: Dictionary, instant: bool = false) -> void:
	if not door.is_in_group("open_doors"):
		door.add_to_group("open_doors")
	if not door.is_in_group("fallen_doors"):
		door.add_to_group("fallen_doors")

	var fall_angle: float = params["fall_angle"]
	var fall_dir: Vector3 = params["fall_dir"]

	if instant:
		# 即座に倒れた状態にする（保留ドアがFoW可視になった場合）
		door.global_transform.basis = door.global_transform.basis * Basis(Vector3.RIGHT, deg_to_rad(fall_angle))
		door.global_position += fall_dir * 0.3
		door_opening_finished.emit(door)
		# 倒れたドアは地面に横たわるためFoW遮蔽を無効化
		if _fow_system:
			_fow_system.set_door_occluder_enabled(door, false)
		if _on_vision_update_callback.is_valid():
			_on_vision_update_callback.call()
		return

	var initial_basis := door.global_transform.basis
	var target_basis := initial_basis * Basis(Vector3.RIGHT, deg_to_rad(fall_angle))
	var target_pos := door.global_position + fall_dir * 0.3

	door_opening_started.emit(door)

	var tween := create_tween()
	tween.set_parallel(true)

	# Basis補間で倒壊アニメーション（重力加速 = EASE_IN + QUAD）
	tween.tween_method(
		func(t: float):
			if is_instance_valid(door):
				door.global_transform.basis = initial_basis.slerp(target_basis, t),
		0.0, 1.0, 0.4
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	# 倒れる方向に少し移動
	tween.tween_property(door, "global_position", target_pos, 0.4) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	tween.chain().tween_callback(func():
		door_opening_finished.emit(door)
		# 倒れたドアは地面に横たわるためFoW遮蔽を無効化
		if _fow_system:
			_fow_system.set_door_occluder_enabled(door, false)
		if _on_vision_update_callback.is_valid():
			_on_vision_update_callback.call()
	)


## キックダメージ適用: ドアのキッカー反対側にいる敵キャラにダメージ
func _apply_kick_damage(door: Node3D, kicker: CharacterBody3D) -> void:
	var space_state := door.get_world_3d().direct_space_state
	if not space_state:
		return

	# ドアの壁面法線（Z軸）でキッカーの側面を判定
	var door_normal := door.global_transform.basis.z.normalized()
	door_normal.y = 0.0
	door_normal = door_normal.normalized()

	var door_to_kicker := (kicker.global_position - door.global_position)
	door_to_kicker.y = 0.0
	var side_dot := door_normal.dot(door_to_kicker.normalized())

	# キッカーの反対側の方向（ドア法線ベース）
	var opposite_dir := -door_normal if side_dot > 0 else door_normal

	# パネル中心を基準に検知ボックスを配置（ヒンジではなくドア面の中央）
	var panel_center := door.global_position + door.global_transform.basis * _DOOR_PANEL_CENTER
	var detect_center := panel_center + opposite_dir * 0.75
	detect_center.y = door.global_position.y + 1.0

	var shape := BoxShape3D.new()
	shape.size = Vector3(GameConstants.DOOR_KICK_DAMAGE_RADIUS * 2.0, 2.0, GameConstants.DOOR_KICK_DAMAGE_RADIUS * 2.0)

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), detect_center)
	query.collision_mask = 1  # キャラクターレイヤー

	var results: Array[Dictionary] = space_state.intersect_shape(query)
	var kicker_char := kicker as GameCharacter

	for result: Dictionary in results:
		var collider: Object = result.collider
		var character: GameCharacter = _find_game_character(collider)
		if not character or not character.is_alive:
			continue
		# キッカー自身はスキップ
		if character == kicker_char:
			continue
		# 敵のみダメージ（味方は安全）
		if kicker_char and not character.is_enemy_of(kicker_char):
			continue
		character.take_damage(GameConstants.DOOR_KICK_DAMAGE)
		# マルチプレイヤー: ダメージをネットワーク同期（被害者の所有クライアントに伝達）
		if _is_multiplayer_mode and kicker_char:
			kick_damage_dealt.emit(kicker_char.network_id, character.network_id, GameConstants.DOOR_KICK_DAMAGE)


## コライダーからGameCharacterを探す（grenade.gdと同パターン）
func _find_game_character(node: Object) -> GameCharacter:
	var current: Node = node as Node
	while current:
		if current is GameCharacter:
			return current
		current = current.get_parent()
	return null


## ネットワークからのドアキックイベントを適用（リモート側用）
func apply_door_kick_from_network(door_id: int, character_network_id: int) -> void:
	var door := get_door_by_id(door_id)
	if not door:
		push_warning("[DoorService] Door not found for network kick: ", door_id)
		return

	# 既に開いているドアは無視
	if door.is_in_group("open_doors"):
		return

	# 既に保留中のドアは無視
	if _pending_enemy_doors.has(door):
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

	# チーム判定：敵チームのドアキックはバッファに保留（次フレームでFoWチェック）
	if _fow_system and character.team != PlayerState.get_player_team():
		var enemy_params := _calculate_door_fall_params(door, character)
		_defer_enemy_door_open(door, enemy_params)
		return

	# 味方チーム or FoWなし → 即座にキック倒壊実行（ダメージはDAMAGEイベント経由）
	var params := _calculate_door_fall_params(door, character)
	_execute_door_fall(door, params)
	door_opened.emit(door, character)


## ========================================
## ドア閉め処理
## ========================================

## ドアがキックで壊れているか判定
func is_door_fallen(door: Node3D) -> bool:
	return door.is_in_group("fallen_doors")


## ドア閉めインパクト時（GameScreenから呼ばれる）
## ネットワークイベント発火 → ドア閉め実行
func on_door_close_done(door: Node3D, character: CharacterBody3D) -> void:
	if not is_instance_valid(door) or not is_instance_valid(character):
		return

	# ローカルキャラクターの閉めのみネットワークイベントを送信
	var game_char := character as GameCharacter
	if game_char and game_char.is_local() and _is_multiplayer_mode:
		var door_id := get_door_id(door)
		if door_id > 0:
			door_close_network_event.emit(door_id, game_char.network_id)

	close_door(door)


## ドアを閉める（保存済みTransformにTweenで戻す）
func close_door(door: Node3D) -> void:
	if not is_instance_valid(door):
		return

	if not _door_original_transforms.has(door):
		push_warning("[DoorService] No original transform saved for door")
		return

	var original_transform: Transform3D = _door_original_transforms[door]

	# FoWオクルーダーアニメーション開始
	door_opening_started.emit(door)

	var tween := create_tween()
	tween.set_parallel(true)

	# 元の位置に戻す
	tween.tween_property(door, "global_position", original_transform.origin, 0.8) \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_CUBIC)

	# 元の回転に戻す
	tween.tween_property(door, "rotation_degrees:y", rad_to_deg(original_transform.basis.get_euler().y), 0.8) \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_CUBIC)

	tween.chain().tween_callback(func():
		# open_doorsグループから除去
		if door.is_in_group("open_doors"):
			door.remove_from_group("open_doors")

		# 保存済みTransformを削除
		_door_original_transforms.erase(door)

		# FoWオクルーダーを再有効化
		door_opening_finished.emit(door)
		if _fow_system:
			_fow_system.set_door_occluder_enabled(door, true)
		if _on_vision_update_callback.is_valid():
			_on_vision_update_callback.call()

		door_closed.emit(door)
	)


## ネットワークからのドア閉めイベントを適用（リモート側用）
func apply_door_close_from_network(door_id: int, character_network_id: int) -> void:
	var door := get_door_by_id(door_id)
	if not door:
		push_warning("[DoorService] Door not found for network close: ", door_id)
		return

	# 閉じているドアは無視
	if not door.is_in_group("open_doors"):
		return

	if not _character_manager:
		push_warning("[DoorService] CharacterManager not set")
		return

	var character := _character_manager.find_character_by_network_id(character_network_id)
	if not character:
		push_warning("[DoorService] Character not found for door close: ", character_network_id)
		return

	# ローカルキャラクターのイベントは無視（二重処理防止）
	if character.is_local():
		return

	close_door(door)
