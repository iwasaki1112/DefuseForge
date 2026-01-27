# MarkerCollection

マーカーの統一管理コレクション。複数種類のマーカーをタイプ別に管理する。

## 継承

`RefCounted`

## 概要

`MarkerCollection`は、複数種類のマーカーデータとメッシュを統一的に管理するクラス。
Undo機能の履歴管理も提供する。

## 主要メソッド

### add_marker(data: ActionMarkerData, mesh: MeshInstance3D = null)

マーカーを追加。履歴にも記録される。

### get_markers(type: ActionMarkerData.Type) -> Array

指定タイプのマーカーデータを取得。

### get_meshes(type: ActionMarkerData.Type) -> Array

指定タイプのマーカーメッシュを取得。

### take_meshes(type: ActionMarkerData.Type) -> Array[MeshInstance3D]

指定タイプのマーカーメッシュを取得して所有権を移譲（内部リストはクリア）。

### get_all_markers() -> Array

全マーカーデータを取得。

### take_all_meshes() -> Array[MeshInstance3D]

全マーカーメッシュを取得して所有権を移譲。

### get_markers_as_dicts(type: ActionMarkerData.Type) -> Array[Dictionary]

指定タイプのマーカーをDictionary配列として取得（後方互換用）。

## Undo関連

### get_last_marker_type() -> int

最後に追加したマーカーのタイプを取得。履歴が空なら-1。

### undo_last_marker() -> Dictionary

最後に追加したマーカーを削除。

戻り値:
```gdscript
{
    "success": bool,
    "type": int,        # ActionMarkerData.Type
    "marker": ActionMarkerData,
    "mesh": MeshInstance3D
}
```

### is_history_empty() -> bool

履歴が空かどうか。

### clear_history()

履歴をクリア。

## クリア関連

### clear_type(type: ActionMarkerData.Type)

指定タイプのマーカーをクリア（メッシュも削除）。

### clear_all()

全マーカーをクリア。

## カウント

### get_marker_count(type: ActionMarkerData.Type) -> int

指定タイプのマーカー数を取得。

### get_total_marker_count() -> int

全マーカー数を取得。

## 後方互換メソッド

各タイプ専用の便利メソッド:

```gdscript
# Vision
get_vision_points() -> Array[Dictionary]
take_vision_meshes() -> Array[MeshInstance3D]

# Run
get_run_segments() -> Array[Dictionary]
take_run_meshes() -> Array[MeshInstance3D]

# Clear
get_clear_points() -> Array[Dictionary]
take_clear_meshes() -> Array[MeshInstance3D]

# Grenade
get_grenade_markers() -> Array[Dictionary]
take_grenade_meshes() -> Array[MeshInstance3D]

# Door
get_door_markers() -> Array[Dictionary]
take_door_meshes() -> Array[MeshInstance3D]
```

## 使用例

```gdscript
var collection = MarkerCollection.new()

# マーカーを追加
var vision_data = ActionMarkerData.VisionMarkerData.new()
vision_data.path_ratio = 0.5
var vision_mesh = create_vision_marker_mesh()
collection.add_marker(vision_data, vision_mesh)

# タイプ別に取得
var vision_markers = collection.get_markers(ActionMarkerData.Type.VISION)

# Undo
var result = collection.undo_last_marker()
if result.success:
    result.mesh.queue_free()

# クリア
collection.clear_all()
```

## 関連クラス

- `ActionMarkerData` - マーカーデータ基底クラス
- `ActionMarker` - マーカー表示クラスの基底
- `PathDrawer` - マーカーを配置するパス描画システム
