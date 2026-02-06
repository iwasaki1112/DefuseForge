# GameSystemFactory

## 概要
GameManagerのシステム生成ロジックを分離するファクトリクラス。各`create_*`メソッドはシステムインスタンスを生成・初期化して返す。シグナル接続はGameManager側で行う（コールバックがGameManagerのメソッドのため）。

## ファイル
`scripts/systems/game_system_factory.gd`

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承 | RefCounted |
| class_name | GameSystemFactory |
| 使用者 | GameManager |

## 責務
- 各サブシステムのインスタンス生成と初期化
- PathDrawerScriptの遅延ロード管理（iOS互換性のため`preload`不使用）
- GameManagerの`setup()`内で使用され、生成後は`add_child()`とシグナル接続をGameManagerが行う

## プロパティ

```gdscript
# iOS互換性のため遅延ロード（preloadは使用しない）
var PathDrawerScript: GDScript = null
```

## ファクトリメソッド一覧

| メソッド | 戻り値 | 説明 |
|---------|--------|------|
| `create_selection_manager()` | CharacterSelectionManager | 選択マネージャーを生成 |
| `create_path_execution_manager(mesh_parent)` | PathExecutionManager | パス実行マネージャーを生成・初期化 |
| `create_idle_manager(characters_ref, is_following_callback, get_primary_callback)` | IdleCharacterManager | アイドルマネージャーを生成・初期化 |
| `create_smoke_area_manager()` | SmokeAreaManager | スモークエリアマネージャーを生成 |
| `create_path_drawer(cam, path_execution_manager)` | Node3D | PathDrawerを生成（set_scriptで動的にスクリプト設定） |
| `setup_path_drawer(drawer, cam, path_execution_manager)` | void | PathDrawerのセットアップ（add_child後に呼ぶ） |
| `create_path_mode_controller(drawer, selection_manager, path_execution_manager)` | PathModeController | パスモードコントローラーを生成・初期化 |
| `create_vision_service(fow_map_size, is_vision_enabled, smoke_area_manager)` | VisionService | ビジョンサービスを生成・初期化 |
| `create_map_manager(map_container, game_manager)` | MapManager | マップマネージャーを生成・初期化 |
| `create_path_service(drawer, selection_manager, path_execution_manager, path_mode_controller)` | PathService | パスサービスを生成・初期化 |
| `create_round_manager(game_manager)` | RoundManager | ラウンドマネージャーを生成・初期化 |
| `create_character_setup_service(...)` | CharacterSetupService | キャラクターセットアップサービスを生成・初期化 |
| `create_character_manager_service()` | CharacterManagerService | キャラクターマネージャーサービスを生成 |
| `create_grenade_service(mesh_parent, smoke_area_manager)` | GrenadeService | グレネードサービスを生成・初期化 |
| `create_door_service(character_manager, vision_update_callback)` | DoorService | ドアサービスを生成・初期化 |
| `create_moving_path_vision_service(mesh_parent, path_execution_manager)` | MovingPathVisionService | 移動パスビジョンサービスを生成・初期化 |

## 使用パターン

```gdscript
# GameManager.setup()内での使用例
func setup(cam: Camera3D, mesh_parent: Node3D, ...) -> void:
    _factory = GameSystemFactory.new()

    # 1. ファクトリでインスタンス生成
    selection_manager = _factory.create_selection_manager()
    add_child(selection_manager)

    # 2. シグナル接続はGameManager側で行う
    selection_manager.selection_changed.connect(_on_selection_changed)
```

## PathDrawerの特殊な生成パターン

PathDrawerはスクリプトを動的に設定するため、2段階の初期化が必要：

```gdscript
# 1. 生成（set_scriptでスクリプト設定）
path_drawer = _factory.create_path_drawer(camera, path_execution_manager)
path_drawer.name = GameConstants.NODE_PATH_DRAWER
add_child(path_drawer)

# 2. セットアップ（add_child後に呼ぶ）
_factory.setup_path_drawer(path_drawer, camera, path_execution_manager)
```

これは`PathDrawer`が`class_name`を持つものの、iOS互換性のため`load()`でスクリプトを読み込み、`Node3D.new()` + `set_script()`で生成するためである。

## 設計原則

1. **生成と接続の分離**: ファクトリはインスタンス生成のみ、シグナル接続はGameManagerが担当
2. **iOS互換性**: `preload()`ではなく`load()`を`_init()`で実行
3. **RefCounted継承**: シーンツリーに追加不要、GameManagerが保持するだけで自動解放
4. **一方向依存**: ファクトリはシステムクラスのみ参照、GameManagerは参照しない（`create_map_manager`と`create_round_manager`を除く）

## 関連クラス
- [GameManager](GameManager.md) - 使用者
- [GameScreen](../Screen/GameScreen.md) - GameManagerの初期化を呼び出す画面
