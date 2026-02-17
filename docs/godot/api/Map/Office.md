# Office

**継承**: [MapBase](MapBase.md)

**ファイル**: `scripts/maps/office.gd`

## 概要

Officeマップの初期化スクリプト。MapBaseを継承し、壁・ドア・床のコリジョンレイヤーを視界システムと移動ブロッキング用に設定します。

## メソッド

### _ready()

マップ名を"OFFICE"に設定し、親クラスの初期化を実行します。

## 関連

- [MapBase](MapBase.md) - マップ基底クラス
- [MapManager](../Systems/MapManager.md) - マップ管理システム
