class_name GameConstants
## ゲーム全体で使用される定数定義
##
## ノード名、グループ名、ボーン名、アニメーション名、ファイルパスなどの
## 共有定数を一元管理する静的クラス。
## 文字列リテラルをコード内に散在させないために使用する。

# ========================================================
# Node Names
# ========================================================
const NODE_CHARACTER_MODEL := "CharacterModel"
const NODE_WEAPON_ATTACHMENT := "WeaponAttachment"
const NODE_WEAPON_SOCKET := "WeaponSocket"
const NODE_WEAPON_MODEL := "WeaponModel"
const NODE_ANIMATION_TREE := "AnimationTree"
const NODE_VISION_COMPONENT := "VisionComponent"
const NODE_COMBAT_AWARENESS := "CombatAwarenessComponent"
const NODE_SELECTION_MANAGER := "SelectionManager"
const NODE_IDLE_MANAGER := "IdleCharacterManager"
const NODE_VISION_SERVICE := "VisionService"
const NODE_MAP_MANAGER := "MapManager"
const NODE_LABEL_MANAGER := "CharacterLabelManager"

# ========================================================
# Group Names
# ========================================================
const GROUP_CHARACTERS := "characters"
const GROUP_DOORS := "doors"

# ========================================================
# Bone Names (ARP / Unity Humanoid)
# ========================================================
const BONE_RIGHT_HAND := "RightHand"
const BONE_SPINE := "Spine"
const BONE_UPPER_CHEST := "UpperChest"
const BONE_LEFT_ARM := "LeftUpperArm"
const BONE_LEFT_FOREARM := "LeftLowerArm"
const BONE_LEFT_HAND := "LeftHand"
# 後方互換エイリアス
const BONE_SPINE_1 := BONE_SPINE
const BONE_SPINE_2 := BONE_UPPER_CHEST

# ========================================================
# Node Names (Left Hand IK)
# ========================================================
const NODE_LEFT_HAND_GRIP := "LeftHandGrip"
const NODE_LEFT_HAND_IK_TARGET := "LeftHandIKTarget"

# ========================================================
# Animation Names
# ========================================================
const ANIM_DEATH := "Rifle_Death_3"
const ANIM_DEATH_FORWARD := "Rifle_Death_3"
const ANIM_DEATH_BACKWARD := "Rifle_Death_3"
const ANIM_DEATH_LEFT := "Rifle_Death_L"
const ANIM_DEATH_RIGHT := "Rifle_Death_R"
const ANIM_RIFLE_DOOR_KICK := "Rifle_Melee_Kick"
const ANIM_PISTOL_DOOR_KICK := "Pistol_Melee_Kick"
const ANIM_PISTOL_LOW_THROWING := "Pistol_Grenade_Throw_Single"
const ANIM_PISTOL_GRENADE_THROW_CLOSE := "Pistol_Grenade_Throw_Close"
const ANIM_RIFLE_GRENADE_THROW_FAR := "Rifle_Grenade_Throw_Far"
const ANIM_RIFLE_GRENADE_THROW_CLOSE := "Rifle_Grenade_Throw_Close"
const ANIM_RIFLE_OPEN_DOOR := "Rifle_OpenDoor"

# ========================================================
# Grenade Settings
# ========================================================
const GRENADE_FUSE_TIME := 3.0  # 導火線時間（秒）
const GRENADE_EXPLOSION_RADIUS := 5.0  # 爆発範囲
const GRENADE_EXPLOSION_DAMAGE := 100.0  # 最大ダメージ
const GRENADE_ARC_HEIGHT := 2.0  # 放物線高さ
const GRENADE_BOUNCE := 0.5  # 跳ね返り係数
const GRENADE_FRICTION := 0.3  # 摩擦係数
const GRENADE_MASS := 0.4  # 質量

# ========================================================
# Smoke Grenade Settings
# ========================================================
const SMOKE_DURATION := 10.0  # スモーク持続時間（秒）
const SMOKE_RADIUS := 5.0  # スモーク半径（メートル）
const SMOKE_EXPAND_TIME := 1.5  # 展開時間（秒）
const SMOKE_FADE_TIME := 2.5  # 消滅時間（秒）
const SMOKE_FUSE_TIME := 3.0  # 導火線時間（秒）

# ========================================================
# Grenade Throw Settings
# ========================================================
const GRENADE_THROW_MAX_DISTANCE := 6.5    # 最大投擲距離（メートル）
const GRENADE_THROW_CLOSE_THRESHOLD := 4.0 # 近投/遠投の閾値（メートル）
const GRENADE_START_HEIGHT := 1.5          # 発射高さ（手の位置近似）
const SMOKE_GRENADE_PER_ROUND := 99        # ラウンドあたりのスモーク数（デバッグ用、本番は1）

# ========================================================
# Scene Paths (Use with load/preload if class_name not available)
# ========================================================
const PRESET_ENVIRONMENT_DEFAULT := "res://data/environment/default.tres"
const SCENE_GRENADE := "res://scenes/weapons/grenade.tscn"
const SCENE_SMOKE_GRENADE := "res://scenes/weapons/smoke_grenade.tscn"
const SCENE_SMOKE_AREA := "res://scenes/effects/smoke_area.tscn"

# ========================================================
# Round Settings
# ========================================================
const ROUND_TIME_LIMIT: float = 90.0      # ラウンド制限時間（秒）
const ROUND_END_DELAY: float = 3.0        # ラウンド終了後の遅延（秒）

# ========================================================
# Node Names (Round System)
# ========================================================
const NODE_ROUND_MANAGER := "RoundManager"
const NODE_ROUND_HUD := "RoundHUD"

# ========================================================
# UI Colors
# ========================================================
## チームカラー
const CT_COLOR := Color(0.4, 0.6, 1.0)   # CT（青）
const T_COLOR := Color(1.0, 0.6, 0.3)    # T（オレンジ）
## ショップUI
const AFFORDABLE_COLOR := Color(0.2, 0.6, 0.2)  # 購入可能時
const SELECTED_COLOR := Color(0.3, 0.5, 0.7)    # 選択時
