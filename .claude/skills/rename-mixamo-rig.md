# Mixamo Rig Rename Skill

Blenderで開いているMixamoリグのボーン名をRescueForgeプロジェクト用にリネームする。

## 概要

Mixamoからダウンロードしたキャラクターのボーン名には数字サフィックス（例: `mixamorig:RightHand_47`）が付いていることがある。このプロジェクトではサフィックスなしの標準Mixamo命名規則（例: `mixamorig:RightHand`）を期待するため、リネームが必要。

## 手順

### 1. Blenderシーン情報を確認

```
mcp__blender__get_scene_info
```

アーマチュアオブジェクトが存在することを確認。

### 2. ボーン名をリネーム

以下のBlenderコードを実行:

```python
import bpy
import re

# Find the armature
armature = None
for obj in bpy.data.objects:
    if obj.type == 'ARMATURE':
        armature = obj
        break

if not armature:
    print("Error: No armature found")
else:
    print(f"Processing armature: {armature.name}")

    # Pattern to match: mixamorig:BoneName_XX (where XX is numbers)
    pattern = re.compile(r'^(mixamorig:.+?)_(\d+)$')

    renamed_count = 0
    rename_map = {}

    # First pass: collect all renames
    for bone in armature.data.bones:
        match = pattern.match(bone.name)
        if match:
            new_name = match.group(1)
            rename_map[bone.name] = new_name

    # Second pass: apply renames
    for old_name, new_name in rename_map.items():
        bone = armature.data.bones.get(old_name)
        if bone:
            bone.name = new_name
            renamed_count += 1
            print(f"  {old_name} -> {new_name}")

    print(f"\nRenamed {renamed_count} bones")
```

### 3. アーマチュア名とルートジョイントを整理

```python
import bpy

armature = None
for obj in bpy.data.objects:
    if obj.type == 'ARMATURE':
        armature = obj
        break

if armature:
    # Rename armature
    armature.name = "Armature"
    armature.data.name = "Armature"

    # Rename root joint if it has GLTF prefix
    for bone in armature.data.bones:
        if "rootJoint" in bone.name or "root" in bone.name.lower():
            if bone.name != "Root":
                old_name = bone.name
                bone.name = "Root"
                print(f"Root renamed: {old_name} -> Root")
                break

    print(f"Armature renamed to: {armature.name}")
```

### 4. 主要ボーンの確認

```python
import bpy

armature = bpy.data.objects.get("Armature")
if armature:
    key_bones = ["Root", "mixamorig:Hips", "mixamorig:RightHand", "mixamorig:Spine1", "mixamorig:Spine2"]
    print("Key bones check:")
    for name in key_bones:
        bone = armature.data.bones.get(name)
        print(f"  {'OK' if bone else 'MISSING'} {name}")
```

## 期待されるボーン名（GLBエクスポート後）

Godotにインポートされると、コロン `:` はアンダースコア `_` に変換される:

| Blender | Godot |
|---------|-------|
| `mixamorig:RightHand` | `mixamorig_RightHand` |
| `mixamorig:Spine1` | `mixamorig_Spine1` |
| `mixamorig:Spine2` | `mixamorig_Spine2` |
| `mixamorig:Hips` | `mixamorig_Hips` |

## 関連ファイル

- `godot/scripts/utils/game_constants.gd` - ボーン名定数
- `godot/scripts/registries/character_registry.gd` - キャラクター生成
