extends Node
class_name IdleCharacterManager
## アイドルキャラクター管理
## TPS操作対象以外のキャラクターの状態更新を担当
## wandering_enabled = true 時、CPUキャラクターが自動的にマップ内を歩き回る
## Beehave BT でCPUキャラクターの行動を制御

## 管理対象キャラクターリスト
var characters: Array[Node] = []

## プライマリキャラクター取得用のコールバック
var get_primary_callback: Callable

## 徘徊モード有効化（トレーニングモードでON）
var wandering_enabled: bool = false

## キャラクターごとの BT インスタンス
var _bt_instances: Dictionary = {}

## BT シーンリソース
var _bt_scene: PackedScene = null

## デバッグ: 初回ログフラグ


## セットアップ
func setup(
	char_list: Array[Node],
	primary_getter: Callable
) -> void:
	characters = char_list
	get_primary_callback = primary_getter


## キャラクターを追加
func add_character(character: Node) -> void:
	if not characters.has(character):
		characters.append(character)


## キャラクターを削除
func remove_character(character: Node) -> void:
	characters.erase(character)
	_remove_bt(character)


## キャラクターリストを更新
func set_characters(char_list: Array[Node]) -> void:
	# 既存の BT インスタンスをすべて破棄
	for character in _bt_instances.keys():
		_remove_bt(character)
	characters = char_list


## アイドル中のキャラクターを更新（毎フレーム呼ぶ）
func process_idle_characters(_delta: float) -> void:
	var primary = get_primary_callback.call() if get_primary_callback.is_valid() else null

	for character in characters:
		var game_char := character as GameCharacter
		if not game_char:
			continue

		# リモートキャラクターはスキップ（ネットワークから状態を受信するため）
		if not game_char.is_local():
			continue

		# プライマリキャラクターはスキップ（TPSPlayerControllerが制御）
		if character == primary:
			continue
		# 死亡中はスキップ
		if not game_char.is_alive:
			continue

		_update_idle_character(character)


## 単一キャラクターのアイドル状態を BT で更新
func _update_idle_character(character: Node) -> void:
	var bt := _get_or_create_bt(character)
	if not bt:
		return

	bt.blackboard.set_value("wandering_enabled", wandering_enabled)
	bt.tick()

	# facing_direction を明示更新（視界判定・同期用）
	var is_tracking: bool = bt.blackboard.get_value("is_tracking", false)
	var look_dir: Vector3 = bt.blackboard.get_value("look_direction", Vector3.ZERO)
	var move_dir: Vector3 = bt.blackboard.get_value("move_direction", Vector3.ZERO)

	if is_tracking and look_dir.length_squared() > 0.01:
		character.set_facing_direction_vec(look_dir)
	elif move_dir.length_squared() > 0.01:
		character.set_facing_direction_vec(move_dir)


## BT インスタンスを取得（なければ作成）
func _get_or_create_bt(character: Node) -> BeehaveTree:
	if _bt_instances.has(character):
		return _bt_instances[character]

	if not _bt_scene:
		_bt_scene = load("res://scenes/ai/cpu_character_bt.tscn")

	var bt: BeehaveTree = _bt_scene.instantiate()
	bt.actor = character
	character.add_child(bt)
	bt.blackboard.set_value("hand_grenade_count", GameConstants.HAND_GRENADE_PER_ROUND)
	_bt_instances[character] = bt
	return bt


## BT インスタンスを破棄
func _remove_bt(character: Node) -> void:
	if _bt_instances.has(character):
		var bt: BeehaveTree = _bt_instances[character]
		if is_instance_valid(bt):
			bt.queue_free()
		_bt_instances.erase(character)


## プライマリキャラクターのアイドル処理（手動操作無効時）
func process_primary_idle(character: Node, delta: float) -> void:
	if not character or not character.is_alive:
		return

	# リモートキャラクターはスキップ（ネットワークから状態を受信するため）
	var game_char := character as GameCharacter
	if game_char and not game_char.is_local():
		return

	# フェーズ1: 敵検知（ターゲット特定のみ）
	if character.combat_awareness and character.combat_awareness.has_method("process"):
		character.combat_awareness.process(delta)

	var anim_ctrl = character.get_anim_controller()
	if not anim_ctrl:
		return

	var look_dir: Vector3 = Vector3.ZERO

	# 敵視認チェック（最優先、ただし手動回転中はスキップ）
	var is_manual_rotating: bool = false
	if character.has_method("is_manual_rotating"):
		is_manual_rotating = character.is_manual_rotating()
	if not is_manual_rotating and character.combat_awareness and character.combat_awareness.has_method("is_tracking_enemy"):
		if character.combat_awareness.is_tracking_enemy():
			look_dir = character.combat_awareness.get_override_look_direction()

	# デフォルト: 現在の向きを維持
	if look_dir.length_squared() < 0.1:
		look_dir = anim_ctrl.get_look_direction()

	# フェーズ2: アニメーション更新（SLERP回転を進める）
	anim_ctrl.update_animation(Vector3.ZERO, look_dir, false, delta)

	# フェーズ3: 射撃判定（回転後に向き完了チェック）
	if character.combat_awareness and character.combat_awareness.has_method("process_firing"):
		character.combat_awareness.process_firing(delta)

	# 重力適用
	character.velocity.x = 0
	character.velocity.z = 0
	if not character.is_on_floor():
		character.velocity.y -= 9.8 * delta
	character.move_and_slide()
