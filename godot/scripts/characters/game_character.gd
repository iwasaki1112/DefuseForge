extends CharacterBody3D
class_name GameCharacter
## Character management class
## Provides HP, death state, and team management
## Works with CharacterAnimationController for animations

# Effect constants moved to MuzzleFlashComponent and BulletTrailComponent

# ============================================
# Team Definition
# ============================================
enum Team { NONE = 0, COUNTER_TERRORIST = 1, TERRORIST = 2 }

# ============================================
# Signals
# ============================================
signal died(character: GameCharacter)
signal state_changed(character: GameCharacter)  ## マルチプレイヤー用：状態変更通知

# ============================================
# Export Settings
# ============================================
@export_group("HP Settings")
@export var max_health: float = 100.0

@export_group("Team Settings")
@export var team: Team = Team.NONE

@export_group("UI Settings")
## キャラクターマーカー名（alpha, bravo, ares, brim）
@export var marker_name: String = ""

# ============================================
# Network Identity (Multiplayer)
# ============================================

## ネットワーク上のグローバルID（0はローカル専用）
var network_id: int = 0

## 所有者のpeer_id（0はローカル/未割当）
var owner_peer_id: int = 0

## キャラクタープリセットID（ネットワーク同期用）
var character_preset_id: String = ""

# ============================================
# State
# ============================================
var current_health: float = 100.0
var is_alive: bool = true

# ============================================
# Remote Interpolation (リモートキャラクター用補間)
# ============================================
## 旧実装との互換用（to_character_state()で使用）
var _remote_target_animation_state: String = ""

# ============================================
# Facing Direction (一元管理)
# ============================================
## キャラクターの向き（正規化済みXZ平面ベクトル）
## すべてのコンポーネント（Animation, Vision）はこれを参照する
var _facing_direction: Vector3 = Vector3.FORWARD

## 手動回転中フラグ（長押しによるユーザー操作中）
## このフラグがtrueの間は、敵の自動追跡を一時停止する
var _is_manual_rotating: bool = false

# ============================================
# References
# ============================================
var anim_ctrl: CharacterAnimationController = null  # CharacterAnimationController
var vision: VisionComponent = null  # VisionComponent for FoW
var combat_awareness: CombatAwarenessComponent = null  # CombatAwarenessComponent for enemy tracking
var remote_interpolation: RemoteInterpolationComponent = null  # Remote interpolation for multiplayer
var current_weapon: WeaponPreset = null  # WeaponPreset
var _weapon_attachment: BoneAttachment3D = null  # 武器アタッチメントノード
var _weapon_socket: Node3D = null  # 武器調整用ソケットノード
var _weapon_model: Node3D = null  # 現在の武器モデル
var muzzle_flash: MuzzleFlashComponent = null  # マズルフラッシュコンポーネント
var bullet_trail: BulletTrailComponent = null  # 弾道表示コンポーネント

# ============================================
# Lifecycle
# ============================================

func _ready() -> void:
	current_health = max_health
	is_alive = true
	add_to_group(GameConstants.GROUP_CHARACTERS)
	# リモート補間コンポーネントをセットアップ
	_setup_remote_interpolation()
	# エフェクトコンポーネントをセットアップ
	_setup_effect_components()


## リモート補間コンポーネントをセットアップ
func _setup_remote_interpolation() -> void:
	if remote_interpolation == null:
		remote_interpolation = RemoteInterpolationComponent.new()
		remote_interpolation.setup(self)


## エフェクトコンポーネントをセットアップ
func _setup_effect_components() -> void:
	if muzzle_flash == null:
		muzzle_flash = MuzzleFlashComponent.new()
		muzzle_flash.setup(self, _weapon_socket)
	if bullet_trail == null:
		bullet_trail = BulletTrailComponent.new()
		bullet_trail.setup(self, _weapon_socket, muzzle_flash, combat_awareness)

# ============================================
# HP API
# ============================================

## Take damage
func take_damage(amount: float, attacker: Node3D = null, is_headshot: bool = false) -> void:
	if not is_alive:
		return

	current_health = max(0.0, current_health - amount)

	if current_health <= 0.0:
		_die(attacker, is_headshot)

## Heal
func heal(amount: float) -> void:
	if not is_alive:
		return
	current_health = min(max_health, current_health + amount)

## Get health ratio (0.0 - 1.0)
func get_health_ratio() -> float:
	return current_health / max_health if max_health > 0 else 0.0

