class_name WeaponResource
extends Resource

## 武器データリソース
## 武器のステータスを外部ファイルで管理し、ランタイムで調整可能にする

@export_group("基本情報")
@export var weapon_id: int = 0
@export var weapon_name: String = ""
@export var weapon_type: int = 0  # CharacterSetup.WeaponType

@export_group("コスト")
@export var price: int = 0
@export var kill_reward: int = 300

@export_group("戦闘性能")
@export var damage: float = 0.0
@export var fire_rate: float = 0.0  # 発射間隔（秒）
@export var accuracy: float = 0.0  # 基本命中率 (0.0-1.0)
@export var effective_range: float = 0.0  # 有効射程距離

@export_group("ダメージ倍率")
@export var headshot_multiplier: float = 4.0
@export var bodyshot_multiplier: float = 1.0

@export_group("リソース")
@export var scene_path: String = ""


## 辞書形式に変換（後方互換性用）
func to_dict() -> Dictionary:
	return {
		"name": weapon_name,
		"type": weapon_type,
		"price": price,
		"damage": damage,
		"fire_rate": fire_rate,
		"accuracy": accuracy,
		"range": effective_range,
		"headshot_multiplier": headshot_multiplier,
		"bodyshot_multiplier": bodyshot_multiplier,
		"scene_path": scene_path,
		"kill_reward": kill_reward
	}


## 辞書からResourceを作成
static func from_dict(data: Dictionary, id: int) -> WeaponResource:
	var res = WeaponResource.new()
	res.weapon_id = id
	res.weapon_name = data.get("name", "")
	res.weapon_type = data.get("type", 0)
	res.price = data.get("price", 0)
	res.damage = data.get("damage", 0.0)
	res.fire_rate = data.get("fire_rate", 0.0)
	res.accuracy = data.get("accuracy", 0.0)
	res.effective_range = data.get("range", 0.0)
	res.headshot_multiplier = data.get("headshot_multiplier", 4.0)
	res.bodyshot_multiplier = data.get("bodyshot_multiplier", 1.0)
	res.scene_path = data.get("scene_path", "")
	res.kill_reward = data.get("kill_reward", 300)
	return res
