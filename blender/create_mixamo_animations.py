"""
Mixamo Animations Master File Creator

このスクリプトをBlenderのスクリプトエディタ（Scripting タブ）で実行してください。

機能:
1. vanguard.glb をインポート
2. メッシュを削除（Armatureとアニメーションのみ残す）
3. 全ActionにFake Userを設定
4. mixamo_animations.blend として保存
"""

import bpy
import os

# パス設定（必要に応じて変更）
PROJECT_ROOT = "/Users/iwasakishungo/Git/github.com/iwasaki1112/godot"
VANGUARD_GLB = os.path.join(PROJECT_ROOT, "godot/assets/characters/vanguard/vanguard.glb")
OUTPUT_BLEND = os.path.join(PROJECT_ROOT, "blender/mixamo_animations.blend")

def clear_scene():
    """シーンをクリア"""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

    # 全てのメッシュデータを削除
    for mesh in bpy.data.meshes:
        bpy.data.meshes.remove(mesh)

    # 使われていないデータをクリア
    for block in bpy.data.meshes:
        if block.users == 0:
            bpy.data.meshes.remove(block)

def import_glb(filepath):
    """GLBファイルをインポート"""
    print(f"Importing: {filepath}")
    bpy.ops.import_scene.gltf(filepath=filepath)
    print("Import complete")

def remove_meshes():
    """メッシュオブジェクトを削除、Armatureのみ残す"""
    # 全オブジェクトを走査
    objects_to_delete = []
    armature = None

    for obj in bpy.data.objects:
        if obj.type == 'ARMATURE':
            armature = obj
            print(f"Found Armature: {obj.name}")
        elif obj.type == 'MESH':
            objects_to_delete.append(obj)
            print(f"Will delete Mesh: {obj.name}")
        elif obj.type == 'EMPTY':
            # 空のオブジェクト（GLTFルートなど）も削除候補
            if not obj.children:
                objects_to_delete.append(obj)

    # メッシュを削除
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects_to_delete:
        obj.select_set(True)

    bpy.ops.object.delete()

    # 未使用メッシュデータを削除
    for mesh in bpy.data.meshes:
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)

    # 未使用マテリアルを削除
    for mat in bpy.data.materials:
        if mat.users == 0:
            bpy.data.materials.remove(mat)

    # 未使用テクスチャを削除
    for img in bpy.data.images:
        if img.users == 0:
            bpy.data.images.remove(img)

    print(f"Deleted {len(objects_to_delete)} mesh objects")
    return armature

def setup_fake_users():
    """全ActionにFake Userを設定"""
    actions = bpy.data.actions
    print(f"\nFound {len(actions)} actions:")

    for action in actions:
        action.use_fake_user = True
        print(f"  - {action.name} (Fake User: ON)")

    return len(actions)

def reset_armature_to_rest(armature):
    """ArmatureをRESTポーズにリセット"""
    if not armature:
        return

    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)

    # RESTポーズに戻す
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.select_all(action='SELECT')
    bpy.ops.pose.transforms_clear()
    bpy.ops.object.mode_set(mode='OBJECT')

    print("Armature reset to REST pose")

def save_blend(filepath):
    """Blendファイルとして保存"""
    # ディレクトリが存在することを確認
    os.makedirs(os.path.dirname(filepath), exist_ok=True)

    bpy.ops.wm.save_as_mainfile(filepath=filepath)
    print(f"\nSaved: {filepath}")

def main():
    print("=" * 50)
    print("Mixamo Animations Master File Creator")
    print("=" * 50)

    # ファイル存在確認
    if not os.path.exists(VANGUARD_GLB):
        print(f"ERROR: File not found: {VANGUARD_GLB}")
        return

    # Step 1: シーンをクリア
    print("\n[Step 1] Clearing scene...")
    clear_scene()

    # Step 2: GLBをインポート
    print("\n[Step 2] Importing vanguard.glb...")
    import_glb(VANGUARD_GLB)

    # Step 3: メッシュを削除
    print("\n[Step 3] Removing meshes...")
    armature = remove_meshes()

    # Step 4: ArmatureをRESTポーズに
    print("\n[Step 4] Resetting armature to REST pose...")
    reset_armature_to_rest(armature)

    # Step 5: Fake Userを設定
    print("\n[Step 5] Setting Fake Users on Actions...")
    action_count = setup_fake_users()

    # Step 6: 保存
    print("\n[Step 6] Saving blend file...")
    save_blend(OUTPUT_BLEND)

    print("\n" + "=" * 50)
    print("COMPLETE!")
    print(f"  - Armature: {armature.name if armature else 'None'}")
    print(f"  - Actions: {action_count}")
    print(f"  - Output: {OUTPUT_BLEND}")
    print("=" * 50)

if __name__ == "__main__":
    main()
