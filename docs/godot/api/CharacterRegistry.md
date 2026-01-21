# CharacterRegistry

キャラクタープリセットを管理するシングルトン。Autoloadとして使用。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/registries/character_registry.gd` |
| 使用方法 | Autoload（`CharacterRegistry`） |

## 定数

| 定数 | 値 | 説明 |
|------|-----|------|
| `ANIMATION_SOURCE` | `"res://assets/animations/character_anims.glb"` | 共有アニメーションライブラリ |
| `PRESET_DIR` | `"res://data/characters/"` | プリセットディレクトリ |

## Public API

### Registration API

#### register(preset: CharacterPreset) -> void
プリセットを登録する。

**引数:**
- `preset` - CharacterPresetリソース

#### unregister(id: String) -> void
プリセットを登録解除する。

**引数:**
- `id` - プリセットID

### Query API

#### get_preset(id: String) -> CharacterPreset
IDでプリセットを取得する。

**引数:**
- `id` - プリセットID

**戻り値:** CharacterPresetまたは`null`

#### has_preset(id: String) -> bool
プリセットが存在するか確認する。

#### get_all() -> Array
全プリセットを取得する。

#### get_by_team(team: GameCharacter.Team) -> Array
チーム別プリセットを取得する。

#### get_terrorists() -> Array
テロリストプリセットを取得する。

#### get_counter_terrorists() -> Array
対テロリストプリセットを取得する。

### Factory API

#### create_character(preset_id: String, position: Vector3 = Vector3.ZERO) -> Node
プリセットIDからGameCharacterインスタンスを作成する。

**引数:**
- `preset_id` - プリセットID
- `position` - 初期位置

**戻り値:** GameCharacterノードまたは`null`

#### create_character_from_preset(preset: CharacterPreset, position: Vector3 = Vector3.ZERO) -> Node
プリセットオブジェクトからGameCharacterインスタンスを作成する。

**引数:**
- `preset` - CharacterPresetリソース
- `position` - 初期位置

**戻り値:** GameCharacterノードまたは`null`

## 使用例

```gdscript
# プリセット取得
var preset = CharacterRegistry.get_preset("bomber")
if preset:
    print(preset.display_name)

# チーム別取得
var cts = CharacterRegistry.get_counter_terrorists()
for ct in cts:
    print(ct.id)

# キャラクター作成
var character = CharacterRegistry.create_character("breacher", Vector3(5, 0, 0))
if character:
    add_child(character)
```

## ライフサイクル

1. `_ready()`:
   - チーム配列初期化
   - アニメーションライブラリ読み込み（GLBから抽出）
   - `PRESET_DIR`から`.tres`ファイルを自動読み込み

## キャラクター作成時の処理

1. プリセットの`model_scene`をインスタンス化
2. `GameCharacter`を作成し、モデルを子として追加
3. `CollisionShape3D`（カプセル）を追加
4. `AnimationPlayer`に共有アニメーションライブラリを設定
5. `CharacterAnimationController`を追加・セットアップ

## プリセットファイル配置

```
data/characters/
├── bomber.tres
├── breacher.tres
└── ...
```
