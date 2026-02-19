# BloodEffectComponent

被弾時の血しぶきエフェクトコンポーネント。GPUParticles3Dによるワンショットバーストで血しぶきを表現する。

## 基本情報

| 項目 | 値 |
|------|-----|
| クラス名 | `BloodEffectComponent` |
| 継承 | `RefCounted` |
| スクリプト | `scripts/characters/blood_effect_component.gd` |

## セットアップ

`GameCharacter._setup_effect_components()` で自動生成される。

```gdscript
blood_effect = BloodEffectComponent.new()
blood_effect.setup(self)
```

## Public API

### `play(attacker_pos: Variant = null) -> void`

血しぶきエフェクトを再生する。

- `attacker_pos`: 攻撃者のワールド位置（`Vector3`）。指定すると攻撃者の反対方向にパーティクルが飛散する。`null`の場合はランダム方向。

### `warm_up() -> void`

GPUParticles3Dノードを事前生成する。シェーダーコンパイルのラグを防止。

## 発動タイミング

`GameCharacter.take_damage()` 内で自動的に呼び出される。

## テクスチャ

| 項目 | 値 |
|------|-----|
| パス | `res://assets/effects/bloods/1.png`, `res://assets/effects/bloods/2.png` |
| 形式 | 透過PNG（256×256px） |

再生のたびにランダムに1枚が選ばれる。テクスチャが存在しない場合は赤色のクワッドで代替表示される。

## パーティクル設定

| パラメータ | 値 |
|-----------|-----|
| パーティクル数 | 12 |
| ライフタイム | 0.4秒 |
| サイズ | 0.15m |
| 初速 | 1.5〜3.0 m/s |
| 重力 | -6.0 m/s² |
| 飛散角度 | 60° |
| 発生高さ | キャラクター原点 +0.8m（胴体） |
