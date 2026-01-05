class_name CharacterAPI
extends RefCounted

## キャラクター操作の統一API
## アニメーション、パス、視界、ステータスなどの操作を簡単に行えるインターフェースを提供

## ========================================
## 静的インスタンス（シングルトンパターン）
## ========================================

static var _instance: CharacterAPI = null
static var _weapon_database: WeaponDatabase = null


static func get_instance() -> CharacterAPI:
	if _instance == null:
		_instance = CharacterAPI.new()
	return _instance


## ========================================
## 武器データベース
## ========================================

## 武器データベースを取得（遅延初期化）
static func get_weapon_database() -> WeaponDatabase:
	if _weapon_database == null:
		# デフォルトパスからロード試行
		var db_path = "res://resources/weapon_database.tres"
		if ResourceLoader.exists(db_path):
			_weapon_database = load(db_path) as WeaponDatabase
		if _weapon_database == null:
			# レガシーデータから作成
			_weapon_database = WeaponDatabase.create_from_legacy_data()
	return _weapon_database


## 武器データベースを設定（カスタムデータベースを使用する場合）
static func set_weapon_database(database: WeaponDatabase) -> void:
	_weapon_database = database


## ========================================
## アニメーションAPI
## ========================================

## アニメーションを再生
## @param character: 対象キャラクター
## @param animation_name: アニメーション名（例: "idle", "walking", "running"）
## @param weapon_type: 武器タイプ（省略時は現在の武器タイプ）
## @param blend_time: ブレンド時間（秒）
static func play_animation(character: CharacterBase, animation_name: String, weapon_type: int = -1, blend_time: float = 0.3) -> bool:
	if not is_instance_valid(character) or not character.anim_player:
		return false

	if weapon_type < 0:
		weapon_type = character.current_weapon_type

	var full_anim_name = CharacterSetup.get_animation_name(animation_name, weapon_type)

	if not character.anim_player.has_animation(full_anim_name):
		# フォールバック: NONEタイプを試す
		full_anim_name = CharacterSetup.get_animation_name(animation_name, CharacterSetup.WeaponType.NONE)
		if not character.anim_player.has_animation(full_anim_name):
			return false

	# AnimationTreeが有効な場合はlocomotionノードを更新
	if character.anim_tree and character.anim_tree.active and character.anim_blend_tree:
		var locomotion_node = character.anim_blend_tree.get_node("locomotion") as AnimationNodeAnimation
		if locomotion_node:
			locomotion_node.animation = full_anim_name
			return true
	else:
		character.anim_player.play(full_anim_name, blend_time)
		return true

	return false


## アニメーション速度を設定
## @param character: 対象キャラクター
## @param speed_scale: 速度倍率（1.0 = 通常速度）
static func set_animation_speed(character: CharacterBase, speed_scale: float) -> void:
	if not is_instance_valid(character) or not character.anim_player:
		return
	character.anim_player.speed_scale = speed_scale


## 現在のアニメーション速度を取得
static func get_animation_speed(character: CharacterBase) -> float:
	if not is_instance_valid(character) or not character.anim_player:
		return 1.0
	return character.anim_player.speed_scale


## 射撃アニメーションを設定
## @param character: 対象キャラクター
## @param animation_name: アニメーション名（例: "shoot", "idle_aiming"）
static func set_shoot_animation(character: CharacterBase, animation_name: String) -> bool:
	if not is_instance_valid(character):
		return false
	if not character.anim_tree or not character.anim_blend_tree:
		return false

	var full_anim_name = CharacterSetup.get_animation_name(animation_name, character.current_weapon_type)
	if not character.anim_player.has_animation(full_anim_name):
		return false

	var shoot_node = character.anim_blend_tree.get_node("shoot") as AnimationNodeAnimation
	if shoot_node:
		shoot_node.animation = full_anim_name
		return true

	return false


## 利用可能なアニメーション一覧を取得
static func get_available_animations(character: CharacterBase) -> Array[String]:
	var result: Array[String] = []
	if not is_instance_valid(character) or not character.anim_player:
		return result

	for anim_name in character.anim_player.get_animation_list():
		result.append(anim_name)
	return result


## ========================================
## 歩行シーケンスAPI
## walk_start -> walk_loop -> walk_end の自動遷移
## ========================================

## 歩行シーケンスを開始
## @param character: 対象キャラクター
## @param base_name: "walk" や "sprint" などのベース名
## @param blend_time: ブレンド時間（秒）
## @example: CharacterAPI.start_walk_sequence(player, "walk") -> rifle_walk_start -> rifle_walk (loop)
static func start_walk_sequence(character: CharacterBase, base_name: String = "walk", blend_time: float = 0.3) -> void:
	if not is_instance_valid(character):
		return
	character.start_walk_sequence(base_name, blend_time)


