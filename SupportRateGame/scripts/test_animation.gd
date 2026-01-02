extends Node3D

## アニメーションテストシーン
## ボタンで各アニメーション状態を切り替えて確認
## Sキーで射撃状態をトグル（上半身ブレンディングテスト）

var model: Node3D
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var anim_blend_tree: AnimationNodeBlendTree
var skeleton: Skeleton3D

var is_shooting: bool = false
var current_locomotion: String = "idle_rifle"
var muzzle_flash: Node = null
var shoot_timer: float = 0.0
const SHOOT_INTERVAL: float = 0.1  # 連射間隔（秒）

func _ready() -> void:
	print("=== Animation Test Scene ===")

	# FBXモデルをロード
	var fbx_scene = load("res://assets/characters/gsg9/gsg9.fbx")
	model = fbx_scene.instantiate()
	model.name = "TestCharacter"
	model.transform = Transform3D(Basis().scaled(Vector3(2, 2, 2)), Vector3(0, 0, 0))
	add_child(model)

	# スケルトンを取得
	skeleton = CharacterSetup.find_skeleton(model)
	if skeleton:
		# スキンバインディングを修正
		CharacterSetup.fix_skin_bindings(model, skeleton, "Test")

		# Y位置オフセットを適用
		var y_offset = CharacterSetup.calculate_y_offset_from_skeleton(skeleton, 2.0, "Test")
		model.position.y = y_offset

	# AnimationPlayerを取得してアニメーションをロード
	anim_player = CharacterSetup.find_animation_player(model)
	if anim_player:
		CharacterSetup.load_animations(anim_player, model, "Test")

		# 既存のAnimationTreeを無効化
		var existing_tree = model.get_node_or_null("AnimationTree")
		if existing_tree:
			existing_tree.active = false

	# テクスチャを適用
	CharacterSetup.setup_materials(model, "Test")

	# 武器を装着
	if skeleton:
		CharacterSetup.attach_weapon_to_character(model, skeleton, CharacterSetup.WeaponId.AK47, "Test")
		# マズルフラッシュの参照を取得
		_find_muzzle_flash()

	# AnimationTreeをセットアップ（上半身ブレンド用）
	_setup_animation_tree()

	# 利用可能なアニメーションを表示
	print("[Test] Available animations:")
	for anim_name in anim_player.get_animation_list():
		print("  - %s" % anim_name)


func _setup_animation_tree() -> void:
	if not anim_player or not skeleton:
		return

	# AnimationTreeを作成
	anim_tree = AnimationTree.new()
	anim_tree.name = "TestAnimationTree"
	model.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)

	# BlendTreeを作成
	anim_blend_tree = AnimationNodeBlendTree.new()
	anim_tree.tree_root = anim_blend_tree

	# locomotionアニメーション（全身）
	var locomotion_anim = AnimationNodeAnimation.new()
	locomotion_anim.animation = "idle_rifle"
	anim_blend_tree.add_node("locomotion", locomotion_anim, Vector2(0, 0))

	# shootアニメーション（上半身用 - idle_aiming_rifleを使用：構え姿勢）
	var shoot_anim = AnimationNodeAnimation.new()
	shoot_anim.animation = "idle_aiming_rifle"
	anim_blend_tree.add_node("shoot", shoot_anim, Vector2(0, 200))

	# Blend2ノード（上半身のみブレンド）
	var blend2 = AnimationNodeBlend2.new()
	anim_blend_tree.add_node("upper_blend", blend2, Vector2(300, 100))

	# 接続
	anim_blend_tree.connect_node("upper_blend", 0, "locomotion")
	anim_blend_tree.connect_node("upper_blend", 1, "shoot")
	anim_blend_tree.connect_node("output", 0, "upper_blend")

	# 上半身フィルターを設定
	_setup_upper_body_filter(blend2)

	# AnimationTreeを有効化
	anim_tree.active = true
	print("[Test] AnimationTree setup complete")


