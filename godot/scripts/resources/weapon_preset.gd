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

# ============================================
# Accuracy Curve
# ============================================
@export_group("Accuracy Curve")
@export var accuracy_peak: float = 0.85      ## 最適距離での命中精度
@export var accuracy_close: float = 0.75     ## 至近距離(0m)での命中精度
@export var accuracy_far: float = 0.15       ## 最大距離以降の命中精度
@export var accuracy_range_min: float = 0.0  ## 最適距離帯の開始(m)
@export var accuracy_range_max: float = 15.0 ## 最適距離帯の終了(m)
@export var accuracy_max_distance: float = 40.0 ## 精度最低到達距離(m)

# ============================================
# Movement Penalties
# ============================================
@export_group("Movement Penalties")
@export var shooter_walk_penalty: float = 0.8   ## 歩行時の精度乗数
@export var shooter_sprint_penalty: float = 0.4 ## スプリント時の精度乗数
@export var target_move_penalty: float = 0.15   ## ターゲット移動ペナルティ係数
@export var target_speed_reference: float = 6.0 ## ターゲット速度基準値(m/s)
@export var steady_aim_bonus: float = 1.25      ## 静止時の最大精度ボーナス（Steady Aim）
@export var steady_aim_time: float = 0.5        ## ボーナス最大到達までの時間（秒）
@export var reaction_time: float = 0.3          ## 移動中に敵検知時の初弾リアクションタイム（秒）

# ============================================
# Damage Falloff
# ============================================
@export_group("Damage Falloff")
@export var damage_falloff_enabled: bool = false  ## ダメージ距離減衰の有効化
@export var damage_falloff_start: float = 20.0    ## 減衰開始距離(m)
@export var damage_falloff_min: float = 0.5       ## 最低ダメージ倍率
@export var damage_falloff_end: float = 50.0      ## 最低ダメージ到達距離(m)

# ============================================
# Vision
# ============================================
@export_group("Vision")
@export var vision_range: float = 7.0  ## 武器装備時の視界距離（メートル）
@export var vision_fov: float = 60.0  ## 武器装備時の視界角度（度）

# ============================================
# Recoil
# ============================================
@export_group("Recoil")
@export var recoil_strength: float = 0.15  ## Recoil animation strength
@export var recoil_recovery: float = 10.0  ## Recoil recovery speed

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
# IK Settings
# ============================================
@export_group("IK Settings")
@export var left_hand_grip_enabled: bool = false  ## 左手IKグリップを有効化（ライフル等の両手持ち武器用）
@export var left_hand_grip_offset: Vector3 = Vector3.ZERO  ## フォールバック用：LeftHandGripノードがない場合のオフセット
@export var right_hand_ik_offset: Vector3 = Vector3.ZERO  ## 右手IKオフセット（デフォルトREADYポーズからの相対）

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
