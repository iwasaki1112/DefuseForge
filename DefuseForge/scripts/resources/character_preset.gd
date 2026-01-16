extends Resource
class_name CharacterPreset
## Character preset definition
## Stores character metadata for team-based selection

const MixamoCharacterScript = preload("res://scripts/characters/mixamo_character.gd")

# ============================================
# Basic Info
# ============================================
@export_group("Basic Info")
@export var id: String = ""  ## Unique identifier (e.g., "bomber", "breacher")
@export var display_name: String = ""  ## Display name for UI
@export var description: String = ""  ## Character description

# ============================================
# Team
# ============================================
@export_group("Team")
@export var team: MixamoCharacterScript.Team = MixamoCharacterScript.Team.NONE

# ============================================
# Model
# ============================================
@export_group("Model")
@export var model_scene: PackedScene  ## Character model scene (.glb imported as scene)

# ============================================
# Stats
# ============================================
@export_group("Stats")
@export var max_health: float = 100.0
@export var walk_speed: float = 2.5
@export var run_speed: float = 5.0

# ============================================
# UI
# ============================================
@export_group("UI")
@export var icon: Texture2D  ## Character icon for selection UI
@export var portrait: Texture2D  ## Character portrait for detail view
