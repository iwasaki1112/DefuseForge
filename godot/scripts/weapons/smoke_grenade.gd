class_name SmokeGrenade
extends Grenade
## スモークグレネード
## Grenadeを継承し、爆発時にスモークエリアを生成する

signal smoke_deployed(area: Node3D)

## スモーク設定
@export var smoke_duration: float = GameConstants.SMOKE_DURATION
@export var smoke_radius: float = GameConstants.SMOKE_RADIUS
@export var smoke_expand_time: float = GameConstants.SMOKE_EXPAND_TIME
@export var smoke_fade_time: float = GameConstants.SMOKE_FADE_TIME

## スモークエリアシーン
var _smoke_area_scene: PackedScene = null

## SmokeAreaManagerへの参照（オプション）
var _smoke_manager: SmokeAreaManager = null


func _init() -> void:
	# 爆発ダメージと爆発範囲を無効化（煙のみ）
	explosion_damage = 0.0
	explosion_radius = 0.0


func _ready() -> void:
	super._ready()
	# スモークエリアシーンをロード
	_smoke_area_scene = load(GameConstants.SCENE_SMOKE_AREA)


## SmokeAreaManagerを設定
func set_smoke_manager(manager: SmokeAreaManager) -> void:
	_smoke_manager = manager


## 爆発処理をオーバーライド（スモークエリアを生成）
func _explode() -> void:
	if _has_exploded:
		return
	_has_exploded = true
	_is_active = false

	# スモークエリアを生成
	_deploy_smoke()

	# シグナル発火（親クラスと同じ）
	exploded.emit(global_position)


## スモークエリアを展開
func _deploy_smoke() -> void:
	if not _smoke_area_scene:
		push_warning("[SmokeGrenade] Smoke area scene not loaded")
		return

	var smoke_area: SmokeArea = _smoke_area_scene.instantiate() as SmokeArea
	if not smoke_area:
		push_warning("[SmokeGrenade] Failed to instantiate smoke area")
		return

	# 親ノードに追加（グレネードと同じ親）
	var parent: Node = get_parent()
	if parent:
		parent.add_child(smoke_area)
	else:
		push_warning("[SmokeGrenade] No parent node to add smoke area")
		smoke_area.queue_free()
		return

	# 位置を設定
	smoke_area.global_position = global_position

	# スモーク設定を適用
	smoke_area.max_radius = smoke_radius
	smoke_area.duration = smoke_duration
	smoke_area.expand_time = smoke_expand_time
	smoke_area.fade_time = smoke_fade_time

	# スモークを開始
	smoke_area.start(_smoke_manager)

	# シグナル発火
	smoke_deployed.emit(smoke_area)