## 歩行シーケンスを停止（end アニメーションを再生してから idle に戻る）
## @param character: 対象キャラクター
## @param blend_time: ブレンド時間（秒）
## @example: CharacterAPI.stop_walk_sequence(player) -> rifle_walk_end -> idle
static func stop_walk_sequence(character: CharacterBase, blend_time: float = 0.3) -> void:
	if not is_instance_valid(character):
		return
	character.stop_walk_sequence(blend_time)


## 歩行シーケンスを強制終了（即座に停止、end アニメーションなし）
## @param character: 対象キャラクター
static func cancel_walk_sequence(character: CharacterBase) -> void:
	if not is_instance_valid(character):
		return
	character.cancel_walk_sequence()


## 歩行シーケンスがアクティブか確認
## @param character: 対象キャラクター
## @return: 歩行シーケンス中なら true
static func is_walk_sequence_active(character: CharacterBase) -> bool:
	if not is_instance_valid(character):
		return false
	return character.is_walk_sequence_active()


## ========================================
## パスAPI
## ========================================

## パスを設定
## @param character: 対象キャラクター
## @param waypoints: ウェイポイント配列（Vector3またはDictionary）
## @param auto_run_flags: 走り/歩きフラグを自動生成するか
static func set_path(character: CharacterBase, waypoints: Array, auto_run_flags: bool = false) -> void:
	if not is_instance_valid(character):
		return

	var formatted_waypoints: Array = []

	for i in range(waypoints.size()):
		var wp = waypoints[i]
		if wp is Vector3:
			var run = false
			if auto_run_flags and i < waypoints.size() - 1:
				# 次のポイントとの距離が長ければ走る
				var next_wp = waypoints[i + 1]
				if next_wp is Vector3:
					run = wp.distance_to(next_wp) > 3.0
			formatted_waypoints.append({"position": wp, "run": run})
		elif wp is Dictionary:
			formatted_waypoints.append(wp)

	character.set_path(formatted_waypoints)


## パスをクリア
static func clear_path(character: CharacterBase) -> void:
	if is_instance_valid(character):
		character.stop()


## 単一地点へ移動
## @param character: 対象キャラクター
## @param target: 目標地点
## @param run: 走るか
static func move_to(character: CharacterBase, target: Vector3, run: bool = false) -> void:
	if is_instance_valid(character):
		character.move_to(target, run)


## 移動を停止
static func stop(character: CharacterBase) -> void:
	if is_instance_valid(character):
		character.stop()


## パス完了を待機
static func await_path_complete(character: CharacterBase) -> void:
	if is_instance_valid(character) and character.is_moving:
		await character.path_completed


## ========================================
## 視界API
## ========================================

## 視野角を設定
## @param character: 対象キャラクター
## @param fov_degrees: 視野角（度）
static func set_fov(character: CharacterBase, fov_degrees: float) -> void:
	var vision = _get_vision_component(character)
	if vision:
		vision.fov_angle = fov_degrees


## 視野角を取得
static func get_fov(character: CharacterBase) -> float:
	var vision = _get_vision_component(character)
	return vision.fov_angle if vision else 120.0


## 視野距離を設定
## @param character: 対象キャラクター
## @param distance: 視野距離（ワールド単位）
static func set_view_distance(character: CharacterBase, distance: float) -> void:
	var vision = _get_vision_component(character)
	if vision:
		vision.view_distance = distance


## 視野距離を取得
static func get_view_distance(character: CharacterBase) -> float:
	var vision = _get_vision_component(character)
	return vision.view_distance if vision else 15.0


## 位置が視野内か判定
## @param character: 対象キャラクター
## @param target_pos: 判定する位置
static func is_position_visible(character: CharacterBase, target_pos: Vector3) -> bool:
	var vision = _get_vision_component(character)
	return vision.is_position_visible(target_pos) if vision else false


## キャラクターが視野内か判定
## @param observer: 観察者
## @param target: 対象キャラクター
static func is_character_visible(observer: CharacterBase, target: CharacterBody3D) -> bool:
	var vision = _get_vision_component(observer)
	return vision.is_character_visible(target) if vision else false


## VisionComponentを取得
static func _get_vision_component(character: CharacterBase) -> Node:
	if not is_instance_valid(character):
		return null
	return character.get_node_or_null("VisionComponent")


## 遮蔽物を考慮した視線チェック
## @param character: 対象キャラクター
## @param target_pos: チェック対象位置
## @param collision_mask: 遮蔽物判定用のコリジョンマスク
static func has_line_of_sight(character: CharacterBase, target_pos: Vector3, collision_mask: int = 6) -> bool:
	var vision = _get_vision_component(character)
	if vision and vision.has_method("has_line_of_sight"):
		return vision.has_line_of_sight(target_pos, collision_mask)
	return false


