extends SkeletonModifier3D
## SkeletonModifier3Dパイプライン内で左手IKターゲット位置を更新
## 右手ボーンの現在ポーズ + キャプチャ済みオフセットからグリップ位置を算出し、
## 手首オフセットを適用してIKターゲットを手首位置に補正する。
##
## TwoBoneIK3DはLeftHandボーン原点（=手首）をターゲットに配置するため、
## グリップ位置そのままだと手首がグリップに来てしまう。
## 手首オフセットを適用することで、手のひらがグリップに来るようにする。
##
## 手首オフセットはアニメーションが安定した後にpipeline内でキャプチャする。
## pipeline内ではIK適用前のアニメーションポーズが取得できるため、
## ベイク済みIKアニメーションの手首位置を正確に読み取れる。

var _target: Marker3D  ## 左手IKターゲットMarker3D
var _grip_in_bone_space: Transform3D  ## 右手ボーンからグリップへのオフセット
var _wrist_in_grip_space: Vector3 = Vector3.ZERO  ## グリップ空間での手首オフセット
var _grip_offset: Vector3 = Vector3.ZERO  ## 追加のグリップオフセット（武器ローカル空間）
var _bone_idx := -1  ## 右手ボーンインデックス
var _left_hand_bone_idx := -1  ## 左手ボーンインデックス（手首オフセットキャプチャ用）
var _is_captured := false  ## 右手→グリップオフセットキャプチャ済み
var _wrist_capture_countdown := -1  ## 手首オフセットキャプチャ待機カウント（-1=待機なし）
var _wrist_captured := false  ## 手首オフセットキャプチャ済み


func _process_modification() -> void:
	if not _is_captured or not _target or _bone_idx < 0:
		return
	var skel := get_skeleton()
	if not skel:
		return

	var bone_world := skel.global_transform * skel.get_bone_global_pose(_bone_idx)
	var grip_transform := bone_world * _grip_in_bone_space

	# 手首オフセットの遅延キャプチャ（アニメーション安定後）
	# pipeline内なのでIK適用前のアニメーションポーズが取得可能
	if _wrist_capture_countdown > 0:
		_wrist_capture_countdown -= 1
	elif _wrist_capture_countdown == 0 and not _wrist_captured and _left_hand_bone_idx >= 0:
		_wrist_capture_countdown = -1
		var left_hand_anim := skel.global_transform * skel.get_bone_global_pose(_left_hand_bone_idx)
		_wrist_in_grip_space = grip_transform.basis.inverse() * (left_hand_anim.origin - grip_transform.origin)
		_wrist_captured = true

	# グリップ位置からIKターゲット位置を計算
	var target_pos := grip_transform.origin
	if _grip_offset.length_squared() > 0.0001:
		target_pos += grip_transform.basis * _grip_offset
	if _wrist_captured and _wrist_in_grip_space.length_squared() > 0.0001:
		target_pos += grip_transform.basis * _wrist_in_grip_space

	_target.global_position = target_pos
