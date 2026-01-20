# SettingsManager

設定管理Autoload。ConfigFileを使用してユーザー設定を永続化する。

## 概要

- **ファイル**: `scripts/systems/settings_manager.gd`
- **種別**: Autoload（シングルトン）
- **保存先**: `user://settings.cfg`

## シグナル

| シグナル | 説明 |
|---------|------|
| `settings_changed` | 設定が変更されたときに発火 |

## 定数

| 定数 | 値 | 説明 |
|-----|-----|------|
| `SETTINGS_PATH` | `"user://settings.cfg"` | 設定ファイルパス |
| `DEFAULT_PLAYER_NAME` | `"Player"` | デフォルトプレイヤー名 |

## メソッド

### get_player_name() -> String

プレイヤー名を取得する。

```gdscript
var name := SettingsManager.get_player_name()
print("Player: %s" % name)
```

### set_player_name(value: String) -> void

プレイヤー名を設定・保存する。空文字列の場合はデフォルト値が使用される。

```gdscript
SettingsManager.set_player_name("NewName")
# settings_changedシグナルが発火
```

## 使用例

### 設定変更の監視

```gdscript
func _ready() -> void:
    SettingsManager.settings_changed.connect(_on_settings_changed)

func _on_settings_changed() -> void:
    var name := SettingsManager.get_player_name()
    _update_display(name)
```

## 設定ファイル形式

```ini
[player]
name="PlayerName"
```

## 関連クラス

- `MainMenuScreen` - プレイヤー名を表示
- `OptionScreen` - プレイヤー名を編集
