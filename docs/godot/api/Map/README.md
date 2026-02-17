# Map API

マップは自己記述型の `.tscn` シーンとして `scenes/maps/` に配置される。各マップは `MapBase` を継承し、`@export` でメタデータ（`map_id`, `map_name` 等）を埋め込む。

| クラス | 概要 |
|--------|------|
| [MapBase](MapBase.md) | マップ基底クラス（GridMapセルからStaticBody3D生成、FoW occluder抽出） |

## マップ登録方式

`MapRegistry` が `scenes/maps/*.tscn` をスキャンし、`map_id` @export 付き MapBase シーンを自動検出・登録する。個別のマップスクリプトは不要。

詳細: [MapRegistry](../Registry/MapRegistry.md)
