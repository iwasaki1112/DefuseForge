# SignalBus

グローバルシグナルバス。システム間のイベント通知を一元管理し、循環依存を避けた疎結合なアーキテクチャを実現する。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/systems/signal_bus.gd` |
| Autoload名 | `SignalBus` |

## 使用方法

```gdscript
# シグナルの発火
SignalBus.round_started.emit()

# シグナルの購読
SignalBus.round_started.connect(_on_round_started)
```

## Signals

### Round Signals

| シグナル | 引数 | 説明 |
|---------|------|------|
| `round_started` | - | ラウンドが開始された |
| `round_ended` | `winner: int, reason: int` | ラウンドが終了した |
| `round_timer_updated` | `remaining: float` | ラウンドタイマーが更新された |
| `survivor_count_changed` | `ct_count: int, t_count: int` | 生存者数が変更された |

## 設計意図

### 循環依存の回避
従来のアーキテクチャでは、GameScreen ↔ GameManager間の直接参照により循環依存が発生していた。SignalBusを介することで、システム間の依存関係が一方向になる。

### イベント駆動アーキテクチャ
- 発行者はシグナルを発火するだけで、購読者を知る必要がない
- 購読者は任意のタイミングで接続/切断可能
- 新しいシステムの追加が既存コードに影響しない

### デバッグ容易性
全てのシステム間通信がSignalBusを経由するため、イベントフローの追跡が容易。

## 注意事項

- シグナルは外部システムから接続されることを想定しているため、`@warning_ignore("unused_signal")`で警告を抑制
- Autoloadとして登録されているため、`class_name`は使用しない
