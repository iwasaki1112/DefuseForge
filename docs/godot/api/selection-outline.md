# Selection Outline API

Godot 4.5のステンシルバッファ機能を使用した選択アウトライン効果。キャラクター選択時にシルエット外周に発光アウトラインを表示する。

## 概要

Godot 4.5で追加された`BaseMaterial3D.STENCIL_MODE_OUTLINE`を使用。メッシュを複製せず、マテリアルのステンシルモードを設定するだけでアウトラインを描画できる。

## 必要バージョン

- **Godot 4.5以上**（ステンシルバッファサポートが必要）

---

## BaseMaterial3D ステンシルプロパティ

### stencil_mode

```gdscript
BaseMaterial3D.StencilMode
```

| 値 | 定数 | Description |
|----|------|-------------|
| `0` | `STENCIL_MODE_DISABLED` | ステンシル無効（デフォルト） |
| `1` | `STENCIL_MODE_OUTLINE` | アウトライン表示 |
| `2` | `STENCIL_MODE_XRAY` | X-Ray（遮蔽物越し表示） |
| `3` | `STENCIL_MODE_CUSTOM` | カスタムステンシル |

---

### stencil_outline_thickness

```gdscript
float stencil_outline_thickness = 0.01
```

アウトラインの太さ。値が大きいほど太くなる。

| 値の目安 | 見た目 |
|----------|--------|
| `0.01` | デフォルト（細い） |
| `0.5` | やや細い |
| `2.0` | 標準的な太さ |
| `3.5` | 太め（推奨） |
| `5.0+` | かなり太い |

---

### stencil_color

```gdscript
Color stencil_color = Color(1, 1, 1, 1)
```

アウトラインの色。

**推奨色**:
- シアン: `Color(0.0, 0.8, 1.0, 1.0)` - 選択表示向け
- 緑: `Color(0.0, 1.0, 0.0, 1.0)` - 味方表示向け
- 赤: `Color(1.0, 0.0, 0.0, 1.0)` - 敵表示向け

---

## 実装パターン

### 基本実装

```gdscript
extends Node3D

var outlined_meshes: Array[MeshInstance3D] = []

## アウトラインを適用
func apply_outline(character: Node, color: Color = Color(0.0, 0.8, 1.0, 1.0), thickness: float = 3.5) -> void:
    var meshes = _find_mesh_instances(character)

    for mesh in meshes:
        var surface_count = mesh.mesh.get_surface_count() if mesh.mesh else 0
        for i in range(surface_count):
            var mat = mesh.get_active_material(i)
            if mat and mat is StandardMaterial3D:
                # マテリアルを複製してステンシルアウトラインを設定
                var mat_copy: StandardMaterial3D = mat.duplicate()
                mat_copy.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE
                mat_copy.stencil_outline_thickness = thickness
                mat_copy.stencil_color = color
                mesh.set_surface_override_material(i, mat_copy)
        outlined_meshes.append(mesh)


## アウトラインを削除
func clear_outline() -> void:
    for mesh in outlined_meshes:
        if is_instance_valid(mesh):
            var surface_count = mesh.mesh.get_surface_count() if mesh.mesh else 0
            for i in range(surface_count):
                mesh.set_surface_override_material(i, null)
    outlined_meshes.clear()


## MeshInstance3Dを再帰的に探す
func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
    var result: Array[MeshInstance3D] = []
    if node is MeshInstance3D:
        result.append(node)
    for child in node.get_children():
        result.append_array(_find_mesh_instances(child))
    return result
```

---

### 選択システムとの統合

```gdscript
var selected_character: Node = null

func _select_character(character: Node) -> void:
    # 以前の選択をクリア
    clear_outline()

    # 新しいキャラクターを選択
    selected_character = character
    if character:
        apply_outline(character)


func _deselect_character() -> void:
    clear_outline()
    selected_character = null
```

---

### チーム別カラー

```gdscript
func apply_team_outline(character: GameCharacter) -> void:
    var color: Color
    match character.team:
        GameCharacter.Team.COUNTER_TERRORIST:
            color = Color(0.0, 0.5, 1.0, 1.0)  # 青
        GameCharacter.Team.TERRORIST:
            color = Color(1.0, 0.3, 0.0, 1.0)  # オレンジ
        _:
            color = Color(1.0, 1.0, 1.0, 1.0)  # 白

    apply_outline(character, color)
```

---

### 非StandardMaterial3D対応

```gdscript
func apply_outline_safe(character: Node) -> void:
    var meshes = _find_mesh_instances(character)

    for mesh in meshes:
        var surface_count = mesh.mesh.get_surface_count() if mesh.mesh else 0
        for i in range(surface_count):
            var mat = mesh.get_active_material(i)

            if mat and mat is StandardMaterial3D:
                # StandardMaterial3Dの場合は複製
                var mat_copy: StandardMaterial3D = mat.duplicate()
                mat_copy.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE
                mat_copy.stencil_outline_thickness = 3.5
                mat_copy.stencil_color = Color(0.0, 0.8, 1.0, 1.0)
                mesh.set_surface_override_material(i, mat_copy)
            else:
                # その他のマテリアルは新規StandardMaterial3Dで上書き
                var new_mat = StandardMaterial3D.new()
                new_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE
                new_mat.stencil_outline_thickness = 3.5
                new_mat.stencil_color = Color(0.0, 0.8, 1.0, 1.0)
                mesh.set_surface_override_material(i, new_mat)

        outlined_meshes.append(mesh)
```

---

## 注意事項

### マテリアル複製の重要性

```gdscript
# 悪い例: 元のマテリアルを直接変更
mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE  # 他のインスタンスにも影響

# 良い例: 複製してから変更
var mat_copy = mat.duplicate()
mat_copy.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE
mesh.set_surface_override_material(i, mat_copy)
```

### サーフェスオーバーライドのクリア

```gdscript
# アウトライン解除時は null を設定
mesh.set_surface_override_material(i, null)
# これにより元のマテリアルが復元される
```

### スケルトンメッシュ対応

ステンシル方式はマテリアルプロパティのみを変更するため、スケルトンアニメーションに自動的に追従する。メッシュ複製方式のようなスケルトン同期問題が発生しない。

---

## 代替手法との比較

| 手法 | メリット | デメリット |
|------|----------|------------|
| **ステンシル（推奨）** | シンプル、高パフォーマンス、アニメーション追従 | Godot 4.5以上必須 |
| メッシュ複製+cull_front | 旧バージョン対応 | スケルトン同期が複雑 |
| SubViewport+エッジ検出 | 高品質なエッジ | パフォーマンスコスト高 |
| next_pass シェーダー | カスタマイズ性高 | 設定が複雑 |

---

## 関連

- [GameCharacter](game-character.md)
- [ContextMenuComponent](context-menu-component.md)
- [Godot PR #80710 - Add stencil support to spatial materials](https://github.com/godotengine/godot/pull/80710)
- [godot-stencil-demo](https://github.com/apples/godot-stencil-demo)
