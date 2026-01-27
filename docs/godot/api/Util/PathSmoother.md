# PathSmoother

手描きパスのスムージングを行うユーティリティクラス。

## 概要

`PathSmoother` は手ブレによる不要なポイントを除去し、滑らかな曲線を生成するための静的メソッドを提供する。

### アルゴリズム

2段階処理を採用:

1. **Ramer-Douglas-Peucker法（RDP）**: 手ブレによる不要ポイントを間引き
2. **Catmull-Rom曲線**: 残ったポイントを滑らかな曲線で補間

## パス

`res://scripts/utils/path_smoother.gd`

## 定数

| 定数名 | 型 | 値 | 説明 |
|--------|----|----|------|
| `DEFAULT_RDP_EPSILON` | `float` | `0.15` | RDP法のデフォルト許容誤差（メートル） |
| `DEFAULT_SEGMENTS` | `int` | `4` | Catmull-Rom曲線のデフォルト分割数 |

## 静的メソッド

### smooth_path

```gdscript
static func smooth_path(
    path: PackedVector3Array,
    epsilon: float = DEFAULT_RDP_EPSILON,
    segments: int = DEFAULT_SEGMENTS
) -> PackedVector3Array
```

パスをスムージングする（RDP間引き + Catmull-Rom補間）。

#### パラメータ
| 名前 | 型 | デフォルト | 説明 |
|------|----|----|------|
| `path` | `PackedVector3Array` | - | 元のパスポイント配列 |
| `epsilon` | `float` | `0.15` | RDP法の許容誤差。大きいほど間引きが強い |
| `segments` | `int` | `4` | Catmull-Rom曲線の各区間の分割数 |

#### 戻り値
- `PackedVector3Array`: スムージング後のパスポイント配列

#### 備考
- ポイント数が3未満の場合、元のパスをそのまま返す
- RDP間引き後のポイント数が2以下の場合、Catmull-Rom補間はスキップ

---

### simplify_rdp

```gdscript
static func simplify_rdp(
    path: PackedVector3Array,
    epsilon: float = DEFAULT_RDP_EPSILON
) -> PackedVector3Array
```

Ramer-Douglas-Peucker法でパスを間引く。

#### パラメータ
| 名前 | 型 | デフォルト | 説明 |
|------|----|----|------|
| `path` | `PackedVector3Array` | - | 元のパスポイント配列 |
| `epsilon` | `float` | `0.15` | 許容誤差。この距離以下のポイントは削除される |

#### 戻り値
- `PackedVector3Array`: 間引き後のパスポイント配列

#### アルゴリズム詳細
1. 始点と終点を結ぶ直線を引く
2. 各ポイントから直線への垂直距離を計算
3. 最大距離が`epsilon`以下なら中間ポイントを削除
4. `epsilon`を超えたら最大距離のポイントで分割し再帰処理

---

### interpolate_catmull_rom

```gdscript
static func interpolate_catmull_rom(
    path: PackedVector3Array,
    segments: int = DEFAULT_SEGMENTS
) -> PackedVector3Array
```

Catmull-Rom曲線でパスを補間。

#### パラメータ
| 名前 | 型 | デフォルト | 説明 |
|------|----|----|------|
| `path` | `PackedVector3Array` | - | 間引き後のパスポイント配列（制御点） |
| `segments` | `int` | `4` | 各区間の分割数 |

#### 戻り値
- `PackedVector3Array`: 補間後のパスポイント配列

#### 備考
- 2点のみの場合は線形補間（元のパスをそのまま返す）
- 端点処理のため、仮想的な制御点を追加
- テンション値は標準の0.5を使用

## 使用例

### 基本的な使用

```gdscript
var raw_path: PackedVector3Array = get_drawn_path()

# デフォルト設定でスムージング
var smoothed = PathSmoother.smooth_path(raw_path)

# カスタム設定でスムージング
var smoothed_custom = PathSmoother.smooth_path(raw_path, 0.2, 5)
```

### RDP間引きのみ

```gdscript
# 間引きのみ実行（曲線補間なし）
var simplified = PathSmoother.simplify_rdp(raw_path, 0.1)
```

### Catmull-Rom補間のみ

```gdscript
# 既に間引き済みのパスを滑らかに補間
var smooth_curve = PathSmoother.interpolate_catmull_rom(simplified_path, 6)
```

## パラメータ調整ガイド

| パラメータ | 推奨範囲 | 効果 |
|-----------|----------|------|
| `epsilon` | 0.1〜0.3m | 大きいほど間引きが強く、ポイント数が減少 |
| `segments` | 3〜6 | 大きいほど滑らかだが、ポイント数が増加 |

### ユースケース別推奨値

| ユースケース | epsilon | segments |
|-------------|---------|----------|
| 手ブレ軽減（軽め） | 0.1 | 3 |
| 通常の手描きパス | 0.15 | 4 |
| 粗いパスの整形 | 0.2〜0.25 | 5 |

## 関連クラス

- [PathDrawer](PathDrawer.md) - パス描画中にリアルタイムでスムージングを適用

## APIリファレンス

### シグナル
なし

### メソッド
なし