## 視野内かつ視線が通っているか判定（遮蔽物考慮）
## @param character: 対象キャラクター
## @param target_pos: チェック対象位置
## @param check_occlusion: 遮蔽物チェックを行うか
static func is_position_truly_visible(character: CharacterBase, target_pos: Vector3, check_occlusion: bool = true) -> bool:
	var vision = _get_vision_component(character)
	if vision and vision.has_method("is_position_truly_visible"):
		return vision.is_position_truly_visible(target_pos, check_occlusion)
	return false


## キャラクターが視野内かつ視線が通っているか判定（遮蔽物考慮）
static func is_character_truly_visible(observer: CharacterBase, target: CharacterBody3D, check_occlusion: bool = true) -> bool:
	var vision = _get_vision_component(observer)
	if vision and vision.has_method("is_character_truly_visible"):
		return vision.is_character_truly_visible(target, check_occlusion)
	return false


## 視界情報を取得
static func get_vision_info(character: CharacterBase) -> Dictionary:
	var vision = _get_vision_component(character)
	if vision and vision.has_method("get_vision_info"):
		return vision.get_vision_info()
	return {}


## 視界を強制更新
static func force_vision_update(character: CharacterBase) -> void:
	var vision = _get_vision_component(character)
	if vision and vision.has_method("force_update"):
		vision.force_update()


## ========================================
## 武器API
## ========================================

## 武器を装備
## @param character: 対象キャラクター
## @param weapon_id: 武器ID
static func equip_weapon(character: CharacterBase, weapon_id: int) -> void:
	if is_instance_valid(character):
		character.set_weapon(weapon_id)


## 武器を解除
static func unequip_weapon(character: CharacterBase) -> void:
	if is_instance_valid(character):
		character.set_weapon(CharacterSetup.WeaponId.NONE)


## 現在の武器IDを取得
static func get_weapon_id(character: CharacterBase) -> int:
	if is_instance_valid(character):
		return character.get_weapon_id()
	return CharacterSetup.WeaponId.NONE


## 武器データを取得
static func get_weapon_data(weapon_id: int) -> Dictionary:
	var db = get_weapon_database()
	var weapon = db.get_weapon(weapon_id)
	if weapon:
		return weapon.to_dict()
	return CharacterSetup.get_weapon_data(weapon_id)


## 武器ステータスを動的に調整
## @param weapon_id: 武器ID
## @param updates: 更新する値（例: {"damage": 40, "accuracy": 0.9}）
static func update_weapon_stats(weapon_id: int, updates: Dictionary) -> bool:
	var db = get_weapon_database()
	return db.update_weapon(weapon_id, updates)


## ========================================
## ステータスAPI
## ========================================

## HPを設定
## @param character: 対象キャラクター
## @param hp: HP値
static func set_health(character: CharacterBase, hp: float) -> void:
	if is_instance_valid(character):
		character.health = clamp(hp, 0.0, 100.0)


## HPを取得
static func get_health(character: CharacterBase) -> float:
	if is_instance_valid(character):
		return character.health
	return 0.0


## アーマーを設定
static func set_armor(character: CharacterBase, armor: float) -> void:
	if is_instance_valid(character):
		character.armor = clamp(armor, 0.0, 100.0)


## アーマーを取得
static func get_armor(character: CharacterBase) -> float:
	if is_instance_valid(character):
		return character.armor
	return 0.0


## ダメージを与える
## @param character: 対象キャラクター
## @param amount: ダメージ量
## @param attacker: 攻撃者（オプション）
## @param is_headshot: ヘッドショットか
static func apply_damage(character: CharacterBase, amount: float, attacker: Node3D = null, is_headshot: bool = false) -> void:
	if is_instance_valid(character):
		character.take_damage(amount, attacker, is_headshot)


## 回復
static func heal(character: CharacterBase, amount: float) -> void:
	if is_instance_valid(character):
		character.heal(amount)


## 完全回復（HP + アーマー）
static func full_heal(character: CharacterBase) -> void:
	if is_instance_valid(character):
		character.health = 100.0
		character.armor = 100.0


## 移動速度を設定
## @param character: 対象キャラクター
## @param walk_speed: 歩行速度
## @param run_speed: 走行速度（省略時は歩行速度の2倍）
static func set_speed(character: CharacterBase, walk_speed: float, run_speed: float = -1.0) -> void:
	if is_instance_valid(character):
		character.base_walk_speed = walk_speed
		character.base_run_speed = run_speed if run_speed > 0 else walk_speed * 2.0
		character._update_speed_from_weapon()


