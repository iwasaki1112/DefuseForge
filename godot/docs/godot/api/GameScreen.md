# GameScreen

ゲーム画面。MapSelectionScreenで選択されたマップをロードし、キャラクターをスポーン、プレイヤーをCT/Tにランダム割り当てする。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node3D` |
| ファイルパス | `scripts/screens/game_screen.gd` |
| シーンパス | `scenes/screens/game.tscn` |

## 責務

| 責務 | 説明 |
|------|------|
| 環境セットアップ | EnvironmentSetupを生成し、環境プリセットを適用 |
| マッチセットアップ | MatchSetupServiceでマップロード・スポーン・カメラ調整を実行 |
| UI更新 | チーム表示、所持金、保留パス数の表示更新 |
| 入力委譲 | InputControllerが入力イベントをGameManagerへ委譲（パス/回転/キャンセル） |
| カメラ操作 | 右ドラッグでカメラを平行移動 |
| フレーム処理 | GameManagerの毎フレーム処理を呼び出し |

## シーン構造

```
GameScreen (Node3D)
├─ WorldEnvironment
├─ DirectionalLight3D
├─ Camera3D (俯瞰視点)
├─ MapContainer (Node3D) ← マップがロードされる
└─ UILayer (CanvasLayer)
    ├─ TeamDisplayLabel ← "You are CT/T" 表示
    └─ MoneyLabel ← 所持金表示
```

## 定数

| 定数 | 値 | 説明 |
|-----|-----|------|
| `DEFAULT_ENVIRONMENT_PRESET` | `"res://data/environment/default.tres"` | 環境プリセット |

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `camera` | `Camera3D` | シーンのカメラ |
| `map_container` | `Node3D` | マップを追加するコンテナ |
| `ui_layer` | `CanvasLayer` | UI用レイヤー |
| `team_display_label` | `Label` | チーム表示ラベル |
| `money_label` | `Label` | 所持金表示ラベル |
| `game_manager` | `GameManager` | コアゲームシステム |
| `environment_setup` | `EnvironmentSetup` | 環境セットアップ |

## 初期化フロー

```
_ready()
├─ _setup_environment()       # 環境プリセット適用
├─ _setup_game_manager()      # GameManager初期化
├─ _setup_hud()               # UI構築
├─ _setup_match_service()     # マッチセットアップ
├─ _load_map()                # マップロード
├─ _update_team_display()     # チーム表示更新
├─ _setup_money()             # 所持金管理
├─ _setup_camera_pan()        # カメラ平行移動
└─ _setup_input_controller() # 入力コントローラー
```

## 入力処理

| 入力 | 処理 |
|------|------|
| 右ドラッグ | カメラ平行移動（CameraPanController） |
| 左クリック | InputController経由でGameManagerに委譲（選択/パス/回転） |
| ESC | InputController経由でキャンセル処理 |

## 使用例

### 画面遷移

```gdscript
# MapSelectionScreenから遷移
func _on_start_pressed() -> void:
    SettingsManager.set_selected_map(selected_map_id)
    get_tree().change_scene_to_file("res://scenes/screens/game.tscn")
```

## 関連クラス

- [GameManager](GameManager.md) - コアゲームシステム統括
- [MapManager](MapManager.md) - マップロード・管理
- [PlayerState](PlayerState.md) - プレイヤーチーム管理
- [CharacterRegistry](CharacterRegistry.md) - キャラクター生成
- [MapPreset](MapPreset.md) - マップ定義（スポーン位置）
- [SettingsManager](SettingsManager.md) - 選択マップ保持
- [EnvironmentSetup](EnvironmentSetup.md) - 環境プリセット適用
- [MapSelectionScreen](MapSelectionScreen.md) - 遷移元画面
- [InputController](InputController.md) - 入力処理
- [GameHUD](GameHUD.md) - 画面操作UI
- [MatchSetupService](MatchSetupService.md) - マッチ初期化
