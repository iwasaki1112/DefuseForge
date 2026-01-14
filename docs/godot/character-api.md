# キャラクター API

CharacterBase のパブリック API リファレンス。

## 座標規約

**重要: このプロジェクトでは `+Z` がキャラクターの前方です。**

```gdscript
# 前方ベクトルの取得
var forward = global_transform.basis.z  # +Z が前方

# 回転角度の計算（movement_component.gd と同じ方式）
var target_angle = atan2(direction.x, direction.z)
```

Godotのデフォルト（`-Z` が前方）とは異なるため、視界判定・自動照準・移動回転など、向きを扱うコードでは必ずこの規約に従うこと。

---

## アウトライン（選択ハイライト）

キャラクター選択時にシルエットのみ発光するアウトラインエフェクト。

### 技術実装

SubViewport マスク + Sobel エッジ検出方式:
1. キャラクターメッシュを専用 SubViewport に白色でレンダリング
2. キャンバス上でエッジ検出シェーダーを適用
3. シルエット外縁のみを発光表示

### 初期化

```gdscript
# メインカメラ取得後に呼び出し必須
character.setup_outline_camera(camera)
```

### 選択状態の制御

```gdscript
# 選択状態を設定
character.set_selected(true)
character.set_selected(false)

# 選択状態を取得
var is_selected: bool = character.is_selected()
```

### カスタマイズ

```gdscript
# アウトライン色を設定（デフォルト: シアン）
character.set_outline_color(Color(0.0, 0.8, 1.0, 1.0))

# アウトライン幅を設定（デフォルト: 2.0）
character.set_outline_width(3.0)
```

### OutlineComponent エクスポート設定

| パラメータ | 型 | デフォルト | 説明 |
|------------|------|------------|------|
| outline_color | Color | (0.0, 0.8, 1.0, 1.0) | シアン色 |
| line_width | float | 2.0 | アウトライン太さ |
| emission_energy | float | 1.0 | 発光強度 |

### 注意事項

- `setup_outline_camera()` はカメラ取得後に必ず呼び出す
- LaserPointer、MuzzleFlash など特定ノードはアウトライン対象外
- レイヤー20をマスク用に使用（メインカメラから自動除外）

### 関連ファイル

- `scripts/characters/components/outline_component.gd` - アウトライン管理
- `shaders/silhouette_mask.gdshader` - マスク描画シェーダー
- `shaders/silhouette_edge_detect.gdshader` - エッジ検出シェーダー

---

## コンテキストメニュー・インタラクション

キャラクタータップ時にコンテキストメニューを表示し、回転などの操作を選択できるシステム。
モバイル（タッチ）とPC（マウス）両対応。

### コンポーネント構成

| コンポーネント | 役割 |
|----------------|------|
| SelectionManager | キャラクター選択状態の管理 |
| ContextMenuComponent | メニューUI表示 |
| CharacterInteractionManager | 状態遷移とワークフロー制御 |
| InputRotationComponent | 回転入力処理 |

### 操作フロー

```
キャラクタータップ
    ↓
選択 + ハイライト + メニュー表示
    ↓
「回転」を選択 → 任意の場所をタップ → その方向にキャラクターが向く
または
「操作」を選択 → そのキャラクターがWASD操作対象になる
```

### 複数キャラクター操作切替

`action_started`シグナルで「操作」アクションを検知し、操作対象キャラクターを切り替える:

```gdscript
var controlled_character: CharacterBase = null

func _ready():
    interaction_manager.action_started.connect(_on_action_started)
    controlled_character = characters[0]  # デフォルト

func _on_action_started(action_id: String, character: CharacterBody3D) -> void:
    if action_id == "control" and character:
        controlled_character = character as CharacterBase

func _physics_process(_delta: float) -> void:
    if controlled_character and controlled_character.movement:
        var input_dir = Vector3.ZERO
        # WASD入力処理...
        controlled_character.movement.set_input_direction(input_dir, is_running)
```

### SelectionManager