func _setup_upper_body_filter(blend_node: AnimationNodeBlend2) -> void:
	blend_node.filter_enabled = true

	var upper_body_bones = [
		"mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2",
		"mixamorig_Neck", "mixamorig_Head", "mixamorig_HeadTop_End",
		"mixamorig_LeftShoulder", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand",
		"mixamorig_RightShoulder", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand",
	]

	# 指のボーンも追加
	for side in ["Left", "Right"]:
		for finger in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			for i in range(1, 5):
				upper_body_bones.append("mixamorig_%sHand%s%d" % [side, finger, i])

	var armature_path = "Armature/" if model.get_node_or_null("Armature") else ""

	for bone_name in upper_body_bones:
		var bone_idx = skeleton.find_bone(bone_name)
		if bone_idx >= 0:
			var bone_path = "%sSkeleton3D:%s" % [armature_path, bone_name]
			blend_node.set_filter_path(NodePath(bone_path), true)


func _play_animation(anim_name: String) -> void:
	if anim_player and anim_player.has_animation(anim_name):
		anim_player.play(anim_name)
		print("[Test] Playing: %s" % anim_name)
	else:
		print("[Test] Animation not found: %s" % anim_name)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_set_locomotion("idle_rifle")
			KEY_2:
				_set_locomotion("walking_rifle")
			KEY_3:
				_set_locomotion("running_rifle")
			KEY_4:
				_set_locomotion("idle_none")
			KEY_5:
				_set_locomotion("walking_none")
			KEY_6:
				_set_locomotion("running_none")
			KEY_7:
				_play_animation("dying")
			KEY_Q:
				_set_locomotion("idle_pistol")
			KEY_W:
				_set_locomotion("walking_pistol")
			KEY_E:
				_set_locomotion("running_pistol")
			KEY_S:
				_toggle_shooting()


func _set_locomotion(anim_name: String) -> void:
	if anim_tree and anim_tree.active:
		# AnimationTree使用時はlocomotionノードのアニメーションを変更
		var locomotion_node = anim_blend_tree.get_node("locomotion") as AnimationNodeAnimation
		if locomotion_node:
			locomotion_node.animation = anim_name
			current_locomotion = anim_name
			print("[Test] Locomotion: %s" % anim_name)
	else:
		_play_animation(anim_name)


func _toggle_shooting() -> void:
	is_shooting = not is_shooting
	if anim_tree:
		anim_tree.set("parameters/upper_blend/blend_amount", 1.0 if is_shooting else 0.0)
	print("[Test] Shooting: %s" % ("ON" if is_shooting else "OFF"))


func _find_muzzle_flash() -> void:
	# 武器はskeletonにWeaponAttachmentとして装着されている
	if skeleton:
		var weapon_attachment = skeleton.get_node_or_null("WeaponAttachment")
		if weapon_attachment:
			muzzle_flash = weapon_attachment.find_child("MuzzleFlash", true, false)
			if muzzle_flash:
				print("[Test] MuzzleFlash found in WeaponAttachment")
				return
	# フォールバック：モデル全体から探す
	muzzle_flash = model.find_child("MuzzleFlash", true, false)
	if muzzle_flash:
		print("[Test] MuzzleFlash found (fallback)")
	else:
		print("[Test] MuzzleFlash not found")


func _process(delta: float) -> void:
	# 射撃中はマズルフラッシュを発生
	if is_shooting and muzzle_flash:
		shoot_timer -= delta
		if shoot_timer <= 0:
			muzzle_flash.flash()
			shoot_timer = SHOOT_INTERVAL

	# 操作説明を画面に表示（60フレームごと）
	if Engine.get_process_frames() == 1:
		print("")
		print("=== Controls ===")
		print("1: idle_rifle")
		print("2: walking_rifle")
		print("3: running_rifle")
		print("4: idle_none")
		print("5: walking_none")
		print("6: running_none")
		print("7: dying")
		print("Q: idle_pistol")
		print("W: walking_pistol")
		print("E: running_pistol")
		print("S: Toggle shooting (upper body blend)")
		print("================")
