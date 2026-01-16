# PlayerState

プレイヤー状態管理（Autoload）。プレイヤーが属するチームを管理し、味方/敵の分類機能を提供。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/systems/player_state.gd` |
| Autoload名 | `PlayerState` |

## Signals

### team_changed(new_team: GameCharacter.Team)
プレイヤーのチームが変更されたときに発火。

**引数:**
- `new_team` - 新しいチーム

## Public API

### get_player_team() -> GameCharacter.Team
プレイヤーの現在のチームを取得。

**戻り値:** `GameCharacter.Team.COUNTER_TERRORIST` または `GameCharacter.Team.TERRORIST`

### set_player_team(team: GameCharacter.Team) -> void
プレイヤーのチームを設定。変更があれば `team_changed` シグナルを発火。

**引数:**
- `team` - 設定するチーム

### get_team_name(team: GameCharacter.Team = current) -> String
チーム名を文字列で取得。

**引数:**
- `team` - チーム（省略時は現在のプレイヤーチーム）

**戻り値:** `"CT"`, `"T"`, または `"NONE"`

### is_friendly(character: Node) -> bool
キャラクターがプレイヤーの味方かどうか判定。

**引数:**
- `character` - 判定対象（GameCharacter）

**戻り値:** 同じチームなら `true`

### is_enemy(character: Node) -> bool
キャラクターがプレイヤーの敵かどうか判定。

**引数:**
- `character` - 判定対象（GameCharacter）

**戻り値:** 異なるチーム（かつNONE以外）なら `true`

### filter_friendlies(characters: Array) -> Array[Node]
配列から味方キャラクターのみを抽出。

**引数:**
- `characters` - キャラクター配列

**戻り値:** 味方キャラクターの配列

### filter_enemies(characters: Array) -> Array[Node]
配列から敵キャラクターのみを抽出。

**引数:**
- `characters` - キャラクター配列

**戻り値:** 敵キャラクターの配列

## 使用例

```gdscript
# チーム設定
PlayerState.set_player_team(GameCharacter.Team.TERRORIST)

# チーム取得
var team = PlayerState.get_player_team()
print("Current team: %s" % PlayerState.get_team_name())

# キャラクター分類
if PlayerState.is_enemy(target):
    # 敵の処理
    pass

# 味方のみ抽出
var friendlies = PlayerState.filter_friendlies(all_characters)
for ally in friendlies:
    ally.heal(10)

# チーム変更を監視
PlayerState.team_changed.connect(_on_team_changed)

func _on_team_changed(new_team: GameCharacter.Team) -> void:
    print("Team changed to: %s" % PlayerState.get_team_name(new_team))
```

## 設計意図

- **グローバルアクセス**: Autoloadなのでどのスクリプトからでもアクセス可能
- **シグナル駆動**: チーム変更時に各システムが自動的に反応可能
- **分類ロジックの集約**: 味方/敵判定を一箇所に集約してコードの重複を防止
