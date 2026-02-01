# GameHUD

**継承:** `Control`

ゲーム画面のUI操作パネル（HUD）。
タイマー、所持金、保留パス数、キャラクターマーカー、アクションボタンなどを管理する。

## ファイル
`scripts/screens/game_hud.gd`

## シグナル

| シグナル | 引数 | 説明 |
|---------|------|------|
| `execute_all_requested` | なし | Executeボタン（再生）押下時 |
| `clear_paths_requested` | なし | ゴミ箱ボタン押下時 |
| `character_marker_pressed` | `character: Node` | キャラクターマーカー押下時 |
| `point_edit_requested` | `action: String` | ポイント編集ボタン（Vision/Wait）押下時 |
| `point_undo_requested` | なし | Undoボタン押下時 |
| `point_cancel_requested` | なし | Cancelボタン押下時 |
| `sync_go_requested` | なし | 同期待機解放（W）ボタン押下時 |

## Public API

### 表示更新

#### `set_pending_paths(count: int) -> void`
保留中のパス数を表示更新する。

#### `update_money(amount: int) -> void`
所持金表示を更新する（カンマ区切り）。

#### `update_timer(remaining: float) -> void`
ラウンドタイマー表示を更新する。残り10秒以下で赤字になる。

### キャラクターマーカー

画面下部に表示されるキャラクター選択用マーカー（Alpha, Bravo, Ares, Brim）。

#### `register_character_marker(character: GameCharacter) -> void`
キャラクターを対応するマーカーに登録・表示する。
キャラクター側の `marker_name` プロパティ（"alpha" 等）に基づいてマッピングされる。

#### `clear_character_points() -> void`
全マーカーをクリア（非表示）にする。

### ポイント編集パネル

#### `show_point_edit_panel() -> void`
ポイント編集パネルを表示する（現在は一時的に無効化中）。

#### `hide_point_edit_panel() -> void`
ポイント編集パネルを非表示にする。

#### `is_point_edit_panel_visible() -> bool`
パネルの表示状態を返す。

### 同期待機ボタン

#### `show_sync_go_button() -> void`
同期待機解放ボタン（Wアイコン）を表示する。

#### `hide_sync_go_button() -> void`
同期待機解放ボタンを非表示にする。

#### `update_sync_go_button_visibility(has_waiting: bool) -> void`
待機中のキャラクターがいるかどうかに基づいてボタンの表示を切り替える。

## UI構造

- **ControlPanel**: 上部の情報表示（パス数など）
- **TimerLabel**: タイマー
- **MoneyLabel**: 所持金
- **ExecuteButton**: 実行ボタン
- **CharacterMarkers**: 下部のキャラクター選択ボタン群
- **MarkerEditPanel**: ポイント編集用ボタン群（Vision, Wait, Undo, Cancel）
- **SyncGoButton**: 同期待機解放ボタン
