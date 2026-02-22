# IKActionPlayer

Tweenベースのアクション（投擲・ドア開け・近接攻撃）IK軌跡管理。AnimationTreeを停止せずに上半身のアクションをIKターゲットの軌跡で表現する。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/modifiers/ik_action_player.gd` |

## データ構造

### ActionKeyframe
| フィールド | 型 | 説明 |
|-----------|-----|------|
| `time` | `float` | 開始からの秒数 |
| `right_hand_pos` | `Vector3` | 右手IKターゲット位置（キャラ原点基準） |
| `right_hand_pole` | `Vector3` | 右手IKポール位置 |
| `left_ik_enabled` | `bool` | 左手IK有効 |
| `spine_pitch` | `float` | 背骨ピッチ（ラジアン） |
| `easing` | `Tween.EaseType` | イージングタイプ |

### ActionDefinition
| フィールド | 型 | 説明 |
|-----------|-----|------|
| `keyframes` | `Array[ActionKeyframe]` | キーフレーム配列 |
| `signals` | `Dictionary` | `{ time: signal_name }` |
| `total_duration` | `float` | 合計時間（自動計算） |

## Signals

| シグナル | 引数 | 説明 |
|---------|------|------|
| `action_signal` | `signal_name: String` | キーフレーム定義のシグナル発火 |
| `action_finished` | なし | アクション完了 |

## Public API

### setup(ubik: UpperBodyIKController) -> void
上半身IKコントローラーを設定。

### play(definition: ActionDefinition) -> void
アクション再生。UpperBodyIKControllerをACTION状態に切り替え、Tweenでキーフレーム間を補間。

### cancel() -> void
アクション中断。READY状態に復帰。

### is_playing() -> bool
再生中かどうか。

## 使用例

```gdscript
var def = IKActionPlayer.ActionDefinition.new()
var kf1 = IKActionPlayer.ActionKeyframe.new(0.0, ready_pos, ready_pole)
var kf2 = IKActionPlayer.ActionKeyframe.new(0.3, throw_pos, throw_pole, false, 0.2)
var kf3 = IKActionPlayer.ActionKeyframe.new(0.8, ready_pos, ready_pole)
def.add_keyframe(kf1)
def.add_keyframe(kf2)
def.add_keyframe(kf3)
def.signals[0.3] = "throw_release"
action_player.play(def)
```
