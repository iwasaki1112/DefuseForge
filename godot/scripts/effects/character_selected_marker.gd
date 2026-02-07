class_name CharacterSelectedMarker
extends Sprite3D

## キャラクター選択マーカー
## 選択中のキャラクターの足元に表示され、360度回転ループする

@export var rotation_speed: float = 90.0  ## 回転速度（度/秒）
@export var height_offset: float = 0.05  ## 地面からの高さ
@export var marker_scale: float = 1.0  ## マーカーのスケール

var _target_character: Node = null


func _ready() -> void:
	_setup_sprite()
	_update_position()


func _setup_sprite() -> void:
	# スプライトの設定
	billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# 地面に平行に配置（X軸を-90度回転）
	rotation_degrees.x = -90

	# テクスチャを読み込み
	var texture_path: String = "res://assets/ui/character_selected_marker/character_selected_marker.png"
	var tex: Texture2D = load(texture_path) as Texture2D
	if tex:
		texture = tex
	else:
		push_warning("CharacterSelectedMarker: テクスチャが見つかりません: %s" % texture_path)

	# アルファ対応
	transparent = true
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED

	# レンダリング設定
	render_priority = 5

	# スケール設定
	pixel_size = 0.005 * marker_scale


func _process(delta: float) -> void:
	# Z軸周りで回転（地面に平行な状態での回転）
	rotation_degrees.z += rotation_speed * delta

	# 360度超えたらリセット
	if rotation_degrees.z >= 360.0:
		rotation_degrees.z -= 360.0

	# ターゲットキャラクターの位置を追従
	_update_position()


func _update_position() -> void:
	if _target_character and is_instance_valid(_target_character):
		var char_pos: Vector3 = _target_character.global_position
		# キャラクターの足元の高さ + オフセット
		global_position = Vector3(char_pos.x, char_pos.y + height_offset, char_pos.z)


## キャラクターにマーカーをアタッチ
func attach_to_character(character: Node) -> void:
	_target_character = character
	if is_inside_tree():
		_update_position()


## マーカーを表示
func show_marker() -> void:
	visible = true


## マーカーを非表示
func hide_marker() -> void:
	visible = false
