# 武器追加ガイド

新しい武器を追加するための手順書です。

## 目次
1. [概要](#概要)
2. [ファイル構造](#ファイル構造)
3. [Blenderでのモデル準備](#blenderでのモデル準備)
4. [追加手順](#追加手順)
5. [WeaponResourceの設定](#weaponresourceの設定)
6. [左手IKの調整](#左手ikの調整)
7. [動作確認](#動作確認)

---

## 概要

武器システムは以下の3つのコンポーネントで構成されています：

| コンポーネント | 役割 |
|--------------|------|
| **WeaponResource** (.tres) | 武器のステータス・設定データ |
| **武器シーン** (.tscn) | 3Dモデル・MuzzlePoint・LeftHandGrip |
| **WeaponDatabase** | 武器データの一元管理・検索 |

## ファイル構造

```
SupportRateGame/
├── resources/weapons/
│   └── {weapon_id}/           # 武器ID名のフォルダ
│       ├── {weapon_id}.tres   # 武器リソースファイル（必須）
│       ├── {weapon_id}.glb    # 3Dモデル（任意：直接配置する場合）
│       └── textures/          # テクスチャ（任意）
│
├── scenes/weapons/
│   └── {weapon_id}.tscn       # 武器シーン（必須）
│
└── assets/weapons/            # 元アセット保管（任意）
    └── {weapon_id}/
```

---

## Blenderでのモデル準備

GLBファイルをエクスポートする前に、Blenderで正しい階層構造を作成する必要があります。

### 必須の階層構造

```
{WeaponID}_Root (Empty)
├── {WeaponID} (Mesh)              # 武器のメッシュ（複数パーツは結合）
└── LeftHandGrip_{WeaponID} (Empty) # 左手IKのターゲット位置
```

**例: AK47の場合**
```
AK47_Root (Empty)
├── AK47 (Mesh)
└── LeftHandGrip_AK47 (Empty)
```

**例: M4A1の場合**
```
M4A1_Root (Empty)
├── M4A1 (Mesh)
└── LeftHandGrip_M4A1 (Empty)
```

> **重要**: LeftHandGripには必ず武器IDを付けてください（例: `LeftHandGrip_AK47`）。
> Blenderでは同名オブジェクトが作成できないため、武器ごとにユニークな名前にする必要があります。

### Blenderでの作成手順

#### 1. メッシュの準備

武器モデルが複数パーツに分かれている場合は結合します：

1. 全てのメッシュパーツを選択（Shift+クリック）
2. `Ctrl+J` で結合
3. 結合したメッシュを武器ID名にリネーム（例: "M4"）

#### 2. ルートEmptyの作成

1. `Add > Empty > Plain Axes` でEmptyを追加
2. 名前を `{WeaponID}_Root` に設定（例: "M4_Root"）
3. 位置を原点 (0, 0, 0) に設定

#### 3. メッシュをルートの子にする

1. メッシュを選択
2. Shift+クリックでルートEmptyも選択（ルートが最後）
3. `Ctrl+P` > `Object` で親子関係を設定

#### 4. LeftHandGripの作成

1. `Add > Empty > Plain Axes` でEmptyを追加
2. 名前を `LeftHandGrip_{WeaponID}` に設定（例: `LeftHandGrip_AK47`）
3. 左手が握る位置（ハンドガード/フォアグリップ付近）に配置
4. ルートEmptyの子にする（上記と同じ手順）

> **注意**: 必ず武器IDを含めた名前にしてください。単なる `LeftHandGrip` だと他の武器と名前が衝突します。

#### 5. スケールと向きの調整

- **スケール**: AK47と同じサイズになるように調整
  - AK47の全長は約1.0m（Blender単位）
- **向き**: 銃口が **+Y方向** を向くように配置
- **原点**: グリップ部分が原点付近に来るように調整

#### 6. トランスフォームの適用

エクスポート前に必ず適用：

1. ルートEmptyとその子を全て選択
2. `Ctrl+A` > `All Transforms` で適用

### GLBエクスポート

1. ルートEmpty（{WeaponID}_Root）とその子を全て選択
2. `File > Export > glTF 2.0 (.glb/.gltf)`
3. エクスポート設定：
   - Format: `glTF Binary (.glb)`
   - Include: `Selected Objects` にチェック
   - Transform: `+Y Up` （デフォルト）
   - Mesh: `Apply Modifiers` にチェック

**エクスポート先:**
```
SupportRateGame/resources/weapons/{weapon_id}/{weapon_id}.glb
```

### 参考: AK47のLeftHandGrip_AK47位置

```
Location: (0.175, 0.009, 0.087)
```

※ 武器によって異なるため、目視で調整してください。

---

## 追加手順

### Step 1: 3Dモデルの準備

1. GLBフォーマットで武器モデルを用意
2. モデルの向き：
   - 銃口が **-Z方向**（前方）を向くように配置
   - グリップ部分がY軸の原点付近に来るように調整

### Step 2: 武器シーンの作成

`scenes/weapons/{weapon_id}.tscn` を作成：

```
{weapon_id} (Node3D)
├── {model_name} (インポートしたGLBモデル)
├── MuzzlePoint (Node3D)      # マズルフラッシュ・弾道の発射位置
└── LeftHandGrip (Node3D)     # 左手IKのターゲット位置（参考用）
```

**MuzzlePointの設定：**
- 銃口の位置に配置
- Z軸が射撃方向を向くように回転

**LeftHandGripの設定（任意）：**
- 左手が握る位置の目安として配置
- 実際のIK位置は.tresファイルで調整

### Step 3: 武器リソースファイルの作成

`resources/weapons/{weapon_id}/{weapon_id}.tres` を作成：

```gdscript
[gd_resource type="Resource" script_class="WeaponResource" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/weapon_resource.gd" id="1_script"]

[resource]
script = ExtResource("1_script")

weapon_id = "m4a1"
weapon_name = "M4A1"
weapon_type = 1

price = 3100
kill_reward = 300

damage = 33.0
fire_rate = 0.09
accuracy = 0.90
effective_range = 22.0

headshot_multiplier = 4.0
bodyshot_multiplier = 1.0

scene_path = "res://scenes/weapons/m4a1.tscn"

attach_position = Vector3(0, 0, 0)
attach_rotation = Vector3(0, 0, 0)

left_hand_ik_enabled = true
left_hand_ik_position = Vector3(-0.02, -0.06, -0.07)
left_hand_ik_rotation = Vector3(-67, -165, 4)
left_hand_ik_disabled_anims = PackedStringArray("rifle_reload", "rifle_death", "rifle_open_door")
```

### Step 4: WeaponDatabaseへの登録

武器リソースファイルが `resources/weapons/{weapon_id}/{weapon_id}.tres` に配置されていれば、`WeaponDatabase.load_from_directory()` で自動的に読み込まれます。

手動で登録する場合は、`resources/weapon_database.tres` の `weapons` 配列に追加してください。

---

## WeaponResourceの設定

### 基本情報

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `weapon_id` | String | 武器の一意識別子（例: "ak47", "m4a1"） |
| `weapon_name` | String | 表示名（例: "AK-47"） |
| `weapon_type` | int | 武器タイプ: 0=NONE, 1=RIFLE, 2=PISTOL |

### コスト

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `price` | int | 購入価格 |
| `kill_reward` | int | キル報酬（デフォルト: 300） |

### 戦闘性能

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `damage` | float | 基本ダメージ |
| `fire_rate` | float | 発射間隔（秒）※小さいほど連射が速い |
| `accuracy` | float | 基本命中率（0.0〜1.0） |
| `effective_range` | float | 有効射程距離（メートル） |

### ダメージ倍率

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `headshot_multiplier` | float | ヘッドショット倍率（デフォルト: 4.0） |
| `bodyshot_multiplier` | float | ボディショット倍率（デフォルト: 1.0） |

### リソース

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `scene_path` | String | 武器シーンのパス（例: "res://scenes/weapons/ak47.tscn"） |

### 装着位置

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `attach_position` | Vector3 | 右手ボーンからの相対位置 |
| `attach_rotation` | Vector3 | 右手ボーンからの相対回転（度数） |

### 左手IK設定

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `left_hand_ik_enabled` | bool | 左手IKを使用するか |
| `left_hand_ik_position` | Vector3 | 左手IKの位置オフセット |
| `left_hand_ik_rotation` | Vector3 | 左手IKの回転オフセット（度数） |
| `left_hand_ik_disabled_anims` | PackedStringArray | IKを無効にするアニメーション名リスト |

---

## 左手IKの調整

左手IKは、武器を両手で構えるアニメーションを実現するための機能です。

### 調整方法

1. **test_animation_viewer** シーンを使用して調整
2. 武器リソースの `left_hand_ik_position` と `left_hand_ik_rotation` を編集
3. Godotエディタでシーンを実行し、見た目を確認
4. 満足するまで値を調整

### AK47の参考値

```
left_hand_ik_position = Vector3(-0.02, -0.06, -0.07)
left_hand_ik_rotation = Vector3(-67, -165, 4)
```

### IKを無効にするアニメーション

リロードや死亡アニメーションなど、左手が武器から離れるアニメーションでは IKを無効にする必要があります。

```
left_hand_ik_disabled_anims = PackedStringArray("rifle_reload", "rifle_death", "rifle_open_door")
```

**よく使うアニメーション名：**
- `rifle_reload` - リロード
- `rifle_death` - 死亡
- `rifle_open_door` - ドア開け
- `pistol_reload` - ピストルリロード

---

## 動作確認

### test_animation_viewerでの確認

1. `scenes/tests/test_animation_viewer.tscn` を開く
2. シーンを実行（F5）
3. 右側のパネル上部のドロップダウンから武器を選択
4. アニメーションボタンで各アニメーションを確認
5. Left Hand IK スライダーで位置・回転を調整
6. 「Print IK Values」ボタンで調整した値をコンソールに出力
7. 出力された値を `.tres` ファイルにコピー

### 武器切り替え機能

test_animation_viewerは `resources/weapons/` ディレクトリを自動スキャンし、利用可能な武器をドロップダウンに表示します。

新しい武器を追加した場合：
1. `resources/weapons/{weapon_id}/{weapon_id}.tres` を作成
2. test_animation_viewerを再起動
3. ドロップダウンに新しい武器が表示される

### チェックリスト

- [ ] 武器モデルが正しく表示される
- [ ] 武器が右手に正しく装着されている
- [ ] 左手が武器のグリップ部分を握っている
- [ ] リロードアニメーション時に左手IKが無効になる
- [ ] 各種アニメーションが正しく再生される

---

## 武器タイプ別の注意点

### ライフル (weapon_type = 1)

- 両手持ちアニメーション（rifle_*）を使用
- 左手IKの調整が必要
- `left_hand_ik_disabled_anims` に "rifle_reload" などを追加

### ピストル (weapon_type = 2)

- 片手/両手持ちアニメーション（pistol_*）を使用
- 左手IKは任意（片手持ちの場合は無効に）
- `left_hand_ik_enabled = false` で片手持ちに

---

## トラブルシューティング

### 武器が表示されない

1. `scene_path` が正しいか確認
2. シーンファイルが存在するか確認
3. GLBモデルが正しくインポートされているか確認

### 左手の位置がおかしい

1. `left_hand_ik_position` と `left_hand_ik_rotation` を調整
2. test_animation_viewer で確認しながら微調整

### 武器がWeaponDatabaseに読み込まれない

1. ファイル構造を確認: `resources/weapons/{weapon_id}/{weapon_id}.tres`
2. `.tres` ファイルの `script_class` が `WeaponResource` か確認
3. `weapon_id` が空でないか確認

### アニメーション再生時にエラー

1. アニメーション名が正しいか確認
2. AnimationPlayerのアニメーションライブラリを確認
