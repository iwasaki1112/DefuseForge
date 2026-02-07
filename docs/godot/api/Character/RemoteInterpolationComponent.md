# RemoteInterpolationComponent

マルチプレイヤーにおけるリモートキャラクターの位置・回転補間を管理するコンポーネント。スナップショットバッファベースの補間と外挿を行う。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `RefCounted` |
| ファイルパス | `scripts/characters/remote_interpolation_component.gd` |

## 依存関係

- `NetworkConstants` - 補間遅延、バッファサイズ等の定数
- `NetworkMessages.CharacterStateMessage` - ネットワーク状態メッセージ

## Public API

### setup(character: GameCharacter) -> void
コンポーネントを初期化する。

**引数:**
- `character` - 所有キャラクター

### set_anim_controller(ctrl: CharacterAnimationController) -> void
アニメーションコントローラを設定する。

### add_snapshot(state: NetworkMessages.CharacterStateMessage, time: float) -> void
受信したスナップショットをバッファに追加する。

**引数:**
- `state` - 受信した状態メッセージ
- `time` - 受信時刻（ローカル時刻）

**動作:**
- 初回受信時にレンダリング時刻基準を初期化
- バッファサイズ制限を適用
- 旧実装との互換用にターゲット値を更新

### clear() -> void
スナップショットバッファと状態をクリアする。

### has_received_first_snapshot() -> bool
初回スナップショットが受信済みか確認する。

### activate() -> void
補間処理を有効化する。

### deactivate() -> void
補間処理を無効化し、バッファをクリアする。

### update(delta: float) -> void
毎フレームの補間更新を行う。キャラクターの`_process`から呼び出す。

**動作:**
1. レンダリング時刻を進める
2. ドリフト補正を適用
3. バッファから補間状態を取得
4. 位置スムージングを適用
5. アニメーション更新

### initialize_position(state: NetworkMessages.CharacterStateMessage) -> void
初回スナップショット受信時に位置を即座に設定する。テレポート防止用。

### is_active() -> bool
補間がアクティブか確認する。

### is_extrapolating() -> bool
現在外挿中か確認する。

### get_target_animation_state() -> String
ターゲットアニメーション状態を取得する（旧実装互換）。

## 補間アルゴリズム

### スナップショット補間
1. `_render_time_base`（現在時刻 - INTERPOLATION_DELAY）を計算
2. バッファから`before_time <= target_time <= after_time`となる2点を探索
3. 線形補間（位置・速度）、角度補間（回転）を適用

### 外挿
- 最新スナップショットより未来の場合は速度ベースで外挿
- `MAX_EXTRAPOLATION_TIME`を超えると外挿停止

### ドリフト補正
- レンダリング時刻とスナップショット到着時刻のドリフトを検出
- ±50ms以上のドリフトを徐々に補正（急激な補正を避ける）

### 位置スムージング
- 補間結果を直接適用せず、追加のスムージングレイヤーを適用
- フォールバックモードとの切り替え時のジャーク防止

### フォールバック
- バッファ不足時は旧実装の単純lerp補間を使用
- スムージング位置を同期してモード切り替え時の滑らかさを維持

## 使用例

```gdscript
# GameCharacter.apply_remote_state()での使用
func apply_remote_state(state: NetworkMessages.CharacterStateMessage) -> void:
    if remote_interpolation:
        var is_first := not remote_interpolation.has_received_first_snapshot()
        remote_interpolation.activate()
        var current_time := Time.get_ticks_msec() / 1000.0
        remote_interpolation.add_snapshot(state, current_time)

        # 初回またはテレポート防止
        if is_first or global_position.distance_to(state.position) > 5.0:
            remote_interpolation.initialize_position(state)

# _process()での更新
func _process(delta: float) -> void:
    if remote_interpolation and remote_interpolation.is_active():
        remote_interpolation.update(delta)
```

## パフォーマンス考慮

- スナップショットバッファサイズ: `NetworkConstants.SNAPSHOT_BUFFER_SIZE`
- 補間遅延: `NetworkConstants.INTERPOLATION_DELAY`（80ms）
- ドリフト補正は毎フレーム軽量な計算のみ
- アニメーション状態は補間せず、近い方のスナップショットを使用
