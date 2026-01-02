class_name CharacterSetup
extends RefCounted

## キャラクターモデルのセットアップユーティリティ
## テクスチャ適用、アニメーション読み込みなどの共通処理を提供

## テクスチャマッピング定義
const TEXTURE_MAP := {
	"t_leet_glass": {
		"albedo": "res://assets/characters/leet/t_leet_glass.tga",
		"normal": ""
	},
	"t_leet": {
		"albedo": "res://assets/characters/leet/t_leet.tga",
		"normal": "res://assets/characters/leet/t_leet_normal.tga"
	},
	"ct_gsg9": {
		"albedo": "res://assets/characters/gsg9/ct_gsg9.tga",
		"normal": "res://assets/characters/gsg9/ct_gsg9_normal.tga"
	}
}

## 武器タイプ（アニメーションカテゴリ）
enum WeaponType { NONE, RIFLE, PISTOL }

## 武器ID
enum WeaponId { NONE, AK47, USP }

## 武器データ定義
## accuracy: 基本命中率 (0.0-1.0)
## range: 有効射程距離 (この距離で命中率が半減)
## headshot_multiplier: ヘッドショット時のダメージ倍率
## bodyshot_multiplier: ボディショット時のダメージ倍率
const WEAPON_DATA := {
	WeaponId.NONE: {
		"name": "None",
		"type": WeaponType.NONE,
		"price": 0,
		"damage": 0,
		"fire_rate": 0.0,
		"accuracy": 0.0,
		"range": 0.0,
		"headshot_multiplier": 1.0,
		"bodyshot_multiplier": 1.0,
		"scene_path": "",
		"kill_reward": 300
	},
	WeaponId.AK47: {
		"name": "AK-47",
		"type": WeaponType.RIFLE,
		"price": 0,
		"damage": 36,
		"fire_rate": 0.1,
		"accuracy": 0.85,
		"range": 20.0,
		"headshot_multiplier": 4.0,
		"bodyshot_multiplier": 1.0,
		"scene_path": "res://scenes/weapons/ak47.tscn",
		"kill_reward": 300
	},
	WeaponId.USP: {
		"name": "USP",
		"type": WeaponType.PISTOL,
		"price": 500,
		"damage": 25,
		"fire_rate": 0.15,
		"accuracy": 0.75,
		"range": 12.0,
		"headshot_multiplier": 4.0,
		"bodyshot_multiplier": 1.0,
		"scene_path": "",
		"kill_reward": 300
	}
}

## 武器ID名称
const WEAPON_ID_NAMES := {
	WeaponId.NONE: "none",
	WeaponId.AK47: "ak47",
	WeaponId.USP: "usp"
}

## アニメーションファイルパス（武器タイプ別）
## 構造: { WeaponType: { "idle": path, "walking": path, "running": path } }
const ANIMATION_FILES := {
	WeaponType.NONE: {
		"idle": "res://assets/characters/animations/none/idle.fbx",
		"walking": "res://assets/characters/animations/none/walking.fbx",
		"running": "res://assets/characters/animations/none/running.fbx"
	},
	WeaponType.RIFLE: {
		"idle": "res://assets/characters/animations/rifle/idle.fbx",
		"idle_aiming": "res://assets/characters/animations/rifle/idleAiming.fbx",
		"walking": "res://assets/characters/animations/rifle/walking.fbx",
		"running": "res://assets/characters/animations/rifle/running.fbx"
	},
	WeaponType.PISTOL: {
		"idle": "res://assets/characters/animations/pistol/idle.fbx",
		"walking": "res://assets/characters/animations/pistol/walking.fbx",
		"running": "res://assets/characters/animations/pistol/running.fbx"
	}
}

## 共通アニメーション（全武器タイプで共有）
## 構造: { "anim_name": { "path": path, "loop": bool, "normalize_mode": string } }
## normalize_mode:
##   "full" - Hips Y を完全に0に固定（locomotion用）
##   "relative" - Hips Y の開始位置を0に合わせ、相対的な動きを維持（dying等）
##   "none" - 正規化なし
const COMMON_ANIMATIONS := {
	"dying": {
		"path": "res://assets/characters/animations/dying.fbx",
		"loop": false,
		"normalize_mode": "relative"
	}
}

