# WeaponShopModal

武器購入モーダルUIコンポーネント。WeaponRegistryから武器一覧を表示し、購入してキャラクターに装備する。

## 概要

- **クラス名**: `WeaponShopModal`
- **継承**: `Control`
- **ファイル**: `godot/scripts/ui/weapon_shop_modal.gd`

## シグナル

| シグナル | 引数 | 説明 |
|---------|------|------|
| `weapon_purchased` | `weapon: WeaponPreset, character: CharacterBody3D` | 武器購入完了時 |
| `closed` | なし | モーダル閉じ完了時 |

## 主要API

### open(character: CharacterBody3D) -> void

モーダルを開く。指定したキャラクターに対して武器購入を行う。

```gdscript
weapon_shop_modal.open(selected_character)
```

### close() -> void

モーダルを閉じる。アニメーション付きで非表示にする。

```gdscript
weapon_shop_modal.close()
```

### is_open() -> bool

モーダルが開いているかを返す。

```gdscript
if weapon_shop_modal.is_open():
    print("Shop is open")
```

## UI構造

```
WeaponShopModal (Control)
├── ColorRect (半透明背景オーバーレイ)
└── PanelContainer (中央モーダル 400x500px)
    └── MarginContainer
        └── VBoxContainer
            ├── HBoxContainer (ヘッダー)
            │   ├── Label "BUY WEAPONS"
            │   └── Label "$xxx" (所持金)
            ├── HSeparator
            ├── ScrollContainer
            │   └── VBoxContainer (武器リスト)
            │       └── Button[] (各武器: 名前 - $価格)
            └── HBoxContainer (フッター)
                ├── Button "Close"
                └── Button "Buy ($xxx)"
```

## 機能詳細

### 武器リスト表示

- `WeaponRegistry.get_all()` から全武器を取得
- 各武器に名前と価格を表示
- 購入不可（所持金不足）の武器はグレーアウト + disabled

### リアルタイム更新

- `PlayerState.money_changed` シグナルを監視
- 所持金変更時に以下を自動更新:
  - 所持金表示
  - 武器リスト（購入可否の再計算）
  - Buyボタン状態

### 購入処理フロー

1. 武器をタップして選択（青色ハイライト）
2. Buyボタンをタップ
3. `PlayerState.spend_money(price)` で支払い
4. `character.equip_weapon(weapon)` で装備
5. `weapon_purchased` シグナル発火
6. モーダル自動クローズ

### 閉じる操作

- Closeボタンタップ
- モーダル外（オーバーレイ部分）タップ

## 使用例

### GameManagerでの統合

```gdscript
# セットアップ
func _setup_weapon_shop_modal() -> void:
    weapon_shop_modal = Control.new()
    weapon_shop_modal.set_script(WeaponShopModalScript)
    weapon_shop_modal.name = GameConstants.NODE_WEAPON_SHOP_MODAL
    _ui_layer.add_child(weapon_shop_modal)
    weapon_shop_modal.weapon_purchased.connect(_on_weapon_purchased)

# 開く
func _open_weapon_shop(character: CharacterBody3D) -> void:
    if weapon_shop_modal:
        weapon_shop_modal.open(character)

# 購入完了ハンドラ
func _on_weapon_purchased(weapon: WeaponPreset, character: CharacterBody3D) -> void:
    print("Purchased: %s for %s" % [weapon.display_name, character.name])
```

## 関連クラス

- **WeaponRegistry**: 武器プリセット一覧の取得
- **WeaponPreset**: 武器定義（ID、名前、価格、モデル等）
- **PlayerState**: 所持金管理（can_afford, spend_money）
- **GameCharacter**: 武器装備（equip_weapon）
- **GameManager**: モーダル統合・コンテキストメニュー連携