```gdscript
# インスタンス作成
var selection_manager = SelectionManager.new()
add_child(selection_manager)

# キャラクターを選択
selection_manager.select(character)

# 選択解除
selection_manager.deselect()

# 現在選択中のキャラクターを取得
var selected = selection_manager.get_selected()

# 選択状態確認
var is_sel = selection_manager.is_selected(character)
```

#### シグナル

```gdscript
signal selection_changed(character: CharacterBody3D)
```

### ContextMenuComponent

```gdscript
# インスタンス作成（CanvasLayerに追加）
var context_menu = ContextMenuComponent.new()
canvas_layer.add_child(context_menu)

# メニュー項目を追加
var rotate_item = ContextMenuItem.create("rotate", "回転", 0)
context_menu.add_item(rotate_item)

# メニューを開く（スクリーン座標とキャラクターを渡す）
context_menu.open(screen_position, character)

# メニューを閉じる
context_menu.close()

# メニュー項目の有効/無効を切り替え
context_menu.set_item_enabled("rotate", false)

# メニュー項目を削除
context_menu.remove_item("rotate")
```

#### エクスポート設定

| パラメータ | 型 | デフォルト | 説明 |
|------------|------|------------|------|
| button_size | Vector2 | (120, 50) | ボタンサイズ（モバイル向け） |
| button_margin | float | 4.0 | ボタン間のマージン |
| panel_padding | float | 8.0 | パネル内側のパディング |
| font_size | int | 16 | フォントサイズ |
| animation_duration | float | 0.15 | 表示/非表示アニメーション時間 |

#### シグナル

```gdscript
signal menu_opened(character: CharacterBody3D)
signal menu_closed()
signal item_selected(action_id: String, character: CharacterBody3D)
```

### ContextMenuItem

メニュー項目を定義するリソース。

```gdscript
# ファクトリーメソッドで作成
var item = ContextMenuItem.create("rotate", "回転", 0)

# プロパティ
item.action_id = "rotate"      # アクション識別子
item.display_name = "回転"     # 表示名
item.icon = preload("...")     # アイコン（オプション）
item.enabled = true            # 有効/無効
item.order = 0                 # 表示順序
```

### CharacterInteractionManager

状態マシンによるワークフロー制御。単一または複数キャラクターに対応。

```gdscript
# インスタンス作成
var interaction_manager = CharacterInteractionManager.new()
add_child(interaction_manager)

# 各コンポーネントを接続（プライマリキャラクター）
interaction_manager.setup(
    selection_manager,
    context_menu,
    input_rotation,  # プライマリキャラクターのInputRotation
    camera
)

# 追加キャラクターのInputRotationを登録（複数キャラクター対応）
for i in range(1, characters.size()):
    var input_rot = characters[i].get_node("InputRotationComponent")
    interaction_manager.register_input_rotation(input_rot, characters[i])

# 現在の状態を取得
var state = interaction_manager.get_current_state()
# 0 = IDLE, 1 = MENU_OPEN, 2 = ROTATING

# 現在のアクションをキャンセル
interaction_manager.cancel_current_action()
```

#### 状態遷移

```
IDLE ←→ MENU_OPEN → ROTATING → IDLE
```

#### シグナル

```gdscript
signal state_changed(old_state: int, new_state: int)
signal action_started(action_id: String, character: CharacterBody3D)
signal action_completed(action_id: String, character: CharacterBody3D)
```

### InputRotationComponent

マウス/タッチによる回転入力処理。

```gdscript
# キャラクターの子として追加
var input_rotation = InputRotationComponent.new()
character.add_child(input_rotation)
input_rotation.setup(camera)

# メニュー経由必須モード（長押し回転を無効化）
input_rotation.require_menu_activation = true

# 外部から回転モードを開始
input_rotation.start_rotation_mode()

# 外部から回転モードを停止
input_rotation.stop_rotation_mode()

# 回転中かどうか
var rotating = input_rotation.is_rotating()
```

#### エクスポート設定

| パラメータ | 型 | デフォルト | 説明 |
|------------|------|------------|------|
| click_radius | float | 0.3 | クリック検出半径 |
| character_collision_mask | int | 1 | キャラクター検出レイヤー |
| ground_plane_height | float | 0.0 | グラウンド平面の高さ |
| hold_duration | float | 0.2 | 長押し判定時間（秒） |
| require_menu_activation | bool | false | メニュー経由必須モード |

