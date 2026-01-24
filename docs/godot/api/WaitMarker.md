# WaitMarker

パス上の待機位置マーカー。砂時計アイコンで待機位置を示し、待機時間をラベルで表示する。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `MeshInstance3D` |
| ファイルパス | `scripts/effects/wait_marker.gd` |

## 概要

`WaitMarker`は、パス上でキャラクターがアイドル待機する位置を示すマーカー。長押し時間が待機時間として設定される。待機完了後、キャラクターはパス追従を再開する。

## Export Properties

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `circle_radius` | `float` | `0.3` | 円の半径 |
| `circle_color` | `Color` | 琥珀色(0.9, 0.7, 0.2, 0.95) | 円の背景色 |
| `icon_color` | `Color` | 白(1.0, 1.0, 1.0, 1.0) | アイコンの色 |
| `height_offset` | `float` | `0.03` | 地面からの高さ |
| `segments` | `int` | `32` | 円のセグメント数 |

## 内部変数

| 変数 | 型 | 説明 |
|-----|-----|------|
| `_wait_duration` | `float` | 待機時間（秒） |
| `_duration_label` | `Label3D` | 待機時間表示ラベル |

## Public API

### set_marker_position(pos: Vector3) -> void
マーカーの位置を設定する。

**引数:**
- `pos` - パス上のアンカー位置

### set_wait_duration(duration: float) -> void
待機時間を設定する。

**引数:**
- `duration` - 待機時間（秒）

**動作:**
- 内部変数`_wait_duration`を更新
- ラベルを「X.Xs」形式で更新（例: 「2.5s」）

### get_wait_duration() -> float
待機時間を取得する。

**戻り値:** 待機時間（秒）

### set_colors(bg_color: Color, fg_color: Color) -> void
マーカーの色を変更する。

**引数:**
- `bg_color` - 背景円の色
- `fg_color` - アイコンの色

## 使用例

```gdscript
var marker = WaitMarker.new()
add_child(marker)

# 位置と待機時間を設定
marker.set_marker_position(Vector3(5, 0, 3))
marker.set_wait_duration(3.0)  # 3秒待機

# 色を変更（キャラクター個別色）
marker.set_colors(Color(0.9, 0.7, 0.2), Color.WHITE)
```

## 内部動作

### メッシュ構成
1. **塗りつぶし円**: 中心点から放射状に三角形を生成
2. **砂時計アイコン**: 2つの三角形が向かい合う形状
3. **待機時間ラベル**: Label3Dでビルボード表示

### マテリアル
- 円: `SHADING_MODE_UNSHADED`, `TRANSPARENCY_ALPHA`, `render_priority = 10`
- アイコン: 発光有効（energy 1.2）, `render_priority = 11`

フォグより上にレンダリングされるため、常に視認可能。

### 長押しによる待機時間設定

`PathDrawer`でWaitモード時に長押しすると、押している時間が待機時間として設定される：

1. タッチ/クリック開始で時刻記録
2. 長押し中はプレビューマーカーが表示され、リアルタイムで待機時間が更新
3. 指を離すと経過時間が待機時間として確定

- 最小待機時間: 0.5秒（これ未満はキャンセル扱い）
- 最大待機時間: 10.0秒

## 関連クラス

- `PathDrawer` - Waitマーカー設定モードでWaitMarkerを生成
- `PathFollowingController` - マーカー位置到達時に待機を開始、完了後にパス再開
- `ActionMarker` - アクションマーカーの基底クラス

## シグナルフロー

```
PathDrawer (wait_marker_added)
    ↓
PathExecutionManager (confirm_path)
    ↓
PathFollowingController (wait marker check, 待機開始)
    ↓
[wait_duration経過]
    ↓
PathFollowingController (待機完了, パス再開)
```

## APIリファレンス

### シグナル
なし

### メソッド
- `set_marker_position(pos: Vector3) -> void`
- `set_wait_duration(duration: float) -> void`
- `get_wait_duration() -> float`
- `set_colors(bg_color: Color, fg_color: Color) -> void`
