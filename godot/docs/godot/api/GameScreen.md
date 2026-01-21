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
| マップロード | SettingsManagerから選択マップIDを取得し、MapManagerでロード |
| キャラクタースポーン | MapPresetのスポーン位置にCT/T両チームのキャラクターを配置 |
| ランダムチーム選定 | プレイヤーをCT/Tどちらかにランダムに割り当て |
| 入力委譲 | 入力イベントをGameManagerに委譲 |
| フレーム処理 | GameManagerの毎フレーム処理を呼び出し |

## シーン構造

```
GameScreen (Node3D)
├─ WorldEnvironment
├─ DirectionalLight3D
├─ Camera3D (俯瞰視点)
├─ MapContainer (Node3D) ← マップがロードされる
└─ UILayer (CanvasLayer)
    └─ TeamDisplayLabel ← "You are CT/T" 表示
```

## 定数

| 定数 | 値 | 説明 |
|-----|-----|------|
| `MAIN_MENU_SCENE` | `"res://scenes/screens/main_menu.tscn"` | メインメニューシーン |
| `MAP_SELECTION_SCENE` | `"res://scenes/screens/map_selection.tscn"` | マップ選択シーン |

## プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `camera` | `Camera3D` | シーンのカメラ |
| `map_container` | `Node3D` | マップを追加するコンテナ |
| `ui_layer` | `CanvasLayer` | UI用レイヤー |
| `team_display_label` | `Label` | チーム表示ラベル |
| `game_manager` | `GameManager` | コアゲームシステム |

## 初期化フロー

```
_ready()
├─ _determine_player_team()     # ランダムチーム決定
├─ _setup_game_manager()        # GameManager初期化
├─ _load_map()                  # マップロード
├─ _spawn_characters()          # キャラクタースポーン
└─ _update_team_display()       # チーム表示UI更新
```

## 内部メソッド

### _determine_player_team()

プレイヤーチームをランダムに決定。

```gdscript
func _determine_player_team() -> void:
    var teams = [GameCharacter.Team.COUNTER_TERRORIST, GameCharacter.Team.TERRORIST]
    var random_team = teams[randi() % 2]
    PlayerState.set_player_team(random_team)
```

### _setup_game_manager()

GameManagerをセットアップ。

```gdscript
func _setup_game_manager() -> void:
    game_manager = GameManager.new()
    game_manager.name = "GameManager"
    add_child(game_manager)
    game_manager.setup(camera, self, ui_layer, Vector2(50, 50), map_container)
```

### _load_map()

SettingsManagerから選択マップIDを取得し、ロード。

```gdscript
func _load_map() -> void:
    var map_id := SettingsManager.get_selected_map()
    var map_instance := game_manager.load_map(map_id)
```

### _spawn_characters()

マッププリセットのスポーン位置にキャラクターを配置。

```gdscript
func _spawn_characters() -> void:
    var preset = game_manager.map_manager.current_preset

    # CT側
    var ct_presets = CharacterRegistry.get_counter_terrorists()
    for i in range(mini(ct_presets.size(), preset.spawn_points_ct.size())):
        var char = CharacterRegistry.create_character(ct_presets[i].id, preset.spawn_points_ct[i])
        map_container.add_child(char)
        game_manager.register_character(char)

    # T側も同様
```

## 入力処理

入力はGameManagerに委譲:

| 入力 | 処理 |
|------|------|
| マウスクリック | `game_manager.handle_click()` |
| 回転モード中クリック | `game_manager.handle_rotation_input()` |
| ESCキー | パス追従キャンセル / 回転キャンセル / パスモードキャンセル |

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
- [MapSelectionScreen](MapSelectionScreen.md) - 遷移元画面
