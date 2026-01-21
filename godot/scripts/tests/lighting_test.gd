extends Node3D
## ライティング調整用テストシーン
## キャラクターを1体配置してライトの見え方を確認する

@onready var spawn_point: Marker3D = $CharacterSpawnPoint

var _character: Node = null


func _ready() -> void:
	_spawn_character()


func _spawn_character() -> void:
	_character = CharacterRegistry.create_character("dummy_ct", spawn_point.global_position)
	if _character:
		add_child(_character)
		print("Character spawned for lighting test")
	else:
		push_error("Failed to spawn character")
