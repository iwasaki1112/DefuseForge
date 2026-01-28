# GameHUD

## 概要

ゲーム画面の操作パネルUI。パス実行、マーカー編集、キャラクター状態表示、ゲーム内通貨やタイマーの表示を提供する。

## クラス情報

- **継承**: `Control`
- **ファイル**: `scripts/screens/game_hud.gd`
- **シーン**: `scenes/ui/game_hud.tscn`

## シグナル

| シグナル | 引数 | 説明 |
|---------|------|------|
| `execute_all_requested` | なし | 全パス実行が要求されたとき（Goボタン） |
| `clear_paths_requested` | なし | 全パスクリアが要求されたとき |
| `character_marker_pressed` | `character: Node` | キャラクターマーカー（Alpha等）が押されたとき |
| `marker_edit_requested` | `action: String` | マーカー編集アクション（Vision等）が選択されたとき |
| `marker_undo_requested` | なし | マーカー編集のUndoが要求されたとき |
| `marker_confirm_requested` | なし | マーカー編集の確定が要求されたとき |
| `marker_cancel_requested` | なし | マーカー編集のキャンセルが要求されたとき |

## UI要素

### メインパネル
- **Go Button**: 全パスの実行を開始する
- **Pending Paths Label**: 未実行のパス数を表示
- **Timer Label**: 残り時間を表示（残り10秒以下で赤字警告）
- **Money Label**: 現在の所持金を表示

### キャラクターマーカー
画面下部に表示されるキャラクター選択ボタン群。
- **Alpha, Bravo, Ares, Brim**: 各キャラクターに対応するボタン
- キャラクター死亡時は半透明（Alpha 0.3）になる

### マーカーエディットパネル
パス描画モード時に表示されるアクション選択パネル。
- **Vision**: 視線ポイント
- **Run**: 走り移動区間
- **Clear**: クリアリングポイント
- **Grenade**: グレネード投擲
- **Smoke**: スモーク投擲
- **Door**: ドア開閉
- **Wait**: 待機

## メソッド

### セットアップ・更新

#### `setup() -> void`
UI要素（キャラクターマーカー、エディットボタン）を初期設定する。

#### `set_pending_paths(count: int) -> void`
保留パス数の表示を更新する。

#### `update_money(amount: int) -> void`
所持金表示を更新する（カンマ区切り）。

#### `update_timer(remaining: float) -> void`
残り時間を更新する（MM:SS形式）。

### キャラクターマーカー操作

#### `register_character_marker(character: GameCharacter) -> void`
キャラクターをHUD上のマーカーボタン（Alpha等）に関連付けて表示する。
死亡シグナルを自動的に購読し、死亡時にUIを更新する。

#### `clear_character_markers() -> void`
登録されたキャラクターマーカーを全てクリアする。

### マーカーエディットパネル操作

#### `show_marker_edit_panel() -> void`
マーカーエディットパネルを表示し、状態をリセットする。

#### `hide_marker_edit_panel() -> void`
マーカーエディットパネルを非表示にする。

#### `is_marker_edit_panel_visible() -> bool`
マーカーエディットパネルが表示中かどうかを返す。

## 内部動作

### アニメーション
- **ボタン押下**: `_play_button_press_animation` で拡大・縮小・透明度変化の演出を行う。
- **マーカー死亡**: `_animate_marker_death` で半透明にするフェードアニメーションを行う。

## 使用例

```gdscript
var hud := GameHUD.new()
ui_layer.add_child(hud)
hud.setup()

# シグナル接続
hud.execute_all_requested.connect(_on_execute)
hud.marker_edit_requested.connect(_on_marker_action)

# キャラクター登録
hud.register_character_marker(character_alpha)

# ゲーム状態更新
hud.update_money(800)
hud.update_timer(115.5)
```

## 関連クラス

- [GameScreen](GameScreen.md)
- [GameCharacter](../Character/GameCharacter.md)