# FogOfWarSystem

Fog of Warシステム。SubViewportテクスチャ方式で可視領域を描画し、外部シェーダーでフォグを表示。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node3D` |
| ファイルパス | `scripts/systems/fog_of_war_system.gd` |
| シェーダー | `shaders/fow.gdshader` |

## Enums

### Quality
品質設定（VisionComponentと連動）。

| 値 | resolution | msaa | ray_count | update_hz | 説明 |
|----|-----------|------|-----------|-----------|------|
| `LOW` | 128 | DISABLED | 36 | 15 | モバイル向け |
| `MEDIUM` | 256 | 2X | 54 | 20 | バランス |
| `HIGH` | 512 | 4X | 72 | 30 | PC向け |

## Export Properties

### Map Settings
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `map_size` | `Vector2` | `(40, 40)` | マップサイズ |
| `fog_height` | `float` | `0.02` | フォグの高さ |

### Visual Settings
| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `fog_color` | `Color` | 暗青(0.85 alpha) | フォグの色 |
| `quality` | `Quality` | `LOW` | 品質設定（モバイル最適化） |

## Public API

### set_map_size(new_size: Vector2) -> void
マップサイズを動的に変更する。フォグメッシュとシェーダーパラメータを再設定。

**引数:**
- `new_size` - 新しいマップサイズ

**注意:** `map_size`プロパティを直接変更しても反映されない。必ずこのメソッドを使用すること。

### register_vision(vision: VisionComponent) -> void
VisionComponentを登録する。

**引数:**
- `vision` - VisionComponentインスタンス

### unregister_vision(vision: VisionComponent) -> void
VisionComponentを解除する。

**引数:**
- `vision` - VisionComponentインスタンス

### set_fog_visible(fog_visible: bool) -> void
フォグの表示/非表示を切り替える。

### set_fog_color(color: Color) -> void
フォグの色を設定する。

### get_visibility_texture() -> ViewportTexture
可視性テクスチャを取得する（壁の照明などに使用可能）。

**戻り値:** ViewportTextureまたは`null`

### force_update() -> void
強制的に可視性テクスチャを更新する。VisionComponentの再登録後などに使用。

### set_quality(q: Quality) -> void
品質プリセットを実行時に変更する。ビューポートサイズとシェーダーパラメータを更新。

**引数:**
- `q` - 品質レベル（LOW/MEDIUM/HIGH）

### get_quality_settings() -> Dictionary
現在の品質設定を辞書形式で取得する（VisionComponentとの同期用）。

**戻り値:** `resolution`, `msaa`, `ray_count`, `update_hz`を含む辞書

## 使用例

```gdscript
# FoWシステム作成
var fow = FogOfWarSystem.new()
fow.map_size = Vector2(50, 50)  # 初期化前なら直接設定可
fow.quality = FogOfWarSystem.Quality.LOW
add_child(fow)

# VisionComponent登録
var vision = character.setup_vision(90.0, 15.0)
fow.register_vision(vision)

# マップサイズを動的に変更（必ずset_map_size()を使用）
fow.set_map_size(Vector2(20, 20))

# 色変更
fow.set_fog_color(Color(0.1, 0.1, 0.2, 0.9))

# 品質変更
fow.set_quality(FogOfWarSystem.Quality.HIGH)

# 非表示
fow.set_fog_visible(false)
```

## 注意事項

### map_sizeの動的変更

**重要:** `_ready()`後に`map_size`プロパティを直接変更しても、フォグメッシュやシェーダーパラメータは更新されない。

```gdscript
# NG: 反映されない
fow.map_size = Vector2(20, 20)

# OK: メッシュとシェーダーも更新される
fow.set_map_size(Vector2(20, 20))
```

**症状:** 視界ポリゴンがキャラクターの足元から離れた位置に描画される。

**原因:** `_ready()`でフォグメッシュ（`PlaneMesh`）とシェーダーパラメータ（`map_min`, `map_max`）が作成・設定される。後から`map_size`を変更しても、これらは更新されないため座標変換がずれる。

## 内部動作

### アーキテクチャ
1. **SubViewport**: 可視領域を白、不可視領域を黒で描画
2. **Polygon2D**: 各VisionComponentの可視ポリゴンを2Dに変換して描画
3. **PlaneMesh + 外部Shader**: SubViewportテクスチャをサンプリングしてフォグを表示

### シェーダー処理（fow.gdshader）
1. ワールド座標をUV座標に変換
2. 5x5 Gaussianブラーでエッジを滑らかに（blur_radius設定可能）
3. `smoothstep`で自然なグラデーション（edge_softness設定可能）
4. 可視領域は透明、不可視領域はフォグ色

### 最適化
- **シグナル駆動**: `vision_updated`シグナルで変更時のみ更新
- **更新間隔制御**: 品質設定に基づく更新頻度（LOW: 15Hz, HIGH: 30Hz）
- **手動レンダリング**: `UPDATE_ONCE`モードで必要時のみ描画
- **複数視界対応**: 複数のVisionComponentを同時に処理可能

## APIリファレンス

### シグナル
なし

### メソッド
- `register_vision(vision) -> void`
- `unregister_vision(vision) -> void`
- `set_fog_visible(fog_visible: bool) -> void`
- `force_update() -> void`
- `set_fog_color(color: Color) -> void`
- `get_visibility_texture() -> ViewportTexture`
- `set_map_size(new_size: Vector2) -> void`
- `set_quality(q: Quality) -> void`
- `get_quality_settings() -> Dictionary`
