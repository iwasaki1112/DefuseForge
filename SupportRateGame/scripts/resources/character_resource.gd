class_name CharacterResource
extends Resource

## キャラクターデータリソース
## キャラクターごとの設定を外部ファイルで管理
##
## 新キャラクター追加時の手順:
## 1. GLBモデルを assets/characters/{character_name}/ に配置
## 2. この .tres ファイルを同じディレクトリに作成
## 3. 各パラメータを設定（特にweapon_offset）

@export_group("基本情報")
@export var character_id: String = ""  ## キャラクターの一意識別子（例: "counter_terrorist"）
@export var character_name: String = ""  ## 表示名（例: "Counter Terrorist"）
@export var model_path: String = ""  ## GLBモデルパス

@export_group("武器装着位置調整")
@export var weapon_position_offset: Vector3 = Vector3.ZERO  ## 武器の位置オフセット
@export var weapon_rotation_offset: Vector3 = Vector3.ZERO  ## 武器の回転オフセット（度数）

@export_group("ステータス")
@export var base_health: float = 100.0  ## 基本HP
@export var base_walk_speed: float = 3.0  ## 歩行速度
@export var base_run_speed: float = 6.0  ## 走行速度


## 辞書形式に変換
func to_dict() -> Dictionary:
	return {
		"id": character_id,
		"name": character_name,
		"model_path": model_path,
		"weapon_position_offset": weapon_position_offset,
		"weapon_rotation_offset": weapon_rotation_offset,
		"base_health": base_health,
		"base_walk_speed": base_walk_speed,
		"base_run_speed": base_run_speed
	}


## 辞書からResourceを作成
static func from_dict(data: Dictionary) -> CharacterResource:
	var res = CharacterResource.new()
	res.character_id = data.get("id", "")
	res.character_name = data.get("name", "")
	res.model_path = data.get("model_path", "")
	res.weapon_position_offset = data.get("weapon_position_offset", Vector3.ZERO)
	res.weapon_rotation_offset = data.get("weapon_rotation_offset", Vector3.ZERO)
	res.base_health = data.get("base_health", 100.0)
	res.base_walk_speed = data.get("base_walk_speed", 3.0)
	res.base_run_speed = data.get("base_run_speed", 6.0)
	return res
