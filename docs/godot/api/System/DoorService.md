# DoorService

ドア管理サービス。ドアID管理・キック処理・ネットワーク同期を一元管理。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| クラス名 | `DoorService` |
| ファイルパス | `scripts/systems/door_service.gd` |
| 抽出元 | GameManager |

## 概要

GameManagerから抽出されたドア管理コンポーネント。ドアの登録・ID管理、キック処理、ネットワーク同期を担当する。

### チーム別可視性システム

マルチプレイヤーモードでFoWが有効な場合、敵チームが開けたドアは即座に開かず、`_pending_enemy_doors` バッファに保留される。`_process()` で定期的にFoW可視性をチェックし、味方の視界にドア位置が入った時点でアニメーション再生＋オクルーダー解除を実行する。

- **保留中のドア**: `open_doors` グループに入らないため、プレイヤーが通常通りドアを開ける操作が可能
- **プレイヤーが先に開けた場合**: 保留バッファからクリアされ、通常通り開く
- **シングルプレイヤー**: `_fow_system` が未設定なので全て即座実行（影響なし）

## シグナル

| シグナル | 引数 | 説明 |
|---------|------|------|
| `door_kick_network_event` | `door_id: int, character_network_id: int` | ドアキック時のネットワークイベント |
| `door_open_network_event` | `door_id: int, character_network_id: int` | ドア開け（静か）時のネットワークイベント |
| `door_opened` | `door: Node3D, character: Node` | ドア開き処理開始時 |

## メソッド

### setup(character_manager: CharacterManagerService) -> void
セットアップ。CharacterManagerServiceへの参照を設定する。

### set_multiplayer_mode(enabled: bool) -> void
マルチプレイヤーモードを設定する。

### set_vision_update_callback(callback: Callable) -> void
ドア開閉時の視界更新コールバックを設定する。

### set_fow_system(fow) -> void
FogOfWarSystemの参照を設定する。GameManagerのsetup()から呼ばれる。設定されると敵チームのドア開放がチーム別可視性制御の対象になる。

### register_door(door: Node3D) -> int
ドアを登録し、一意のIDを割り当てる。

### get_door_by_id(door_id: int) -> Node3D
ドアIDからドアノードを取得する。

### get_door_id(door: Node3D) -> int
ドアノードからドアIDを取得する。

### clear_door_registry() -> void
全ドアを登録解除する。

### register_all_doors_in_map() -> void
マップ内の全ドアを"doors"グループから取得して登録する。

### on_door_kick_done(door: Node3D, character: CharacterBody3D) -> void
ドアキックインパクト時の処理。ローカルキャラクターのキックならネットワークイベントを送信し、ドアを開く。

### open_door(door: Node3D, character: CharacterBody3D) -> void
ドアを開く処理（ローカル・リモート共通）。`_calculate_door_open_params()` でパラメータ計算後、`_execute_door_open()` でTweenアニメーションを実行する。保留中の敵ドアがあればクリアする。

### apply_door_kick_from_network(door_id: int, character_network_id: int) -> void
ネットワークからのドアキックイベントを適用する（リモート側用）。敵チーム＋FoW有効時はバッファに保留し、味方チームまたはFoWなしの場合は即座に実行する。

### on_door_open_done(door: Node3D, character: CharacterBody3D) -> void
ドア開けインパクト時の処理。ローカルキャラクターの開けならネットワークイベントを送信し、ドアを静かに開く。

### open_door_quietly(door: Node3D, character: CharacterBody3D) -> void
ドアを静かに開く処理。キックと異なり、160°回転・0.8秒・EASE_IN_OUTで穏やかに開く。保留中の敵ドアがあればクリアする。

### apply_door_open_from_network(door_id: int, character_network_id: int) -> void
ネットワークからのドア開けイベントを適用する（リモート側用）。敵チーム＋FoW有効時はバッファに保留し、味方チームまたはFoWなしの場合は即座に実行する。

### get_registered_door_count() -> int
登録されているドア数を取得する。

### is_door_open(door: Node3D) -> bool
ドアが開いているか確認する。

## 使用例

