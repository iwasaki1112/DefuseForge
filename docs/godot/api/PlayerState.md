# PlayerState

プレイヤー状態管理（Autoload）。プレイヤーが属するチームを管理し、味方/敵の分類機能を提供。お金（資金）管理機能も含む。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/systems/player_state.gd` |
| Autoload名 | `PlayerState` |

## Constants

| 定数 | 値 | 説明 |
|------|-----|------|
| `INITIAL_MONEY` | `800` | 初期資金（ゲーム開始時） |

## Signals

### team_changed(new_team: GameCharacter.Team)
プレイヤーのチームが変更されたときに発火。

**引数:**
- `new_team` - 新しいチーム

### money_changed(new_amount: int)
所持金が変更されたときに発火。

**引数:**
- `new_amount` - 新しい所持金

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

### get_money() -> int
現在の所持金を取得。

**戻り値:** 所持金

### set_money(amount: int) -> void
所持金を直接設定。負の値は0にクランプされる。

**引数:**
- `amount` - 設定する金額

### add_money(amount: int) -> void
所持金を追加（ラウンド報酬、キル報酬など）。

**引数:**
- `amount` - 追加する金額（0以下は無視）

### spend_money(amount: int) -> bool
所持金を使用。残高不足の場合は失敗。

**引数:**
- `amount` - 使用する金額

**戻り値:** 成功なら `true`、残高不足なら `false`

### can_afford(amount: int) -> bool
指定金額を支払えるか確認。

**引数:**
- `amount` - 確認する金額

**戻り値:** 支払い可能なら `true`

### reset_money() -> void
所持金を初期資金（`INITIAL_MONEY`）にリセット。

### add_round_reward(won: bool, loss_streak: int = 0) -> void
ラウンド報酬を付与。

**引数:**
- `won` - 勝利したかどうか
- `loss_streak` - 連敗数（敗北時のボーナス計算用）

**報酬額:**
| 条件 | 報酬 |
|------|------|
| 勝利 | $3,250 |
| 敗北（連敗0回） | $1,400 |
| 敗北（連敗1回） | $1,900 |
| 敗北（連敗2回） | $2,400 |
| 敗北（連敗3回） | $2,900 |
| 敗北（連敗4回以上） | $3,400 |

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

# ============================================
# お金管理
# ============================================

# ゲーム開始時に初期資金にリセット
PlayerState.reset_money()

# 所持金確認
var current_money = PlayerState.get_money()
print("Current money: $%d" % current_money)

# 武器購入（残高チェック付き）
var weapon_cost = 2700
if PlayerState.can_afford(weapon_cost):
    if PlayerState.spend_money(weapon_cost):
        print("Weapon purchased!")

# ラウンド終了時の報酬
PlayerState.add_round_reward(true)  # 勝利報酬: $3,250
PlayerState.add_round_reward(false, 2)  # 敗北報酬（連敗2回）: $2,400

# 所持金変更を監視（UI更新用）
PlayerState.money_changed.connect(_on_money_changed)

func _on_money_changed(new_amount: int) -> void:
    money_label.text = "$%d" % new_amount
```

## 設計意図

- **グローバルアクセス**: Autoloadなのでどのスクリプトからでもアクセス可能
- **シグナル駆動**: チーム変更・所持金変更時に各システムが自動的に反応可能
- **分類ロジックの集約**: 味方/敵判定を一箇所に集約してコードの重複を防止
- **お金管理**: CS:GOスタイルのラウンド報酬システム（連敗ボーナス対応）

## APIリファレンス

### シグナル
| シグナル | 引数 |
|---------|------|
| `team_changed` | `new_team: GameCharacter.Team` |
| `money_changed` | `new_amount: int` |

### メソッド
- `get_player_team() -> GameCharacter.Team`
- `set_player_team(team: GameCharacter.Team) -> void`
- `get_team_name(team: GameCharacter.Team = _player_team) -> String`
- `is_friendly(character: Node) -> bool`
- `is_enemy(character: Node) -> bool`
- `filter_friendlies(characters: Array) -> Array[Node]`
- `filter_enemies(characters: Array) -> Array[Node]`
- `get_money() -> int`
- `set_money(amount: int) -> void`
- `add_money(amount: int) -> void`
- `spend_money(amount: int) -> bool`
- `can_afford(amount: int) -> bool`
- `reset_money() -> void`
- `add_round_reward(won: bool, loss_streak: int = 0) -> void`
