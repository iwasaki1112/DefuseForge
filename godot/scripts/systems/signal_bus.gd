extends Node
## NOTE: class_name removed - this script is registered as Autoload "SignalBus"

## グローバルシグナルバス
## システム間のイベント通知を一元管理
## 循環依存を避け、疎結合なアーキテクチャを実現
##
## シグナルは外部システムから接続されることを想定しているため
## unused_signal警告を抑制

# ============================================
# Selection Signals
# ============================================

## キャラクター選択が変更された
@warning_ignore("unused_signal")
signal selection_changed(selected: Array[Node], primary: Node)
## プライマリキャラクターが変更された
@warning_ignore("unused_signal")
signal primary_changed(character: Node)

# ============================================
# Combat Signals
# ============================================

## グレネードが投擲された
@warning_ignore("unused_signal")
signal grenade_thrown(grenade: Node3D, character: Node)
## スモークグレネードが投擲された
@warning_ignore("unused_signal")
signal smoke_grenade_thrown(smoke_grenade: Node3D, character: Node)
## ダメージが発生した
@warning_ignore("unused_signal")
signal damage_dealt(attacker: Node, target: Node, damage: float, is_headshot: bool)

# ============================================
# Round Signals
# ============================================

## ラウンドが開始された
@warning_ignore("unused_signal")
signal round_started()
## ラウンドが終了した
@warning_ignore("unused_signal")
signal round_ended(winner: int, reason: int)
## ラウンドタイマーが更新された
@warning_ignore("unused_signal")
signal round_timer_updated(remaining: float)
## 生存者数が変更された
@warning_ignore("unused_signal")
signal survivor_count_changed(ct_count: int, t_count: int)

# ============================================
# Character Signals
# ============================================

## キャラクターが死亡した
@warning_ignore("unused_signal")
signal character_died(character: Node)
## キャラクターが登録された
@warning_ignore("unused_signal")
signal character_registered(character: Node)
## キャラクターが登録解除された
@warning_ignore("unused_signal")
signal character_unregistered(character: Node)

# ============================================
# Map Signals
# ============================================

## マップがロードされた
@warning_ignore("unused_signal")
signal map_loaded(map_id: String, map_instance: Node3D)
## マップがアンロードされる前
@warning_ignore("unused_signal")
signal map_will_unload(map_id: String)

# ============================================
# Autoload Note
# ============================================
# This script is registered as an Autoload in project.godot
# Access via: SignalBus.signal_name.emit(...) or SignalBus.signal_name.connect(...)
