class_name CharacterLabelManager
extends Node
## キャラクターラベル管理コンポーネント
## 味方キャラクターの頭上にA, B, C...のラベルを表示する
##
## 使用例:
##   var label_manager = CharacterLabelManager.new()
##   add_child(label_manager)
##   label_manager.add_label(character)
##   label_manager.refresh_labels(characters_array)

# ============================================
# Export Settings
# ============================================
@export_group("Label Appearance")
@export var background_color: Color = Color(0.1, 0.1, 0.1, 0.9)  ## 背景円の色
@export var text_color: Color = Color(1.0, 1.0, 1.0, 1.0)  ## 文字の色
@export var height_offset: float = 2.0  ## 頭上からの高さ

@export_group("Label Size")
@export var background_font_size: int = 128  ## 背景円のサイズ
@export var text_font_size: int = 64  ## 文字のサイズ
@export var pixel_size: float = 0.006  ## ピクセルサイズ

# ============================================
# State
# ============================================
var _labels: Dictionary = {}  ## character_id -> Node3D (label container)
var _label_index: int = 0  ## 次のラベル用インデックス（A=0, B=1...）
var _tracked_characters: Array[Node] = []  ## 追跡中のキャラクター

# ============================================
# Public API
# ============================================

## キャラクターにラベルを追加（味方のみ）
## @param character: ラベルを追加するキャラクター
## @return: ラベルが追加されたかどうか
func add_label(character: Node) -> bool:
	if not character:
		return false

	# 敵キャラクターにはラベルを付けない
	if PlayerState.is_enemy(character):
		return false

	var char_id = character.get_instance_id()

	# 既にラベルがある場合はスキップ
	if _labels.has(char_id):
		return false

	# ラベルを作成
	var label_char = _get_next_label_char()
	var container = _create_label_container(label_char)

	# キャラクターの子として追加
	character.add_child(container)
	container.position = Vector3(0, height_offset, 0)

	_labels[char_id] = container
	return true


## キャラクターからラベルを削除
## @param character: ラベルを削除するキャラクター
func remove_label(character: Node) -> void:
	if not character:
		return

	var char_id = character.get_instance_id()
	if not _labels.has(char_id):
		return

	var label = _labels[char_id]
	if is_instance_valid(label):
		label.queue_free()
	_labels.erase(char_id)


## 全ラベルをクリア
func clear_all() -> void:
	for char_id in _labels.keys():
		var label = _labels[char_id]
		if is_instance_valid(label):
			label.queue_free()
	_labels.clear()
	_label_index = 0


## キャラクターリストに基づいてラベルを更新（チーム変更時など）
## @param characters: シーン内の全キャラクター
func refresh_labels(characters: Array) -> void:
	# ラベルインデックスをリセット
	_label_index = 0

	# 既存のラベルを全て削除
	clear_all()

	# 味方キャラクターにのみラベルを追加
	for character in characters:
		add_label(character)


## 特定のキャラクターがラベルを持っているか
func has_label(character: Node) -> bool:
	if not character:
		return false
	return _labels.has(character.get_instance_id())


## ラベル数を取得
func get_label_count() -> int:
	return _labels.size()


## キャラクターのラベル色を設定
## @param character: 対象キャラクター
## @param color: 背景色
func set_label_color(character: Node, color: Color) -> void:
	if not character:
		return

	var char_id = character.get_instance_id()
	if not _labels.has(char_id):
		return

	var container = _labels[char_id]
	if not is_instance_valid(container):
		return

	# 背景（●）の色を変更
	var bg_label = container.get_node_or_null("Background")
	if bg_label and bg_label is Label3D:
		bg_label.modulate = Color(color.r, color.g, color.b, 0.9)


## ラベルテキストを更新（CharacterColorManagerと連携用）
## @param character: 対象キャラクター
## @param label_char: 新しいラベル文字
func set_label_text(character: Node, label_char: String) -> void:
	if not character:
		return

	var char_id = character.get_instance_id()
	if not _labels.has(char_id):
		return

	var container = _labels[char_id]
	if not is_instance_valid(container):
		return

	# テキストラベルを更新
	var text_label = container.get_node_or_null("Text")
	if text_label and text_label is Label3D:
		text_label.text = label_char
		container.name = "CharacterLabel_%s" % label_char


# ============================================
# Internal Methods
# ============================================

## 次のラベル文字を取得（A, B, C...）
func _get_next_label_char() -> String:
	var label_char = String.chr(65 + _label_index)  # 65 = 'A'
	_label_index += 1
	return label_char


## ラベルコンテナを作成
func _create_label_container(label_char: String) -> Node3D:
	var container = Node3D.new()
	container.name = "CharacterLabel_%s" % label_char

	# 背景の円（●を使用）
	var bg_label = Label3D.new()
	bg_label.name = "Background"
	bg_label.text = "●"
	bg_label.font_size = background_font_size
	bg_label.pixel_size = pixel_size
	bg_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bg_label.no_depth_test = true
	bg_label.modulate = background_color
	bg_label.outline_size = 0
	container.add_child(bg_label)

	# 前面の文字ラベル
	var text_label = Label3D.new()
	text_label.name = "Text"
	text_label.text = label_char
	text_label.font_size = text_font_size
	text_label.pixel_size = pixel_size
	text_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text_label.no_depth_test = true
	text_label.modulate = text_color
	text_label.outline_size = 0
	text_label.position = Vector3(0, 0, 0.01)  # 少し前に配置
	container.add_child(text_label)

	return container
