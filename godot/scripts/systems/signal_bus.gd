extends Node
## NOTE: class_name removed - this script is registered as Autoload "SignalBus"

## グローバルシグナルバス
## システム間のイベント通知を一元管理
## 循環依存を避け、疎結合なアーキテクチャを実現
##
## シグナルは外部システムから接続されることを想定しているため
## unused_signal警告を抑制

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
# Autoload Note
# ============================================
# This script is registered as an Autoload in project.godot
# Access via: SignalBus.signal_name.emit(...) or SignalBus.signal_name.connect(...)
