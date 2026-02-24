extends Node
class_name SpineIKController

## 上半身ヨー回転コントローラー
##
## SpinePostureModifierを介して背骨チェーン（Hips〜UpperChest）にヨー回転を適用する。
## set_yaw() で目標角度を設定し、update() で毎フレーム SpinePostureModifier に反映。

# ============================================
# Constants
# ============================================
const SMOOTHING_SPEED := 10.0

# ============================================
# References
# ============================================
var _spine_posture: SpinePostureModifier

# ============================================
# State
# ============================================
var _target_yaw := 0.0
var _current_yaw := 0.0
var _is_setup := false
var _enabled := false

# ============================================
# Setup
# ============================================

## Skeleton3Dの子にあるSpinePostureModifierを検索して接続
func setup(skeleton: Skeleton3D) -> void:
	if not skeleton:
		push_warning("[SpineIK] Skeleton is null")
		return

	for child in skeleton.get_children():
		if child is SpinePostureModifier:
			_spine_posture = child
			break

	if not _spine_posture:
		push_warning("[SpineIK] SpinePostureModifier not found in skeleton children")
		return

	_is_setup = true


# ============================================
# Public API
# ============================================

## ヨー角度を設定（rad）
func set_yaw(yaw: float) -> void:
	_target_yaw = yaw


## 有効/無効を切替
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		_target_yaw = 0.0
		_current_yaw = 0.0
		if _spine_posture:
			_spine_posture.set_yaw(0.0)


## 毎フレーム更新（CharacterAnimationControllerから呼ばれる）
func update(delta: float) -> void:
	if not _is_setup or not _enabled:
		return

	if _spine_posture:
		_spine_posture.set_yaw(_target_yaw)

	# UI表示用にスムーズ追従
	var alpha := 1.0 - exp(-SMOOTHING_SPEED * delta)
	_current_yaw = lerpf(_current_yaw, _target_yaw, alpha)


## セットアップ済みかどうか
func is_setup() -> bool:
	return _is_setup


## 有効状態を取得
func is_enabled() -> bool:
	return _enabled


## 現在のヨー角度を取得（UI表示用、スムージング済み）
func get_current_yaw() -> float:
	return _current_yaw


# ============================================
# Cleanup
# ============================================

func _exit_tree() -> void:
	if _spine_posture and _enabled:
		_spine_posture.set_yaw(0.0)
	_spine_posture = null
