class_name HandGrenade
extends Grenade
## ハンドグレネード（爆発ダメージ付き）
## Grenadeを継承し、着地時に即爆発 + 爆発VFXを生成

## 爆発VFXシーン（GrenadeServiceから注入）
var _explosion_effect_scene: PackedScene = null


func _init() -> void:
	explosion_radius = GameConstants.HAND_GRENADE_EXPLOSION_RADIUS
	explosion_damage = GameConstants.HAND_GRENADE_EXPLOSION_DAMAGE


## 爆発VFXシーンを設定（GrenadeServiceから注入）
func set_explosion_effect_scene(scene: PackedScene) -> void:
	_explosion_effect_scene = scene


## 着地した瞬間に即爆発
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _is_grounded and not _has_exploded:
		_explode()


## 爆発処理をオーバーライド（親のダメージ処理 + 爆発VFX）
func _explode() -> void:
	if _has_exploded:
		return

	# 親クラスの爆発処理（ダメージ + シグナル発火）
	super._explode()

	# 爆発VFXをスポーン
	_spawn_explosion_effect()


## 爆発VFXを生成
func _spawn_explosion_effect() -> void:
	if not _explosion_effect_scene:
		return

	var effect: Node3D = _explosion_effect_scene.instantiate() as Node3D
	if not effect:
		return

	var parent: Node = get_parent()
	if parent:
		parent.add_child(effect)
		effect.global_position = global_position
	else:
		effect.queue_free()
