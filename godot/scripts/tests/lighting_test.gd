extends Node3D
## ライティング調整用テストシーン
## キャラクターを1体配置してライトの見え方を確認する

const DEFAULT_LIGHTING_PRESET := "res://data/lighting/default.tres"

@onready var spawn_point: Marker3D = $CharacterSpawnPoint

var _character: Node = null
var _lighting_setup: LightingSetup = null


func _ready() -> void:
	# LightingSetupを使用（GameScreenと同じ方法）
	_setup_lighting()
	_spawn_character()


func _setup_lighting() -> void:
	_lighting_setup = LightingSetup.new()
	_lighting_setup.name = "LightingSetup"
	var preset := load(DEFAULT_LIGHTING_PRESET) as LightingPreset
	if preset:
		_lighting_setup.preset = preset
	add_child(_lighting_setup)
	print("[LightingTest] Using LightingSetup")


func _spawn_character() -> void:
	_character = CharacterRegistry.create_character("dummy_ct", spawn_point.global_position)
	if _character:
		add_child(_character)
		print("Character spawned for lighting test")
	else:
		push_error("Failed to spawn character")
