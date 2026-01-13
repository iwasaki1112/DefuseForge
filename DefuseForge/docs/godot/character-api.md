# CharacterAPI リファレンス

キャラクター操作の統一API。CharacterBaseインスタンスの生成、配置、アニメーション、武器、IK操作を提供。

## 基本的な使い方

```gdscript
const CharacterAPI = preload("res://scripts/api/character_api.gd")

# アニメーション再生
CharacterAPI.play_animation(character, "idle", 0.3)

# キャラクター切り替え
CharacterAPI.switch_character_model(character, "shade")
```

## Animation API

### get_available_animations
```gdscript
static func get_available_animations(character: CharacterBase, filtered: bool = true) -> Array[String]
```
利用可能なアニメーション一覧を取得。`filtered=true`で優先アニメーションのみ返す。

### play_animation
```gdscript
static func play_animation(character: CharacterBase, animation_name: String, blend_time: float = 0.3) -> void
```
アニメーションを再生。

### setup_animations
```gdscript
static func setup_animations(character: CharacterBase, character_id: String) -> void
```
キャラクターIDに基づいてアニメーションを自動セットアップ。アニメーション共有（shade/phantom→vanguard）を自動処理。

### copy_animations_from
```gdscript
static func copy_animations_from(character: CharacterBase, source_character_id: String) -> void
```
別キャラクターからアニメーションをコピー。同じARPリグを使用するキャラクター間で使用。

## Model Switching API

### switch_character_model
```gdscript
static func switch_character_model(
    character: CharacterBase,
    character_id: String,
    weapon_id: int = -1
) -> bool
```
キャラクターモデルを切り替える。以下を自動処理:
1. 古いモデル削除
2. 新モデル読み込み
3. コンポーネント再初期化（`reload_model()`）
4. アニメーションセットアップ
5. 武器再装備
6. キャラクター固有IKオフセット適用

**パラメータ:**
- `character`: 対象CharacterBase
- `character_id`: "vanguard", "shade", "phantom"等
- `weapon_id`: 切り替え後の武器ID（-1で現在の武器を維持）

**使用例:**
```gdscript
# 武器を維持してキャラクター切り替え
CharacterAPI.switch_character_model(player, "shade")

# 武器も指定して切り替え
CharacterAPI.switch_character_model(player, "phantom", WeaponRegistry.WeaponId.M4A1)
```

## Weapon IK Tuning API

武器のIK（左手）を調整するAPI。主にデバッグ・チューニング用。

### update_elbow_pole_position
```gdscript
static func update_elbow_pole_position(character: CharacterBase, x: float, y: float, z: float) -> void
```
肘ポール位置を更新。IKの肘の曲がり方向を制御。

### update_left_hand_position
```gdscript
static func update_left_hand_position(character: CharacterBase, x: float, y: float, z: float) -> void
```
左手IKターゲット位置を更新。

### set_character_ik_offset
```gdscript
static func set_character_ik_offset(character: CharacterBase, hand_offset: Vector3, elbow_offset: Vector3) -> void
```
キャラクター固有のIKオフセットを設定。腕の長さが異なるキャラクター間での補正に使用。

### apply_character_ik_from_resource
```gdscript
static func apply_character_ik_from_resource(character: CharacterBase, character_id: String) -> void
```
CharacterResourceからIKオフセットを自動適用。`switch_character_model`内部で自動呼び出しされる。

## Laser Pointer API

### toggle_laser
```gdscript
static func toggle_laser(character: CharacterBase) -> void
```
レーザーポインターをトグル。

### set_laser_active
```gdscript
static func set_laser_active(character: CharacterBase, active: bool) -> void
```
レーザーポインターの状態を明示的に設定。

## アニメーション共有マッピング

`ANIMATION_SOURCE`定数で定義。同じARPリグを使用するキャラクター間でアニメーションを共有:

```gdscript
const ANIMATION_SOURCE := {
    "shade": "vanguard",    # shadeはvanguardのアニメーションを使用
    "phantom": "vanguard"   # phantomもvanguardのアニメーションを使用
}
```

新しいキャラクターを追加する場合、ここにマッピングを追加。

## CharacterBaseの関連メソッド

CharacterAPIは内部でCharacterBaseのメソッドを呼び出す:

### reload_model
```gdscript
func reload_model(new_model: Node3D = null) -> void
```
モデルをリロードし、全コンポーネントを再初期化。モデル入れ替え後に呼び出す。

```gdscript
# 低レベル操作（通常はswitch_character_modelを使用）
var new_model = load("res://path/to/model.glb").instantiate()
character.add_child(new_model)
character.reload_model(new_model)
```

## 設計原則

1. **CharacterAPIを経由**: 直接`character.weapon.xxx()`を呼ばず、CharacterAPIを使用
2. **nullチェック内蔵**: すべてのAPIメソッドはnullチェックを行い、警告を出力
3. **静的メソッド**: すべてのAPIは`static func`で、第一引数にcharacterを取る
