# LeftHandIKModifier

TwoBoneIK3Dによる左手IKの制御を管理するノード。武器モデル内のグリップノードに左手を追従させ、リアルな武器保持を実現する。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/modifiers/left_hand_ik_modifier.gd` |

## 概要

右手IKからのデルタ方式でキャラクター相対座標から左手位置を計算する。走行中のズレを防止し、GUN_UP/リコイルにも自動追従する。

**位置計算式:**
```
左手ワールド位置 = char_pos + model_basis * (rh_pos + delta + grip_offset)
```

- `rh_pos`: 右手のキャラ相対位置（UpperBodyIKController経由で取得）
- `delta`: グリップ設定時に1回キャプチャ（グリップのキャラ相対位置 − 右手のキャラ相対位置）
- `grip_offset`: 武器固有の微調整オフセット

## Constants

| 定数 | 値 | 説明 |
|------|-----|------|
| `DEFAULT_BLEND_SPEED` | `15.0` | influence遷移速度 |
| `DEFAULT_POLE_OFFSET` | `0.3` | ポールターゲットのデフォルトオフセット（肘方向制御） |

## Public API

### setup(skeleton: Skeleton3D, model: Node3D) -> void
IKノードとターゲットを作成してスケルトンに追加する。

**引数:**
- `skeleton`: IKチェーンを構築するSkeleton3D
- `model`: キャラクターモデル（座標変換の基準）

**処理内容:**
1. IKターゲット用Marker3D（`LeftHandIKTarget`）を作成
2. ポールターゲット用Marker3D（`LeftHandIKPole`）を作成
3. TwoBoneIK3Dノードを作成、IKチェーンを設定
4. ターゲットは常にMarker3D

### set_enabled(enabled: bool) -> void
IKの有効/無効を設定する。influenceはlerpで滑らかに遷移する。

### disable_immediate() -> void
IKを即座に無効化する（死亡時など、遷移なし）。

### set_grip_source(grip_node: Node3D) -> void
武器モデル内のグリップソースノードを設定する。常にMarker3D経由で追従し、2フレーム待機後にデルタをキャプチャする。

### clear_grip_source() -> void
グリップソースをクリアし、デルタ・キャプチャ状態をリセットする。

### has_grip_source() -> bool
グリップソースが有効に設定されているかを返す。

### is_enabled() -> bool
IKが有効かどうかを返す（target_influence > 0.5）。

### set_grip_offset(offset: Vector3) -> void
グリップ位置オフセットを設定（キャラ相対空間）。

### set_pole_offset(offset: Vector3) -> void
ポールオフセットを設定（キャラクター空間XYZ）。

### set_rh_position_getter(getter: Callable) -> void
右手キャラ相対位置を返すCallableを設定する。UpperBodyIKController.setup()から呼ばれる。

## 内部動作

### デルタキャプチャ
`set_grip_source()`呼び出し後、2フレーム待機してから`_capture_delta()`を実行:
1. グリップノードのワールド位置をキャラ相対座標に変換
2. 右手のキャラ相対位置を取得
3. デルタ = グリップ相対位置 − 右手相対位置

### _process(delta)
毎フレーム以下を処理:
1. **influence遷移**: 現在のinfluenceを目標値に向けてlerp
2. **キャプチャカウントダウン**: 0到達時にデルタをキャプチャ
3. **IKターゲット位置更新**:
   - デルタ方式（キャプチャ完了後）: `char_pos + model_basis * (rh_pos + delta + offset)`
   - フォールバック（キャプチャ待機中）: グリップノード直接追跡
4. **ポール位置更新**: 肩と手の中点 + キャラクター空間オフセット

### 状態遷移の挙動

| 状態 | 挙動 |
|------|------|
| READY | `rh_pos + delta` で安定追従 |
| GUN_UP | 右手移動に自動追従（delta不変） |
| ACTION | influence=0で無効化、復帰時はdelta有効のまま |
| DISABLED | influence=0即時設定 |
| 武器切替 | clear→set_grip_sourceでデルタ再キャプチャ |

## 使用例

```gdscript
# CharacterAnimationController内での使用
var left_hand_ik = LeftHandIKModifier.new()
character.add_child(left_hand_ik)
left_hand_ik.setup(skeleton, model)

# 右手位置取得用Callableを設定（UpperBodyIKControllerから）
left_hand_ik.set_rh_position_getter(upper_body_ik.get_current_hand_pos)

# 武器装備時
var grip = weapon_model.find_child("LeftHandGrip")
left_hand_ik.set_grip_source(grip)
left_hand_ik.set_enabled(true)

# 武器解除時
left_hand_ik.clear_grip_source()
```

## IKチェーン

```
LeftUpperArm (root)
  └─ LeftLowerArm (middle)
      └─ LeftHand (end) → Marker3D (target, char-relative position)
```

## 関連クラス
- [UpperBodyIKController](UpperBodyIKController.md) - 右手IK位置を提供
- [CharacterAnimationController](CharacterAnimationController.md) - IKの管理親
- [GameConstants](../Util/GameConstants.md) - ボーン名定数
