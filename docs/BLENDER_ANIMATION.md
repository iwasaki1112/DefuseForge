# Blender Animation Guide

## 概要
このプロジェクトではMixamoリギングを使用した共通のアニメーションシステムを採用しています。

## アニメーションマスターファイル

### `blender/mixamo_animations.blend`
Mixamo互換のマスターアニメーションファイルです。新キャラクター追加時にこのファイルからアニメーションをリンク/アペンドできます。

**含まれるアニメーション:**
| Action名 | 用途 |
|----------|------|
| Rifle_Idle | 待機 |
| Rifle_WalkFwdLoop | 歩行（ループ） |
| Rifle_SprintLoop | 走行（ループ） |
| Rifle_CrouchLoop | しゃがみ（ループ） |
| Rifle_Death_L | 死亡（左） |
| Rifle_Death_R | 死亡（右） |
| Rifle_Death_3 | 死亡（バリエーション） |
| Rifle_OpenDoor | ドア開閉 |
| Rifle_Reload_2 | リロード |

## 新キャラクターへのアニメーション適用

### 方法: Blenderでアペンド
```
1. 新キャラクターの.blendファイルを開く
2. File > Append > mixamo_animations.blend > Action
3. 必要なActionを全て選択してアペンド
4. NLA EditorでArmatureを選択
5. 各ActionをPush Down（NLAトラックに追加）
6. GLBエクスポート
```

### エクスポート設定
- Format: glTF Binary (.glb)
- Include: ✓ Armatures, ✓ Animations (NLA Tracks)
- Animation: Export NLA Tracks にチェック

## 新アニメーション追加（リターゲット）

### 前提条件
- Auto-Rig Pro (Blenderアドオン)
- MixamoのTポーズFBX

### 手順
1. `blender/animations/` から新しいアニメーションGLBを開く
2. MixamoのTポーズFBXをインポート
3. Auto-Rig Proでリターゲット:
   - Build Bones Listでボーンリストを表示
   - PoseモードでKUBOLDの方をMIXAMOのキャラクターと同じポーズに角度を調整
   - Refile Rest Poseボタンを押す
   - Current Poseを選択してOK
   - Applyする（KUBOLDキャラクターのポーズが元に戻る）
   - Re-Targetボタンを押す（MIXAMOがKUBOLDのTポーズと一致）
4. リターゲット済みActionを `mixamo_animations.blend` にアペンド
5. Fake Userを設定して保存

## ファイル構成

```
blender/
├── mixamo_animations.blend  # マスターアニメーションファイル
├── animations/              # オリジナルアニメーション（Mixamo非互換）
│   ├── rifle_animset_pro.glb
│   └── ...
├── characters/              # キャラクターBlendファイル用
└── remap_preset.bmap        # Auto-Rig Proリマップ設定
```

## 注意事項
- 全ActionにFake Userが設定されています（保存時に消えない）
- Armature名は `2.COUNTER_TERRORIST2` (Mixamo標準)
- ボーン名は `mixamorig_*` プレフィックス