## 射撃アニメーション（武器タイプ別）
## 上半身のみで再生される想定
const SHOOTING_ANIMATIONS := {
	WeaponType.RIFLE: {
		"shoot": "res://assets/characters/animations/rifle/shoot.fbx"
	},
	WeaponType.PISTOL: {
		"shoot": "res://assets/characters/animations/pistol/shoot.fbx"
	}
}

## 武器タイプ名称
const WEAPON_TYPE_NAMES := {
	WeaponType.NONE: "none",
	WeaponType.RIFLE: "rifle",
	WeaponType.PISTOL: "pistol"
}

## 武器タイプ別の速度倍率（None > Pistol > Rifle の順で速い）
const WEAPON_SPEED_MODIFIER := {
	WeaponType.NONE: 1.0,
	WeaponType.PISTOL: 0.9,
	WeaponType.RIFLE: 0.75
}

## アニメーションのHips Y位置の目標値（全武器タイプで統一）
## この値にHips Yを正規化することで、武器タイプ切替時の位置ズレを防ぐ
const ANIMATION_HIPS_TARGET_Y: float = 0.0

## Skeletonのレストポーズからfeet-to-hips距離を計算してYオフセットを算出
## アニメーションでHips Yを0に正規化した場合、
## feet_to_hips距離分だけモデルを上にオフセットすることで足が地面に接地する
##
## 計算式: y_offset = character_feet_to_hips × scale
##
## 注意: 現在はidle/walk/runのみ対応。ジャンプ/しゃがみ等の上下動アニメーションは
## Hips固定方式では対応できないため、別途対応が必要
##
## @param skeleton: キャラクターのSkeleton3D
## @param model_scale: モデルのスケール（通常は2.0）
## @param debug_name: デバッグ用キャラクター名
## @return: Y位置オフセット
static func calculate_y_offset_from_skeleton(skeleton: Skeleton3D, model_scale: float = 2.0, debug_name: String = "") -> float:
	if skeleton == null:
		push_warning("[CharacterSetup] %s: Skeleton is null, cannot calculate Y offset" % debug_name)
		return 0.0

	# Hipsボーンを探す（Mixamo各種表記に対応）
	var hips_idx := _find_bone_by_name(skeleton, [
		"mixamorig_Hips", "mixamorig1_Hips", "mixamorig:Hips", "Hips"
	])
	if hips_idx == -1:
		push_warning("[CharacterSetup] %s: Hips bone not found, Y offset will be 0" % debug_name)
		return 0.0

	# ToeBaseボーンを探す（左右どちらでもOK、各種表記に対応）
	var toe_idx := _find_bone_by_name(skeleton, [
		"mixamorig_LeftToeBase", "mixamorig1_LeftToeBase", "mixamorig:LeftToeBase", "LeftToeBase",
		"mixamorig_RightToeBase", "mixamorig1_RightToeBase", "mixamorig:RightToeBase", "RightToeBase"
	])
	if toe_idx == -1:
		push_warning("[CharacterSetup] %s: ToeBase bone not found, Y offset will be 0" % debug_name)
		return 0.0

	# レストポーズのグローバル位置を取得
	var hips_rest: Transform3D = skeleton.get_bone_global_rest(hips_idx)
	var toe_rest: Transform3D = skeleton.get_bone_global_rest(toe_idx)

	# キャラクター固有のfeet-to-hips距離
	var character_feet_to_hips := hips_rest.origin.y - toe_rest.origin.y

	# アニメーションでHips Yを0に正規化した場合、
	# feet_to_hips距離分だけモデルを上にオフセットすることで足が地面に接地する
	var y_offset := character_feet_to_hips * model_scale

	if debug_name:
		print("[CharacterSetup] %s: Y offset: feet_to_hips=%.3f, scale=%.1f, total=%.3f" % [
			debug_name, character_feet_to_hips, model_scale, y_offset
		])

	return y_offset


## ボーン名リストから最初に見つかったボーンのインデックスを返す
static func _find_bone_by_name(skeleton: Skeleton3D, bone_names: Array) -> int:
	for bone_name in bone_names:
		var idx := skeleton.find_bone(bone_name)
		if idx != -1:
			return idx
	return -1


