# RoundHUD

ラウンドHUD。タイマー、生存者数、ラウンド結果を表示するUI。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承 | Control |
| クラス名 | RoundHUD |
| ファイル | `scripts/ui/round_hud.gd` |

## 定数

| 定数 | 型 | 値 | 説明 |
|-----|-----|-----|------|
| `TIMER_WARNING_THRESHOLD` | float | 10.0 | 残り時間警告閾値（秒） |
| `TIMER_WARNING_COLOR` | Color | 赤 | 警告時のタイマー色 |
| `TIMER_NORMAL_COLOR` | Color | 白 | 通常時のタイマー色 |
| `CT_COLOR` | Color | 青 | CTの表示色 |
| `T_COLOR` | Color | オレンジ | Tの表示色 |

## UI構成

### 上部バー
画面上部中央に配置。

```
[CT: 3]  [1:30]  [T: 2]
```

- **CTラベル**: CT生存者数（青色）
- **タイマー**: 残り時間（分:秒形式）
- **Tラベル**: T生存者数（オレンジ色）

### 結果オーバーレイ
ラウンド終了時に画面全体を覆う半透明オーバーレイ。

| 結果 | 表示テキスト | 色 |
|-----|-------------|-----|
| CT勝利 | "COUNTER-TERRORIST WINS" | 青 |
| T勝利 | "TERRORIST WINS" | オレンジ |
| ドロー | "DRAW" | 白 |

## メソッド

### update_timer(remaining: float) -> void
タイマー表示を更新。残り10秒以下で警告色に変更。

```gdscript
round_hud.update_timer(45.5)  # "0:45" と表示
```

### update_survivor_counts(ct: int, t: int) -> void
生存者数表示を更新。

```gdscript
round_hud.update_survivor_counts(3, 2)  # "CT: 3", "T: 2" と表示
```

### show_result(winner: int, reason: int) -> void
結果オーバーレイを表示。フェードインアニメーション付き。

```gdscript
round_hud.show_result(GameCharacter.Team.COUNTER_TERRORIST, RoundManager.EndReason.T_ELIMINATED)
```

### hide_result() -> void
結果オーバーレイを非表示にする。

## 使用例

```gdscript
# GameScreenが自動的にセットアップ・シグナル接続
func _setup_round_hud() -> void:
    _round_hud = RoundHUD.new()
    _round_hud.name = GameConstants.NODE_ROUND_HUD
    ui_layer.add_child(_round_hud)

    game_manager.round_timer_updated.connect(_round_hud.update_timer)
    game_manager.survivor_count_changed.connect(_round_hud.update_survivor_counts)
    game_manager.round_ended.connect(_round_hud.show_result)
```

## 関連クラス

- [RoundManager](RoundManager.md) - ラウンド状態管理
- [GameHUD](GameHUD.md) - 操作パネルUI
- [GameScreen](GameScreen.md) - RoundHUDを統合
