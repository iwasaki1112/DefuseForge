class_name CharacterSetup
extends RefCounted

## キャラクターモデルのセットアップユーティリティ
## テクスチャ適用、アニメーション読み込みなどの共通処理を提供

## テクスチャマッピング定義
## キャラクター: phantom = Terrorist, vanguard = Counter-Terrorist
const TEXTURE_MAP := {
	"phantom": {
		"albedo": "res://assets/characters/phantom/phantom_phantom_basecolor.png",
		"normal": ""
	},
	"vanguard": {
		"albedo": "res://assets/characters/vanguard/vanguard_basecolor.png",
		"normal": ""
	}
}

## キャラクターの明るさ補正（1.0=変更なし、1.3=30%明るく）
const CHARACTER_BRIGHTNESS: float = 1.8

## 武器タイプ（アニメーションカテゴリ）
enum WeaponType { NONE, RIFLE, PISTOL }

## 武器ID
enum WeaponId { NONE, AK47, USP, M4A1 }

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
		"magazine_size": 0,
		"reload_time": 0.0,
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
		"magazine_size": 30,
		"reload_time": 2.5,
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
		"magazine_size": 12,
		"reload_time": 1.8,
		"scene_path": "",
		"kill_reward": 300
	},
	WeaponId.M4A1: {
		"name": "M4A1",
		"type": WeaponType.RIFLE,
		"price": 0,
		"damage": 33,
		"fire_rate": 0.09,
		"accuracy": 0.88,
		"range": 22.0,
		"headshot_multiplier": 4.0,
		"bodyshot_multiplier": 1.0,
		"magazine_size": 30,
		"reload_time": 2.3,
		"scene_path": "res://scenes/weapons/m4a1.tscn",
		"kill_reward": 300
	}
}

## 武器ID名称
const WEAPON_ID_NAMES := {
	WeaponId.NONE: "none",
	WeaponId.AK47: "ak47",
	WeaponId.USP: "usp",
	WeaponId.M4A1: "m4a1"
}

## Rifle Animset Pro FBXファイルパス
const RIFLE_ANIMSET_PRO_PATH := "res://assets/characters/animations/rifle_animset_pro/"
const RIFLE_ANIMSET_FBX := {
	"main": RIFLE_ANIMSET_PRO_PATH + "RifleAnimsetPro.fbx",
	"sprint": RIFLE_ANIMSET_PRO_PATH + "RifleAnimsetPro_Sprint.fbx",
	"additionals": RIFLE_ANIMSET_PRO_PATH + "RifleAnimsetPro_Additionals.fbx",
	"diagonals": RIFLE_ANIMSET_PRO_PATH + "RifleAnimsetPro_Diagonals.fbx",
	"equips": RIFLE_ANIMSET_PRO_PATH + "RifleAnimsetPro_Equips.fbx",
	"jumps": RIFLE_ANIMSET_PRO_PATH + "RifleAnimsetPro_Platformer_Jumps.fbx"
}

