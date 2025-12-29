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

## アニメーションファイルパス
const ANIMATION_FILES := {
	"idle": "res://assets/characters/animations/idle.fbx",
	"walking": "res://assets/characters/animations/walking.fbx",
	"running": "res://assets/characters/animations/running.fbx"
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


## AnimationPlayerにアニメーションを読み込む
static func load_animations(anim_player: AnimationPlayer, model: Node, debug_name: String = "") -> void:
	var lib = anim_player.get_animation_library("")
	if lib == null:
		if debug_name:
			print("[CharacterSetup] %s: No animation library found!" % debug_name)
		return

	if debug_name:
		print("[CharacterSetup] %s: Loading animations..." % debug_name)

	for anim_name in ANIMATION_FILES.keys():
		_load_animation_from_fbx(lib, ANIMATION_FILES[anim_name], anim_name, model, debug_name)

	if debug_name:
		print("[CharacterSetup] %s: Available animations: %s" % [debug_name, anim_player.get_animation_list()])


## FBXファイルからアニメーションを読み込む
static func _load_animation_from_fbx(lib: AnimationLibrary, path: String, anim_name: String, model: Node, debug_name: String) -> void:
	var scene = load(path)
	if scene == null:
		if debug_name:
			print("[CharacterSetup] %s: Failed to load %s" % [debug_name, path])
		return

	var instance = scene.instantiate()
	var scene_anim_player = instance.get_node_or_null("AnimationPlayer")
	if scene_anim_player:
		for anim_name_in_lib in scene_anim_player.get_animation_list():
			var anim = scene_anim_player.get_animation(anim_name_in_lib)
			if anim:
				var anim_copy = anim.duplicate()
				anim_copy.loop_mode = Animation.LOOP_LINEAR
				_adjust_animation_paths(anim_copy, model)
				lib.add_animation(anim_name, anim_copy)
				break
	else:
		if debug_name:
			print("[CharacterSetup] %s: No AnimationPlayer in %s" % [debug_name, path])
	instance.queue_free()


## アニメーションのトラックパスをモデル階層に合わせて調整
static func _adjust_animation_paths(anim: Animation, model: Node) -> void:
	if model == null:
		return

	# Armatureノードが存在するかチェック
	var has_armature = model.get_node_or_null("Armature") != null

	# トラックパスを調整
	for i in range(anim.get_track_count()):
		var track_path = anim.track_get_path(i)
		var path_str = str(track_path)

		# ボーン名の違いを修正（アニメーションは"mixamorig1_"、キャラクターは"mixamorig_"）
		path_str = path_str.replace("mixamorig1_", "mixamorig_")

		# Armatureノードがある場合のみプレフィックスを追加
		if has_armature and path_str.begins_with("Skeleton3D:"):
			path_str = "Armature/" + path_str

		anim.track_set_path(i, NodePath(path_str))


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