## 移動速度を取得
static func get_speed(character: CharacterBase) -> Dictionary:
	if is_instance_valid(character):
		return {
			"walk": character.walk_speed,
			"run": character.run_speed,
			"base_walk": character.base_walk_speed,
			"base_run": character.base_run_speed,
			"modifier": character.get_speed_modifier()
		}
	return {"walk": 0.0, "run": 0.0, "base_walk": 0.0, "base_run": 0.0, "modifier": 1.0}


## ステータス倍率を適用
## @param character: 対象キャラクター
## @param modifiers: 倍率辞書（例: {"speed_mult": 1.2, "damage_mult": 0.8}）
static func apply_stat_modifiers(character: CharacterBase, modifiers: Dictionary) -> void:
	if not is_instance_valid(character):
		return

	if modifiers.has("speed_mult"):
		var mult = modifiers.speed_mult
		character.base_walk_speed *= mult
		character.base_run_speed *= mult
		character._update_speed_from_weapon()


## ========================================
## モデルAPI
## ========================================

## キャラクターモデルを変更
## @param character: 対象キャラクター
## @param model_scene_path: モデルシーンパス
## @param preserve_weapon: 武器を維持するか
static func set_model(character: CharacterBase, model_scene_path: String, preserve_weapon: bool = true) -> bool:
	if not is_instance_valid(character):
		return false

	if not ResourceLoader.exists(model_scene_path):
		push_warning("[CharacterAPI] Model not found: %s" % model_scene_path)
		return false

	var current_weapon_id = character.current_weapon_id if preserve_weapon else CharacterSetup.WeaponId.NONE

	# 既存モデルを削除
	var old_model = character.get_node_or_null("CharacterModel")
	if old_model:
		old_model.queue_free()

	# 新しいモデルをロード
	var model_scene = load(model_scene_path)
	if not model_scene:
		return false

	var new_model = model_scene.instantiate()
	new_model.name = "CharacterModel"
	character.add_child(new_model)

	# キャラクターを再セットアップ
	character._setup_character()

	# 武器を復元
	if preserve_weapon and current_weapon_id != CharacterSetup.WeaponId.NONE:
		character.set_weapon(current_weapon_id)

	return true


## モデルのテクスチャを変更
## @param character: 対象キャラクター
## @param albedo_path: アルベドテクスチャパス
## @param normal_path: 法線マップパス（オプション）
static func set_model_textures(character: CharacterBase, albedo_path: String, normal_path: String = "") -> bool:
	if not is_instance_valid(character):
		return false

	var model = character.get_node_or_null("CharacterModel")
	if not model:
		return false

	var albedo_tex = load(albedo_path) as Texture2D
	if not albedo_tex:
		return false

	var normal_tex: Texture2D = null
	if not normal_path.is_empty():
		normal_tex = load(normal_path) as Texture2D

	# 全メッシュにテクスチャを適用
	var meshes = CharacterSetup.find_meshes(model)
	for mesh_instance in meshes:
		if mesh_instance.mesh:
			for i in range(mesh_instance.mesh.get_surface_count()):
				var mat = mesh_instance.get_active_material(i)
				var new_mat: StandardMaterial3D

				if mat and mat is StandardMaterial3D:
					new_mat = mat.duplicate() as StandardMaterial3D
				else:
					new_mat = StandardMaterial3D.new()

				new_mat.albedo_texture = albedo_tex
				if normal_tex:
					new_mat.normal_enabled = true
					new_mat.normal_texture = normal_tex

				mesh_instance.set_surface_override_material(i, new_mat)

	return true


## ========================================
## ユーティリティ
## ========================================

## キャラクターが生存しているか
static func is_alive(character: CharacterBase) -> bool:
	return is_instance_valid(character) and character.is_alive


## キャラクターが移動中か
static func is_moving(character: CharacterBase) -> bool:
	return is_instance_valid(character) and character.is_moving


## キャラクターの現在位置を取得
static func get_position(character: CharacterBase) -> Vector3:
	if is_instance_valid(character):
		return character.global_position
	return Vector3.ZERO


## キャラクターの向きを取得（ラジアン）
static func get_rotation(character: CharacterBase) -> float:
	if is_instance_valid(character):
		return character.rotation.y
	return 0.0


## キャラクターの向きを設定（ラジアン）
static func set_rotation(character: CharacterBase, rotation_y: float) -> void:
	if is_instance_valid(character):
		character.rotation.y = rotation_y


## キャラクターを指定方向に向かせる
static func look_at_position(character: CharacterBase, target: Vector3) -> void:
	if is_instance_valid(character):
		var direction = target - character.global_position
		direction.y = 0
		if direction.length() > 0.1:
			character.rotation.y = atan2(direction.x, direction.z)
