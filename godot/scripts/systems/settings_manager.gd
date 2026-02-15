extends Node
## 設定管理Autoload
##
## ConfigFileを使用してユーザー設定を永続化する。
## プレイヤー名などの設定を保存・読み込みする。

## 設定が変更されたときに発火
signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"
const SECTION_PLAYER := "player"
const KEY_PLAYER_NAME := "name"
const DEFAULT_PLAYER_NAME := "Player"

var _config: ConfigFile

## セッション中のみ保持（永続化しない）
var _selected_map_id: String = ""
var _game_mode: String = ""


func _ready() -> void:
	_config = ConfigFile.new()
	_load_settings()


func _load_settings() -> void:
	var err := _config.load(SETTINGS_PATH)
	if err != OK:
		# ファイルが存在しない場合はデフォルト値で初期化
		_config.set_value(SECTION_PLAYER, KEY_PLAYER_NAME, DEFAULT_PLAYER_NAME)
		_save_settings()


func _save_settings() -> void:
	var err := _config.save(SETTINGS_PATH)
	if err != OK:
		push_error("SettingsManager: Failed to save settings: %d" % err)


## プレイヤー名を取得
func get_player_name() -> String:
	return _config.get_value(SECTION_PLAYER, KEY_PLAYER_NAME, DEFAULT_PLAYER_NAME)


## プレイヤー名を設定
func set_player_name(value: String) -> void:
	var trimmed := value.strip_edges()
	if trimmed.is_empty():
		trimmed = DEFAULT_PLAYER_NAME
	_config.set_value(SECTION_PLAYER, KEY_PLAYER_NAME, trimmed)
	_save_settings()
	settings_changed.emit()


# ============================================
# Selected Map (Session Only)
# ============================================

## 選択中のマップIDを取得
func get_selected_map() -> String:
	return _selected_map_id


## 選択中のマップIDを設定（セッション中のみ保持）
func set_selected_map(map_id: String) -> void:
	_selected_map_id = map_id


## 選択中のマップIDをクリア
func clear_selected_map() -> void:
	_selected_map_id = ""


# ============================================
# Game Mode (Session Only)
# ============================================

## ゲームモードを取得（"" / "coop" / "multiplayer"）
func get_game_mode() -> String:
	return _game_mode


## ゲームモードを設定（セッション中のみ保持）
func set_game_mode(mode: String) -> void:
	_game_mode = mode


## ゲームモードをクリア
func clear_game_mode() -> void:
	_game_mode = ""
