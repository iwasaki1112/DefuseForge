# WeaponAdjustment

## 概要

武器のアタッチ位置・回転、マズルフラッシュのオフセット/回転/スケールをリアルタイムに調整するテストツールシーン。

## クラス情報

- **継承**: `Node3D`
- **ファイル**: `scripts/tests/weapon_adjustment.gd`

## 主な機能

- キャラクター/武器の切り替え
- 武器のアタッチ位置と回転の調整
- マズルフラッシュの位置・回転・スケールの調整
- カメラアングルの切り替え

## 主な処理

### `_select_character(idx: int) -> void`
キャラクターを切り替えてシーンを再構築する。

### `_select_weapon(idx: int) -> void`
武器を装備して各UI値を同期する。

### `_update_transform() -> void`
武器ソケットの位置/回転を更新する。

### `_update_muzzle_flash() -> void`
マズルフラッシュの調整値を反映する。

## 関連クラス

- [GameCharacter](GameCharacter.md)
- [WeaponPreset](WeaponPreset.md)
- [CharacterPreset](CharacterPreset.md)
- [CharacterAnimationController](CharacterAnimationController.md)

## APIリファレンス

### シグナル
なし

### メソッド
なし
