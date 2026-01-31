# Effect API

| クラス | 概要 |
|--------|------|
| [ActionPoint](ActionPoint.md) | アクションポイントの基底クラス（Vision/Waitの共通機能） |
| [ActionPointData](ActionPointData.md) | ポイントデータの統一基底クラス＋Vision/Waitポイントデータサブクラス |
| [PointCollection](PointCollection.md) | ポイントの統一管理コレクション（タイプ別管理・Undo対応） |
| [PathDrawer](PathDrawer.md) | マウスドラッグでパス描画＋視線ポイント＋Waitポイント設定 |
| [PathCalculator](PathCalculator.md) | パス計算ユーティリティ（最近点検索・オフセット計算等の静的メソッド） |
| [PathRaycastHelper](PathRaycastHelper.md) | レイキャスト・壁検出ユーティリティ（静的メソッド） |
| [PointHandlerBase](PointHandlerBase.md) | ポイントハンドラ基底クラス（共通インターフェース） |
| [PointHandlers](PointHandlers.md) | 各アクションポイント（Vision/Wait）の入力ハンドラ詳細 |
| [PointFactory](PointFactory.md) | ポイントメッシュ作成ファクトリ（Vision/Wait作成の一元化） |
| [PathLineMesh](PathLineMesh.md) | 破線＋終点ドーナツ円のパスメッシュ描画 |
| [VisionPoint](VisionPoint.md) | 円＋矢印で視線方向を示すポイント（ActionPoint継承） |
| [WaitPoint](WaitPoint.md) | 待機（Wait）アクションポイント（ActionPoint継承） |
| [CharacterSelectedMarker](CharacterSelectedMarker.md) | 選択中キャラクター足元の回転マーカー |
| [SmokeArea](SmokeArea.md) | スモークの視覚効果と視線ブロックロジック |