## モデルにテクスチャとマテリアルを適用
static func setup_materials(model: Node, debug_name: String = "") -> void:
	_setup_lit_materials_recursive(model, debug_name)


## 再帰的にマテリアルを設定
static func _setup_lit_materials_recursive(node: Node, debug_name: String) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_apply_textures_to_mesh(mesh_instance, debug_name)

	for child in node.get_children():
		_setup_lit_materials_recursive(child, debug_name)


## メッシュにテクスチャを適用
static func _apply_textures_to_mesh(mesh_instance: MeshInstance3D, debug_name: String) -> void:
	var mesh_name = mesh_instance.name.to_lower()
	var albedo_path := ""
	var normal_path := ""

	# メッシュ名に基づいてテクスチャパスを決定
	for key in TEXTURE_MAP.keys():
		if key in mesh_name:
			albedo_path = TEXTURE_MAP[key]["albedo"]
			normal_path = TEXTURE_MAP[key]["normal"]
			break

	if albedo_path.is_empty():
		return

	# テクスチャをロード
	var albedo_tex = load(albedo_path) as Texture2D
	if albedo_tex == null:
		if debug_name:
			print("[CharacterSetup] %s: Failed to load texture: %s" % [debug_name, albedo_path])
		return

	var normal_tex: Texture2D = null
	if not normal_path.is_empty():
		normal_tex = load(normal_path) as Texture2D

	# 各サーフェスにマテリアルを適用
	if mesh_instance.mesh:
		var surface_count = mesh_instance.mesh.get_surface_count()
		for i in range(surface_count):
			var mat = mesh_instance.get_active_material(i)
			var new_mat: StandardMaterial3D

			if mat and mat is StandardMaterial3D:
				new_mat = mat.duplicate() as StandardMaterial3D
			else:
				new_mat = StandardMaterial3D.new()

			new_mat.albedo_texture = albedo_tex
			new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

			if normal_tex:
				new_mat.normal_enabled = true
				new_mat.normal_texture = normal_tex

			mesh_instance.set_surface_override_material(i, new_mat)

	if debug_name:
		print("[CharacterSetup] %s: Applied texture to mesh '%s'" % [debug_name, mesh_instance.name])


## AnimationPlayerにアニメーションを読み込む（全武器タイプ + 共通 + 射撃）
static func load_animations(anim_player: AnimationPlayer, model: Node, _debug_name: String = "") -> void:
	var lib = anim_player.get_animation_library("")
	if lib == null:
		return

	# 全武器タイプのアニメーションを読み込み（Hips Y完全正規化）
	for weapon_type in ANIMATION_FILES.keys():
		var weapon_name = WEAPON_TYPE_NAMES[weapon_type]
		var anims = ANIMATION_FILES[weapon_type]
		for anim_name in anims.keys():
			var full_anim_name = "%s_%s" % [anim_name, weapon_name]  # 例: idle_none, walking_rifle
			_load_animation_from_fbx(lib, anims[anim_name], full_anim_name, model, true, "full")

	# 射撃アニメーションを読み込み（ループなし、Hips Y完全正規化）
	for weapon_type in SHOOTING_ANIMATIONS.keys():
		var weapon_name = WEAPON_TYPE_NAMES[weapon_type]
		var anims = SHOOTING_ANIMATIONS[weapon_type]
		for anim_name in anims.keys():
			var full_anim_name = "%s_%s" % [anim_name, weapon_name]  # 例: shoot_rifle
			_load_animation_from_fbx(lib, anims[anim_name], full_anim_name, model, false, "full")

	# 共通アニメーションを読み込み
	for anim_name in COMMON_ANIMATIONS.keys():
		var anim_data = COMMON_ANIMATIONS[anim_name]
		var normalize_mode = anim_data.get("normalize_mode", "none")
		_load_animation_from_fbx(lib, anim_data.path, anim_name, model, anim_data.loop, normalize_mode)


## 指定した武器タイプのアニメーション名を取得
static func get_animation_name(base_name: String, weapon_type: int) -> String:
	var weapon_name = WEAPON_TYPE_NAMES.get(weapon_type, "none")
	return "%s_%s" % [base_name, weapon_name]


