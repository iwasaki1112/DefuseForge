# VisionLight

**継承:** `Node`

## 概要

キャラクターの視界（Fog of War）を表現するための光源管理クラス。
3D空間上のキャラクターの位置・向き・視界範囲を、2D空間（SubViewport）上の `PointLight2D` に同期させます。

## ファイル

`godot/scripts/characters/vision_light.gd`

## 機能

*   **視界の同期:** 3Dキャラクターの位置を2Dマップ座標（UV）に変換し、ライト位置を更新します。
*   **向きの同期:** キャラクターの向き（`facing_direction`）に合わせてライトを回転させます。
*   **FOVテクスチャ:** `FovTextureGenerator` を使用して、現在の視野角（FOV）に応じた扇形テクスチャを適用します。
*   **周辺視界:** メインの視界とは別に、キャラクター周囲の至近距離（360度）を照らす `PeripheralLight` を管理します。
*   **影の生成:** `Light2D` のシャドウ機能を利用して、壁（Occluder）による視界の遮蔽を自動計算します。

## プロパティ

| プロパティ名 | 型 | 説明 |
| :--- | :--- | :--- |
| `fov_degrees` | `float` | 視野角（度）。変更時にテクスチャが再生成されます。 |
| `view_distance` | `float` | 視認距離（メートル）。ライトのスケールに反映されます。 |
| `peripheral_distance` | `float` | 周辺視界（360度）の距離。 |

## メソッド

### setup

```gdscript
func setup(viewport: SubViewport, character: Node3D, map_size: Vector2, resolution: int) -> void
```

視界ライトを初期化し、指定されたViewportに追加します。

### sync_transform

```gdscript
func sync_transform() -> void
```

キャラクターの現在の `global_position` と向きに合わせて、ライトの位置と回転を更新します。
通常、`_process` または `_physics_process` で毎フレーム呼び出されます。

**回転の補間:**
ライトの回転は `ROTATION_SMOOTHING` により滑らかに補間されます。

### set_fov_degrees

```gdscript
func set_fov_degrees(fov: float) -> void
```

視野角を変更し、テクスチャを更新します。

### set_view_distance

```gdscript
func set_view_distance(distance: float) -> void
```

視認距離を変更し、ライトのテクスチャスケールを更新します。

## 内部構造

*   **メインライト (`_light`):** 扇形の視界を担当。キャラクターの前方を照らします。
*   **周辺ライト (`_peripheral_light`):** 足元の360度視界を担当。壁際や背後の至近距離が見えるようにします。

どちらのライトも `Light2D.BLEND_MODE_ADD` で描画され、Fog of Warマスク（黒）を「明るく（透明に）」切り抜く役割を果たします。