## HumanIK → Mixamo ボーン名マッピング
const BONE_NAME_MAP := {
	"Hips": "mixamorig_Hips",
	"Spine": "mixamorig_Spine",
	"Spine1": "mixamorig_Spine1",
	"Spine2": "mixamorig_Spine2",
	"Neck": "mixamorig_Neck",
	"Head": "mixamorig_Head",
	"HeadTop_End": "mixamorig_HeadTop_End",
	"LeftShoulder": "mixamorig_LeftShoulder",
	"LeftArm": "mixamorig_LeftArm",
	"LeftArmRoll": "mixamorig_LeftArm",  # Roll bones map to parent
	"LeftForeArm": "mixamorig_LeftForeArm",
	"LeftForeArmRoll": "mixamorig_LeftForeArm",
	"LeftHand": "mixamorig_LeftHand",
	"LeftHandThumb1": "mixamorig_LeftHandThumb1",
	"LeftHandThumb2": "mixamorig_LeftHandThumb2",
	"LeftHandThumb3": "mixamorig_LeftHandThumb3",
	"LeftHandThumb4": "mixamorig_LeftHandThumb4",
	"LeftHandIndex1": "mixamorig_LeftHandIndex1",
	"LeftHandIndex2": "mixamorig_LeftHandIndex2",
	"LeftHandIndex3": "mixamorig_LeftHandIndex3",
	"LeftHandIndex4": "mixamorig_LeftHandIndex4",
	"LeftHandMiddle1": "mixamorig_LeftHandMiddle1",
	"LeftHandMiddle2": "mixamorig_LeftHandMiddle2",
	"LeftHandMiddle3": "mixamorig_LeftHandMiddle3",
	"LeftHandMiddle4": "mixamorig_LeftHandMiddle4",
	"LeftHandRing1": "mixamorig_LeftHandRing1",
	"LeftHandRing2": "mixamorig_LeftHandRing2",
	"LeftHandRing3": "mixamorig_LeftHandRing3",
	"LeftHandRing4": "mixamorig_LeftHandRing4",
	"LeftHandPinky1": "mixamorig_LeftHandPinky1",
	"LeftHandPinky2": "mixamorig_LeftHandPinky2",
	"LeftHandPinky3": "mixamorig_LeftHandPinky3",
	"LeftHandPinky4": "mixamorig_LeftHandPinky4",
	"RightShoulder": "mixamorig_RightShoulder",
	"RightArm": "mixamorig_RightArm",
	"RightArmRoll": "mixamorig_RightArm",
	"RightForeArm": "mixamorig_RightForeArm",
	"RightForeArmRoll": "mixamorig_RightForeArm",
	"RightHand": "mixamorig_RightHand",
	"RightHandThumb1": "mixamorig_RightHandThumb1",
	"RightHandThumb2": "mixamorig_RightHandThumb2",
	"RightHandThumb3": "mixamorig_RightHandThumb3",
	"RightHandThumb4": "mixamorig_RightHandThumb4",
	"RightHandIndex1": "mixamorig_RightHandIndex1",
	"RightHandIndex2": "mixamorig_RightHandIndex2",
	"RightHandIndex3": "mixamorig_RightHandIndex3",
	"RightHandIndex4": "mixamorig_RightHandIndex4",
	"RightHandMiddle1": "mixamorig_RightHandMiddle1",
	"RightHandMiddle2": "mixamorig_RightHandMiddle2",
	"RightHandMiddle3": "mixamorig_RightHandMiddle3",
	"RightHandMiddle4": "mixamorig_RightHandMiddle4",
	"RightHandRing1": "mixamorig_RightHandRing1",
	"RightHandRing2": "mixamorig_RightHandRing2",
	"RightHandRing3": "mixamorig_RightHandRing3",
	"RightHandRing4": "mixamorig_RightHandRing4",
	"RightHandPinky1": "mixamorig_RightHandPinky1",
	"RightHandPinky2": "mixamorig_RightHandPinky2",
	"RightHandPinky3": "mixamorig_RightHandPinky3",
	"RightHandPinky4": "mixamorig_RightHandPinky4",
	"LeftUpLeg": "mixamorig_LeftUpLeg",
	"LeftUpLegRoll": "mixamorig_LeftUpLeg",
	"LeftLeg": "mixamorig_LeftLeg",
	"LeftLegRoll": "mixamorig_LeftLeg",
	"LeftFoot": "mixamorig_LeftFoot",
	"LeftToeBase": "mixamorig_LeftToeBase",
	"LeftToeBase_END": "mixamorig_LeftToe_End",
	"RightUpLeg": "mixamorig_RightUpLeg",
	"RightUpLegRoll": "mixamorig_RightUpLeg",
	"RightLeg": "mixamorig_RightLeg",
	"RightLegRoll": "mixamorig_RightLeg",
	"RightFoot": "mixamorig_RightFoot",
	"RightToeBase": "mixamorig_RightToeBase",
	"RightToeBase_END": "mixamorig_RightToe_End"
}