## 指定した武器タイプのアニメーションが存在するか確認
static func has_weapon_animations(anim_player: AnimationPlayer, weapon_type: int) -> bool:
	var weapon_name = WEAPON_TYPE_NAMES.get(weapon_type, "none")
	return anim_player.has_animation("idle_%s" % weapon_name)


## FBXファイルからアニメーションを読み込む
## @param lib: アニメーションライブラリ
## @param path: FBXファイルパス
## @param anim_name: 登録するアニメーション名
## @param model: モデルノード（パス調整用）
## @param loop: ループするか（デフォルト: true）
## @param normalize_mode: Hips Y正規化モード ("full", "relative", "none")
static func _load_animation_from_fbx(lib: AnimationLibrary, path: String, anim_name: String, model: Node, loop: bool = true, normalize_mode: String = "full") -> void:
	if not ResourceLoader.exists(path):
		return

	var scene = load(path)
	if scene == null:
		return

	var instance = scene.instantiate()
	var scene_anim_player = instance.get_node_or_null("AnimationPlayer")
	if scene_anim_player:
		for anim_name_in_lib in scene_anim_player.get_animation_list():
			var anim = scene_anim_player.get_animation(anim_name_in_lib)
			if anim:
				var anim_copy = anim.duplicate()
				anim_copy.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
				_adjust_animation_paths(anim_copy, model, normalize_mode)
				lib.add_animation(anim_name, anim_copy)
				break
	instance.queue_free()


## アニメーションのトラックパスをモデル階層に合わせて調整
## @param anim: アニメーション
## @param model: モデルノード
## @param normalize_mode: Hips Y正規化モード
##   "full" - X,Z=0, Y=目標値に完全固定（locomotion用）
##   "relative" - 開始位置を目標値に合わせ、相対的な動きを維持（dying等）
##   "none" - 正規化なし
static func _adjust_animation_paths(anim: Animation, model: Node, normalize_mode: String = "full") -> void:
	if model == null:
		return

	# Armatureノードが存在するかチェック
	var has_armature = model.get_node_or_null("Armature") != null

	# Hips位置トラックを修正するためのリスト
	var hips_position_tracks: Array[int] = []

	# トラックパスを調整
	for i in range(anim.get_track_count()):
		var track_path = anim.track_get_path(i)
		var path_str = str(track_path)
		var track_type = anim.track_get_type(i)

		# Mixamoボーン名を統一形式に変換
		# mixamorig1_ / mixamorig: → mixamorig_（Godotインポート後の標準形式）
		path_str = path_str.replace("mixamorig1_", "mixamorig_")
		path_str = path_str.replace("mixamorig:", "mixamorig_")

		# Hips位置トラックをマーク（正規化が必要な場合）
		if normalize_mode != "none" and "Hips" in path_str and track_type == Animation.TYPE_POSITION_3D:
			hips_position_tracks.append(i)

		# Armatureノードがある場合のみプレフィックスを追加
		if has_armature and path_str.begins_with("Skeleton3D:"):
			path_str = "Armature/" + path_str

		anim.track_set_path(i, NodePath(path_str))

	# Hips位置トラックを正規化
	for track_idx in hips_position_tracks:
		var key_count = anim.track_get_key_count(track_idx)
		if key_count == 0:
			continue

		if normalize_mode == "full":
			# 完全正規化: X,Z=0, Y=目標値に固定
			for key_idx in range(key_count):
				var normalized_pos = Vector3(0, ANIMATION_HIPS_TARGET_Y, 0)
				anim.track_set_key_value(track_idx, key_idx, normalized_pos)

		elif normalize_mode == "relative":
			# 相対正規化: 開始位置を目標値に合わせ、相対的な動きを維持
			var first_pos: Vector3 = anim.track_get_key_value(track_idx, 0)
			var offset = Vector3(-first_pos.x, ANIMATION_HIPS_TARGET_Y - first_pos.y, -first_pos.z)
			for key_idx in range(key_count):
				var original_pos: Vector3 = anim.track_get_key_value(track_idx, key_idx)
				var adjusted_pos = original_pos + offset
				anim.track_set_key_value(track_idx, key_idx, adjusted_pos)