#### シグナル

```gdscript
signal rotation_started()
signal rotation_ended()
signal clicked()        # キャラクター上の短いクリック
signal clicked_empty()  # 空きエリアのクリック
```

### 統合例

```gdscript
# セットアップ
func _ready():
    # SelectionManager
    _selection_manager = SelectionManager.new()
    add_child(_selection_manager)
    _selection_manager.selection_changed.connect(_on_selection_changed)

    # InputRotationComponent
    _input_rotation = InputRotationComponent.new()
    character.add_child(_input_rotation)
    _input_rotation.setup(camera)
    _input_rotation.require_menu_activation = true

    # ContextMenuComponent
    _context_menu = ContextMenuComponent.new()
    canvas_layer.add_child(_context_menu)
    _context_menu.add_item(ContextMenuItem.create("rotate", "回転", 0))

    # CharacterInteractionManager
    _interaction_manager = CharacterInteractionManager.new()
    add_child(_interaction_manager)
    _interaction_manager.setup(
        _selection_manager,
        _context_menu,
        _input_rotation,
        camera
    )
```

### 関連ファイル

- `scripts/managers/selection_manager.gd` - 選択管理
- `scripts/managers/character_interaction_manager.gd` - インタラクション管理
- `scripts/ui/context_menu_component.gd` - コンテキストメニューUI
- `scripts/resources/context_menu_item.gd` - メニュー項目リソース
- `scripts/characters/components/input_rotation_component.gd` - 回転入力

---

## コリジョンレイヤー規約

プロジェクト全体で統一された物理レイヤー構成。

### レイヤー定義

| Layer | 用途 | 使用例 |
|-------|------|--------|
| 1 | 物理衝突 | キャラクター、床、物体 |
| 2 | 視界遮断 | 壁、障害物（VisionComponent用） |

### 推奨設定

**キャラクター（CharacterBody3D）**:
```gdscript
collision_layer = 1  # Layer 1に存在
collision_mask = 3   # Layer 1 + Layer 2と衝突
```

**壁（StaticBody3D）**:
```gdscript
collision_layer = 3  # Layer 1（物理衝突）+ Layer 2（視界検出）
collision_mask = 0   # 静的オブジェクトなので検出不要
```

**床（StaticBody3D）**:
```gdscript
collision_layer = 1  # Layer 1
collision_mask = 0   # 静的オブジェクトなので検出不要
```

### Blender GLBインポート時のコリジョン

Blenderからインポートするマップ用GLBファイルでコリジョンを生成する方法:

**方法1: メッシュ名によるサフィックス（推奨）**

Blenderでメッシュ名にサフィックスを付与:
- `-col`: ConvexShape（凸包コリジョン、シンプルな形状用）
- `-colonly`: コリジョンのみ生成（メッシュ非表示）
- `-trimesh`: ConcaveShape（複雑な形状用）

例: `Wall-col` → StaticBody3D + CollisionShape3D が自動生成

**方法2: インポート設定**

1. GLBファイルをダブルクリック → インポート設定
2. `Physics > Shape Type` を選択
3. 「Reimport」をクリック

**注意**: インポート後、壁の `collision_layer` を 3 に変更する必要あり。

---

## 移動

MovementComponentは2つの移動モードをサポート:

| モード | 用途 | メソッド |
|--------|------|----------|
| パス追従 | ドロワーパス、AI移動 | `set_path()`, `move_to()` |
| リアルタイム入力 | WASD、ジョイスティック | `set_input_direction()` |

両モードとも同じ `locomotion_changed` シグナルを発火し、アニメーション自動切り替えが動作する。

### パス追従モード（ドロワーパス対応）

```gdscript
# パスを設定して移動開始（ドロワーパスの座標配列を渡す）
character.set_path(points: Array[Vector3], run: bool = false)

# 単一目標地点に移動
character.move_to(target: Vector3, run: bool = false)

# 移動を停止
character.stop()

# 走る/歩くを切り替え
character.set_running(running: bool)

# 移動中かどうか
var moving: bool = character.is_moving()
```

