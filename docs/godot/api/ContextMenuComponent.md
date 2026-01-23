# ContextMenuComponent

コンテキストメニューUIコンポーネント。キャラクタータップ時にメニューを表示し、操作を選択させる。モバイル/PC両対応。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Control` |
| ファイルパス | `scripts/ui/context_menu_component.gd` |
| シーンパス | `scenes/ui/context_menu_component.tscn` |

## Signals

| シグナル | 引数 | 説明 |
|---------|------|------|
| `item_selected` | `action_id: String, character: CharacterBody3D` | メニュー項目選択時 |

## 定数

### DEFAULT_MENU_ITEMS
標準メニュー項目の定義（単一選択時用）。

```gdscript
const DEFAULT_MENU_ITEMS: Array[Dictionary] = [
    {"id": "move", "name": "Move", "order": 0},
    {"id": "rotate", "name": "Rotate", "order": 1},
    {"id": "crouch", "name": "Crouch", "order": 2},
    {"id": "buy", "name": "Buy", "order": 3},
]
```

**複数選択時:**
`setup_multi_select_items()`によりMOVEのみ表示される。

## Export Properties

### 外観設定
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `button_size` | `Vector2` | `(120, 50)` | ボタンサイズ |
| `font_size` | `int` | `16` | フォントサイズ |
| `show_button_text` | `bool` | `true` | ボタンのテキスト表示 |

### ラジアル配置
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `radial_radius` | `float` | `120.0` | 中心からボタン中心までの距離 |
| `radial_start_angle_degrees` | `float` | `-90.0` | 最初のボタン角度（度） |
| `radial_padding` | `float` | `8.0` | 画面端マージン |
| `use_background_texture_layout` | `bool` | `false` | 背景テクスチャ前提の配置を使用 |
| `background_texture` | `Texture2D` | - | 背景テクスチャ（4分割固定向け） |
| `background_scale` | `float` | `1.0` | 背景テクスチャのスケール |
| `background_radial_radius_ratio` | `float` | `0.34` | 背景サイズからのラジアル半径比率 |

### セグメント画像
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `use_segment_textures` | `bool` | `false` | セグメント画像を使う |
| `segment_move_texture` | `Texture2D` | - | Move用セグメント |
| `segment_rotation_texture` | `Texture2D` | - | Rotate用セグメント |
| `segment_buy_texture` | `Texture2D` | - | Buy用セグメント |
| `segment_crouch_texture` | `Texture2D` | - | Crouch用セグメント |
| `segment_move_rotation_degrees` | `float` | `0.0` | Moveセグメントの回転 |
| `segment_rotation_rotation_degrees` | `float` | `90.0` | Rotateセグメントの回転 |
| `segment_buy_rotation_degrees` | `float` | `180.0` | Buyセグメントの回転 |
| `segment_crouch_rotation_degrees` | `float` | `270.0` | Crouchセグメントの回転 |
| `segment_scale` | `float` | `1.0` | セグメントのスケール |
| `segment_pivot_offset` | `Vector2` | `(256, 256)` | セグメント回転中心 |

### アニメーション
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `animation_duration` | `float` | `0.15` | 表示/非表示アニメーション時間 |
| `item_animation_duration` | `float` | `0.18` | 各ボタンの表示アニメーション時間 |
| `item_stagger_delay` | `float` | `0.06` | ボタン表示の遅延間隔 |
| `item_scale_start` | `float` | `0.6` | 表示開始時スケール |
| `item_scale_peak` | `float` | `1.06` | ふわっと膨らむピーク |
| `item_scale_end` | `float` | `1.0` | 最終スケール |

## Public API

### Menu Control

#### open(screen_position: Vector2, character: CharacterBody3D, is_multi_select: bool = false) -> void
メニューを開く。

**引数:**
- `screen_position` - 画面上の表示位置
- `character` - 対象キャラクター
- `is_multi_select` - 複数キャラクター選択時はtrue（MOVEのみ表示）

#### close() -> void
メニューを閉じる。

#### is_open() -> bool
メニューが開いているか確認する。

#### get_current_character() -> CharacterBody3D
現在のキャラクターを取得する。

#### update_screen_position(screen_position: Vector2) -> void
メニュー位置を更新する（カメラ移動時などに追従させる）。

### Item Management

#### add_item(item: ContextMenuItem) -> void
メニュー項目を追加する（order順にソートされる）。

**引数:**
- `item` - ContextMenuItemリソース

#### remove_item(action_id: String) -> void
メニュー項目を削除する。

#### set_item_enabled(action_id: String, enabled: bool) -> void
メニュー項目の有効/無効を設定する。

#### clear_items() -> void
全メニュー項目をクリアする。

#### setup_default_items() -> void
標準メニュー項目をセットアップする（Move, Rotate, Crouch）。

#### setup_multi_select_items() -> void
複数選択時用のメニュー項目をセットアップする（MOVEのみ）。

## 使用例

```gdscript
# CanvasLayerの子として追加
var context_menu = Control.new()
context_menu.set_script(preload("res://scripts/ui/context_menu_component.gd"))
ui_layer.add_child(context_menu)

# 標準項目をセットアップ
context_menu.setup_default_items()

# シグナル接続
context_menu.item_selected.connect(_on_menu_item_selected)

# メニューを開く（単一選択時）
context_menu.open(screen_position, character)

# 複数選択時はis_multi_select=trueでMOVEのみ表示
var is_multi = selection_manager.get_selection_count() > 1
context_menu.open(screen_position, character, is_multi)

# カスタム項目追加
var item = ContextMenuItem.create("fire", "Fire", 3)
context_menu.add_item(item)

# シグナルハンドラ
func _on_menu_item_selected(action_id: String, character: CharacterBody3D):
    match action_id:
        "move":
            start_move_mode(character)
        "rotate":
            start_rotate_mode(character)
```

## 内部動作

### UI構成
- `Control`（メニュー用ルート） > `Button[]`（円周配置）
- セグメント画像の場合は `click_mask` を設定してアルファ領域のみ反応

### 表示アニメーション
- フェードイン + スケールアップ（0.9 → 1.0）
- Tweenで制御（`animation_duration`秒）
- ボタンは順番にフェードイン + ふわっと拡大して戻る（`item_stagger_delay`秒間隔）

### 画面端クリッピング対策
- メニュー中心を基準にメニュー矩形を生成し、画面端にはみ出さないようにクランプ
- `radial_padding`で端の余白を調整

### メニュー外クリック検出
- `_gui_input`でパネル外クリックを検出して自動で閉じる

### エディタプレビュー
- `@tool` + `Engine.is_editor_hint()` の場合はデフォルト項目で描画して表示する
- プロパティ変更時は自動でプレビューを再構築する

## APIリファレンス

### シグナル
| シグナル | 引数 |
|---------|------|
| `item_selected` | `action_id: String, character: CharacterBody3D` |
| `background_clicked` | `character: CharacterBody3D` |

### メソッド
- `open(screen_position: Vector2, character: CharacterBody3D, is_multi_select: bool = false) -> void`
- `close() -> void`
- `add_item(item: Resource) -> void`
- `remove_item(action_id: String) -> void`
- `set_item_enabled(action_id: String, enabled: bool) -> void`
- `set_item_display_name(action_id: String, display_name: String) -> void`
- `clear_items() -> void`
- `setup_default_items() -> void`
- `setup_multi_select_items() -> void`
- `is_open() -> bool`
- `get_current_character() -> CharacterBody3D`
- `get_panel_rect() -> Rect2`
- `update_screen_position(screen_position: Vector2) -> void`