## モデルからSkeletonを探す
static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = find_skeleton(child)
		if result:
			return result
	return null


## モデルからAnimationPlayerを探す
static func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = find_animation_player(child)
		if result:
			return result
	return null


## モデルからMeshInstance3Dを全て探す
static func find_meshes(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		meshes.append_array(find_meshes(child))
	return meshes


## 武器IDから武器タイプを取得
static func get_weapon_type_from_id(weapon_id: int) -> int:
	var data = WEAPON_DATA.get(weapon_id, null)
	if data:
		return data.type
	return WeaponType.NONE


## 武器IDから武器データを取得
static func get_weapon_data(weapon_id: int) -> Dictionary:
	return WEAPON_DATA.get(weapon_id, WEAPON_DATA[WeaponId.NONE])


## 武器シーンをロード
static func create_weapon_attachment(weapon_id: int) -> Node3D:
	var data = WEAPON_DATA.get(weapon_id, null)
	if data == null or data.scene_path.is_empty():
		return null
	
	var scene = load(data.scene_path)
	if scene == null:
		print("[CharacterSetup] Failed to load weapon scene: %s" % data.scene_path)
		return null
	
	var weapon_instance = scene.instantiate()
	return weapon_instance


## キャラクターに武器をアタッチ
static func attach_weapon_to_character(character: Node, skeleton: Skeleton3D, weapon_id: int, debug_name: String = "") -> Node3D:
	if skeleton == null:
		if debug_name:
			print("[CharacterSetup] %s: No skeleton found for weapon attachment" % debug_name)
		return null
	
	# 既存の武器を削除
	var existing = character.get_node_or_null("WeaponAttachment")
	if existing:
		existing.queue_free()
	
	# 武器なしの場合
	if weapon_id == WeaponId.NONE:
		return null
	
	var data = WEAPON_DATA.get(weapon_id, null)
	if data == null or data.scene_path.is_empty():
		if debug_name:
			print("[CharacterSetup] %s: No weapon scene for weapon_id %d" % [debug_name, weapon_id])
		return null
	
	# 右手のボーンインデックスを取得
	var bone_name = "mixamorig_RightHand"
	var bone_idx = skeleton.find_bone(bone_name)
	if bone_idx == -1:
		# 代替ボーン名を試す
		bone_name = "mixamorig1_RightHand"
		bone_idx = skeleton.find_bone(bone_name)
	
	if bone_idx == -1:
		if debug_name:
			print("[CharacterSetup] %s: Could not find hand bone" % debug_name)
		return null
	
	# BoneAttachment3Dを作成
	var bone_attachment = BoneAttachment3D.new()
	bone_attachment.name = "WeaponAttachment"
	bone_attachment.bone_name = bone_name
	skeleton.add_child(bone_attachment)
	
	# 武器シーンをロード（位置・回転はシーンファイル内で設定済み）
	var weapon_model = create_weapon_attachment(weapon_id)
	if weapon_model:
		bone_attachment.add_child(weapon_model)
		
		if debug_name:
			print("[CharacterSetup] %s: Attached weapon %s to %s" % [debug_name, data.name, bone_name])
		
		return bone_attachment
	
	bone_attachment.queue_free()
	return null


## ノードツリーをデバッグ出力
static func print_tree(node: Node, depth: int = 0, prefix: String = "") -> void:
	var indent = "  ".repeat(depth)
	var extra = ""
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		extra = " [mesh=%s, visible=%s]" % [mi.mesh != null, mi.visible]
	elif node is Skeleton3D:
		var skel = node as Skeleton3D
		extra = " [bones=%d]" % skel.get_bone_count()
	elif node is AnimationPlayer:
		var ap = node as AnimationPlayer
		extra = " [anims=%s]" % ap.get_animation_list()
	print("%s%s%s (%s)%s" % [prefix, indent, node.name, node.get_class(), extra])
	for child in node.get_children():
		print_tree(child, depth + 1, prefix)


## スキンバインディングを修正（FBXインポート時にbone_idx=-1になる問題の対策）
## この関数は、MeshInstance3Dのスキンに正しいボーンインデックスを設定し、
## スケルトンに登録することでアニメーションが正しく動作するようにする
## @param model: キャラクターモデルのルートノード
## @param skeleton: 対象のSkeleton3D（nullの場合は自動検索）
## @param debug_name: デバッグ用の名前
static func fix_skin_bindings(model: Node, skeleton: Skeleton3D = null, debug_name: String = "") -> void:
	# スケルトンが未指定の場合は自動検索
	if skeleton == null:
		skeleton = find_skeleton(model)

	if skeleton == null:
		if debug_name:
			print("[CharacterSetup] %s: Cannot fix skin bindings - skeleton not found" % debug_name)
		return

	_fix_skin_bindings_recursive(model, skeleton, debug_name)


## 再帰的にスキンバインディングを修正
static func _fix_skin_bindings_recursive(node: Node, skeleton: Skeleton3D, debug_name: String) -> void:
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		var original_skin = mesh_instance.skin

		if original_skin and skeleton:
			# 新しいスキンを作成してボーンインデックスを正しく設定
			var new_skin = Skin.new()
			var fixed_count := 0

			for i in range(original_skin.get_bind_count()):
				var bind_name = original_skin.get_bind_name(i)
				var bind_pose = original_skin.get_bind_pose(i)

				# スケルトンからボーンインデックスを取得
				var bone_idx = skeleton.find_bone(bind_name)

				new_skin.add_bind(bone_idx, bind_pose)
				new_skin.set_bind_name(i, bind_name)

				if bone_idx >= 0:
					fixed_count += 1

			# 新しいスキンを適用
			mesh_instance.skin = new_skin

			# スキンをスケルトンに登録
			skeleton.register_skin(new_skin)

			if debug_name:
				print("[CharacterSetup] %s: Fixed skin '%s' - %d/%d binds resolved" % [
					debug_name, mesh_instance.name, fixed_count, new_skin.get_bind_count()
				])

	for child in node.get_children():
		_fix_skin_bindings_recursive(child, skeleton, debug_name)


## 上半身ボーンのリストを取得（アニメーションブレンディング用）
## Spineより上の全てのボーン（頭、腕、手、指など）を返す
static func get_upper_body_bones(skeleton: Skeleton3D) -> Array[String]:
	var upper_bones: Array[String] = []
	if skeleton == null:
		return upper_bones

	# 上半身の起点ボーン（Spine以上）
	var upper_root_bones = [
		"mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2",
		"mixamorig_Neck", "mixamorig_Head",
		"mixamorig_LeftShoulder", "mixamorig_RightShoulder"
	]

	# 全ボーンをチェックして上半身ボーンを収集
	for i in range(skeleton.get_bone_count()):
		var bone_name = skeleton.get_bone_name(i)

		# 上半身ボーンかどうかを判定
		if _is_upper_body_bone(bone_name):
			upper_bones.append(bone_name)

	return upper_bones


## ボーンが上半身に属するかを判定
static func _is_upper_body_bone(bone_name: String) -> bool:
	# 上半身に属するキーワード
	var upper_keywords = [
		"Spine", "Neck", "Head",
		"Shoulder", "Arm", "ForeArm", "Hand",
		"Thumb", "Index", "Middle", "Ring", "Pinky"  # 指
	]

	for keyword in upper_keywords:
		if keyword in bone_name:
			return true

	return false


## 下半身ボーンのリストを取得（アニメーションブレンディング用）
## Hipsより下の全てのボーン（脚、足など）を返す
static func get_lower_body_bones(skeleton: Skeleton3D) -> Array[String]:
	var lower_bones: Array[String] = []
	if skeleton == null:
		return lower_bones

	for i in range(skeleton.get_bone_count()):
		var bone_name = skeleton.get_bone_name(i)

		# 下半身ボーンかどうかを判定
		if _is_lower_body_bone(bone_name):
			lower_bones.append(bone_name)

	return lower_bones


## ボーンが下半身に属するかを判定
static func _is_lower_body_bone(bone_name: String) -> bool:
	# 下半身に属するキーワード
	var lower_keywords = [
		"Hips",
		"UpLeg", "Leg", "Foot", "Toe"
	]

	for keyword in lower_keywords:
		if keyword in bone_name:
			return true

	return false
