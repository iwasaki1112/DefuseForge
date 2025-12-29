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
const WEAPON_DATA := {
	WeaponId.NONE: {
		"name": "None",
		"type": WeaponType.NONE,
		"price": 0,
		"damage": 0,
		"fire_rate": 0.0,
		"scene_path": "",
		"kill_reward": 300
	},
	WeaponId.AK47: {
		"name": "AK-47",
		"type": WeaponType.RIFLE,
		"price": 2700,
		"damage": 36,
		"fire_rate": 0.1,
		"scene_path": "res://scenes/weapons/ak47.tscn",  # シーンファイルを使用
		"kill_reward": 300
	},
	WeaponId.USP: {
		"name": "USP",
		"type": WeaponType.PISTOL,
		"price": 500,
		"damage": 25,
		"fire_rate": 0.15,
		"scene_path": "",  # TODO: USPシーンを追加
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
		"idle": "res://assets/characters/animations/idle.fbx",
		"walking": "res://assets/characters/animations/walking.fbx",
		"running": "res://assets/characters/animations/running.fbx"
	},
	WeaponType.RIFLE: {
		"idle": "res://assets/characters/animations/rifle/idle.fbx",
		"walking": "res://assets/characters/animations/rifle/walking.fbx",
		"running": "res://assets/characters/animations/rifle/running.fbx"
	},
	WeaponType.PISTOL: {
		"idle": "res://assets/characters/animations/pistol/idle.fbx",
		"walking": "res://assets/characters/animations/pistol/walking.fbx",
		"running": "res://assets/characters/animations/pistol/running.fbx"
	}
}

## 武器タイプ名称
const WEAPON_TYPE_NAMES := {
	WeaponType.NONE: "none",
	WeaponType.RIFLE: "rifle",
	WeaponType.PISTOL: "pistol"
}

## 武器タイプ別のY位置調整（アニメーションのHips位置の差を補正）
const WEAPON_Y_OFFSET := {
	WeaponType.NONE: 0.0,
	WeaponType.RIFLE: 0.0,
	WeaponType.PISTOL: 0.0
}

## キャラクター別のY位置オフセット（足の位置を地面に合わせるため）
## スケール2の場合の値。toe base bone Y=0になるよう計算。
const CHARACTER_Y_OFFSET := {
	"leet": -1.14,  # toe base local Y(0.57) * scale(2) = 1.14
	"gsg9": -1.23,  # toe base local Y(0.616) * scale(2) = 1.23
}


## キャラクター名からYオフセットを取得
static func get_y_offset(character_name: String) -> float:
	var key = character_name.to_lower()
	for k in CHARACTER_Y_OFFSET.keys():
		if k in key:
			return CHARACTER_Y_OFFSET[k]
	return 0.0


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


## AnimationPlayerにアニメーションを読み込む（全武器タイプ）
static func load_animations(anim_player: AnimationPlayer, model: Node, debug_name: String = "") -> void:
	var lib = anim_player.get_animation_library("")
	if lib == null:
		if debug_name:
			print("[CharacterSetup] %s: No animation library found!" % debug_name)
		return

	if debug_name:
		print("[CharacterSetup] %s: Loading animations..." % debug_name)

	# 全武器タイプのアニメーションを読み込み
	for weapon_type in ANIMATION_FILES.keys():
		var weapon_name = WEAPON_TYPE_NAMES[weapon_type]
		var anims = ANIMATION_FILES[weapon_type]
		for anim_name in anims.keys():
			var full_anim_name = "%s_%s" % [anim_name, weapon_name]  # 例: idle_none, walking_rifle
			_load_animation_from_fbx(lib, anims[anim_name], full_anim_name, model, debug_name)

	if debug_name:
		print("[CharacterSetup] %s: Available animations: %s" % [debug_name, anim_player.get_animation_list()])


## 指定した武器タイプのアニメーション名を取得
static func get_animation_name(base_name: String, weapon_type: int) -> String:
	var weapon_name = WEAPON_TYPE_NAMES.get(weapon_type, "none")
	return "%s_%s" % [base_name, weapon_name]


## 指定した武器タイプのアニメーションが存在するか確認
static func has_weapon_animations(anim_player: AnimationPlayer, weapon_type: int) -> bool:
	var weapon_name = WEAPON_TYPE_NAMES.get(weapon_type, "none")
	return anim_player.has_animation("idle_%s" % weapon_name)