### リアルタイム入力モード

```gdscript
# 直接入力で移動（WASD等のリアルタイム入力用）
# direction: 移動方向ベクトル（正規化済み、長さ0で停止）
# run: trueで走り、falseで歩き
character.movement.set_input_direction(direction: Vector3, run: bool = false)
```

使用例（WASD移動）:
```gdscript
func _physics_process(_delta: float) -> void:
    var input_dir = Vector3.ZERO
    if Input.is_key_pressed(KEY_W): input_dir.z -= 1
    if Input.is_key_pressed(KEY_S): input_dir.z += 1
    if Input.is_key_pressed(KEY_A): input_dir.x -= 1
    if Input.is_key_pressed(KEY_D): input_dir.x += 1

    if input_dir.length_squared() > 0:
        input_dir = input_dir.normalized()

    var is_running = Input.is_key_pressed(KEY_SHIFT)
    character.movement.set_input_direction(input_dir, is_running)
```

### ドロワーパス実装ガイド

ドロワーパスシステムを実装する場合、描画したパスの座標配列を `set_path()` に渡すだけで動作する:

```gdscript
# ドロワーパス描画完了時
func _on_path_drawn(path_points: Array[Vector3]) -> void:
    character.set_path(path_points, false)  # 歩き
    # または
    character.set_path(path_points, true)   # 走り
```

アニメーション連携は自動で行われる:
```
set_path() / set_input_direction()
    ↓
MovementComponent (locomotion_changed シグナル)
    ↓
CharacterBase._on_locomotion_changed()
    ↓
AnimationComponent.set_locomotion()
    ↓
rifle_idle / rifle_walking / rifle_sprint 自動切り替え
```

### MovementComponentエクスポート設定

| パラメータ | 型 | デフォルト | 説明 |
|------------|------|------------|------|
| walk_speed | float | 3.0 | 歩行速度 |
| run_speed | float | 6.0 | 走行速度 |
| rotation_speed | float | 10.0 | 回転速度 |
| waypoint_threshold | float | 0.3 | ウェイポイント到達判定距離 |

### シグナル

```gdscript
signal waypoint_reached(index: int)  # ウェイポイント到達時
signal path_completed               # パス移動完了時
signal locomotion_changed(state: int)  # 移動状態変化時 (0=IDLE, 1=WALK, 2=RUN)
```

### 関連ファイル

- `scripts/characters/components/movement_component.gd` - 移動コンポーネント
- `scripts/characters/components/animation_component.gd` - アニメーション管理

---

## 武器

```gdscript
# 武器を設定
character.set_weapon(weapon_id: int)

# 現在の武器IDを取得
var id: int = character.get_weapon_id()

# 武器リソースを取得
var resource: WeaponResource = character.get_weapon_resource()

# リコイルを適用
character.apply_recoil(intensity: float = 1.0)
```

### リコイル動作

`apply_recoil()` は以下の動作を実行:

1. **武器オフセット**: 武器を後方に跳ねさせる（Y+0.02, Z+0.05 × intensity）
2. **MuzzleFlash発火**: 銃口のフラッシュエフェクトを表示（50ms）
3. **TracerEffect発火**: 弾道トレーサーを表示
4. **ヒット検出**: RayCast3Dで敵キャラクターを検出してダメージを適用
5. **上半身リコイル**: Spineボーンを後方に傾ける（~4.5度）→ 滑らかに回復

```gdscript
# 射撃時に呼び出し（test_animation_viewer.gd参照）
func _shoot() -> void:
    character.apply_recoil(1.0)
```

### 射撃ヒット検出

`apply_recoil()` 呼び出し時、内部で `fire()` が実行され RayCast3D によるヒット検出が行われる。

#### 処理フロー

