extends Resource
class_name MapPreset
## Map preset definition
## Stores map metadata, scene reference, and spawn points

# ============================================
# Basic Info
# ============================================
@export_group("Basic Info")
@export var id: String = ""  ## Unique identifier (e.g., "test_map", "warehouse")
@export var display_name: String = ""  ## Display name for UI
@export var description: String = ""  ## Map description

# ============================================
# Scene
# ============================================
@export_group("Scene")
@export var map_scene: PackedScene  ## Map scene (.tscn)

# ============================================
# Map Settings
# ============================================
@export_group("Map Settings")
@export var map_size: Vector2 = Vector2(50, 50)  ## Map size for FogOfWar system

# ============================================
# Spawn Points
# ============================================
@export_group("Spawn Points")
@export var spawn_points_ct: Array[Vector3] = []  ## Counter-Terrorist spawn positions
@export var spawn_points_t: Array[Vector3] = []  ## Terrorist spawn positions
@export var spawn_rotations_ct: Array[float] = []  ## Counter-Terrorist spawn Y rotations (radians)
@export var spawn_rotations_t: Array[float] = []  ## Terrorist spawn Y rotations (radians)
@export var spawn_points_hostage: Array[Vector3] = []  ## Hostage spawn positions
@export var spawn_rotations_hostage: Array[float] = []  ## Hostage spawn Y rotations (radians)

# ============================================
# UI
# ============================================
@export_group("UI")
@export var thumbnail: Texture2D  ## Map thumbnail for selection UI
