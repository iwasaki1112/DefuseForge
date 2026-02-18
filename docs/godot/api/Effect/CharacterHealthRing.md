# CharacterHealthRing

キャラクター足元に表示されるHP円形インジケーター。

## 概要

- **継承**: `MeshInstance3D`
- **ファイル**: `scripts/effects/character_health_ring.gd`
- **シェーダー**: `shaders/health_ring.gdshader`
- **用途**: キャラクターのHP割合をリングの塗りつぶし量で視覚的に表示

## 機能

- HP割合に応じてリングの塗りつぶし量が変化（時計回りに12時から開始）
- HP割合に応じた色変化:
  - 50%超: 緑
  - 25%超: 黄色
  - 25%以下: 赤
- 未充填部分は暗い半透明背景で表示
- 死亡時は自動非表示
- HP変化時のみシェーダーパラメータ更新（パフォーマンス最適化）

## 定数

| 定数 | 値 | 説明 |
|------|-----|------|
| `RING_SIZE` | `1.0` | リングメッシュのサイズ（m） |
| `HEIGHT_OFFSET` | `0.05` | 地面からの高さ |

## 主要メソッド

### setup(character: GameCharacter) -> void

HPリングを初期化し、キャラクターに紐付ける。

## ライフサイクル

`GameCharacter._ready()` で自動的に作成・追加される。手動で生成する必要はない。

## シェーダーパラメータ

| パラメータ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `health_ratio` | `float` | `1.0` | HP割合（0.0〜1.0） |
| `ring_radius` | `float` | `0.80` | リングの半径（UV空間） |
| `ring_width` | `float` | `0.12` | リングの太さ（UV空間） |
| `color_high` | `vec4` | 緑 | HP > 50% の色 |
| `color_mid` | `vec4` | 黄 | HP 25%〜50% の色 |
| `color_low` | `vec4` | 赤 | HP <= 25% の色 |
| `bg_color` | `vec4` | 暗灰 | 未充填部分の色 |

## 関連クラス

- `GameCharacter` - HPリングのライフサイクル管理