## Reset health
func reset_health() -> void:
	current_health = max_health
	is_alive = true
	# Re-enable vision on respawn
	if vision:
		vision.enable()

# ============================================
# Team API
# ============================================

## Check if target is enemy team
func is_enemy_of(other: GameCharacter) -> bool:
	if other == null:
		return false
	if team == Team.NONE or other.team == Team.NONE:
		return false
	return team != other.team

# ============================================
# Animation Controller API
# ============================================

## Set CharacterAnimationController
func set_anim_controller(controller: CharacterAnimationController) -> void:
	if anim_ctrl and anim_ctrl.fired.is_connected(_on_anim_fired):
		anim_ctrl.fired.disconnect(_on_anim_fired)
	anim_ctrl = controller
	if anim_ctrl and not anim_ctrl.fired.is_connected(_on_anim_fired):
		anim_ctrl.fired.connect(_on_anim_fired)

## Get CharacterAnimationController
func get_anim_controller() -> CharacterAnimationController:
	return anim_ctrl

# ============================================
# Facing Direction API (一元管理)
# ============================================

## キャラクターの向きを設定（ベクトル）
## Animation、Visionすべてがこの向きを参照する
func set_facing_direction_vec(direction: Vector3) -> void:
	direction.y = 0
	if direction.length_squared() < 0.001:
		return
	_facing_direction = direction.normalized()
	# ローカルキャラクターのみ即座にモデル向きを更新
	# リモートキャラクターは update_remote_interpolation() で四元数SLERP補間を使用
	if is_local() and anim_ctrl:
		anim_ctrl.set_model_direction(_facing_direction)


## キャラクターの向きを設定（Y軸回転、ラジアン）
func set_facing_direction(y_rotation: float) -> void:
	# y_rotation=0 → +Z方向（モデルの前方向）
	var direction := Vector3(sin(y_rotation), 0, cos(y_rotation))
	set_facing_direction_vec(direction)


## ターゲット位置の方向を向く
func face_towards(target_pos: Vector3) -> void:
	var dir := target_pos - global_position
	set_facing_direction_vec(dir)


## 現在の向きを取得（すべてのコンポーネントはこれを参照すべき）
func get_facing_direction() -> Vector3:
	return _facing_direction


## 手動回転モードを設定（長押し回転中に呼ばれる）
func set_manual_rotating(rotating: bool) -> void:
	_is_manual_rotating = rotating


## 手動回転中かどうかを取得
func is_manual_rotating() -> bool:
	return _is_manual_rotating

# ============================================
# Vision Component API
# ============================================

## Set VisionComponent
func set_vision_component(component: VisionComponent) -> void:
	vision = component

## Get VisionComponent
func get_vision_component() -> VisionComponent:
	return vision

## Setup vision component (auto-create if not exists)
func setup_vision(fov: float = 90.0, view_dist: float = 15.0) -> VisionComponent:
	if vision == null:
		vision = VisionComponent.new()
		vision.name = GameConstants.NODE_VISION_COMPONENT
		add_child(vision)

	vision.set_fov(fov)
	vision.set_view_distance(view_dist)
	return vision

# ============================================
# Combat Awareness API
# ============================================

## Setup combat awareness component (auto-create if not exists)
func setup_combat_awareness() -> CombatAwarenessComponent:
	if combat_awareness == null:
		combat_awareness = CombatAwarenessComponent.new()
		combat_awareness.name = GameConstants.NODE_COMBAT_AWARENESS
		add_child(combat_awareness)
		combat_awareness.setup(self)
		# BulletTrailComponentにもCombatAwarenessを伝播
		if bullet_trail:
			bullet_trail.set_combat_awareness(combat_awareness)
	return combat_awareness


## Get CombatAwarenessComponent
func get_combat_awareness() -> CombatAwarenessComponent:
	return combat_awareness

# ============================================
# Weapon API
# ============================================

