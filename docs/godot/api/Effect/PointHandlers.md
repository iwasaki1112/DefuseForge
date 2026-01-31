# PointHandlers

`PointHandlerBase` を継承し、各アクションポイント固有の入力処理、データ管理、描画を担当するハンドラクラス群です。
`PathInputHandler` によって統括され、現在の描画モードに応じて切り替えて使用されます。

## 概要

| クラス名 | ポイントタイプ | 機能概要 |
| :--- | :--- | :--- |
| `VisionPointHandler` | Vision | パス上から視線方向を設定（ドラッグ操作） |
| `WaitPointHandler` | Wait | 待機時間を設定（長押し操作） |

---

## VisionPointHandler

視線ポイント（矢印）を管理します。

### 操作
*   **プレス:** パス上の点を始点（アンカー）として設定。
*   **ドラッグ:** 視線方向を決定。
*   **リリース:** ポイントを確定。

### データ構造
```gdscript
{
    "path_ratio": float,   # パス上の位置（0.0-1.0）
    "anchor": Vector3,     # アンカー座標
    "target_point": Vector3 # 視線の先（ターゲット）座標
}
```

---

## WaitPointHandler

待機アクションを管理します。

### 操作
*   **長押し:** 待機時間を設定。押している時間に応じて `wait_duration` が増加します。
*   **リリース:** アクションを確定。
*   **制限:** `WAIT_MIN_DURATION` 未満はキャンセル、`WAIT_MAX_DURATION` でキャップされます。

### データ構造
```gdscript
{
    "path_ratio": float,    # パス上の位置
    "anchor": Vector3,      # 待機位置
    "wait_duration": float  # 待機時間（秒）
}
```