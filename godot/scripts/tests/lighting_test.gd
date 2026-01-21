extends Node3D
## ライティング調整用テストシーン
## キャラクターを1体配置してライトの見え方を確認する

const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"

@onready var spawn_point: Marker3D = $CharacterSpawnPoint

var _character: Node = null
var _environment_setup: EnvironmentSetup = null


func _ready() -> void:
	# EnvironmentSetupを使用（GameScreenと同じ方法）
	_setup_environment()
	_spawn_character()


func _setup_environment() -> void:
	_environment_setup = EnvironmentSetup.new()
	_environment_setup.name = "EnvironmentSetup"
	var preset := load(DEFAULT_ENVIRONMENT_PRESET) as EnvironmentPreset
	if preset:
		_environment_setup.preset = preset
	add_child(_environment_setup)
	print("[LightingTest] Using EnvironmentSetup")


func _spawn_character() -> void:
	_character = CharacterRegistry.create_character("dummy_ct", spawn_point.global_position)
	if _character:
		add_child(_character)
		print("Character spawned for lighting test")
	else:
		push_error("Failed to spawn character")