## Find Skeleton3D recursively in node tree
func _find_skeleton_in_node(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton_in_node(child)
		if result:
			return result
	return null


## Create or get BoneAttachment3D for weapon
func _ensure_weapon_attachment() -> BoneAttachment3D:
	if _weapon_attachment:
		return _weapon_attachment

	var model = get_node_or_null(GameConstants.NODE_CHARACTER_MODEL)
	if not model:
		push_warning("GameCharacter: CharacterModel not found")
		return null

	var skeleton = _find_skeleton_in_node(model)
	if not skeleton:
		push_warning("GameCharacter: Skeleton not found")
		return null

	var bone_idx = skeleton.find_bone(GameConstants.BONE_RIGHT_HAND)
	if bone_idx < 0:
		push_warning("GameCharacter: RightHand bone not found")
		return null

	_weapon_attachment = BoneAttachment3D.new()
	_weapon_attachment.name = GameConstants.NODE_WEAPON_ATTACHMENT
	_weapon_attachment.bone_name = GameConstants.BONE_RIGHT_HAND
	skeleton.add_child(_weapon_attachment)

	return _weapon_attachment


## Create or get WeaponSocket under BoneAttachment3D
func _ensure_weapon_socket(attachment: BoneAttachment3D) -> Node3D:
	if _weapon_socket and _weapon_socket.is_inside_tree():
		return _weapon_socket

	_weapon_socket = Node3D.new()
	_weapon_socket.name = GameConstants.NODE_WEAPON_SOCKET
	attachment.add_child(_weapon_socket)

	# エフェクトコンポーネントに武器ソケットを通知
	_update_effect_component_sockets()

	return _weapon_socket


## エフェクトコンポーネントの武器ソケット参照を更新
func _update_effect_component_sockets() -> void:
	if muzzle_flash:
		muzzle_flash.set_weapon_socket(_weapon_socket)
	if bullet_trail:
		bullet_trail.set_weapon_socket(_weapon_socket)


## Attach weapon model to right hand
func _attach_weapon_model(weapon: WeaponPreset) -> void:
	# Remove old weapon model
	if _weapon_model:
		_weapon_model.queue_free()
		_weapon_model = null

	if not weapon or not weapon.model_scene:
		push_warning("GameCharacter: No model_scene for weapon")
		return

	var attachment = _ensure_weapon_attachment()
	if not attachment:
		return

	var socket = _ensure_weapon_socket(attachment)
	if not socket:
		return

	_weapon_model = weapon.model_scene.instantiate()
	_weapon_model.name = GameConstants.NODE_WEAPON_MODEL
	socket.add_child(_weapon_model)

	# ARP skeleton is 1.0 scale, weapon at 1:1
	_weapon_model.scale = Vector3.ONE
	_weapon_model.position = Vector3.ZERO
	_weapon_model.rotation_degrees = Vector3.ZERO

	# Apply offset from WeaponPreset (use defaults for ARP if not set)
	if weapon.attach_offset != Vector3.ZERO:
		socket.position = weapon.attach_offset
	else:
		# Default offset for ARP right hand (要実機調整)
		socket.position = Vector3(0.01, 0.07, 0.02)

	if weapon.attach_rotation != Vector3.ZERO:
		socket.rotation_degrees = weapon.attach_rotation
	else:
		# Default rotation for ARP right hand (要実機調整)
		socket.rotation_degrees = Vector3(-79, -66, -28)

	# 左手IKグリップ設定
	_update_left_hand_ik(weapon)



## 左手IKグリップを武器モデルから検出してAnimationControllerに通知
func _update_left_hand_ik(weapon: WeaponPreset) -> void:
	if not anim_ctrl:
		return
	if not weapon or not weapon.left_hand_grip_enabled or not _weapon_model:
		anim_ctrl.set_left_hand_grip(null)
		return

	var grip_node := _weapon_model.get_node_or_null(GameConstants.NODE_LEFT_HAND_GRIP) as Node3D
	if grip_node:
		anim_ctrl.set_left_hand_grip(grip_node)
	else:
		anim_ctrl.set_left_hand_grip(null)


## Equip a weapon from WeaponPreset
## Applies weapon type and recoil settings to CharacterAnimationController
## Also attaches weapon model to right hand bone
func equip_weapon(weapon: WeaponPreset) -> void:
	current_weapon = weapon

	# Attach weapon model to right hand
	_attach_weapon_model(weapon)

	if not anim_ctrl:
		return

	# Convert WeaponCategory to CharacterAnimationController.Weapon
	# WeaponCategory: RIFLE=0, PISTOL=1, SMG=2, SHOTGUN=3, SNIPER=4
	# Weapon: NONE=0, RIFLE=1, PISTOL=2
	var weapon_type: CharacterAnimationController.Weapon = CharacterAnimationController.Weapon.RIFLE
	if weapon.category == WeaponPreset.WeaponCategory.PISTOL:
		weapon_type = CharacterAnimationController.Weapon.PISTOL

	anim_ctrl.set_weapon(weapon_type)

	# Apply recoil settings directly to controller
	if "rifle_recoil_strength" in anim_ctrl:
		# Apply weapon's recoil to both rifle/pistol slots based on category
		if weapon.category == WeaponPreset.WeaponCategory.PISTOL:
			anim_ctrl.pistol_recoil_strength = weapon.recoil_strength
		else:
			anim_ctrl.rifle_recoil_strength = weapon.recoil_strength

	if "recoil_recovery" in anim_ctrl:
		anim_ctrl.recoil_recovery = weapon.recoil_recovery

## Get current weapon
func get_current_weapon() -> WeaponPreset:
	return current_weapon

## Get weapon socket node (for adjustment/tools)
func get_weapon_socket() -> Node3D:
	return _weapon_socket

# ============================================
# Muzzle Flash & Bullet Trail (コンポーネント委譲)
# ============================================

func _on_anim_fired() -> void:
	_play_muzzle_flash()
	_play_bullet_trail()


func set_muzzle_flash_preview(enabled: bool) -> void:
	if muzzle_flash:
		muzzle_flash.set_preview(enabled, current_weapon, _weapon_model)


func update_muzzle_flash_preview() -> void:
	if muzzle_flash:
		muzzle_flash.update_preview(current_weapon, _weapon_model)


func _play_muzzle_flash() -> void:
	if muzzle_flash:
		muzzle_flash.play(current_weapon, _weapon_model)


func _play_bullet_trail() -> void:
	if bullet_trail:
		bullet_trail.play(current_weapon, _weapon_model)


## Set Quad1 X offset for muzzle flash adjustment
func set_muzzle_flash_quad1_x(x_offset: float) -> void:
	if muzzle_flash:
		muzzle_flash.set_quad1_x(x_offset)


## Get Quad1 X offset
func get_muzzle_flash_quad1_x() -> float:
	if muzzle_flash:
		return muzzle_flash.get_quad1_x()
	return 0.032


## Set Quad1 Z offset for muzzle flash adjustment
func set_muzzle_flash_quad1_z(z_offset: float) -> void:
	if muzzle_flash:
		muzzle_flash.set_quad1_z(z_offset)


## Get Quad1 Z offset
func get_muzzle_flash_quad1_z() -> float:
	if muzzle_flash:
		return muzzle_flash.get_quad1_z()
	return 0.026

# ============================================
# Death Processing
# ============================================

## 壁検出用定数
const WALL_DETECT_DISTANCE := 1.2  # 壁検出レイキャスト距離
const WALL_COLLISION_MASK := 2  # 壁コリジョンマスク

## 4方向の壁を検出（死亡アニメーション選択用）
## @return Dictionary { HitDirection(int) -> bool } 壁があればtrue
func _detect_nearby_walls() -> Dictionary:
	# HitDirection: FRONT=0, BACK=1, LEFT=2, RIGHT=3
	var result := { 0: false, 1: false, 2: false, 3: false }

	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return result

	var origin := global_position + Vector3(0, 0.8, 0)  # 胴体高さ
	var forward := global_transform.basis.z.normalized()
	forward.y = 0
	var right := forward.cross(Vector3.UP).normalized()

	var directions := {
		0: forward,    # FRONT
		1: -forward,   # BACK
		2: -right,     # LEFT
		3: right,      # RIGHT
	}

	for dir_idx in directions:
		var direction: Vector3 = directions[dir_idx]
		var query := PhysicsRayQueryParameters3D.create(
			origin, origin + direction * WALL_DETECT_DISTANCE, WALL_COLLISION_MASK
		)
		query.exclude = [get_rid()]
		if space_state.intersect_ray(query):
			result[dir_idx] = true

	return result


## 壁を避けた最適な死亡方向を選択
## @param hit_direction 被弾方向（HitDirection）
## @param walls 壁検出結果（_detect_nearby_walls()の戻り値）
## @return 安全な被弾方向（HitDirection）
func _select_safe_death_direction(hit_direction: int, walls: Dictionary) -> int:
	# 被弾方向 → 倒れる方向のマッピング
	# FRONT(0)から撃たれた → BACK(1)方向に倒れる（death_forwardアニメ）
	# BACK(1)から撃たれた → FRONT(0)方向に倒れる（death_backwardアニメ）
	# LEFT(2)から撃たれた → RIGHT(3)方向に倒れる（death_leftがないので注意）
	# RIGHT(3)から撃たれた → LEFT(2)方向に倒れる（death_rightアニメ）
	var fall_map := { 0: 1, 1: 0, 2: 3, 3: 2 }
	var fall_dir: int = fall_map[hit_direction]

	# 第1候補: 被弾方向の反対側に倒れる（壁がなければOK）
	if not walls[fall_dir]:
		return hit_direction

	# 第2候補: 他の安全な方向を探す
	# 優先順位: 後ろ(1) > 前(0) > 右(3)
	# LEFT(2)への被弾はdeath_leftがないのでスキップ
	var priority := [1, 0, 3]  # BACK, FRONT, RIGHT
	for check_hit_dir in priority:
		if check_hit_dir == hit_direction:
			continue
		var check_fall_dir: int = fall_map[check_hit_dir]
		if not walls[check_fall_dir]:
			return check_hit_dir

	# 全方向に壁 → 元の方向をそのまま使用
	return hit_direction


func _die(killer: Node3D = null, is_headshot: bool = false) -> void:
	is_alive = false

	# Play death animation via CharacterAnimationController
	if anim_ctrl and anim_ctrl.has_method("play_death"):
		var hit_dir := _calculate_hit_direction(killer)
		# 壁を検出して安全な方向を選択
		var walls := _detect_nearby_walls()
		var safe_hit_dir := _select_safe_death_direction(hit_dir, walls)
		anim_ctrl.play_death(safe_hit_dir, is_headshot)

	# Disable vision on death
	if vision:
		vision.disable()

	# Clear combat awareness target on death
	if combat_awareness and combat_awareness.has_method("clear_target"):
		combat_awareness.clear_target()

	# Hide character label (A, B, etc.)
	_hide_character_label()

	# Make corpse passable by other characters but keep ground collision
	_make_corpse_passable()

	# Emit died signal for path cleanup
	died.emit(self)

## Calculate HitDirection from attacker position
func _calculate_hit_direction(attacker: Node3D) -> int:
	if attacker == null:
		return 0  # FRONT

	var to_attacker := (attacker.global_position - global_position).normalized()
	to_attacker.y = 0

	var forward := global_transform.basis.z  # +Z forward
	forward.y = 0
	forward = forward.normalized()

	var angle := rad_to_deg(forward.signed_angle_to(to_attacker, Vector3.UP))

	# CharacterAnimationController.HitDirection
	# FRONT = 0, BACK = 1, LEFT = 2, RIGHT = 3
	if abs(angle) < 45:
		return 0  # FRONT
	elif abs(angle) > 135:
		return 1  # BACK
	elif angle < 0:
		return 2  # LEFT
	else:
		return 3  # RIGHT

## Hide character label (A, B marker above head)
func _hide_character_label() -> void:
	for child in get_children():
		if child.name.begins_with("CharacterLabel_"):
			child.visible = false
			break


## Make corpse passable by other characters while keeping ground collision
func _make_corpse_passable() -> void:
	# Set collision_layer to 0 so other characters don't collide with this corpse
	# Keep collision_mask unchanged so corpse still detects ground
	collision_layer = 0

	# タップ検出用Area3Dのcollision_layerも0にしてレイキャストに引っかからないようにする
	var tap_area := get_node_or_null("TapArea") as Area3D
	if tap_area:
		tap_area.collision_layer = 0


# ============================================
# Multiplayer API
# ============================================

## ローカルプレイヤーのキャラクターか判定
## シングルプレイヤー時は常にtrue
func is_local() -> bool:
	if owner_peer_id == 0:
		return true  # シングルプレイヤーモード
	return owner_peer_id == PlayerState.get_local_peer_id()


## ネットワークIDを設定
func set_network_id(id: int) -> void:
	network_id = id


## 所有者のpeer_idを設定
func set_owner_peer_id(peer_id: int) -> void:
	owner_peer_id = peer_id


## リモートからの状態更新を適用
## ローカルキャラクターには適用しない（自分の入力が優先）
func apply_remote_state(state: NetworkMessages.CharacterStateMessage) -> void:
	if is_local():
		return  # ローカルキャラクターは自分で状態を管理

	# リモート補間コンポーネントに委譲
	if remote_interpolation:
		# 初回受信判定（activate前に確認）
		var is_first_snapshot := not remote_interpolation.has_received_first_snapshot()

		remote_interpolation.activate()
		var current_time := Time.get_ticks_msec() / 1000.0
		remote_interpolation.add_snapshot(state, current_time)

		# 初回受信時またはテレポート防止で即座に位置を設定
		if is_first_snapshot or global_position.distance_to(state.position) > 5.0:
			remote_interpolation.initialize_position(state)

	# 旧実装との互換（段階的に削除予定）
	_remote_target_animation_state = state.animation_state

	# HPを更新（即座に反映）
	current_health = state.current_health

	# 生存状態を更新（即座に反映）
	if is_alive and not state.is_alive:
		# 死亡 - アニメーションを再生
		is_alive = false
		if remote_interpolation:
			remote_interpolation.deactivate()
		if anim_ctrl and anim_ctrl.has_method("play_death"):
			# リモート死亡の場合はデフォルト方向で再生
			anim_ctrl.play_death(CharacterAnimationController.HitDirection.FRONT, false)
		if vision:
			vision.disable()
		_hide_character_label()
		_make_corpse_passable()
		died.emit(self)
	elif not is_alive and state.is_alive:
		# 復活（通常は起こらないが念のため）
		reset_health()

	# 武器の同期（初回または変更時のみ）
	if not state.weapon_id.is_empty():
		var current_weapon_id := current_weapon.id if current_weapon else ""
		if current_weapon_id != state.weapon_id:
			var weapon_preset = WeaponRegistry.get_preset(state.weapon_id)
			if weapon_preset:
				equip_weapon(weapon_preset)


## リモートキャラクターの補間更新（毎フレーム呼び出し）
func update_remote_interpolation(delta: float) -> void:
	if is_local() or not is_alive:
		return
	# コンポーネントに委譲
	if remote_interpolation:
		remote_interpolation.update(delta)


## 現在の状態をCharacterStateMessageに変換
func to_character_state() -> NetworkMessages.CharacterStateMessage:
	var state := NetworkMessages.CharacterStateMessage.new()
	state.character_id = network_id if network_id != 0 else get_instance_id()
	state.position = global_position
	state.rotation = atan2(_facing_direction.x, _facing_direction.z)
	state.current_health = int(current_health)
	state.is_alive = is_alive
	state.velocity = velocity
	state.character_preset_id = character_preset_id
	state.weapon_id = current_weapon.id if current_weapon else ""
	state.timestamp = Time.get_ticks_msec()

	# アニメーション状態を取得
	# リモートキャラクターの場合は受信した状態を使用
	if not is_local() and not _remote_target_animation_state.is_empty():
		state.animation_state = _remote_target_animation_state
	elif anim_ctrl and anim_ctrl.has_method("get_animation_state"):
		state.animation_state = anim_ctrl.get_animation_state()

	return state


## 現在の状態をCharacterSnapshotに変換（より詳細）
func to_character_snapshot() -> SyncState.CharacterSnapshot:
	var snapshot := SyncState.CharacterSnapshot.new()
	snapshot.character_id = network_id if network_id != 0 else get_instance_id()
	snapshot.owner_peer_id = owner_peer_id
	snapshot.position = global_position
	snapshot.rotation = atan2(_facing_direction.x, _facing_direction.z)
	snapshot.facing_direction = _facing_direction
	snapshot.velocity = velocity
	snapshot.current_health = current_health
	snapshot.max_health = max_health
	snapshot.is_alive = is_alive
	snapshot.team = team
	snapshot.timestamp = Time.get_ticks_msec()

	# 武器ID
	if current_weapon:
		snapshot.weapon_id = current_weapon.id

	# アニメーション状態
	# リモートキャラクターの場合は受信した状態を使用
	if not is_local() and not _remote_target_animation_state.is_empty():
		snapshot.animation_state = _remote_target_animation_state
	elif anim_ctrl and anim_ctrl.has_method("get_animation_state"):
		snapshot.animation_state = anim_ctrl.get_animation_state()

	return snapshot


## CharacterSnapshotから状態を復元（リモートキャラクター用）
func apply_character_snapshot(snapshot: SyncState.CharacterSnapshot) -> void:
	if is_local():
		return  # ローカルキャラクターは自分で状態を管理

	global_position = snapshot.position
	set_facing_direction(snapshot.rotation)
	velocity = snapshot.velocity
	current_health = snapshot.current_health

	# 生存状態
	if is_alive and not snapshot.is_alive:
		is_alive = false
		if vision:
			vision.disable()
		_hide_character_label()
		_make_corpse_passable()
		died.emit(self)
	elif not is_alive and snapshot.is_alive:
		reset_health()


## 状態変更を通知（ネットワーク同期用）
## HPや位置が大きく変わった時に呼ぶ
func notify_state_changed() -> void:
	state_changed.emit(self)
