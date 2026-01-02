class_name CharacterModelResource
extends Resource

## キャラクターモデルリソース
## モデルの外観設定を外部ファイルで管理し、動的な切り替えを可能にする

@export_group("基本情報")
@export var model_id: String = ""
@export var display_name: String = ""
@export var team: int = 0  # GameManager.Team

@export_group("モデル")
@export var scene_path: String = ""
@export var model_scale: Vector3 = Vector3(2.0, 2.0, 2.0)

@export_group("テクスチャ")
@export var albedo_texture_path: String = ""
@export var normal_texture_path: String = ""

@export_group("アニメーション")
## カスタムアニメーションパス（省略時はCharacterSetup.ANIMATION_FILESを使用）
@export var custom_animation_paths: Dictionary = {}


## テクスチャ情報を辞書形式で取得
func get_texture_info() -> Dictionary:
	return {
		"albedo": albedo_texture_path,
		"normal": normal_texture_path
	}
