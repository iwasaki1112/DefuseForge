# RoundManager

ラウンド管理システム。ラウンドの状態管理、タイマー制御、生存者数追跡、勝敗判定を行う。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承 | Node |
| クラス名 | RoundManager |
| ファイル | `scripts/systems/round_manager.gd` |

## 列挙型

### RoundPhase
ラウンドの進行状態。

| 値 | 説明 |
|----|------|
| `NONE` | ラウンド未開始 |
| `ACTIVE` | ラウンド進行中 |
| `ENDED` | ラウンド終了 |

### EndReason
ラウンド終了理由。

| 値 | 説明 |
|----|------|
| `TIME_UP` | タイムアップ（ドロー） |
| `CT_ELIMINATED` | CT全滅（T勝利） |
| `T_ELIMINATED` | T全滅（CT勝利） |

## シグナル

| シグナル | 引数 | 説明 |
|---------|------|------|
| `round_started` | なし | ラウンド開始時に発火 |
| `round_ended` | `winner: int, reason: int` | 勝敗確定時に発火。winnerはGameCharacter.Team、reasonはEndReason |
| `timer_updated` | `remaining_seconds: float` | タイマー更新時（秒が変わった時）に発火 |
| `survivor_count_changed` | `ct_count: int, t_count: int` | 生存者数変更時に発火 |

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `current_phase` | `RoundPhase` | 現在のラウンド状態 |
| `remaining_time` | `float` | 残り時間（秒） |
| `ct_alive_count` | `int` | CT生存者数 |
| `t_alive_count` | `int` | T生存者数 |
| `winner_team` | `int` | 勝利チーム（GameCharacter.Team）。NONEならドロー |

## メソッド

### setup(game_manager: GameManager) -> void
初期化処理。GameManagerへの参照を保持する。

```gdscript
round_manager.setup(game_manager)
```

### start_round() -> void
ラウンドを開始。タイマーを90秒にセットし、生存者数をカウントする。

```gdscript
round_manager.start_round()
```

### end_round(winner: int, reason: EndReason) -> void
ラウンドを終了。勝利チームと終了理由を指定。

```gdscript
round_manager.end_round(GameCharacter.Team.COUNTER_TERRORIST, RoundManager.EndReason.T_ELIMINATED)
```

### process(delta: float) -> void
毎フレーム処理。タイマー更新と勝敗判定を行う。GameManager.process_frame()から呼び出される。

### register_character(character: GameCharacter) -> void
キャラクターを追跡対象として登録。死亡シグナルを自動接続する。

```gdscript
round_manager.register_character(character)
```

### unregister_character(character: GameCharacter) -> void
キャラクターの追跡を解除。

## 勝敗判定ロジック

1. **CT全滅** → T勝利（EndReason.CT_ELIMINATED）
2. **T全滅** → CT勝利（EndReason.T_ELIMINATED）
3. **両チーム全滅** → ドロー（winner_team = NONE）
4. **タイムアップ** → ドロー（EndReason.TIME_UP）

## 使用例

```gdscript
# GameManagerが自動的にセットアップ
# GameScreenでラウンド開始
func _ready() -> void:
    game_manager.round_manager.start_round()

# シグナル接続例
game_manager.round_ended.connect(_on_round_ended)

func _on_round_ended(winner: int, reason: int) -> void:
    match winner:
        GameCharacter.Team.COUNTER_TERRORIST:
            print("CT wins!")
        GameCharacter.Team.TERRORIST:
            print("T wins!")
        _:
            print("Draw!")
```

## Multiplayer API

### is_authority() -> bool
このインスタンスが権限を持つか（ホスト/サーバー判定）。

### set_authority(authority: bool) -> void
権限フラグを設定する。クライアント側は`false`に設定。

### to_round_state() -> NetworkMessages.RoundStateMessage
現在のラウンド状態をRoundStateMessageに変換する。

### apply_round_state(state: NetworkMessages.RoundStateMessage) -> void
RoundStateMessageからラウンド状態を適用する（クライアント側用）。権限がない場合のみ適用。

### set_survivor_counts(ct_count: int, t_count: int) -> void
外部から生存者数を直接設定する（ネットワーク同期用）。

### set_remaining_time(time: float) -> void
外部から残り時間を直接設定する（ネットワーク同期用）。

### force_end_round(winner: int, reason: int) -> void
ラウンドを強制終了する（ネットワーク同期用）。権限チェックなしで終了処理を実行。

## 関連クラス

- [GameManager](GameManager.md) - RoundManagerを統合
- [RoundHUD](RoundHUD.md) - タイマー・生存者数のUI表示
- [GameCharacter](GameCharacter.md) - 追跡対象のキャラクター
- [NetworkMessages](NetworkMessages.md) - ネットワークメッセージ型
- [SyncState](SyncState.md) - 同期状態クラス
