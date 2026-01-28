# RoundHUD

ラウンドHUD。生存者数とラウンド結果を表示するUI。
（タイマー表示機能は `GameHUD` に移動しました）

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承 | Control |
| クラス名 | RoundHUD |
| ファイル | `scripts/ui/round_hud.gd` |

## 定数

| 定数 | 型 | 値 | 説明 |
|-----|-----|-----|------|
| `CT_COLOR` | Color | 青 | CTの表示色 |
| `T_COLOR` | Color | オレンジ | Tの表示色 |

## UI構成

### 上部バー
画面上部中央に配置（設定により非表示の場合あり）。

```
[CT: 3]         [T: 2]
```

- **CTラベル**: CT生存者数（青色）
- **Tラベル**: T生存者数（オレンジ色）

### 結果オーバーレイ
ラウンド終了時に画面全体を覆う半透明オーバーレイ。

| 結果 | 表示テキスト | 色 |
|-----|-------------|-----|
| CT勝利 | "COUNTER-TERRORIST WINS" | 青 |
| T勝利 | "TERRORIST WINS" | オレンジ |
| ドロー | "DRAW" | 白 |

## メソッド

### `update_survivor_counts(ct: int, t: int) -> void`
生存者数表示を更新。

```gdscript
round_hud.update_survivor_counts(3, 2)  # "CT: 3", "T: 2" と表示
```

### `show_result(winner: int, _reason: int) -> void`
結果オーバーレイを表示。フェードインアニメーション付き。
`_reason` 引数は現在使用されていないが、シグナル接続の互換性のために維持されている。

```gdscript
round_hud.show_result(GameCharacter.Team.COUNTER_TERRORIST, RoundManager.EndReason.T_ELIMINATED)
```

### `hide_result() -> void`
結果オーバーレイを非表示にする。

## 使用例

```gdscript
# GameScreenが自動的にセットアップ・シグナル接続
func _setup_round_hud() -> void:
    _round_hud = RoundHUD.new()
    _round_hud.name = GameConstants.NODE_ROUND_HUD
    ui_layer.add_child(_round_hud)

    game_manager.survivor_count_changed.connect(_round_hud.update_survivor_counts)
    game_manager.round_ended.connect(_round_hud.show_result)
```

## 関連クラス

- [RoundManager](../System/RoundManager.md)
- [GameHUD](GameHUD.md)
- [GameScreen](../Screen/GameScreen.md)