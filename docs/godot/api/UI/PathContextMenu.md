# PathContextMenu

パス上をタップした際に表示されるコンテキストメニュー。A/B/Cのボタンを表示し、将来的にWait Point等の機能に拡張可能。

## 概要

- **スクリプト**: `godot/scripts/ui/path_context_menu.gd`
- **クラス名**: `PathContextMenu`
- **継承**: `Control`

## 機能

- パス上をタップした際にコンテキストメニューを表示
- A/B/Cの3つのボタンを提供
- 半透明オーバーレイでメニュー外タップを検出して閉じる
- フェードイン・スケールアニメーション付き
- 画面端を考慮した位置調整

## シグナル

| シグナル名 | パラメータ | 説明 |
|-----------|-----------|------|
| `menu_item_selected` | `item_id: String, path_data: Dictionary` | メニュー項目が選択された時に発火 |
| `menu_closed` | なし | メニューが閉じられた時に発火 |

## 定数

| 定数名 | 値 | 説明 |
|-------|-----|------|
| `MENU_WIDTH` | `150` | メニューの幅（ピクセル） |
| `BUTTON_HEIGHT` | `50` | ボタンの高さ（ピクセル） |
| `OVERLAY_COLOR` | `Color(0, 0, 0, 0.3)` | オーバーレイの色 |
| `BUTTON_MARGIN` | `8` | ボタン周囲のマージン |

## エクスポートプロパティ

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `animation_duration` | `float` | `0.15` | 表示/非表示アニメーション時間 |

## 公開メソッド

### show_at_position

```gdscript
func show_at_position(screen_pos: Vector2, path_data: Dictionary) -> void
```

指定位置にメニューを表示します。

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| `screen_pos` | `Vector2` | 表示位置（スクリーン座標） |
| `path_data` | `Dictionary` | パス情報（character, path_ratio, point等） |

### close

```gdscript
func close() -> void
```

メニューを閉じます。

### is_open

```gdscript
func is_open() -> bool
```

メニューが開いているかどうかを返します。

## 使用例

```gdscript
# GameManagerからの呼び出し
func show_path_context_menu(screen_pos: Vector2, path_data: Dictionary) -> void:
    if path_context_menu and not path_context_menu.is_open():
        path_context_menu.show_at_position(screen_pos, path_data)

# シグナルハンドラ
func _on_path_context_menu_selected(item_id: String, path_data: Dictionary) -> void:
    match item_id:
        "a":
            # Wait 1秒の処理
            pass
        "b":
            # Wait 3秒の処理
            pass
        "c":
            # Wait 5秒の処理
            pass
```

## 動作フロー

```
パス上をタッチダウン
  ↓
長押し待機開始（0.5秒）
  ↓
指を離す（タッチアップ）
  ├─ タイマー < 0.5秒 → タップ判定
  │   └─ show_path_context_menu() 呼び出し
  └─ タイマー >= 0.5秒 → Visionポイントモード（従来通り）
  ↓
メニュー表示
  ├─ A/B/Cボタン
  └─ オーバーレイ外タップで閉じる
  ↓
ボタン選択
  └─ menu_item_selected シグナル発火
```

## 関連クラス

- [GameManager](../System/GameManager.md): コンテキストメニューの管理・表示を担当
- [InputController](../System/InputController.md): パス上タップ検出を担当
- [WeaponShopModal](WeaponShopModal.md): 同様のモーダルUIパターン
