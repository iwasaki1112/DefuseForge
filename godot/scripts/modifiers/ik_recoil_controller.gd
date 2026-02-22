extends Node
class_name IKRecoilController

## IK target-based recoil controller
##
## 射撃時にIKターゲット位置にオフセットを加算し、指数減衰で復帰する。
## SkeletonModifier3Dではなく、IKターゲットのMarker3D位置を操作するNode。

# ============================================
# Configuration
# ============================================
## デフォルトのリコイル復帰速度
var recovery_speed := 10.0

# ============================================
# State
# ============================================
var _recoil_offset := Vector3.ZERO

# ============================================
# Public API
# ============================================

## リコイルを発動（上方向にオフセット）
func trigger_recoil(strength: float) -> void:
	# リコイルは上方向（+Y）と後方向（-Z）に適用
	_recoil_offset += Vector3(0.0, strength * 0.5, -strength * 0.3)


## 現在のリコイルオフセットを取得
func get_recoil_offset() -> Vector3:
	return _recoil_offset


## 毎フレーム更新（指数減衰復帰）
func update(delta: float) -> void:
	if _recoil_offset.length_squared() > 0.000001:
		_recoil_offset = _recoil_offset.lerp(Vector3.ZERO, 1.0 - exp(-recovery_speed * delta))
	else:
		_recoil_offset = Vector3.ZERO


## リコイルをリセット
func reset() -> void:
	_recoil_offset = Vector3.ZERO