```
apply_recoil()
    ↓
WeaponComponent.apply_recoil()
    ├─ MuzzleFlash.flash()
    ├─ TracerEffect.fire()
    └─ fire()  ← ヒット検出
            ↓
        RayCast3D.force_raycast_update()
            ↓
        衝突判定 && CharacterBase?
            ↓
        is_enemy_of(target)?
            ↓ Yes
        _calculate_damage() → target.take_damage()
```

#### ダメージ計算

```gdscript
# WeaponResource の damage 値を使用
# ヘッドショット時は 2.5 倍
var damage = weapon_resource.damage  # 例: AK-47 = 36.0
if is_headshot:
    damage *= 2.5  # 90.0
```

#### シグナル

```gdscript
# WeaponComponent から発火
signal hit_detected(target: Node3D, hit_point: Vector3, is_headshot: bool)

# 使用例
character.weapon.hit_detected.connect(_on_hit)
func _on_hit(target: Node3D, hit_point: Vector3, is_headshot: bool) -> void:
    if is_headshot:
        show_headshot_indicator()
```

#### RayCast設定

| パラメータ | 値 | 説明 |
|------------|-----|------|
| target_position | (0, 0, -effective_range) | 武器の有効射程 |
| collision_mask | 1 | キャラクターレイヤー |
| exclude | owner_character | 自分自身を除外 |

### MuzzleFlash

武器シーン（ak47.tscn等）に含まれる銃口フラッシュエフェクト。

| パラメータ | 型 | デフォルト | 説明 |
|------------|------|------------|------|
| flash_duration | float | 0.05 | フラッシュ表示時間（秒） |

### TracerEffect

弾道トレーサーエフェクト。発砲時にマズルから着弾点まで伸び縮みする白い弾道ラインを表示。

#### 動作
1. **伸張フェーズ**: マズルから着弾点まで先端が伸びる
2. **縮小フェーズ**: 尾部が着弾点に向かって縮む
3. **消滅**: アニメーション完了後に非表示

#### 構造
- **コア**: 細くて明るい中心ライン（発光強度3.0）
- **グロー**: 太くて半透明のぼかし外周（発光強度1.5、透明度25%）

| パラメータ | 型 | デフォルト | 説明 |
|------------|------|------------|------|
| tracer_color | Color | (1.0, 1.0, 0.9, 0.9) | トレーサーの色 |
| core_radius | float | 0.003 | コアの半径 |
| glow_radius | float | 0.012 | グローの半径 |
| max_range | float | 100.0 | 最大射程（m） |
| extend_time | float | 0.03 | 伸張時間（秒） |
| shrink_time | float | 0.08 | 縮小時間（秒） |

#### 武器シーン構成

```
AK47 (Node3D)
├─ Model
│  ├─ MuzzlePoint
│  │  ├─ MuzzleFlash
│  │  ├─ LaserPointer
│  │  └─ TracerEffect  ← 弾道トレーサー
```

### 関連ファイル

- `scripts/effects/muzzle_flash.gd` - MuzzleFlashスクリプト
- `scenes/effects/muzzle_flash.tscn` - MuzzleFlashシーン
- `scripts/effects/tracer_effect.gd` - TracerEffectスクリプト
- `scenes/effects/tracer_effect.tscn` - TracerEffectシーン

---

## レーザーポインター

武器に装着されたレーザーサイト。

```gdscript
# レーザーのオン/オフをトグル
CharacterAPI.toggle_laser(character)

# レーザーの状態を直接設定
CharacterAPI.set_laser_active(character, true)
CharacterAPI.set_laser_active(character, false)
```

### 関連ファイル

- `scripts/effects/laser_pointer.gd` - レーザーポインター
- `scenes/effects/laser_pointer.tscn` - レーザーシーン

---

## IK調整

武器保持時の左手IKとエルボーポールの調整。

```gdscript
# エルボーポール位置を更新
CharacterAPI.update_elbow_pole_position(character, x, y, z)

# 左手IK位置を更新
CharacterAPI.update_left_hand_position(character, x, y, z)

# キャラクターIKオフセットを直接設定
CharacterAPI.set_character_ik_offset(character, hand_offset, elbow_offset)

# キャラクターリソースからIKオフセットを適用
CharacterAPI.apply_character_ik_from_resource(character, character_id)
```

