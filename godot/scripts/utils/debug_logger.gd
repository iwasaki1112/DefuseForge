extends Node
## デバッグログユーティリティ
## Autoloadシングルトンとして使用（Debug）
##
## 既存のprint文の前に if Debug.enabled: を追加することで制御
## デプロイ時はENABLE_LOGSをfalseにするか、
## OS.is_debug_build()で自動的に無効化される

# ============================================
# 設定
# ============================================

## ログを有効にするかどうか（手動設定用）
## falseにすると全てのログが無効になる
const ENABLE_LOGS: bool = false

## デバッグビルドでのみログを出力するかどうか
## trueにするとリリースビルドでログが自動的に無効化される
const DEBUG_BUILD_ONLY: bool = true

# ============================================
# 公開プロパティ
# ============================================

## ログが有効かどうか（読み取り専用）
## 使用例: if Debug.enabled: print("message")
var enabled: bool = false


func _ready() -> void:
	_update_enabled()


func _update_enabled() -> void:
	if not ENABLE_LOGS:
		enabled = false
		return

	if DEBUG_BUILD_ONLY and not OS.is_debug_build():
		enabled = false
		return

	enabled = true


# ============================================
# Public API - 便利関数
# ============================================

## 可変引数風のログ出力（配列で渡す）
## 使用例: Debug.log(["message: ", value, ", other: ", other])
func log(args: Array) -> void:
	if not enabled:
		return
	var msg := ""
	for i in range(args.size()):
		msg += str(args[i])
		if i < args.size() - 1:
			msg += " "
	print(msg)


## 単一メッセージのログ出力
## 使用例: Debug.print_msg("message")
func print_msg(message: String) -> void:
	if not enabled:
		return
	print(message)


## 警告ログ（常に出力）
func warn(message: String) -> void:
	push_warning(message)


## エラーログ（常に出力）
func error(message: String) -> void:
	push_error(message)
