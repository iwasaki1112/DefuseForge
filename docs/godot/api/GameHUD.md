# GameHUD

## 概要

ゲーム画面の操作パネルUI。パス実行やクリアなどの操作ボタンと状態表示を提供する。

## クラス情報

- **継承**: `Control`
- **ファイル**: `scripts/screens/game_hud.gd`

## シグナル

| シグナル | 説明 |
|---------|------|
| `execute_all_requested` | 全パス実行が要求されたとき |
| `clear_paths_requested` | 全パスクリアが要求されたとき |

## メソッド

### `setup() -> void`
UI要素を構築する。

### `set_pending_paths(count: int) -> void`
保留パス数の表示を更新する。

## 使用例

```gdscript
var hud := GameHUD.new()
ui_layer.add_child(hud)
hud.setup()
hud.execute_all_requested.connect(_on_execute)
hud.clear_paths_requested.connect(_on_clear)
```

## 関連クラス

- [GameScreen](GameScreen.md)
