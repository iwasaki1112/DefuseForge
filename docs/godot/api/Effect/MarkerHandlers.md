# MarkerHandlers

`MarkerHandlerBase` を継承し、各アクションマーカー固有の入力処理、データ管理、描画を担当するハンドラクラス群です。
`PathInputHandler` によって統括され、現在の描画モードに応じて切り替えて使用されます。

## 概要

| クラス名 | マーカータイプ | 機能概要 |
| :--- | :--- | :--- |
| `VisionMarkerHandler` | Vision | パス上から視線方向を設定（ドラッグ操作） |
| `RunMarkerHandler` | Run | パス上の区間をダッシュ指定（始点・終点） |
| `ClearMarkerHandler` | Clear | 視線やダッシュ状態をリセットするポイントを設定 |
| `GrenadeMarkerHandler` | Grenade | 投擲位置と目標地点を設定（2ステップ操作） |
| `SmokeGrenadeMarkerHandler` | SmokeGrenade | スモーク投擲位置と目標地点を設定（2ステップ操作） |
| `DoorMarkerHandler` | Door | ドアキック位置を設定（ドアへのレイキャスト） |
| `WaitMarkerHandler` | Wait | 待機時間を設定（長押し操作） |

---

## VisionMarkerHandler

視線マーカー（矢印）を管理します。

### 操作
*   **プレス:** パス上の点を始点（アンカー）として設定。
*   **ドラッグ:** 視線方向を決定。
*   **リリース:** マーカーを確定。

### データ構造
```gdscript
{
    "path_ratio": float,   # パス上の位置（0.0-1.0）
    "anchor": Vector3,     # アンカー座標
    "target_point": Vector3 # 視線の先（ターゲット）座標
}
```

---

## RunMarkerHandler

ダッシュ区間（Run）を管理します。

### 操作
*   **1回目のクリック:** Run開始点を設定。
*   **2回目のクリック:** Run終了点を設定し、区間を確定。
*   **（注）:** 開始点が終了点より後ろにある場合、自動的に入れ替えられます。

### データ構造
```gdscript
{
    "start_ratio": float, # 開始比率
    "end_ratio": float    # 終了比率
}
```

---

## ClearMarkerHandler

設定リセット地点（Clear）を管理します。この地点を通過すると、視線方向やダッシュ状態がリセットされます。

### 操作
*   **クリック:** パス上にClearポイントを追加。

### データ構造
```gdscript
{
    "path_ratio": float # パス上の位置
}
```

---

## GrenadeMarkerHandler / SmokeGrenadeMarkerHandler

グレネードおよびスモークグレネードの投擲アクションを管理します。

### 操作
1.  **パス上をクリック:** 投擲位置（アンカー）を設定。軌道プレビューが表示されます。
2.  **任意の場所をクリック:** 目標地点（着弾点）を設定し、アクションを確定。

### データ構造
```gdscript
{
    "path_ratio": float,    # 投擲位置の比率
    "anchor": Vector3,      # 投擲位置
    "target_pos": Vector3,  # 目標位置
    "bounce_point": Vector3,# （将来用）跳ね返り位置
    "bounce_normal": Vector3 # （将来用）跳ね返り法線
}
```

---

## DoorMarkerHandler

ドアキックアクションを管理します。

### 操作
*   **ドアをクリック:** 
    1. クリックされたドアを検出。
    2. ドアからパス上の最近点を計算。
    3. `DOOR_KICK_OFFSET` 分だけ手前にマーカーを配置。
    4. 距離が `DOOR_PROXIMITY_THRESHOLD` 以内なら確定。

### データ構造
```gdscript
{
    "path_ratio": float,   # パス上の位置
    "anchor": Vector3,     # アクション位置
    "door_node": Node3D    # 対象のドアノード
}
```

---

## WaitMarkerHandler

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
