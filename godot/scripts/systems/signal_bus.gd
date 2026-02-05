extends Node
class_name SignalBus

## グローバルシグナルバス
## システム間のイベント通知を一元管理
## 循環依存を避け、疎結合なアーキテクチャを実現

# ============================================
# Selection Signals
# ============================================

## キャラクター選択が変更された
signal selection_changed(selected: Array[Node], primary: Node)
## プライマリキャラクターが変更された
signal primary_changed(character: Node)

# ============================================
# Path Signals
# ============================================

## パスモードが開始された
signal path_mode_started(character: Node)
## パスモードが終了した
signal path_mode_ended()
## パスモードがキャンセルされた
signal path_mode_cancelled()
## パスが準備完了
signal path_ready()
## パスが確定された
signal path_confirmed(count: int)
## 全パスの実行が開始された
signal paths_execution_started(count: int)
## 全パスの実行が完了した
signal all_paths_completed()
## パスがクリアされた
signal paths_cleared()
## パスモードが変更された（MOVE, VISION, WAIT等）
signal path_mode_changed(mode: int)
## 視線ポイントが追加された
signal vision_point_added(anchor: Vector3, direction: Vector3)

# ============================================
# Combat Signals
# ============================================

## グレネードが投擲された
signal grenade_thrown(grenade: Node3D, character: Node)
## スモークグレネードが投擲された
signal smoke_grenade_thrown(smoke_grenade: Node3D, character: Node)
## ダメージが発生した
signal damage_dealt(attacker: Node, target: Node, damage: float, is_headshot: bool)

# ============================================
# Round Signals
# ============================================

## ラウンドが開始された
signal round_started()
## ラウンドが終了した
signal round_ended(winner: int, reason: int)
## ラウンドタイマーが更新された
signal round_timer_updated(remaining: float)
## 生存者数が変更された
signal survivor_count_changed(ct_count: int, t_count: int)

# ============================================
# Character Signals
# ============================================

## キャラクターが死亡した
signal character_died(character: Node)
## キャラクターが登録された
signal character_registered(character: Node)
## キャラクターが登録解除された
signal character_unregistered(character: Node)

# ============================================
# Network Signals (Multiplayer)
# ============================================

## グレネードネットワークイベント
signal grenade_network_event(start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int)
## グレネード爆発ネットワークイベント
signal grenade_explode_network_event(grenade_id: int, position: Vector3, is_smoke: bool)
## ドアキックネットワークイベント
signal door_kick_network_event(door_id: int, character_network_id: int)
## ダメージネットワークイベント
signal damage_network_event(attacker_id: int, target_id: int, damage: float, is_headshot: bool)

# ============================================
# Map Signals
# ============================================

## マップがロードされた
signal map_loaded(map_id: String, map_instance: Node3D)
## マップがアンロードされる前
signal map_will_unload(map_id: String)

# ============================================
# Singleton Instance
# ============================================

static var _instance: SignalBus = null


static func get_instance() -> SignalBus:
	if _instance == null:
		_instance = SignalBus.new()
		_instance.name = "SignalBus"
	return _instance


## インスタンスをリセット（テスト用）
static func reset() -> void:
	if _instance:
		_instance.queue_free()
		_instance = null
