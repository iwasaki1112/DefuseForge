# SmokeGrenadeMarker

**継承:** `GrenadeMarker`

スモークグレネード投擲アクションを表示するためのマーカークラス。
`GrenadeMarker` を継承し、視覚的なスタイル（色）をスモークグレネード用に変更しています。

## 詳細

*   **Circle Color:** `Color(0.2, 0.2, 0.2, 0.95)` （暗い灰色）
*   **Icon Color:** `Color(0.9, 0.9, 0.9, 1.0)` （白）
*   **Trajectory Color:** `Color(0.7, 0.7, 0.7, 0.8)` （薄い灰色）

`get_action_marker_type()` は `MarkerType.SMOKE_GRENADE` を返します。
