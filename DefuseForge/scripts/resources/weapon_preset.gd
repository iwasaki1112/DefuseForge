extends Resource
class_name WeaponPreset
## Weapon preset definition
## Stores weapon stats for combat system

# ============================================
# Weapon Category
# ============================================
enum WeaponCategory { RIFLE, PISTOL, SMG, SHOTGUN, SNIPER }

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

# ============================================
# Recoil
# ============================================
@export_group("Recoil")
@export var recoil_strength: float = 0.08  ## Recoil animation strength
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
