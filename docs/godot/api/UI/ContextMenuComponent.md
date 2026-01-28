# ContextMenuComponent

コンテキストメニューUIコンポーネント。キャラクタータップ時にメニューを表示し、操作を選択させる。モバイル/PC両対応。
通常のボタン配置に加え、画像を使用した円形（セグメント）メニューにも対応している。

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
| `background_clicked` | `character: CharacterBody3D` | メニュー外（背景）クリック時 |

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

## Export Properties

### 外観設定
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `button_size` | `Vector2` | `(120, 50)` | ボタンサイズ（通常モード時） |
| `font_size` | `int` | `16` | フォントサイズ |
| `show_button_text` | `bool` | `true` | ボタンのテキスト表示 |

### ラジアル配置 (通常モード)
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `radial_radius` | `float` | `120.0` | 中心からボタン中心までの距離 |
| `radial_start_angle_degrees` | `float` | `-90.0` | 最初のボタン角度（度） |
| `radial_padding` | `float` | `8.0` | 画面端マージン |
| `use_background_texture_layout` | `bool` | `false` | 背景テクスチャサイズに基づいた配置を使用 |
| `background_texture` | `Texture2D` | - | 背景テクスチャ |
| `background_scale` | `float` | `1.0` | 背景テクスチャのスケール |
| `background_radial_radius_ratio` | `float` | `0.34` | 背景サイズに対するボタン配置半径の比率 |

### セグメント画像 (画像メニューモード)
`use_segment_textures` を有効にすると、分割された画像を用いたメニューになります。

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `use_segment_textures` | `bool` | `false` | セグメント画像モードを使用 |
| `segment_*_texture` | `Texture2D` | - | 各アクション（move, rotation, buy, crouch）の画像 |
| `segment_*_rotation_degrees` | `float` | 各自 | 各画像の回転角度 |
| `segment_scale` | `float` | `1.0` | セグメントのスケール |
| `segment_pivot_offset` | `Vector2` | `(256, 256)` | セグメント画像の回転中心ピクセル |

### アニメーション
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `animation_duration` | `float` | `0.15` | メニュー全体の表示/非表示時間 |
| `item_animation_duration` | `float` | `0.18` | 各アイテムのポップアップ時間 |
| `item_stagger_delay` | `float` | `0.06` | アイテム表示の遅延間隔 |
| `item_scale_start` | `float` | `0.6` | 表示開始時スケール |
| `item_scale_peak` | `float` | `1.06` | バウンスピークスケール |
| `item_scale_end` | `float` | `1.0` | 最終スケール |

## Public API

### Menu Control

#### `open(screen_position: Vector2, character: CharacterBody3D) -> void`
メニューを指定位置に開き、アニメーション再生する。

#### `close() -> void`
メニューを閉じる。

#### `is_open() -> bool`
メニューが開いているか確認する。

#### `update_screen_position(screen_position: Vector2) -> void`
メニュー位置を更新する（追従用）。画面端でのクリッピング補正も行われる。

### Item Management

#### `add_item(item: Resource) -> void`
#### `remove_item(action_id: String) -> void`
#### `set_item_enabled(action_id: String, enabled: bool) -> void`
#### `set_item_display_name(action_id: String, display_name: String) -> void`
#### `clear_items() -> void`
#### `setup_default_items() -> void`

## 内部動作

### セグメントクリック判定 (`_gui_input`, `_get_segment_at_angle`)
セグメント画像モード時、四角形のボタン領域ではなく、**画像のアルファ値（不透明度）** に基づいてクリック判定を行う。
これにより、円形や扇形の複雑な形状のボタンでも、見た目通りにクリック判定ができる。
クリック位置を逆回転・スケール変換してテクスチャ座標に戻し、ピクセル色を取得して判定している。

### エディタプレビュー (`@tool`)
エディタ上でもプロパティ変更時にリアルタイムでプレビューが表示される（`_queue_editor_refresh`）。