# GameModeProvider

ゲームモードのプロバイダー基底クラス。TrainingモードとMultiplayerモードの差異を抽象化します。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承 | RefCounted |
| パス | `scripts/screens/game_mode_provider.gd` |

## 概要

GameModeProviderはStrategy/Providerパターンの基底クラスです。
モード固有の処理（チーム決定、キャラクター登録、ネットワーク同期など）を抽象化し、
GameScreenがモードを意識せずに動作できるようにします。

## メソッド

### get_mode_name

```gdscript
func get_mode_name() -> String
```

モード名を返します。サブクラスでオーバーライドします。

**戻り値:**
- `"training"` - TrainingModeProvider
- `"multiplayer"` - MultiplayerModeProvider

### initialize

```gdscript
func initialize(_game_screen: Node, _game_manager: GameManager) -> void
```

プロバイダーを初期化します。GameScreenとGameManagerへの参照を受け取ります。

### determine_player_team

```gdscript
func determine_player_team() -> void
```

プレイヤーのチームを決定します。

- **Training**: ランダムにCT/Tを割り当て
- **Multiplayer**: ネットワークから取得

### register_character

```gdscript
func register_character(_game_manager: GameManager, _character: GameCharacter, _network_id: int) -> void
```

キャラクターをGameManagerに登録します。

- **Training**: `game_manager.register_character()`
- **Multiplayer**: `game_manager.register_character_with_network()`

### on_round_ended

```gdscript
func on_round_ended(_winner: int, _reason: int) -> void
```

ラウンド終了時に呼ばれます。Multiplayerモードではホストが結果をブロードキャストします。

### can_start_round

```gdscript
func can_start_round() -> bool
```

ラウンドを開始可能かどうかを返します。

- **Training**: 常に`true`
- **Multiplayer**: ホストのみ`true`

### cleanup

```gdscript
func cleanup() -> void
```

リソースのクリーンアップを行います。

## 実装クラス

| クラス | 説明 |
|--------|------|
| [TrainingModeProvider](./TrainingModeProvider.md) | シングルプレイヤー用 |
| [MultiplayerModeProvider](./MultiplayerModeProvider.md) | マルチプレイヤー用 |

## 拡張方法

新しいモードを追加する場合：

```gdscript
class_name CpuModeProvider
extends GameModeProvider

func get_mode_name() -> String:
    return "cpu"

func determine_player_team() -> void:
    # プレイヤーは常にCT
    PlayerState.set_player_team(GameCharacter.Team.COUNTER_TERRORIST)

func register_character(game_manager: GameManager, character: GameCharacter, _network_id: int) -> void:
    game_manager.register_character(character)
    if character.team == GameCharacter.Team.TERRORIST:
        # CPUコントローラーをアタッチ
        character.add_child(CpuController.new())
```
