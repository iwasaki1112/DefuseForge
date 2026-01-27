# Bank

## 概要

Bankマップの初期化スクリプト。壁・ドアのコリジョンレイヤー設定とドアグループ登録を行い、視界計算用の壁キャッシュを更新する。

## クラス情報

- **継承**: `Node3D`
- **ファイル**: `scripts/maps/bank.gd`

## 主な処理

### `_ready() -> void`
マップ内のStaticBody3Dを走査し、壁/ドアのコリジョンレイヤーとグループを設定する。

### `_setup_collisions(node: Node) -> void`
`wall_` / `door_`プレフィックスを持つノード（またはその親）に対してコリジョンレイヤーを設定する。

## 関連クラス

- [VisionComponent](VisionComponent.md)
- [GameConstants](GameConstants.md)

## APIリファレンス

### シグナル
なし

### メソッド
なし
