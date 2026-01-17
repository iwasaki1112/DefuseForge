# PathLineMesh

パスの線描画クラス。破線と終点のドーナツ型円を描画する。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `MeshInstance3D` |
| ファイルパス | `scripts/effects/path_line_mesh.gd` |

## Export Properties

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `line_height` | `float` | `0.02` | 地面からの高さ |
| `line_width` | `float` | `0.04` | 線の幅 |
| `line_color` | `Color` | 白(0.9 alpha) | 線の色 |
| `dash_length` | `float` | `0.15` | 破線の長さ |
| `gap_length` | `float` | `0.1` | 破線の間隔 |
| `end_circle_radius` | `float` | `0.15` | 終点円の半径 |
| `end_circle_thickness` | `float` | `0.04` | 終点円の太さ |
| `circle_segments` | `int` | `24` | 円のセグメント数 |

## Public API

### update_from_points(points: PackedVector3Array) -> void
ポイント配列から線メッシュを生成する。

**引数:**
- `points` - パスポイントの配列（最低2点必要）

### set_line_color(color: Color) -> void
線の色を変更する。

**引数:**
- `color` - 新しい色

### clear() -> void
メッシュをクリアする。

## 使用例

```gdscript
var path_mesh = MeshInstance3D.new()
path_mesh.set_script(preload("res://scripts/effects/path_line_mesh.gd"))
add_child(path_mesh)

# ポイントからメッシュを生成
var points = PackedVector3Array([
    Vector3(0, 0, 0),
    Vector3(1, 0, 0),
    Vector3(2, 0, 1)
])
path_mesh.update_from_points(points)

# 色を変更
path_mesh.set_line_color(Color.GREEN)

# クリア
path_mesh.clear()
```

## 内部動作

### 描画要素
1. **破線**: `dash_length`と`gap_length`パターンで描画
2. **終点円**: ドーナツ型（リング）のメッシュ

### マテリアル
- `SHADING_MODE_UNSHADED`: 照明の影響を受けない
- `emission_enabled`: 発光エフェクト（energy 1.5）
- `TRANSPARENCY_ALPHA`: アルファブレンディング
- `CULL_DISABLED`: 両面描画