---

## キャラクター作成・切替

CharacterAPIによるキャラクター作成とモデル切替。

```gdscript
# プリセットからキャラクター作成
var character = CharacterAPI.create_from_preset(
    CharacterRegistry.CharacterId.VANGUARD,
    WeaponRegistry.WeaponId.AK47
)

# カスタム設定でキャラクター作成
var character = CharacterAPI.create(
    character_id,
    model_path,
    weapon_id
)

# キャラクターモデルを切替
CharacterAPI.switch_character_model(character, "swat", weapon_id)

# アニメーションを別キャラクターからコピー
CharacterAPI.copy_animations_from(character, "vanguard")
```

### character_id によるアニメーション自動セットアップ

CharacterBaseに`character_id`を設定すると、`_ready()`時にアニメーションが自動セットアップされる。
これにより、手動で`CharacterAPI.setup_animations()`を呼ぶ必要がなくなり、T-ポーズ問題を防止できる。

```gdscript
# エクスポートプロパティ
@export var character_id: String = ""  # "vanguard", "phantom" など
```

**シーンファイルでの設定例:**
```ini
[node name="CharacterBody" type="CharacterBody3D" parent="."]
script = ExtResource("character_base")
team = 2
character_id = "phantom"
```

**動作:**
1. `character_id`が設定されている場合、`_ready()`で自動的に`CharacterAPI.setup_animations()`が呼ばれる
2. アニメーションがない場合、共有元（vanguard等）からコピーされる
3. 手動呼び出しは不要

**利点:**
- 実行順序を気にする必要がない
- 名前ベースの脆弱な判定が不要
- シーンファイルで宣言的に設定できる

---

## FogOfWarSystem

視界に基づく霧システム。視界外を霧で覆い隠す。複数キャラクターの視界統合に対応。

```gdscript
# FogOfWarSystemを作成
var fog_system = FogOfWarSystem.new()
add_child(fog_system)

# キャラクターの視界を登録（複数登録可能）
fog_system.register_vision(character1.vision)
fog_system.register_vision(character2.vision)
# → 両キャラクターの視界が統合されて表示

# 視界登録を解除
fog_system.unregister_vision(character.vision)

# 可視性テクスチャを取得（シェーダー用）
var texture = fog_system.get_visibility_texture()
```

### 複数視界の統合

複数の`VisionComponent`を登録すると、各視界ポリゴンが自動的に統合描画される。
チーム全員の視界を合成した「共有視界」を実現可能。

```gdscript
# チーム全員の視界を登録
for character in team_characters:
    if character.vision:
        fog_system.register_vision(character.vision)
```

### エクスポート設定

| パラメータ | 型 | デフォルト | 説明 |
|------------|------|------------|------|
| map_size | Vector2 | (40, 40) | マップサイズ |
| fog_height | float | 0.02 | 霧の高さ |
| fog_color | Color | (0.1, 0.15, 0.25, 0.85) | 霧の色 |
| texture_resolution | int | 512 | 可視性テクスチャ解像度 |

### 関連ファイル

- `scripts/systems/fog_of_war_system.gd` - FogOfWarシステム
- `scripts/characters/components/vision_component.gd` - 視界コンポーネント

---

## レジストリ

キャラクターと武器のリソース管理。

### CharacterRegistry

```gdscript
# キャラクターリソースを取得
var resource = CharacterRegistry.get_character("vanguard")

# キャラクターIDから列挙値を取得
var id = CharacterRegistry.CharacterId.VANGUARD
```

### WeaponRegistry

```gdscript
# 武器リソースを取得
var resource = WeaponRegistry.get_weapon(WeaponRegistry.WeaponId.AK47)

# 武器シーンをロード
var scene = WeaponRegistry.get_weapon_scene(WeaponRegistry.WeaponId.AK47)
```

### 関連ファイル

- `scripts/registries/character_registry.gd` - キャラクターレジストリ
- `scripts/registries/weapon_registry.gd` - 武器レジストリ
- `scripts/resources/character_resource.gd` - キャラクターリソース
- `scripts/resources/weapon_resource.gd` - 武器リソース

