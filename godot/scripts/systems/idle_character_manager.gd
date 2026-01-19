extends Node
class_name IdleCharacterManager
## アイドルキャラクター管理
## パス追従していないキャラクターの状態更新を担当

## 管理対象キャラクターリスト
var characters: Array[Node] = []

## パス追従中チェック用のコールバック
var is_following_path_callback: Callable

## プライマリキャラクター取得用のコールバック
var get_primary_callback: Callable


## セットアップ
func setup(
	char_list: Array[Node],
	following_check: Callable,
	primary_getter: Callable
) -> void:
	characters = char_list
	is_following_path_callback = following_check
	get_primary_callback = primary_getter


## キャラクターを追加
func add_character(character: Node) -> void:
	if not characters.has(character):
		characters.append(character)


## キャラクターを削除
func remove_character(character: Node) -> void:
	characters.erase(character)


## キャラクターリストを更新
func set_characters(char_list: Array[Node]) -> void:
	characters = char_list


## アイドル中のキャラクターを更新（毎フレーム呼ぶ）
func process_idle_characters(delta: float) -> void:
	var primary = get_primary_callback.call() if get_primary_callback.is_valid() else null

	for character in characters:
		# パス追従中はスキップ
		if is_following_path_callback.is_valid() and is_following_path_callback.call(character):
			continue
		# プライマリキャラクターはスキップ（別処理）
		if character == primary:
			continue
		# 死亡中はスキップ（GameCharacterのみ）
		var game_char := character as GameCharacter
		if game_char and not game_char.is_alive:
			continue

		_update_idle_character(character, delta)


## 単一キャラクターのアイドル状態を更新
func _update_idle_character(character: Node, delta: float) -> void:
	# Combat awarenessを処理（アイドル中も敵を追跡）
	if character.combat_awareness and character.combat_awareness.has_method("process"):
		character.combat_awareness.process(delta)

	var anim_ctrl = character.get_anim_controller()
	if not anim_ctrl:
		return

	var look_dir: Vector3 = Vector3.ZERO

	# 敵視認チェック（最優先）
	if character.combat_awareness and character.combat_awareness.has_method("is_tracking_enemy"):
		if character.combat_awareness.is_tracking_enemy():
			look_dir = character.combat_awareness.get_override_look_direction()

	# デフォルト: 現在の向きを維持
	if look_dir.length_squared() < 0.1:
		look_dir = anim_ctrl.get_look_direction()

	anim_ctrl.update_animation(Vector3.ZERO, look_dir, false, delta)


## プライマリキャラクターのアイドル処理（手動操作無効時）
func process_primary_idle(character: Node, delta: float) -> void:
	if not character or not character.is_alive:
		return

	# Combat awarenessを処理
	if character.combat_awareness and character.combat_awareness.has_method("process"):
		character.combat_awareness.process(delta)

	var anim_ctrl = character.get_anim_controller()
	if not anim_ctrl:
		return

	var look_dir: Vector3 = Vector3.ZERO

	# 敵視認チェック（最優先）
	if character.combat_awareness and character.combat_awareness.has_method("is_tracking_enemy"):
		if character.combat_awareness.is_tracking_enemy():
			look_dir = character.combat_awareness.get_override_look_direction()

	# デフォルト: 現在の向きを維持
	if look_dir.length_squared() < 0.1:
		look_dir = anim_ctrl.get_look_direction()

	anim_ctrl.update_animation(Vector3.ZERO, look_dir, false, delta)

	# 重力適用
	character.velocity.x = 0
	character.velocity.z = 0
	if not character.is_on_floor():
		character.velocity.y -= 9.8 * delta
	character.move_and_slide()
