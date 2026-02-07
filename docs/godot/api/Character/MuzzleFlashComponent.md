# MuzzleFlashComponent

射撃時のマズルフラッシュエフェクト表示を管理するコンポーネント。GameCharacterから抽出された機能。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `RefCounted` |
| ファイルパス | `scripts/characters/muzzle_flash_component.gd` |

## Constants

| 定数 | 値 | 説明 |
|------|-----|------|
| `MUZZLE_FLASH_BASE_SIZE` | `0.25` | マズルフラッシュの基本サイズ |
| `MUZZLE_FLASH_SCALE_MULTIPLIER` | `200.0` | スケール倍率 |
| `MUZZLE_FLASH_DURATION` | `0.09` | 表示時間（3フレーム × 0.03秒） |
| `MUZZLE_FLASH_FRAME_TIME` | `0.03` | 各フレームの表示時間 |

## Public API

### setup(character: Node3D, weapon_socket: Node3D) -> void
コンポーネントを初期化する。

**引数:**
- `character` - 所有キャラクター
- `weapon_socket` - 武器ソケットノード

### set_weapon_socket(socket: Node3D) -> void
武器ソケットを更新する。武器切り替え時に使用。

### play(current_weapon: Resource, weapon_model: Node3D) -> void
マズルフラッシュを再生する。

**引数:**
- `current_weapon` - 現在装備中の武器リソース
- `weapon_model` - 武器の3Dモデル

**動作:**
1. 武器のオフセット/回転/スケール設定を取得
2. スプライトシートアニメーション再生（3フレーム）
3. スケールとフェードアウトのTween再生
4. OmniLight3Dによる光源エフェクト

### set_preview(enabled: bool, current_weapon: Resource, weapon_model: Node3D) -> void
プレビューモードを切り替える。エディタや調整画面で使用。

### update_preview(current_weapon: Resource, weapon_model: Node3D) -> void
プレビューを更新する。

### get_world_position() -> Vector3
マズルフラッシュのワールド位置を取得する。BulletTrailComponentから使用される。

**戻り値:** マズルフラッシュのグローバル座標（無効な場合はVector3.ZERO）

### set_quad1_x(x_offset: float) -> void
Quad1のXオフセットを設定する。

### get_quad1_x() -> float
Quad1のXオフセットを取得する。

### set_quad1_z(z_offset: float) -> void
Quad1のZオフセットを設定する。

### get_quad1_z() -> float
Quad1のZオフセットを取得する。

## 内部動作

### マズルフラッシュ構造
- 2枚のQuadMesh（直交配置でビルボード効果）
- OmniLight3D（オレンジ色の光源）
- スプライトシートアニメーション（3フレーム）

### オフセット自動計算
武器リソースに`muzzle_flash_offset`が設定されていない場合、武器モデルのAABBから銃口位置を自動計算する：
1. 武器モデル配下のMeshInstance3Dを全て収集
2. グローバル変換を考慮してAABBを合成
3. Z軸方向の最遠端を銃口位置として使用

## 使用例

```gdscript
# GameCharacterでのセットアップ（内部実装）
muzzle_flash = MuzzleFlashComponent.new()
muzzle_flash.setup(self, weapon_socket)

# 射撃時
func fire() -> void:
    muzzle_flash.play(current_weapon, weapon_model)
```

## パフォーマンス考慮

- ノードは遅延作成（初回play()時に作成）
- Tweenはキャラクターから作成（キャラクター破棄時に自動停止）
- テクスチャはpreloadで事前ロード