## アニメーション

```gdscript
# アニメーションを再生
character.play_animation(anim_name: String, blend_time: float = 0.3)

# 射撃状態を設定
character.set_shooting(shooting: bool)

# 上半身回転を設定（ヨー + ピッチ）
character.set_upper_body_rotation(yaw_degrees: float, pitch_degrees: float = 0.0)

# アニメーションリストを取得
var list: PackedStringArray = character.get_animation_list()
```

### 移動アニメーション遷移

移動状態（idle/walk/run）の切り替えは `AnimationNodeTransition` によるクロスフェードで滑らかに遷移する。

| 定数 | 値 | 説明 |
|------|-----|------|
| LOCOMOTION_XFADE_TIME | 0.2 | 移動アニメーション遷移のクロスフェード時間（秒） |

遷移は `locomotion_changed` シグナル経由で自動発火するため、WASD入力・ドロワーパス移動の両方で同じクロスフェードが適用される。

## チーム

キャラクターのチーム所属とチーム判定。射撃時のダメージ判定に使用。

### Team Enum

| 値 | 定数 | 説明 |
|----|------|------|
| 0 | NONE | チームなし（中立） |
| 1 | COUNTER_TERRORIST | カウンターテロリストチーム |
| 2 | TERRORIST | テロリストチーム |

### CharacterBase API

```gdscript
# エクスポートプロパティとして設定
@export var team: Team = Team.NONE

# 対象が敵チームかどうか判定
var is_enemy: bool = character.is_enemy_of(other_character)
```

### 使用例

```gdscript
# チーム設定
character1.team = CharacterBase.Team.COUNTER_TERRORIST
character2.team = CharacterBase.Team.TERRORIST

# 敵判定（射撃時に自動で使用される）
if character1.is_enemy_of(character2):
    # character2 は敵 → ダメージを与える
```

---

## PlayerManager

プレイヤーの操作チームを一元管理するAutoloadシングルトン。
チーム切替が1行で完了し、全システム（視界、選択、FoW等）に自動反映される。

### 基本API

```gdscript
# 操作チームを設定（デフォルト: TERRORIST）
PlayerManager.player_team = CharacterBase.Team.TERRORIST
PlayerManager.player_team = CharacterBase.Team.COUNTER_TERRORIST

# 指定チームがプレイヤーチームかどうか
var is_mine: bool = PlayerManager.is_player_team(character.team)

# 指定チームが敵チームかどうか
var is_enemy: bool = PlayerManager.is_enemy_team(character.team)
```

### 使用例

```gdscript
# チームを切り替える（これだけで全システムに反映）
PlayerManager.player_team = CharacterBase.Team.COUNTER_TERRORIST

# キャラクター選択時に敵をブロック
if PlayerManager.is_enemy_team(character.team):
    return  # 選択不可

# FoW視界登録をプレイヤーチームのみに限定
if PlayerManager.is_player_team(character.team):
    fog_system.register_vision(character.vision)
```

### 影響範囲

PlayerManagerを参照しているシステム:

| システム | 用途 |
|----------|------|
| CharacterBase | 敵の可視性更新判定 |
| CharacterInteractionManager | 敵チーム選択ブロック |
| FogOfWarSystem | プレイヤーチームのみ視界登録 |
| テストシーン | 操作対象キャラクター決定 |

### 関連ファイル

- `scripts/managers/player_manager.gd` - PlayerManagerシングルトン
- `project.godot` - Autoload登録

---

## HP

```gdscript
# ダメージを受ける
character.take_damage(amount: float, attacker: Node3D = null, is_headshot: bool = false)

# 回復
character.heal(amount: float)

# HP割合を取得 (0.0〜1.0)
var ratio: float = character.get_health_ratio()

# HPを取得
var hp: float = character.get_health()
```

### 死亡時の動作

HP が 0 以下になると `died` シグナルが発火し、以下の処理が自動実行される:

