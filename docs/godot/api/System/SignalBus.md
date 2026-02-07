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
SignalBus.character_died.emit(character)

# シグナルの購読
SignalBus.character_died.connect(_on_character_died)
```

## Signals

### Selection Signals

| シグナル | 引数 | 説明 |
|---------|------|------|
| `selection_changed` | `selected: Array[Node], primary: Node` | キャラクター選択が変更された |
| `primary_changed` | `character: Node` | プライマリキャラクターが変更された |

### Path Signals

| シグナル | 引数 | 説明 |
|---------|------|------|
| `path_mode_started` | `character: Node` | パスモードが開始された |
| `path_mode_ended` | - | パスモードが終了した |
| `path_mode_cancelled` | - | パスモードがキャンセルされた |
| `path_ready` | - | パスが準備完了 |
| `path_confirmed` | `count: int` | パスが確定された |
| `paths_execution_started` | `count: int` | 全パスの実行が開始された |
| `all_paths_completed` | - | 全パスの実行が完了した |
| `paths_cleared` | - | パスがクリアされた |
| `path_mode_changed` | `mode: int` | パスモードが変更された（MOVE, VISION, WAIT等） |
| `vision_point_added` | `anchor: Vector3, direction: Vector3` | 視線ポイントが追加された |

### Combat Signals

| シグナル | 引数 | 説明 |
|---------|------|------|
| `grenade_thrown` | `grenade: Node3D, character: Node` | グレネードが投擲された |
| `smoke_grenade_thrown` | `smoke_grenade: Node3D, character: Node` | スモークグレネードが投擲された |
| `damage_dealt` | `attacker: Node, target: Node, damage: float, is_headshot: bool` | ダメージが発生した |

### Round Signals

| シグナル | 引数 | 説明 |
|---------|------|------|
| `round_started` | - | ラウンドが開始された |
| `round_ended` | `winner: int, reason: int` | ラウンドが終了した |
| `round_timer_updated` | `remaining: float` | ラウンドタイマーが更新された |
| `survivor_count_changed` | `ct_count: int, t_count: int` | 生存者数が変更された |

### Character Signals

| シグナル | 引数 | 説明 |
|---------|------|------|
| `character_died` | `character: Node` | キャラクターが死亡した |
| `character_registered` | `character: Node` | キャラクターが登録された |
| `character_unregistered` | `character: Node` | キャラクターが登録解除された |

### Network Signals (Multiplayer)

| シグナル | 引数 | 説明 |
|---------|------|------|
| `grenade_network_event` | `start_pos: Vector3, velocity: Vector3, is_smoke: bool, grenade_id: int` | グレネードネットワークイベント |
| `grenade_explode_network_event` | `grenade_id: int, position: Vector3, is_smoke: bool` | グレネード爆発ネットワークイベント |
| `door_kick_network_event` | `door_id: int, character_network_id: int` | ドアキックネットワークイベント |
| `damage_network_event` | `attacker_id: int, target_id: int, damage: float, is_headshot: bool` | ダメージネットワークイベント |

### Map Signals

| シグナル | 引数 | 説明 |
|---------|------|------|
| `map_loaded` | `map_id: String, map_instance: Node3D` | マップがロードされた |
| `map_will_unload` | `map_id: String` | マップがアンロードされる前 |

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
