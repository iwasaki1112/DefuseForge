# ShellEjectionComponent

射撃時に薬莢を銃から排出するエフェクトコンポーネント。薬莢は放物線を描いて地面に落下し、数秒後にフェードアウトして消える。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `RefCounted` |
| ファイルパス | `scripts/characters/shell_ejection_component.gd` |
| 3Dモデル | `assets/effects/bullet_casing.glb` |

## 定数

| 定数 | 値 | 説明 |
|------|-----|------|
| `MAX_CASINGS` | `20` | 同時表示最大数（オブジェクトプール） |
| `CASING_LIFETIME` | `3.0` | 地面到達後の表示時間（秒） |
| `CASING_FADE_DURATION` | `0.5` | フェードアウト時間（秒） |
| `GRAVITY` | `9.8` | 重力加速度 |
| `EJECT_SPEED_RIGHT` | `1.5` | 横方向射出速度（m/s） |
| `EJECT_SPEED_UP` | `2.0` | 上方向射出速度（m/s） |
| `EJECT_SPEED_FORWARD` | `0.3` | 前後方向射出速度（m/s） |
| `SPIN_SPEED` | `720.0` | 回転速度（度/秒） |
| `CASING_SCALE` | `2.0` | トップダウン視認性向上スケール |

## Public API

### setup(character: Node3D, weapon_socket: Node3D) -> void
コンポーネントをセットアップする。

### set_weapon_socket(socket: Node3D) -> void
武器ソケットを更新する。

### warm_up() -> void
ウォームアップ（他コンポーネントとのインターフェース一貫性用）。

### play(current_weapon: Resource, weapon_model: Node3D) -> void
薬莢を排出する。射撃イベント時にGameCharacterから呼び出される。

### cleanup() -> void
全プールオブジェクトを解放する。

## 内部動作

### 薬莢排出の流れ
1. 武器ソケットの位置からキャラクターの右方向にオフセットして排出位置を決定
2. オブジェクトプールから利用可能な薬莢を取得（非表示のものを優先、なければ新規作成、上限超過なら最古を再利用）
3. ランダム化した射出速度と回転を適用
4. Tweenで放物線軌道をアニメーション（重力シミュレーション）
5. 地面到達後、`CASING_LIFETIME`秒間静止
6. `CASING_FADE_DURATION`秒かけて`transparency`プロパティでフェードアウト
7. 非表示にしてプール再利用可能状態に戻す

### パフォーマンス最適化（モバイル向け）
- オブジェクトプール方式で薬莢ノードを再利用（GC負荷軽減）
- 影描画無効（`SHADOW_CASTING_SETTING_OFF`）
- 最大20個の同時表示制限
- GLBメッシュを全薬莢で共有（GPU VRAM節約）
