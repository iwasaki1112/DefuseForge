class_name ExplosionEffect
extends Node3D
## 爆発VFXエフェクト
## GPUParticles3Dのone-shot再生とOmniLight3Dの閃光を管理
## パーティクル完了後に自動削除

## エフェクトの総寿命（秒）
@export var lifetime: float = 2.0

## 閃光設定
@export var flash_energy: float = 4.0
@export var flash_range: float = 6.0
@export var flash_fade_time: float = 0.3

var _light: OmniLight3D = null
var _particles: GPUParticles3D = null


func _ready() -> void:
	_particles = $Particles as GPUParticles3D
	_light = $FlashLight as OmniLight3D

	# パーティクル開始
	if _particles:
		_particles.emitting = true

	# 閃光Tween（一瞬明るくして減衰）
	if _light:
		_light.light_energy = flash_energy
		_light.omni_range = flash_range
		var tween := create_tween()
		tween.tween_property(_light, "light_energy", 0.0, flash_fade_time)

	# 自動削除タイマー
	var timer := get_tree().create_timer(lifetime)
	timer.timeout.connect(queue_free)
