# TestCharacterSelector

キャラクター選択テストシーン。CharacterRegistryからキャラクターをテストするデバッグツール。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node3D` |
| ファイルパス | `scripts/tests/test_character_selector.gd` |
| シーン | `scenes/tests/test_character.tscn` |

## 機能

- 起動時に2体のCT + 2体のTキャラクターを自動生成
- **キャラクターラベル表示**（味方のみ、A, B, C...の順で頭上に表示）
- **複数キャラクター同時選択**（トグル選択で追加/解除）
- マウスクリックでキャラクター選択
- クリックでコンテキストメニュー表示
- ドロップダウンからキャラクター追加
- **複数選択キャラクターが同じパスを隊列で移動**
- 視線ポイント設定（Slice the Pie）
- Run区間設定（部分的に走る）
- 全キャラクター同時実行
- 回転モードで向き変更
- しゃがみ/立ちトグル
- WASD/マウスによる手動操作（トグル可能）

## 操作方法

### 基本操作（複数選択対応）
| 操作 | 説明 |
|------|------|
| クリック（キャラクター上） | **トグル選択**（選択中なら解除、未選択なら追加）+ コンテキストメニュー |
| クリック（地面） | **全選択解除** + メニュー閉じる |
| ドロップダウン | キャラクター追加 |
| ESC | パス追従中/回転モードのキャンセル |

### 手動操作（Manual Control ON時）
| 操作 | 説明 |
|------|------|
| WASD | 移動 |
| マウス | エイム方向 |
| Shift | 走る |
| C | しゃがみ |
| F | エイム |
| Space + F | 発射 |
| 1 | ライフル装備 |
| 2 | ピストル装備 |
| K | 自殺（テスト用） |
| R | リスポーン |

### パスモード（複数キャラクター同時対応・隊列移動）
1. **複数キャラクターをクリックして選択**（トグルで追加）
2. コンテキストメニューで「Move」選択
   - **この時点で選択中のキャラクターがパス適用対象として確定**
3. **プライマリキャラクター**（最後に選択したキャラクター）を基準にパス描画
4. 視線ポイントモードに自動移行
5. 「Add Vision」ボタンでパス上をクリック→ドラッグで視線方向設定
6. 「Add Run」ボタンでRun区間を設定（開始点→終点クリック）
7. **キャンセル**: キャラクター以外の場所をクリック
8. 「Confirm Path」ボタンで**パス適用対象キャラクターに同じパスを適用**
   - 各キャラクターは**自分の位置からパス開始点への接続線**を自動生成
   - その後、全員が**同じパス**を歩く（隊列移動）
   - 視線ポイント・Run区間の比率は接続線の長さを考慮して自動調整
   - **確定後、選択は自動解除**
9. 「Execute All」ボタンで全キャラクター同時実行
10. 全キャラクター到着後にパスと視線マーカーが自動削除

#### 隊列移動の動作
- プライマリキャラクターはパス開始点から直接移動
- 他のキャラクターは自分の位置 → パス開始点 → パス終点の順に移動
- 接続線もパスメッシュとして描画され、移動経路が可視化される

### 回転モード
1. コンテキストメニューで「Rotate」選択
2. 地面をクリックして向きを設定
3. Confirm/Cancelで確定

## コンテキストメニュー項目

| ID | 名前 | 説明 |
|----|------|------|
| `move` | Move | パス描画モード開始 |
| `rotate` | Rotate | 回転モード開始 |
| `crouch` | Crouch/Stand | しゃがみ/立ちトグル（状態により表示変化） |

## UIパネル

### ControlPanel（左上、常時表示）
| ボタン | 説明 |
|--------|------|
| Manual Control | 手動操作のON/OFF切替 |
| Vision/FoW | 視界/Fog of WarのON/OFF切替 |
| Pending: N paths | 確定済みパス数の表示 |
| Execute All (Walk) | 全キャラクターを歩きで同時実行 |
| Execute All (Run) | 全キャラクターを走りで同時実行 |
| Clear All Paths | 全ての確定パスをクリア |

### PathPanel（パス描画後、画面下部）
| ボタン | 説明 |
|--------|------|
| Vision Points: N | 設定済み視線ポイント数 |
| Add Vision | 視線ポイント追加モード |
| Undo | 最後の視線ポイントを削除 |
| Confirm Path | パスを確定して保存 |
| Cancel | パス描画をキャンセル |

## State Variables

| 変数 | 型 | 説明 |
|------|-----|------|
| `is_debug_control_enabled` | `bool` | 手動操作有効フラグ |
| `is_vision_enabled` | `bool` | 視界/FoW有効フラグ |
| `is_path_mode` | `bool` | パス描画モード中 |
| `path_editing_character` | `Node` | パス編集中のキャラクター |
| `characters` | `Array[Node]` | シーン内の全キャラクター |

## マネージャー

| 変数 | 型 | 説明 |
|------|-----|------|
| `selection_manager` | `CharacterSelectionManager` | **選択管理**（詳細は[CharacterSelectionManager](CharacterSelectionManager.md)参照） |
| `path_execution_manager` | `PathExecutionManager` | **パス実行管理**（詳細は[PathExecutionManager](PathExecutionManager.md)参照） |
| `label_manager` | `CharacterLabelManager` | **ラベル管理**（詳細は[CharacterLabelManager](CharacterLabelManager.md)参照） |

## シーン構成

```
TestCharacterSelector (Node3D)
├── Camera3D
├── UI (CanvasLayer)
│   ├── CharacterDropdown
│   ├── InfoLabel
│   ├── ControlPanel
│   │   ├── ManualControlButton
│   │   ├── VisionToggleButton
│   │   ├── Separator
│   │   ├── PendingPathsLabel
│   │   ├── ExecuteWalkButton
│   │   ├── ExecuteRunButton
│   │   └── ClearPathsButton
│   ├── PathPanel
│   │   ├── VisionLabel
│   │   ├── VisionHBox/AddVisionButton, UndoVisionButton
│   │   ├── ConfirmButton
│   │   └── CancelButton
│   └── RotatePanel
│       ├── RotateConfirmButton
│       └── RotateCancelButton
├── Floor (CSGBox3D)
└── Wall (CSGBox3D)
```

## 内部クラス依存

- `CharacterRegistry` - キャラクター作成
- `PlayerState` - プレイヤーチーム管理・敵味方判定
- `CharacterSelectionManager` - 選択管理・アウトライン表示
- `PathExecutionManager` - パス確定・実行・pending_paths管理
- `CharacterLabelManager` - 味方キャラクターのラベル管理
- `CharacterColorManager` - キャラクター個別色管理
- `FogOfWarSystem` - 視界表示
- `ContextMenuComponent` - コンテキストメニュー
- `PathDrawer` - パス描画
- `CharacterRotationController` - 回転制御
- `CharacterAnimationController` - アニメーション制御
