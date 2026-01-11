class_name WeaponResource
extends Resource

## 武器データリソース
## 武器のステータスを外部ファイルで管理し、ランタイムで調整可能にする
##
## 新武器追加時の手順:
## 1. GLBモデルを resources/weapons/{weapon_name}/ に配置
## 2. scenes/weapons/{weapon_name}.tscn を作成（MuzzlePoint, LeftHandGrip含む）
## 3. この .tres ファイルを作成し、各パラメータを設定
## 4. WeaponDatabase に登録

@export_group("基本情報")
@export var weapon_id: String = ""  ## 武器の一意識別子（例: "ak47", "m4a1"）
@export var weapon_name: String = ""  ## 表示名（例: "AK-47"）
@export var weapon_type: int = 0  ## 武器タイプ: 0=NONE, 1=RIFLE, 2=PISTOL

@export_group("コスト")
@export var price: int = 0  ## 購入価格
@export var kill_reward: int = 300  ## キル報酬

@export_group("戦闘性能")
@export var damage: float = 0.0  ## 基本ダメージ
@export var fire_rate: float = 0.0  ## 発射間隔（秒）
@export var accuracy: float = 0.0  ## 基本命中率 (0.0-1.0)
@export var effective_range: float = 0.0  ## 有効射程距離

@export_group("ダメージ倍率")
@export var headshot_multiplier: float = 4.0  ## ヘッドショット倍率
@export var bodyshot_multiplier: float = 1.0  ## ボディショット倍率

@export_group("弾薬")
@export var magazine_size: int = 30  ## マガジン容量
@export var reload_time: float = 2.5  ## リロード時間（秒）

@export_group("リソース")
@export var scene_path: String = ""  ## 武器シーンパス（例: "res://scenes/weapons/ak47.tscn"）

@export_group("装着位置（BoneAttachment内での位置・回転）")
@export var attach_position: Vector3 = Vector3.ZERO  ## 右手ボーンからの相対位置
@export var attach_rotation: Vector3 = Vector3.ZERO  ## 右手ボーンからの相対回転（度数）

@export_group("アニメーション設定")
## アニメーション状態ごとの位置・回転オフセット
## 構造: { AnimState(int): { "position": Vector3, "rotation": Vector3 (degrees) } }
## AnimState: 0=IDLE, 1=WALKING, 2=RUNNING, 3=FIRE
@export var animation_offsets: Dictionary = {}


## リソースのバリデーション
## @return: { "valid": bool, "errors": Array[String] }
func validate() -> Dictionary:
	var errors: Array[String] = []

	# 必須フィールドのチェック
	if weapon_id.is_empty():
		errors.append("weapon_id is empty")

	if weapon_name.is_empty():
		errors.append("weapon_name is empty")

	# シーンパスのチェック
	if scene_path.is_empty():
		errors.append("scene_path is empty")
	elif not ResourceLoader.exists(scene_path):
		errors.append("scene_path does not exist: %s" % scene_path)

	# 武器タイプのチェック
	if weapon_type < TYPE_NONE or weapon_type > TYPE_PISTOL:
		errors.append("Invalid weapon_type: %d" % weapon_type)

	# 戦闘性能の妥当性チェック
	if damage < 0:
		errors.append("damage cannot be negative: %f" % damage)
	if fire_rate < 0:
		errors.append("fire_rate cannot be negative: %f" % fire_rate)
	if accuracy < 0.0 or accuracy > 1.0:
		errors.append("accuracy must be between 0.0 and 1.0: %f" % accuracy)

	return {
		"valid": errors.is_empty(),
		"errors": errors
	}


## 辞書形式に変換（後方互換性用）
func to_dict() -> Dictionary:
	return {
		"id": weapon_id,
		"name": weapon_name,
		"type": weapon_type,
		"price": price,
		"damage": damage,
		"fire_rate": fire_rate,
		"accuracy": accuracy,
		"range": effective_range,
		"headshot_multiplier": headshot_multiplier,
		"bodyshot_multiplier": bodyshot_multiplier,
		"magazine_size": magazine_size,
		"reload_time": reload_time,
		"scene_path": scene_path,
		"kill_reward": kill_reward,
		"attach_position": attach_position,
		"attach_rotation": attach_rotation,
		"animation_offsets": animation_offsets
	}


## 辞書からResourceを作成（後方互換性用）
static func from_dict(data: Dictionary, id: String = "") -> WeaponResource:
	var res = WeaponResource.new()
	res.weapon_id = id if not id.is_empty() else data.get("id", "")
	res.weapon_name = data.get("name", "")
	res.weapon_type = data.get("type", 0)
	res.price = data.get("price", 0)
	res.damage = data.get("damage", 0.0)
	res.fire_rate = data.get("fire_rate", 0.0)
	res.accuracy = data.get("accuracy", 0.0)
	res.effective_range = data.get("range", 0.0)
	res.headshot_multiplier = data.get("headshot_multiplier", 4.0)
	res.bodyshot_multiplier = data.get("bodyshot_multiplier", 1.0)
	res.magazine_size = data.get("magazine_size", 30)
	res.reload_time = data.get("reload_time", 2.5)
	res.scene_path = data.get("scene_path", "")
	res.kill_reward = data.get("kill_reward", 300)
	res.attach_position = data.get("attach_position", Vector3.ZERO)
	res.attach_rotation = data.get("attach_rotation", Vector3.ZERO)
	res.animation_offsets = data.get("animation_offsets", {})
	return res


## 武器タイプ定数（CharacterSetup.WeaponTypeと同じ値）
const TYPE_NONE: int = 0
const TYPE_RIFLE: int = 1
const TYPE_PISTOL: int = 2
