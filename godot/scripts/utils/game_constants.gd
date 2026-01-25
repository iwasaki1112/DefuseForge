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
const NODE_PATH_EXECUTION_MANAGER := "PathExecutionManager"
const NODE_IDLE_MANAGER := "IdleCharacterManager"
const NODE_PATH_DRAWER := "PathDrawer"
const NODE_PATH_MODE_CONTROLLER := "PathModeController"
const NODE_ROTATION_CONTROLLER := "RotationController"
const NODE_VISION_SERVICE := "VisionService"
const NODE_MAP_MANAGER := "MapManager"
const NODE_CONTEXT_MENU := "ContextMenu"
const NODE_MARKER_EDIT_PANEL := "MarkerEditPanel"
const NODE_LABEL_MANAGER := "CharacterLabelManager"
const NODE_PATH_SERVICE := "PathService"
const NODE_WEAPON_SHOP_MODAL := "WeaponShopModal"

# ========================================================
# Group Names
# ========================================================
const GROUP_CHARACTERS := "characters"
const GROUP_DOORS := "doors"

# ========================================================
# Bone Names (Mixamo Standard)
# ========================================================
const BONE_RIGHT_HAND := "mixamorig_RightHand"
const BONE_SPINE_1 := "mixamorig_Spine1"
const BONE_SPINE_2 := "mixamorig_Spine2"

# ========================================================
# Animation Names
# ========================================================
const ANIM_DEATH := "death_forward"  # デフォルト死亡アニメーション
const ANIM_DEATH_FORWARD := "death_forward"  # 前から撃たれて後ろに倒れる
const ANIM_DEATH_BACKWARD := "death_backward"  # 後ろから撃たれて前に倒れる
const ANIM_DEATH_RIGHT := "death_right"  # 右から撃たれて左に倒れる
# Note: death_left は存在しない → フォールバック処理で対応
const ANIM_RIFLE_DOOR_KICK := "rifle_door_kick"
const ANIM_PISTOL_DOOR_KICK := "pistol_door_kick"

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