1. **移動停止**: `movement.stop()`
2. **IK無効化**: `weapon.disable_ik()`
3. **視界(FoW)無効化**: `vision.disable()` - 視界ポリゴンがクリアされる
4. **コライダー無効化**: `CollisionShape3D.disabled = true` - 弾が貫通するようになる
5. **死亡アニメーション再生**: `rifle_death` 等の武器タイプに応じたアニメーション

```gdscript
# 死亡シグナルをハンドリング
character.died.connect(_on_character_died)

func _on_character_died(killer: Node3D) -> void:
    print("キャラクターが死亡しました")
    # 死亡処理（スコア加算など）
```

## アクション

```gdscript
# アクションを開始
character.start_action(action_type: int, duration: float)

# アクションをキャンセル
character.cancel_action()

# アクション中かどうか
var in_action: bool = character.is_in_action()
```

## 自動照準（Auto Aim）

敵が視界内に入ると、上半身が自動的に敵の方向を向く機能。

### エクスポート設定

```gdscript
@export var auto_aim_enabled: bool = true  # 自動照準の有効/無効
```

### 動作仕様

1. **敵検出**: 視界内で最も近い敵キャラクターをターゲット
2. **ヨー（水平）照準**: 上半身を左右に回転（±45度制限）
3. **ピッチ（垂直）照準**: 上半身を上下に傾け、銃口を敵に向ける（±30度制限）

### ターゲット位置

銃口から敵の腹部（`global_position + 0.7m`）への方向ベクトルを計算し、照準角度を決定。

### 関連API

```gdscript
# 上半身回転を手動で設定（自動照準無効時に使用）
character.set_upper_body_rotation(yaw_degrees: float, pitch_degrees: float = 0.0)

# AnimationComponent経由
character.animation.apply_spine_rotation(yaw_degrees: float, pitch_degrees: float = 0.0)
```

### AnimationComponent設定

| パラメータ | 型 | デフォルト | 説明 |
|------------|------|------------|------|
| aim_rotation_speed | float | 10.0 | 照準補間速度 |
| aim_max_angle_deg | float | 90.0 | 最大ヨー角度 |
| aim_max_pitch_deg | float | 30.0 | 最大ピッチ角度 |

### 関連ファイル

- `scripts/characters/character_base.gd` - 自動照準ロジック（`_update_auto_aim()`）
- `scripts/characters/components/animation_component.gd` - 上半身回転補間
- `scripts/utils/upper_body_rotation_modifier.gd` - スケルトンボーン回転

---

## 視界

```gdscript
# 視野角を設定
character.set_vision_fov(degrees: float)

# 視界距離を設定
character.set_vision_distance(distance: float)

# 視界ポリゴンを取得
var polygon: PackedVector3Array = character.get_vision_polygon()

# 壁ヒットポイントを取得
var hits: PackedVector3Array = character.get_wall_hit_points()

# 視界を無効化（死亡時に自動呼び出し）
character.vision.disable()

# 視界を有効化
character.vision.enable()
```

### VisionComponent API

```gdscript
# 視界を無効化
# - 更新処理を停止
# - 視界ポリゴンをクリア
# - vision_updated/wall_hit_updated シグナルで空配列を通知
func disable() -> void

# 視界を有効化
# - 更新処理を再開
# - 即座に視界を再計算
func enable() -> void

# 即座に視界を更新
func force_update() -> void
```

## シグナル

### CharacterBase シグナル

```gdscript
signal path_completed
signal waypoint_reached(index: int)
signal died(killer: Node3D)
signal damaged(amount: float, attacker: Node3D, is_headshot: bool)
signal weapon_changed(weapon_id: int)
signal locomotion_changed(state: int)
signal action_started(action_type: int)
signal action_completed(action_type: int)
```

### WeaponComponent シグナル

```gdscript
# ヒット検出時に発火
signal hit_detected(target: Node3D, hit_point: Vector3, is_headshot: bool)
```

### AnimationComponent シグナル

```gdscript
# 死亡アニメーション完了時に発火
signal death_animation_finished
```

### VisionComponent シグナル

```gdscript
# 視界更新時に発火
signal vision_updated(visible_points: PackedVector3Array)
signal wall_hit_updated(hit_points: PackedVector3Array)
```
