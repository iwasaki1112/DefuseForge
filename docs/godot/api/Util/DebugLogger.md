# DebugLogger

デバッグログユーティリティ。Autoloadシングルトン（`Debug`）として使用。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/utils/debug_logger.gd` |
| Autoload名 | `Debug` |

## 概要

既存の`print`文の前に`if Debug.enabled:`を追加することでログ出力を制御する。デプロイ時は`ENABLE_LOGS`を`false`にするか、`OS.is_debug_build()`で自動的に無効化される。

## 定数

| 定数 | 値 | 説明 |
|------|-----|------|
| `ENABLE_LOGS` | `false` | ログを有効にするか（手動設定） |
| `DEBUG_BUILD_ONLY` | `true` | デバッグビルドでのみログを出力するか |

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `enabled` | `bool` | ログが有効かどうか（読み取り専用） |

## メソッド

### log(args: Array) -> void
可変引数風のログ出力（配列で渡す）。

### print_msg(message: String) -> void
単一メッセージのログ出力。

### warn(message: String) -> void
警告ログ（`enabled`に関わらず常に出力）。

### error(message: String) -> void
エラーログ（`enabled`に関わらず常に出力）。

## 使用例

```gdscript
# 条件付きログ
if Debug.enabled: print("[MySystem] value=", some_value)

# ユーティリティメソッド
Debug.log(["message: ", value, ", other: ", other])
Debug.print_msg("simple message")

# 常に出力
Debug.warn("something unexpected")
Debug.error("critical error")
```

## APIリファレンス

### メソッド
- `log(args: Array) -> void`
- `print_msg(message: String) -> void`
- `warn(message: String) -> void`
- `error(message: String) -> void`
