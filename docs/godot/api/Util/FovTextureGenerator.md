# FovTextureGenerator

**継承:** `RefCounted`

## 概要

`Light2D` で使用するためのFOV（視野角）テクスチャを動的に生成・キャッシュするユーティリティクラス。
扇形や円形の滑らかなグラデーションテクスチャをピクセル操作により生成します。

## ファイル

`godot/scripts/utils/fov_texture_generator.gd`

## 機能

*   **動的生成:** 任意の角度（FOV）とサイズでテクスチャを生成します。
*   **キャッシュ:** 一度生成したパラメータのテクスチャはキャッシュされ、再利用されます。
*   **アンチエイリアス:** エッジ部分（角度および距離）に滑らかなフォールオフ（減衰）処理を適用します。
*   **特殊テクスチャ:** 通常のFOVテクスチャに加え、360度円形テクスチャや周辺視界用テクスチャも生成可能です。

## 静的メソッド

### generate_fov_texture

```gdscript
static func generate_fov_texture(fov_degrees: float, size: int = DEFAULT_SIZE, falloff: float = 0.3) -> ImageTexture
```

指定された視野角の扇形テクスチャを生成します。

*   `fov_degrees`: 視野角（度）
*   `size`: テクスチャの縦横サイズ（ピクセル）
*   `falloff`: エッジのボケ具合（0.0 - 1.0）。値が大きいほどシャープになります。

### generate_circular_texture

```gdscript
static func generate_circular_texture(size: int = DEFAULT_SIZE, falloff: float = 0.3) -> ImageTexture
```

360度の完全な円形テクスチャを生成します。

### generate_peripheral_texture

```gdscript
static func generate_peripheral_texture(size: int = DEFAULT_SIZE) -> ImageTexture
```

周辺視界（足元用）のテクスチャを生成します。
視認性を確保するため、中心からほぼエッジまで均一な明るさを保ち、最外周のみソフトに減衰します。

### pregenerate_textures

```gdscript
static func pregenerate_textures(fov_list: Array[float], size: int = DEFAULT_SIZE) -> void
```

指定されたFOVリストのテクスチャを事前に生成し、キャッシュします。ロード時のスパイクを防ぐために使用できます。

### clear_cache

```gdscript
static func clear_cache() -> void
```

生成済みテクスチャのキャッシュをクリアします。メモリ解放時に使用します。