## Rifle Animset Proのアニメーションマッピング
## 構造: { "内部アニメーション名": { "fbx": FBXキー, "clip": クリップ名, "loop": bool } }
## 全武器タイプで同じアニメーションを使用（タクティカルシューターでは一般的）
const RIFLE_ANIMSET_ANIMATIONS := {
	# RIFLE アニメーション
	"idle_rifle": { "fbx": "main", "clip": "Rifle_Idle", "loop": true },
	"walking_rifle": { "fbx": "main", "clip": "Rifle_WalkFwdLoop", "loop": true },
	"running_rifle": { "fbx": "sprint", "clip": "Rifle_SprintLoop", "loop": true },
	"shoot_rifle": { "fbx": "main", "clip": "Rifle_ShootOnce", "loop": false },
	"reload_rifle": { "fbx": "main", "clip": "Rifle_Reload_2", "loop": false },
	"melee_rifle": { "fbx": "main", "clip": "Rifle_Melee_Hard", "loop": false },

	# PISTOL アニメーション（ライフルと同じアニメーションを使用）
	"idle_pistol": { "fbx": "main", "clip": "Rifle_Idle", "loop": true },
	"walking_pistol": { "fbx": "main", "clip": "Rifle_WalkFwdLoop", "loop": true },
	"running_pistol": { "fbx": "sprint", "clip": "Rifle_SprintLoop", "loop": true },
	"shoot_pistol": { "fbx": "main", "clip": "Rifle_ShootOnce", "loop": false },

	# NONE アニメーション（武器なし - ライフルと同じアニメーションを使用）
	"idle_none": { "fbx": "main", "clip": "Rifle_Idle", "loop": true },
	"walking_none": { "fbx": "main", "clip": "Rifle_WalkFwdLoop", "loop": true },
	"running_none": { "fbx": "sprint", "clip": "Rifle_SprintLoop", "loop": true },

	# 共通アニメーション
	"dying": { "fbx": "main", "clip": "Rifle_Death_R", "loop": false },
	"dying_left": { "fbx": "main", "clip": "Rifle_Death_L", "loop": false },

	# ターンアニメーション
	"turn_right_90": { "fbx": "main", "clip": "Rifle_TurnR_90", "loop": false },
	"turn_left_90": { "fbx": "main", "clip": "Rifle_TurnL_90", "loop": false },
	"turn_right_180": { "fbx": "main", "clip": "Rifle_TurnR_180", "loop": false },
	"turn_left_180": { "fbx": "main", "clip": "Rifle_TurnL_180", "loop": false },

	# ヒットリアクション
	"hit_left": { "fbx": "main", "clip": "Rifle_Hit_L_1", "loop": false },
	"hit_right": { "fbx": "main", "clip": "Rifle_Hit_R_2", "loop": false },
	"hit_center": { "fbx": "main", "clip": "Rifle_Hit_C_1", "loop": false },

	# グレネード
	"grenade_throw": { "fbx": "main", "clip": "Rifle_Grenade_Throw_Single", "loop": false }
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

## アニメーション状態の定義
enum AnimState { IDLE, WALKING, RUNNING, FIRE }

## アニメーション状態名からAnimState enumに変換するマップ
const ANIM_STATE_MAP := {
	"idle": AnimState.IDLE,
	"walking": AnimState.WALKING,
	"running": AnimState.RUNNING,
	"fire": AnimState.FIRE,
	"shoot": AnimState.FIRE,  # shootもfireとして扱う
	"idle_aiming": AnimState.FIRE  # idle_aimingもfireとして扱う
}

## 武器のアニメーションごとの位置・回転オフセット
## 構造: { WeaponId: { AnimState: { "position": Vector3, "rotation": Vector3 (degrees) } } }
## 値を変更する場合はこの定数を直接編集してください
## 注意: rotation はオイラー角（度数法）で指定し、内部でラジアンに変換
const WEAPON_ANIMATION_OFFSETS := {
	WeaponId.AK47: {
		AnimState.IDLE: {
			"position": Vector3(0.0, 0.0, 0.0),
			"rotation": Vector3(0.0, 0.0, 0.0)
		},
		AnimState.WALKING: {
			"position": Vector3(0.0, 0.0, 0.0),
			"rotation": Vector3(0.0, 0.0, 0.0)
		},
		AnimState.RUNNING: {
			"position": Vector3(0.0, 0.0, 0.0),
			"rotation": Vector3(0.0, 0.0, 0.0)
		},
		AnimState.FIRE: {
			"position": Vector3(0.0, 0.0, 0.0),
			"rotation": Vector3(0.0, 0.0, 0.0)
		}
	},
	WeaponId.USP: {
		AnimState.IDLE: {
			"position": Vector3(0.0, 0.0, 0.0),
			"rotation": Vector3(0.0, 0.0, 0.0)
		},
		AnimState.WALKING: {
			"position": Vector3(0.0, 0.0, 0.0),
			"rotation": Vector3(0.0, 0.0, 0.0)
		},
		AnimState.RUNNING: {
			"position": Vector3(0.0, 0.0, 0.0),
			"rotation": Vector3(0.0, 0.0, 0.0)
		},
		AnimState.FIRE: {
			"position": Vector3(0.0, 0.0, 0.0),
			"rotation": Vector3(0.0, 0.0, 0.0)
		}
	}
}

## 武器のベース位置・回転（ak47.tscn内のModelトランスフォームからコピー）
## これにアニメーションオフセットが加算される
const WEAPON_BASE_TRANSFORM := {
	WeaponId.AK47: {
		"position": Vector3(-0.03, 0.13, 0.02),
		"rotation": Vector3(-6.13, 56.77, 3.96)  # 度数法
	},
	WeaponId.USP: {
		"position": Vector3(0.0, 0.0, 0.0),
		"rotation": Vector3(0.0, 0.0, 0.0)
	}
}

## アニメーションのHips Y位置の目標値（全武器タイプで統一）
## この値にHips Yを正規化することで、武器タイプ切替時の位置ズレを防ぐ
const ANIMATION_HIPS_TARGET_Y: float = 0.0

## Skeletonのレストポーズから足が地面に接地するためのYオフセットを算出
## アニメーションでHips YをレストポーズのY位置に正規化している前提
##
## 計算式: y_offset = -toe_rest_y × scale
## （ToeBaseがレスト位置にある場合、その分だけモデルを上げて地面に合わせる）
##
## @param skeleton: キャラクターのSkeleton3D
## @param model_scale: モデルのスケール（通常は2.0）
## @param debug_name: デバッグ用キャラクター名
## @return: Y位置オフセット
static func calculate_y_offset_from_skeleton(skeleton: Skeleton3D, model_scale: float = 2.0, debug_name: String = "") -> float:
	if skeleton == null:
		push_warning("[CharacterSetup] %s: Skeleton is null, cannot calculate Y offset" % debug_name)
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
	var toe_rest: Transform3D = skeleton.get_bone_global_rest(toe_idx)

	# ToeBaseのレストY位置の逆数がオフセット
	# （ToeBaseが地面レベル Y=0 になるようにモデルを配置）
	var y_offset := -toe_rest.origin.y * model_scale

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


## メッシュにテクスチャを適用（または明るさ補正のみ適用）
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

	# テクスチャをロード（マッチした場合のみ）
	var albedo_tex: Texture2D = null
	var normal_tex: Texture2D = null
	if not albedo_path.is_empty():
		albedo_tex = load(albedo_path) as Texture2D
		if not normal_path.is_empty():
			normal_tex = load(normal_path) as Texture2D

	# 各サーフェスにマテリアルを適用（明るさ補正は常に適用）
	if mesh_instance.mesh:
		var surface_count = mesh_instance.mesh.get_surface_count()
		for i in range(surface_count):
			var mat = mesh_instance.get_active_material(i)
			var new_mat: StandardMaterial3D

			if mat and mat is StandardMaterial3D:
				new_mat = mat.duplicate() as StandardMaterial3D
			else:
				new_mat = StandardMaterial3D.new()

			# テクスチャがある場合は適用
			if albedo_tex:
				new_mat.albedo_texture = albedo_tex

			new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			# 明るさ補正を常に適用
			new_mat.albedo_color = Color(CHARACTER_BRIGHTNESS, CHARACTER_BRIGHTNESS, CHARACTER_BRIGHTNESS, 1.0)

			if normal_tex:
				new_mat.normal_enabled = true
				new_mat.normal_texture = normal_tex

			mesh_instance.set_surface_override_material(i, new_mat)


## AnimationPlayerにアニメーションを読み込む（Rifle Animset Pro使用）
static func load_animations(anim_player: AnimationPlayer, model: Node, debug_name: String = "") -> void:
	var lib = anim_player.get_animation_library("")
	if lib == null:
		return

	# Rifle Animset Proからアニメーションを読み込み（外部FBXファイルから）
	_load_rifle_animset_pro_animations(lib, model, debug_name)

	# 外部FBXからの読み込みが失敗した場合、GLB埋め込みアニメーションを使用
	# idle_rifleが存在しなければフォールバック
	if not lib.has_animation("idle_rifle"):
		_load_embedded_animations_as_aliases(lib, anim_player)


## GLB埋め込みアニメーションを内部名にマッピング（フォールバック用）
static func _load_embedded_animations_as_aliases(lib: AnimationLibrary, anim_player: AnimationPlayer) -> void:
	# GLBのアニメーション名 -> 内部アニメーション名のマッピング
	var glb_to_internal := {
		"Rifle_Idle": ["idle_rifle", "idle_pistol", "idle_none"],
		"Rifle_WalkFwdLoop": ["walking_rifle", "walking_pistol", "walking_none"],
		"Rifle_SprintLoop": ["running_rifle", "running_pistol", "running_none"],
		"Rifle_Reload_2": ["reload_rifle"],
		"Rifle_Death_R": ["dying"],
		"Rifle_Death_L": ["dying_left"],
		"Rifle_Death_3": ["dying_3"],
		"Rifle_CrouchLoop": ["crouch_rifle", "crouch_pistol", "crouch_none"],
		"Rifle_OpenDoor": ["open_door"]
	}

	var loaded_count := 0
	for glb_name in glb_to_internal.keys():
		if anim_player.has_animation(glb_name):
			var anim = anim_player.get_animation(glb_name)
			if anim:
				var internal_names: Array = glb_to_internal[glb_name]
				for internal_name in internal_names:
					if not lib.has_animation(internal_name):
						var anim_copy = anim.duplicate()
						# ループ設定
						if internal_name.contains("idle") or internal_name.contains("walking") or internal_name.contains("running") or internal_name.contains("crouch"):
							anim_copy.loop_mode = Animation.LOOP_LINEAR
						lib.add_animation(internal_name, anim_copy)
						loaded_count += 1

	if loaded_count > 0:
		print("[CharacterSetup] Loaded %d animations from GLB fallback" % loaded_count)


## Rifle Animset Proからアニメーションを読み込む
static func _load_rifle_animset_pro_animations(lib: AnimationLibrary, model: Node, debug_name: String = "") -> void:
	# FBXファイルをキャッシュ（同じFBXから複数アニメーションを読み込むため）
	var fbx_cache: Dictionary = {}

	for anim_name in RIFLE_ANIMSET_ANIMATIONS.keys():
		var anim_data: Dictionary = RIFLE_ANIMSET_ANIMATIONS[anim_name]
		var fbx_key: String = anim_data.fbx
		var clip_name: String = anim_data.clip
		var loop: bool = anim_data.loop

		# FBXパスを取得
		var fbx_path: String = RIFLE_ANIMSET_FBX.get(fbx_key, "")
		if fbx_path.is_empty():
			continue

		# FBXがまだロードされていなければロード
		if not fbx_cache.has(fbx_key):
			if not ResourceLoader.exists(fbx_path):
				continue
			var scene = load(fbx_path)
			if scene:
				fbx_cache[fbx_key] = scene.instantiate()

		var fbx_instance = fbx_cache.get(fbx_key, null)
		if fbx_instance == null:
			continue

		# FBXからAnimationPlayerを取得
		var scene_anim_player = fbx_instance.get_node_or_null("AnimationPlayer")
		if scene_anim_player == null:
			continue

		# 指定されたクリップを検索
		if not scene_anim_player.has_animation(clip_name):
			continue

		# アニメーションをコピーして追加
		var anim = scene_anim_player.get_animation(clip_name)
		if anim:
			var anim_copy = anim.duplicate()
			anim_copy.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
			_adjust_animation_paths(anim_copy, model, "full", true)  # リターゲット有効
			lib.add_animation(anim_name, anim_copy)

	# キャッシュしたインスタンスを解放
	for key in fbx_cache.keys():
		var instance = fbx_cache[key]
		if instance:
			instance.queue_free()


## 指定した武器タイプのアニメーション名を取得
static func get_animation_name(base_name: String, weapon_type: int) -> String:
	var weapon_name = WEAPON_TYPE_NAMES.get(weapon_type, "none")
	return "%s_%s" % [base_name, weapon_name]


## 武器タイプからプレフィックスを取得（例: RIFLE -> "rifle_"）
## 歩行シーケンスなど、武器名が先に来るアニメーション用
static func get_weapon_prefix(weapon_type: int) -> String:
	var weapon_name = WEAPON_TYPE_NAMES.get(weapon_type, "")
	if weapon_name.is_empty() or weapon_name == "none":
		return ""
	return weapon_name + "_"


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
## @param retarget: ボーン名をリターゲットするか（デフォルト: false）
static func _load_animation_from_fbx(lib: AnimationLibrary, path: String, anim_name: String, model: Node, loop: bool = true, normalize_mode: String = "full", retarget: bool = false) -> void:
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
				_adjust_animation_paths(anim_copy, model, normalize_mode, retarget)
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
## @param retarget: HumanIK → Mixamoボーン名リターゲットを行うか
static func _adjust_animation_paths(anim: Animation, model: Node, normalize_mode: String = "full", retarget: bool = false) -> void:
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

		# リターゲット: HumanIK → Mixamo ボーン名変換
		if retarget:
			path_str = _retarget_bone_path(path_str)

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
	# 注意: CharacterBody3D + 物理演算で接地する場合、この正規化は参考程度
	# 物理がキャラクターを地面に押し付けるため、Hips Yの値は視覚的に影響しにくい
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


## HumanIK ボーン名を Mixamo ボーン名にリターゲット
## @param path_str: トラックパス文字列（例: "Skeleton3D:Hips"）
## @return: リターゲット後のパス文字列（例: "Skeleton3D:mixamorig_Hips"）
static func _retarget_bone_path(path_str: String) -> String:
	# パスを分解: "Skeleton3D:BoneName" or "Armature/Skeleton3D:BoneName"
	var colon_idx := path_str.rfind(":")
	if colon_idx == -1:
		return path_str

	var prefix := path_str.substr(0, colon_idx + 1)  # "Skeleton3D:" など
	var bone_name := path_str.substr(colon_idx + 1)  # "Hips" など

	# ボーン名をマッピング
	if BONE_NAME_MAP.has(bone_name):
		return prefix + BONE_NAME_MAP[bone_name]

	return path_str


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
		return null

	var weapon_instance = scene.instantiate()
	return weapon_instance


## キャラクターに武器をアタッチ
static func attach_weapon_to_character(character: Node, skeleton: Skeleton3D, weapon_id: int, _debug_name: String = "") -> Node3D:
	if skeleton == null:
		return null

	# 既存の武器を削除（スケルトンの子として探す）
	# queue_free() ではなく即座に削除して、武器が重複表示されないようにする
	var to_remove: Array[Node] = []
	for child in skeleton.get_children():
		if child is BoneAttachment3D and (child.name == "WeaponAttachment" or child.name.begins_with("@BoneAttachment3D")):
			to_remove.append(child)
	for node in to_remove:
		skeleton.remove_child(node)
		node.queue_free()
	
	# 武器なしの場合
	if weapon_id == WeaponId.NONE:
		return null

	var data = WEAPON_DATA.get(weapon_id, null)
	if data == null or data.scene_path.is_empty():
		return null

	# 右手のボーンインデックスを取得
	var bone_name = "mixamorig_RightHand"
	var bone_idx = skeleton.find_bone(bone_name)
	if bone_idx == -1:
		# 代替ボーン名を試す
		bone_name = "mixamorig1_RightHand"
		bone_idx = skeleton.find_bone(bone_name)

	if bone_idx == -1:
		return null

	# BoneAttachment3Dを作成
	var bone_attachment = BoneAttachment3D.new()
	bone_attachment.name = "WeaponAttachment"
	bone_attachment.bone_idx = bone_idx
	skeleton.add_child(bone_attachment)

	# 武器シーンをロード（位置・回転はシーンファイル内で設定済み）
	var weapon_model = create_weapon_attachment(weapon_id)
	if weapon_model:
		bone_attachment.add_child(weapon_model)

		# スケルトンのスケールを補正（test_animation_viewerと同様）
		# キャラクターモデルがスケールダウンされている場合、武器が小さすぎて見えなくなる
		var skeleton_global_scale = skeleton.global_transform.basis.get_scale()
		if skeleton_global_scale.x < 0.5:  # スケルトンが大幅にスケールダウンされている場合
			var compensation_scale = 1.0 / skeleton_global_scale.x
			weapon_model.scale = Vector3(compensation_scale, compensation_scale, compensation_scale)
			print("[CharacterSetup] Applied weapon scale compensation: %s (skeleton scale: %s)" % [compensation_scale, skeleton_global_scale])

		print("[CharacterSetup] Weapon attached: %s to bone_idx=%d" % [weapon_model.name, bone_idx])
		return bone_attachment

	print("[CharacterSetup] Failed to create weapon model for weapon_id=%d" % weapon_id)
	bone_attachment.queue_free()
	return null


## アニメーション状態に応じて武器の位置・回転を更新
## @param weapon_attachment: attach_weapon_to_characterで返されたBoneAttachment3D
## @param weapon_id: 武器ID
## @param anim_state: アニメーション状態（AnimState enum）
## @param debug_name: デバッグ用キャラクター名
## 注意: 位置・回転は武器ルートノードに適用される（Modelノードのシーントランスフォームは保持）
static func update_weapon_position(weapon_attachment: Node3D, weapon_id: int, anim_state: int, _debug_name: String = "") -> void:
	if weapon_attachment == null:
		return

	# 武器ルートノード（BoneAttachment3Dの子ノード）を取得
	var weapon_node: Node3D = null
	for child in weapon_attachment.get_children():
		if child is Node3D:
			weapon_node = child as Node3D
			break

	if weapon_node == null:
		return

	# アニメーションオフセットのみを取得（ベーストランスフォームはシーンファイルで設定済み）
	var offset_pos := Vector3.ZERO
	var offset_rot := Vector3.ZERO
	if WEAPON_ANIMATION_OFFSETS.has(weapon_id):
		var weapon_offsets: Dictionary = WEAPON_ANIMATION_OFFSETS[weapon_id]
		if weapon_offsets.has(anim_state):
			var offset_data: Dictionary = weapon_offsets[anim_state]
			offset_pos = offset_data.get("position", Vector3.ZERO)
			offset_rot = offset_data.get("rotation", Vector3.ZERO)

	# 武器ルートノードにオフセットを適用（Modelノードのシーントランスフォームは保持）
	# test_animation_viewerと同様のアプローチ
	weapon_node.position = offset_pos
	weapon_node.rotation_degrees = offset_rot


## アニメーション名からアニメーション状態を取得
## @param anim_name: アニメーション名（例: "idle_rifle", "walking_none"）
## @return: AnimState enum値（見つからない場合はAnimState.IDLE）
static func get_anim_state_from_name(anim_name: String) -> int:
	# アニメーション名からベース名を抽出（例: "idle_rifle" -> "idle"）
	var parts := anim_name.split("_")
	if parts.size() > 0:
		var base_name := parts[0]
		if ANIM_STATE_MAP.has(base_name):
			return ANIM_STATE_MAP[base_name]
	return AnimState.IDLE


## move_stateからAnimState enumに変換
## @param move_state: 0=idle, 1=walk, 2=run
## @param is_shooting: 射撃中かどうか
## @return: AnimState enum値
static func get_anim_state_from_move_state(move_state: int, is_shooting: bool = false) -> int:
	if is_shooting:
		return AnimState.FIRE
	match move_state:
		0:
			return AnimState.IDLE
		1:
			return AnimState.WALKING
		2:
			return AnimState.RUNNING
		_:
			return AnimState.IDLE


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
		extra = " [anims=%s]" % str(ap.get_animation_list())
	push_warning("%s%s%s (%s)%s" % [prefix, indent, node.name, node.get_class(), extra])
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
