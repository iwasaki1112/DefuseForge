# LightingTest

## 概要

ライティング調整用のテストシーン。EnvironmentPresetを適用してキャラクターを1体スポーンし、ライトの見え方を確認する。

## クラス情報

- **継承**: `Node3D`
- **ファイル**: `scripts/tests/lighting_test.gd`

## 主な処理

### `_ready() -> void`
環境設定を行い、キャラクターをスポーンする。

### `_setup_environment() -> void`
`EnvironmentSetup`にデフォルトプリセットを適用して追加する。

### `_spawn_character() -> void`
`CharacterRegistry`を使ってテスト用キャラクターを生成する。

## 関連クラス

- [EnvironmentSetup](EnvironmentSetup.md)
- [CharacterRegistry](CharacterRegistry.md)

## APIリファレンス

### シグナル
なし

### メソッド
なし