## FBXファイルからアニメーションを読み込む
static func _load_animation_from_fbx(lib: AnimationLibrary, path: String, anim_name: String, model: Node, debug_name: String) -> void:
	# ファイルが存在するか確認（エラー抑制のため）
	if not ResourceLoader.exists(path):
		return

	var scene = load(path)
	if scene == null:
		if debug_name:
			print("[CharacterSetup] %s: Failed to load %s" % [debug_name, path])
		return

	# rifle/pistolアニメーションはHips位置トラックのX,Z座標を0に固定（移動防止、高さは保持）
	var fix_hips_position = anim_name.ends_with("_rifle") or anim_name.ends_with("_pistol")
	if fix_hips_position and debug_name:
		print("[CharacterSetup] %s: Will fix Hips position XZ for %s" % [debug_name, anim_name])

	var instance = scene.instantiate()
	var scene_anim_player = instance.get_node_or_null("AnimationPlayer")
	if scene_anim_player:
		for anim_name_in_lib in scene_anim_player.get_animation_list():
			var anim = scene_anim_player.get_animation(anim_name_in_lib)
			if anim:
				var anim_copy = anim.duplicate()
				anim_copy.loop_mode = Animation.LOOP_LINEAR
				_adjust_animation_paths(anim_copy, model, fix_hips_position)
				lib.add_animation(anim_name, anim_copy)
				break
	else:
		if debug_name:
			print("[CharacterSetup] %s: No AnimationPlayer in %s" % [debug_name, path])
	instance.queue_free()


## アニメーションのトラックパスをモデル階層に合わせて調整
static func _adjust_animation_paths(anim: Animation, model: Node, fix_hips_position: bool = false) -> void:
	if model == null:
		return

	# Armatureノードが存在するかチェック
	var has_armature = model.get_node_or_null("Armature") != null

	# Hips位置トラックを修正するためのリスト
	var hips_position_tracks: Array[int] = []

	# デバッグ: 全トラックを確認
	if fix_hips_position:
		print("[CharacterSetup] Checking %d tracks for Hips position fix" % anim.get_track_count())

	# トラックパスを調整
	for i in range(anim.get_track_count()):
		var track_path = anim.track_get_path(i)
		var path_str = str(track_path)
		var track_type = anim.track_get_type(i)

		# デバッグ: Hips位置トラック情報（全アニメーション）
		if "Hips" in path_str and track_type == Animation.TYPE_POSITION_3D:
			var key_count = anim.track_get_key_count(i)
			if key_count > 0:
				var first_pos: Vector3 = anim.track_get_key_value(i, 0)
				print("[CharacterSetup] Hips position track found - Y: %.3f (fix=%s)" % [first_pos.y, fix_hips_position])

		# ボーン名の違いを修正（アニメーションは"mixamorig1_"、キャラクターは"mixamorig_"）
		path_str = path_str.replace("mixamorig1_", "mixamorig_")

		# rifle/pistolの場合、Hips位置トラックのX,Z座標を0に固定（Y座標は保持）
		if fix_hips_position and "Hips" in path_str:
			if track_type == Animation.TYPE_POSITION_3D:
				print("[CharacterSetup] Marking track %d for XZ fix: %s" % [i, path_str])
				hips_position_tracks.append(i)

		# Armatureノードがある場合のみプレフィックスを追加
		if has_armature and path_str.begins_with("Skeleton3D:"):
			path_str = "Armature/" + path_str

		anim.track_set_path(i, NodePath(path_str))

	# Hips位置トラックを修正：X,Z座標を0に固定し、Y座標をNONEアニメーションと合わせる
	# NONEアニメーションのHips Y: 約0.99、RIFLEアニメーションのHips Y: 約0.35
	# 差分（約0.62）を加算してNONEと同じ高さに補正
	const HIPS_Y_OFFSET: float = 0.62

	for track_idx in hips_position_tracks:
		var key_count = anim.track_get_key_count(track_idx)
		# 最初のキーのY座標を出力（デバッグ用）
		if key_count > 0:
			var first_pos: Vector3 = anim.track_get_key_value(track_idx, 0)
			print("[CharacterSetup] Hips Y before fix: %.3f, after fix: %.3f" % [first_pos.y, first_pos.y + HIPS_Y_OFFSET])
		for key_idx in range(key_count):
			var pos: Vector3 = anim.track_get_key_value(track_idx, key_idx)
			# X,Zを0に固定し、YにオフセットをNONEと合わせるための補正を加算
			var fixed_pos = Vector3(0, pos.y + HIPS_Y_OFFSET, 0)
			anim.track_set_key_value(track_idx, key_idx, fixed_pos)


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
	if data == null or data.model_path.is_empty():
		if debug_name:
			print("[CharacterSetup] %s: No weapon model for weapon_id %d" % [debug_name, weapon_id])
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