```gdscript
# GameSystemFactory経由で生成
var door_service = factory.create_door_service(character_manager, _force_update_all_vision)

# ドアキック処理
door_service.on_door_kick_done(door, character)

# ドア開け処理（静かに）
door_service.on_door_open_done(door, character)

# ネットワーク同期
door_service.door_kick_network_event.connect(_on_door_kick_network_event)
door_service.door_open_network_event.connect(_on_door_open_network_event)
```

## 関連クラス

- [GameManager](GameManager.md) - 使用者
- [CharacterManagerService](CharacterManagerService.md) - キャラクター検索（ネットワーク同期用）
- [GameSystemFactory](GameSystemFactory.md) - 生成元

## APIリファレンス

### シグナル
| シグナル | 引数 |
|---------|------|
| `door_kick_network_event` | `door_id: int, character_network_id: int` |
| `door_open_network_event` | `door_id: int, character_network_id: int` |
| `door_opened` | `door: Node3D, character: Node` |

### メソッド
- `setup(character_manager: CharacterManagerService) -> void`
- `set_multiplayer_mode(enabled: bool) -> void`
- `set_vision_update_callback(callback: Callable) -> void`
- `set_fow_system(fow) -> void`
- `register_door(door: Node3D) -> int`
- `get_door_by_id(door_id: int) -> Node3D`
- `get_door_id(door: Node3D) -> int`
- `clear_door_registry() -> void`
- `register_all_doors_in_map() -> void`
- `on_door_kick_done(door: Node3D, character: CharacterBody3D) -> void`
- `open_door(door: Node3D, character: CharacterBody3D) -> void`
- `on_door_open_done(door: Node3D, character: CharacterBody3D) -> void`
- `open_door_quietly(door: Node3D, character: CharacterBody3D) -> void`
- `apply_door_kick_from_network(door_id: int, character_network_id: int) -> void`
- `apply_door_open_from_network(door_id: int, character_network_id: int) -> void`
- `get_registered_door_count() -> int`
- `is_door_open(door: Node3D) -> bool`

### 内部メソッド（チーム別可視性システム）
- `_calculate_door_open_params(door, character, is_kick) -> Dictionary` — 回転量・ヒンジシフトを計算
- `_execute_door_open(door, params, instant) -> void` — Tweenアニメーション実行（instant=trueで即座に開く）
- `_defer_enemy_door_open(door, params) -> void` — バッファに保留
- `_reveal_deferred_door(door) -> void` — バッファから取り出してTween実行＋シグナル発火
- `_process(delta) -> void` — バッファのドアをFoW可視性チェック（~4Hz）
- `_is_door_visible_to_local_team(door) -> bool` — FoWチェック + Raycast LOSチェック
- `_can_character_see_door(character, door, panel_center) -> bool` — 距離 + 視野角 + LOS raycast判定
- `_calculate_max_opening_angle(door, target_angle) -> float` — スイープテストで壁衝突しない最大角度を算出
- `_collect_door_exclude_rids(door) -> Array[RID]` — スイープテスト除外RID収集

### 内部メソッド詳細

#### `_calculate_max_opening_angle()`
ドアが壁と衝突せずに開ける最大角度をスイープテストで算出する。

- `_SWEEP_STEP_DEG`（10°）刻みでドアパネルのBoxShape3D（`_DOOR_PANEL_SIZE`: 1.0x2.0x0.154m）を回転
- 各角度で `PhysicsShapeQueryParameters3D` を使い壁レイヤーとの `intersect_shape` 衝突検出
- 衝突検出時は前のステップ角度から `_SWEEP_MARGIN_DEG`（3°）を引いた安全角度を返す
- ドアパネル自身とドアフレーム（近隣3m以内のdoor系StaticBody3D）は除外

#### `_can_character_see_door()`
キャラクターがドアを視認できるか3段階で判定する。

1. **近距離チェック**: `_DOOR_VIS_NEAR_DISTANCE`（1.5m）以内なら方向不問で可視
2. **視野角チェック**: キャラクターの`fov_degrees / 2` + `_DOOR_VIS_FOV_MARGIN_DEG`（10°）以内か
3. **LOS raycast**: 眼の高さから壁レイヤーのみチェック。ヒットがドア自身なら可視扱い
