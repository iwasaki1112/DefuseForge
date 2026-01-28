# TrainingModeProvider

Trainingモード（シングルプレイヤー）用のプロバイダー。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承 | GameModeProvider |
| パス | `scripts/screens/training_mode_provider.gd` |

## 概要

TrainingModeProviderはシングルプレイヤー用のシンプルな実装です。
ネットワーク同期は行わず、ローカルでのみ動作します。

## 実装詳細

### get_mode_name

```gdscript
func get_mode_name() -> String:
    return "training"
```

### determine_player_team

```gdscript
func determine_player_team() -> void:
    var teams = [GameCharacter.Team.COUNTER_TERRORIST, GameCharacter.Team.TERRORIST]
    var random_team = teams[randi() % 2]
    PlayerState.set_player_team(random_team)
```

ランダムにCTまたはTを割り当てます。

### register_character

```gdscript
func register_character(game_manager: GameManager, character: GameCharacter, _network_id: int) -> void:
    game_manager.register_character(character)
```

ネットワークIDは使用せず、通常のキャラクター登録を行います。

### can_start_round

```gdscript
func can_start_round() -> bool:
    return true
```

常にラウンド開始可能です。

## 使用例

```gdscript
# GameScreen._ready()で自動的に使用される
func _ready() -> void:
    if _mode_provider == null:
        _mode_provider = TrainingModeProvider.new()
        _map_id = SettingsManager.get_selected_map()
        _initialize_game()
```

## 関連クラス

- [GameModeProvider](./GameModeProvider.md)
- [MultiplayerModeProvider](./MultiplayerModeProvider.md)
