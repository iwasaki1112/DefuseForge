class_name TimelineManager
extends Node

## タイムライン更新管理
## 同一フレーム内の重複発火を排除し、効率的なタイムライン更新を実現

## タイムラインが更新された時のシグナル
signal timeline_updated()

## 更新リクエストフラグ（同一フレーム内で1回だけ発火するため）
var _update_requested: bool = false


## タイムラインデータが変更されたことをマーク
## 同一フレーム内で複数回呼ばれても、実際の発火は1回のみ
func mark_dirty() -> void:
	if not _update_requested:
		_update_requested = true
		call_deferred("_flush_updates")


## 遅延更新処理（フレーム終了時に呼ばれる）
func _flush_updates() -> void:
	_update_requested = false
	timeline_updated.emit()
