extends Node
## キャラクター個別色管理（Autoload）
## 味方キャラクターに固有色を割り当て、UI要素で統一的に使用する
##
## 使用例:
##   var color = CharacterColorManager.get_character_color(character)
##   var index = CharacterColorManager.assign_color(character)
##   CharacterColorManager.release_color(character)

# ============================================
# Color Palette（6色固定）
# ============================================
const COLOR_PALETTE: Array[Color] = [
	Color(0.2, 0.6, 1.0),   # A: 青
	Color(0.2, 0.8, 0.2),   # B: 緑
	Color(1.0, 0.8, 0.0),   # C: 黄
	Color(0.8, 0.3, 0.8),   # D: 紫
	Color(1.0, 0.5, 0.0),   # E: オレンジ
	Color(0.0, 0.8, 0.8),   # F: シアン
]

## デフォルト色（未割り当て時）
const DEFAULT_COLOR: Color = Color(0.5, 0.5, 0.5)

# ============================================
# State
# ============================================
## キャラクターID → 色インデックスのマッピング
var _color_assignments: Dictionary = {}  # { character_id: int }

## 使用中の色インデックス
var _used_indices: Array[int] = []

# ============================================
# シグナル
# ============================================
signal color_assigned(character: Node, color: Color, index: int)
signal color_released(character: Node)

# ============================================
# Public API
# ============================================

## キャラクターに色を割り当てる
## @param character: 色を割り当てるキャラクター
## @return: 割り当てられた色インデックス（-1 = 割り当て失敗）
func assign_color(character: Node) -> int:
	if not character:
		return -1

	var char_id = character.get_instance_id()

	# 既に割り当て済みの場合はそのインデックスを返す
	if _color_assignments.has(char_id):
		return _color_assignments[char_id]

	# 空いているインデックスを探す
	var available_index = _find_available_index()
	if available_index == -1:
		push_warning("[CharacterColorManager] All colors are in use")
		return -1

	# 割り当て
	_color_assignments[char_id] = available_index
	_used_indices.append(available_index)

	var assigned_color = COLOR_PALETTE[available_index]
	color_assigned.emit(character, assigned_color, available_index)

	return available_index


## キャラクターの色を解放
## @param character: 色を解放するキャラクター
func release_color(character: Node) -> void:
	if not character:
		return

	var char_id = character.get_instance_id()
	if not _color_assignments.has(char_id):
		return

	var index = _color_assignments[char_id]
	_color_assignments.erase(char_id)
	_used_indices.erase(index)

	color_released.emit(character)


## キャラクターの色を取得
## @param character: キャラクター
## @return: 割り当てられた色（未割り当ての場合はDEFAULT_COLOR）
func get_character_color(character: Node) -> Color:
	if not character:
		return DEFAULT_COLOR

	var char_id = character.get_instance_id()
	if not _color_assignments.has(char_id):
		return DEFAULT_COLOR

	var index = _color_assignments[char_id]
	return COLOR_PALETTE[index]


## キャラクターの色インデックスを取得
## @param character: キャラクター
## @return: 色インデックス（-1 = 未割り当て）
func get_character_color_index(character: Node) -> int:
	if not character:
		return -1

	var char_id = character.get_instance_id()
	if not _color_assignments.has(char_id):
		return -1

	return _color_assignments[char_id]


## インデックスから色を取得
## @param index: 色インデックス（0-5）
## @return: 色
func get_color_by_index(index: int) -> Color:
	if index < 0 or index >= COLOR_PALETTE.size():
		return DEFAULT_COLOR
	return COLOR_PALETTE[index]


## インデックスからラベル文字を取得（A-F）
## @param index: 色インデックス（0-5）
## @return: ラベル文字
func get_label_char(index: int) -> String:
	if index < 0 or index >= COLOR_PALETTE.size():
		return "?"
	return String.chr(65 + index)  # 65 = 'A'


## キャラクターのラベル文字を取得
## @param character: キャラクター
## @return: ラベル文字（未割り当ての場合は"?"）
func get_character_label(character: Node) -> String:
	var index = get_character_color_index(character)
	return get_label_char(index)


## 色が割り当てられているか確認
## @param character: キャラクター
## @return: 割り当て済みならtrue
func has_color(character: Node) -> bool:
	if not character:
		return false
	return _color_assignments.has(character.get_instance_id())


## 全ての色割り当てをクリア
func clear_all() -> void:
	_color_assignments.clear()
	_used_indices.clear()


## 割り当て済みの色数を取得
func get_assigned_count() -> int:
	return _color_assignments.size()


## パレットの色数を取得
func get_palette_size() -> int:
	return COLOR_PALETTE.size()


# ============================================
# Internal Methods
# ============================================

## 空いている最小のインデックスを探す
func _find_available_index() -> int:
	for i in range(COLOR_PALETTE.size()):
		if not _used_indices.has(i):
			return i
	return -1
