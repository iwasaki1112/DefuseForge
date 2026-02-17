# Home

**継承**: [MapBase](MapBase.md)

**ファイル**: `scripts/maps/home.gd`

## 概要

Homeマップの初期化スクリプト。MapBaseを継承し、壁・ドア・床のコリジョンレイヤーを視界システムと移動ブロッキング用に設定します。

## プロパティ

継承元の[MapBase](MapBase.md)を参照。

## メソッド

### _ready()

マップ名を"HOME"に設定し、親クラスの初期化を実行します。

## 関連

- [MapBase](MapBase.md) - マップ基底クラス
- [MapManager](../Systems/MapManager.md) - マップ管理システム
