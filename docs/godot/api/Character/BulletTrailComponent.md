# BulletTrailComponent

射撃時の弾道トレイルエフェクト表示を管理するコンポーネント。GameCharacterから抽出された機能。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `RefCounted` |
| ファイルパス | `scripts/characters/bullet_trail_component.gd` |

## Constants

| 定数 | 値 | 説明 |
|------|-----|------|
| `BULLET_TRAIL_DURATION` | `0.15` | トレイル表示時間 |
| `BULLET_TRAIL_WIDTH` | `0.01` | トレイルの幅 |
| `BULLET_TRAIL_MAX_DISTANCE` | `50.0` | 最大距離（フォールバック用） |

## Public API

### setup(character: Node3D, weapon_socket: Node3D, muzzle_flash: MuzzleFlashComponent, combat_awareness = null) -> void
コンポーネントを初期化する。

**引数:**
- `character` - 所有キャラクター
- `weapon_socket` - 武器ソケットノード
- `muzzle_flash` - MuzzleFlashComponent（銃口位置取得用）
- `combat_awareness` - CombatAwarenessComponent（ターゲット/命中判定用、オプション）

### set_weapon_socket(socket: Node3D) -> void
武器ソケットを更新する。

### set_combat_awareness(awareness) -> void
CombatAwarenessComponentを設定する。後から設定可能。

### play(current_weapon: Resource, weapon_model: Node3D) -> void
弾道トレイルを再生する。

**引数:**
- `current_weapon` - 現在装備中の武器リソース
- `weapon_model` - 武器の3Dモデル

**動作:**
1. MuzzleFlashComponentから銃口位置を取得
2. CombatAwarenessからターゲット位置と命中判定を取得
3. 外れた場合はmiss_offsetを適用
4. 2枚のQuadMeshで弾道を描画
5. Tweenでフェードアウト

### cleanup() -> void
トレイルノードをクリーンアップする。キャラクター破棄時に自動呼び出し。

## 内部動作

### 弾道終点の決定
1. **CombatAwarenessからターゲット取得**（優先）
   - ターゲット位置 + 高さ補正（1.2m）
   - 外れた場合はmiss_offsetを加算
2. **フォールバック**
   - キャラクターの前方（-Z方向）に50m延長

### シェーダーパラメータ
- `trail_color`: Color(1.0, 0.95, 0.85, 1.0)（暖色）
- `edge_softness`: 1.5
- `tip_roundness`: 0.12
- `glow_intensity`: 1.8
- `overall_alpha`: フェードアウト用

### クリーンアップ
キャラクターの`tree_exited`シグナルに接続し、シーンから削除される際にトレイルノードを自動破棄。

## 使用例

```gdscript
# GameCharacterでのセットアップ（内部実装）
bullet_trail = BulletTrailComponent.new()
bullet_trail.setup(self, weapon_socket, muzzle_flash, combat_awareness)

# 射撃時
func fire() -> void:
    muzzle_flash.play(current_weapon, weapon_model)
    bullet_trail.play(current_weapon, weapon_model)
```

## パフォーマンス考慮

- ノードは遅延作成（初回play()時に作成）
- ワールド空間に追加（キャラクター位置に依存しない）
- 自動クリーンアップでメモリリーク防止
- シェーダーベースの描画で軽量
