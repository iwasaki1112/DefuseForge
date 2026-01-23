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

# ========================================================
# Bone Names (Mixamo Standard)
# ========================================================
const BONE_RIGHT_HAND := "mixamorig_RightHand"
const BONE_SPINE_1 := "mixamorig_Spine1"
const BONE_SPINE_2 := "mixamorig_Spine2"

# ========================================================
# Animation Names
# ========================================================
const ANIM_DEATH := "death"
const ANIM_RIFLE_DOOR_KICK := "rifle_door_kick"
const ANIM_PISTOL_DOOR_KICK := "pistol_door_kick"

# ========================================================
# Scene Paths (Use with load/preload if class_name not available)
# ========================================================
const PRESET_ENVIRONMENT_DEFAULT := "res://data/environment/default.tres"
