# Effect API

| クラス | 概要 |
|--------|------|
| [ActionMarker](ActionMarker.md) | アクションマーカーの基底クラス（Vision/Clear/Run/Door/Grenadeの共通機能） |
| [ActionMarkerData](ActionMarkerData.md) | マーカーデータの統一基底クラス＋各種マーカーデータサブクラス |
| [MarkerCollection](MarkerCollection.md) | マーカーの統一管理コレクション（タイプ別管理・Undo対応） |
| [PathDrawer](PathDrawer.md) | マウスドラッグでパス描画（ドア貫通可能）＋視線ポイント＋Run/Clear/Grenade/Doorマーカー設定 |
| [PathCalculator](PathCalculator.md) | パス計算ユーティリティ（最近点検索・オフセット計算等の静的メソッド） |
| [PathRaycastHelper](PathRaycastHelper.md) | レイキャスト・壁検出ユーティリティ（静的メソッド） |
| [PathInputHandler](PathInputHandler.md) | 入力処理統括（マーカーハンドラへの委譲） |
| [PathState](PathState.md) | パス状態管理（描画状態・モード・有効フラグ等） |
| [MarkerHandlerBase](MarkerHandlerBase.md) | マーカーハンドラ基底クラス（共通インターフェース） |
| [PathLineMesh](PathLineMesh.md) | 破線＋終点ドーナツ円のパスメッシュ描画 |
| [RunMarker](RunMarker.md) | Run区間の開始/終点を示すマーカー（ActionMarker継承） |
| [VisionMarker](VisionMarker.md) | 円＋矢印で視線方向を示すマーカー（ActionMarker継承） |
| [ClearMarker](ClearMarker.md) | Clearポイント（視線・Runリセット）を示すマーカー（ActionMarker継承） |
| [GrenadeMarker](GrenadeMarker.md) | パス上のグレネード投擲位置＋軌道を示すマーカー（ActionMarker継承） |
| [SmokeGrenadeMarker](SmokeGrenadeMarker.md) | スモークグレネード投擲アクションのプレビュー表示 |
| [DoorMarker](DoorMarker.md) | パス上のドアキック位置＋対象ドアを示すマーカー（ActionMarker継承） |
| [CharacterSelectedMarker](CharacterSelectedMarker.md) | 選択中キャラクター足元の回転マーカー |
| [SmokeArea](SmokeArea.md) | スモークの視覚効果と視線ブロックロジック |
| [WaitMarker](WaitMarker.md) | 待機（Wait）アクションマーカー |
