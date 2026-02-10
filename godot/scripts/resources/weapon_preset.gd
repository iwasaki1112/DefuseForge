extends Resource
class_name WeaponPreset
## Weapon preset definition
## Stores weapon stats for combat system

# ============================================
# Enums
# ============================================
enum WeaponCategory { RIFLE, PISTOL, SMG, SHOTGUN, SNIPER }
enum FiringMode { SINGLE, BURST, FULL_AUTO }

# ============================================
# Basic Info
# ============================================
@export_group("Basic Info")
@export var id: String = ""  ## Unique identifier (e.g., "m4a1", "glock")
@export var display_name: String = ""  ## Display name for UI
@export var category: WeaponCategory = WeaponCategory.RIFLE

# ============================================
# Combat Stats
# ============================================
@export_group("Combat Stats")
@export var damage: float = 30.0  ## Damage per hit
@export var fire_rate: float = 0.1  ## Fire interval in seconds
@export var accuracy: float = 0.9  ## Accuracy (0.0 - 1.0)
@export var spread: float = 0.1  ## Spread (0.0 - 1.0, lower is tighter grouping)
@export var effective_range: float = 20.0  ## Effective range in meters

# ============================================
# Recoil
# ============================================
@export_group("Recoil")
@export var recoil_strength: float = 0.15  ## Recoil animation strength
@export var recoil_recovery: float = 10.0  ## Recoil recovery speed

# ============================================
# Economy
# ============================================
@export_group("Economy")
@export var price: int = 0  ## Purchase price

# ============================================
# Visual
# ============================================
@export_group("Visual")
@export var model_scene: PackedScene  ## Weapon model (optional)
@export var icon: Texture2D  ## Weapon icon for UI

# ============================================
# Attachment
# ============================================
@export_group("Attachment")
@export var attach_offset: Vector3 = Vector3.ZERO  ## Position offset when attached to hand
@export var attach_rotation: Vector3 = Vector3.ZERO  ## Rotation offset in degrees when attached to hand

# ============================================
# Muzzle Flash
# ============================================
@export_group("Muzzle Flash")
@export var muzzle_flash_offset: Vector3 = Vector3.ZERO  ## Local offset from WeaponSocket
@export var muzzle_flash_scale: float = 1.0  ## Muzzle flash scale multiplier
@export var muzzle_flash_rotation: Vector3 = Vector3.ZERO  ## Muzzle flash rotation in degrees

# ============================================
# Left Hand Grip (IK)
# ============================================
@export_group("Left Hand Grip")
@export var left_hand_grip_enabled: bool = false  ## 左手IKグリップを有効化（ライフル等の両手持ち武器用）
@export var left_hand_grip_offset: Vector3 = Vector3.ZERO  ## フォールバック用：LeftHandGripノードがない場合のオフセット

# ============================================
# Auto Firing Mode (RIFLE/SMG only)
# ============================================
@export_group("Auto Firing Mode")
@export var auto_firing_mode_enabled: bool = false  ## Enable distance-based firing mode switching

# CQB Range (0-5m default)
@export_subgroup("CQB Range")
@export var cqb_max_distance: float = 5.0  ## Max distance for CQB range (meters)
@export var cqb_firing_mode: FiringMode = FiringMode.FULL_AUTO  ## Firing mode for CQB range
@export var cqb_shots_per_burst: int = 0  ## Shots per burst (0 = continuous for FULL_AUTO)
@export var cqb_burst_interval: float = 0.08  ## Interval between shots in burst (seconds)
@export var cqb_pause_after_burst: float = 0.0  ## Pause after burst completion (seconds)
@export var cqb_accuracy_modifier: float = 0.85  ## Accuracy multiplier for CQB range
@export var cqb_critical_rate: float = 0.1  ## Critical hit chance (0.0-1.0)

# Medium Range (5-15m default)
@export_subgroup("Medium Range")
@export var medium_max_distance: float = 15.0  ## Max distance for medium range (meters)
@export var medium_firing_mode: FiringMode = FiringMode.BURST  ## Firing mode for medium range
@export var medium_shots_per_burst: int = 3  ## Shots per burst
@export var medium_burst_interval: float = 0.10  ## Interval between shots in burst (seconds)
@export var medium_pause_after_burst: float = 0.40  ## Pause after burst completion (seconds)
@export var medium_accuracy_modifier: float = 1.0  ## Accuracy multiplier for medium range
@export var medium_critical_rate: float = 0.25  ## Critical hit chance (0.0-1.0)

# Long Range (15m+ default)
@export_subgroup("Long Range")
@export var long_firing_mode: FiringMode = FiringMode.SINGLE  ## Firing mode for long range
@export var long_shots_per_burst: int = 1  ## Shots per burst (1 for single)
@export var long_burst_interval: float = 0.0  ## Not used for SINGLE
@export var long_pause_after_burst: float = 0.60  ## Pause after shot (seconds)
@export var long_accuracy_modifier: float = 1.15  ## Accuracy multiplier for long range
@export var long_critical_rate: float = 0.5  ## Critical hit chance (0.0-1.0)
