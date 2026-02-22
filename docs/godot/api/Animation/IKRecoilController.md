# IKRecoilController

IKターゲット位置ベースのリコイル制御。射撃時にIKターゲット位置にオフセットを加算し、指数減衰で復帰する。

## 基本情報

| 項目 | 値 |
|------|-----|
| 継承元 | `Node` |
| ファイルパス | `scripts/modifiers/ik_recoil_controller.gd` |

## Public API

### trigger_recoil(strength: float) -> void
リコイルを発動。上方向（+Y）と後方向（-Z）にオフセットを加算。

### get_recoil_offset() -> Vector3
現在のリコイルオフセットを取得。UpperBodyIKControllerが毎フレーム参照。

### update(delta: float) -> void
毎フレーム更新。指数減衰で`Vector3.ZERO`に復帰。

### reset() -> void
リコイルをリセット。

## プロパティ

| プロパティ | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `recovery_speed` | `float` | `10.0` | 復帰速度 |
