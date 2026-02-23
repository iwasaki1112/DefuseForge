---
name: blender-weight-transfer
description: Blender MCPでARPリグのウェイト転送・調整を行う。KD-tree転送、指ウェイト統合、CorrectiveSmooth設定の全手順。
allowed-tools: Bash(*), Read, Write, Edit, Glob, Grep
---

# Blenderウェイト転送・調整ガイド

異なるメッシュ間でARPリグのウェイトを転送し、デフォーメーション品質を調整するガイド。
Blender MCP (`mcp__blender__execute_blender_code`) を使用。

## 前提条件

- ソースメッシュ（例: `base`）が正しくリギング済み
- ターゲットメッシュ（例: `base2`）が同じARPリグに親子関係設定済み
- `matrix_parent_inverse` が正しいこと（ずれている場合は `.identity()` でリセット）

## 全体フロー

```
1. 座標系の確認（スケール・回転・位置の差異把握）
2. KD-tree重心合わせウェイト転送（K=3体 / K=1手）
3. 指ウェイトの処理 ← メッシュ形状で分岐
   ├─ パターンA（5本指分離）→ そのまま使用、必要なら隣接指混在を修正
   └─ パターンB（ミトン型）→ 全指ウェイトをhandに統合
       └─ オプション: グリップ分割（指先をカールボーンに割当）
4. CorrectiveSmoothモディファイア追加（マスク付き）
5. ポーズ確認・微調整
```

## Step 1: 座標系の確認

ソースとターゲットのワールド変換を必ず確認する。

```python
import bpy
for name in ["base", "base2"]:
    obj = bpy.data.objects[name]
    print(f"{name}: location={obj.location[:]}, rotation={obj.rotation_euler[:]}")
    print(f"  matrix_world:\n{obj.matrix_world}")
```

**注意点**:
- ARP/Mixamoモデルはスケール0.01+90°X回転の場合がある
- `matrix_world` にはペアレント変換も含まれる
- `matrix_parent_inverse` にオフセットが焼かれている場合がある → `.identity()` でリセット

## Step 2: KD-tree重心合わせウェイト転送

メッシュ間のワールド位置オフセットを重心で補正し、最近傍マッチングでウェイトを転送する。

### 体: K=3加重平均 / 手: K=1単一最近傍

手/指エリアは繊細なため単一最近傍、体は滑らかな加重平均を使用。

```python
import bpy
from mathutils import Vector, kdtree

base = bpy.data.objects["base"]
base2 = bpy.data.objects["base2"]
rig = bpy.data.objects["base2_rig"]  # ターゲットのリグ

# ウェイトクリア
base2.vertex_groups.clear()

# 重心計算
base_world = [base.matrix_world @ v.co for v in base.data.vertices]
base2_world = [base2.matrix_world @ v.co for v in base2.data.vertices]
base_centroid = sum(base_world, Vector((0,0,0))) / len(base_world)
base2_centroid = sum(base2_world, Vector((0,0,0))) / len(base2_world)

# KD-tree構築（重心合わせ）
kd = kdtree.KDTree(len(base_world))
for i, pos in enumerate(base_world):
    kd.insert(pos - base_centroid, i)
kd.balance()

# 頂点グループ作成
group_map = {}
for vg in base.vertex_groups:
    new_vg = base2.vertex_groups.new(name=vg.name)
    group_map[vg.index] = new_vg.index

# 手エリア判定（ボーン近傍）
hand_bones = []
for bone in rig.data.bones:
    if bone.use_deform and any(kw in bone.name for kw in
            ['hand', 'pinky', 'ring', 'middle', 'index', 'thumb']):
        h = rig.matrix_world @ bone.head_local
        t = rig.matrix_world @ bone.tail_local
        hand_bones.append((h, t))

def is_near_hand(pos, threshold=0.06):
    for bh, bt in hand_bones:
        ab = bt - bh
        sq = ab.length_squared
        if sq < 1e-8:
            if (pos - bh).length < threshold: return True
            continue
        t = max(0, min(1, (pos - bh).dot(ab) / sq))
        if (pos - (bh + t * ab)).length < threshold: return True
    return False

hand_set = set()
for v in base2.data.vertices:
    if is_near_hand(base2.matrix_world @ v.co):
        hand_set.add(v.index)

# 転送実行
K_BODY = 3
for v2_idx, v2_pos in enumerate(base2_world):
    centered = v2_pos - base2_centroid
    if v2_idx in hand_set:
        # K=1: 手エリア
        co, idx, dist = kd.find(centered)
        for g in base.data.vertices[idx].groups:
            if g.group in group_map and g.weight > 0.001:
                base2.vertex_groups[group_map[g.group]].add(
                    [v2_idx], g.weight, 'REPLACE')
    else:
        # K=3: 体エリア
        neighbors = kd.find_n(centered, K_BODY)
        wa = {}
        ti = 0.0
        for co, idx, dist in neighbors:
            inf = 1.0 / (dist + 0.001)
            ti += inf
            for g in base.data.vertices[idx].groups:
                if g.group in group_map and g.weight > 0.001:
                    k = group_map[g.group]
                    wa[k] = wa.get(k, 0) + g.weight * inf
        if ti > 0:
            for gi, w in wa.items():
                nw = w / ti
                if nw > 0.001:
                    base2.vertex_groups[gi].add([v2_idx], nw, 'REPLACE')
```

### 品質指標

- 平均マッチング距離: 0.025m以下が理想
- 非空グループ: 68/68（ARPデフォームボーン全て）

## Step 3: 指ウェイトの処理（メッシュ形状で分岐）

KD-tree転送後、指のデフォーメーション品質を確認する。
**メッシュの指ジオメトリによって対応が異なる。**

### 判断方法: レストポーズで手を拡大表示

```python
# base2のレストポーズで手を拡大表示して目視確認
# ビューポートで手をズームし、指の形状を観察する
```

### パターンA: 指が5本独立したメッシュ（ハイポリ）

指が分離しており各指に十分な頂点がある場合、KD-tree転送のウェイトがそのまま使える。

**対応**: 追加作業なし（Step 2の転送結果をそのまま使用）

ただし以下を確認:
- 各指ボーンの頂点グループが非空であること
- game_idleなどのポーズで指が自然にカールすること
- 隣接する指のウェイトが混ざっていないこと（KD-treeで別の指にマッチするケースがある）

**隣接指のウェイト混在が起きた場合**: 指エリアのみボーン距離ベースのガウシアンウェイトで再計算する。
```python
import math
SIGMA = 0.012  # ガウシアン幅（指の太さに応じて調整）
# 各頂点から各指デフォームボーンへの距離を計算
# w = exp(-(d^2) / (2*SIGMA^2)) で重み付け → 正規化
```

### パターンB: ミトン型メッシュ（指が分離していない / ローポリ）

指のジオメトリが一体化している場合、個別の指ボーンウェイトはメッシュを崩壊させる。
**全指ウェイトを `hand` ボーンに統合する。**

典型的な症状:
- 指が引き裂かれたように変形する
- 面が反転する、頂点が飛ぶ
- レストポーズでは正常だがポーズ適用時に崩壊

### パターンBの統合コード

```python
finger_keywords = ['pinky', 'ring', 'middle', 'index', 'thumb']
for side in ['.l', '.r']:
    hand_vg = base2.vertex_groups.get(f"hand{side}")
    finger_vgs = [vg for vg in base2.vertex_groups
                  if vg.name.endswith(side)
                  and any(kw in vg.name for kw in finger_keywords)]

    for v in base2.data.vertices:
        finger_w = 0
        hand_w = 0
        for g in v.groups:
            vg = base2.vertex_groups[g.group]
            if vg.index == hand_vg.index:
                hand_w = g.weight
            elif vg in finger_vgs and g.weight > 0.001:
                finger_w += g.weight
        if finger_w > 0.001:
            hand_vg.add([v.index], hand_w + finger_w, 'REPLACE')
            for fvg in finger_vgs:
                try: fvg.remove([v.index])
                except: pass
```

## Step 4: グリップ分割（パターンBのオプション）

パターンB（ミトン型）でhand統合した後、指先にカール感を出したい場合。
手のひらと指先エリアを分離し、指先を1つのグリップボーンに割り当てる。

**パターンA（5本指分離）では不要** — 個別の指ボーンが正常に機能する。

### ボーン選択の注意

指ボーンのローカルカール量を確認して、実際に曲がるボーンを選ぶ。

```python
# 各指ボーンの親ボーンからの角度変化（カール量）を確認
# c_middle1_base: カール0°（中手骨、動かない）
# middle1: カール0°
# c_middle2: カール63.5°  ← ここが曲がる
# c_middle3: カール14.4°
```

**重要**: `c_middle1_base`（中手骨）はほとんどカールしない。グリップには `c_middle2` 以降を使う。
ただし `c_middle2` に大量の頂点を割り当てるとメッシュが崩壊する場合がある（要テスト）。

### 分割コード（hand軸の70%以降を指先と判定）

```python
for side in ['.l', '.r']:
    hand_vg = base2.vertex_groups.get(f"hand{side}")
    grip_vg = base2.vertex_groups.get(f"c_middle1_base{side}")  # or c_middle2
    hb = rig.data.bones[f"hand{side}"]
    hh = rig.matrix_world @ hb.head_local
    ht = rig.matrix_world @ hb.tail_local
    ha = (ht - hh).normalized()
    hl = (ht - hh).length

    for v in base2.data.vertices:
        hw = 0
        for g in v.groups:
            if g.group == hand_vg.index: hw = g.weight; break
        if hw < 0.01: continue
        vw = base2.matrix_world @ v.co
        along = (vw - hh).dot(ha) / hl
        if along > 0.7:
            grip_vg.add([v.index], hw, 'REPLACE')
            hand_vg.add([v.index], 0.0, 'REPLACE')
```

## Step 5: CorrectiveSmoothモディファイア

ローポリメッシュのデフォーメーション品質を改善。手/指/頭は除外する。

```python
# マスク頂点グループ作成（手/指/頭を除外）
smooth_vg = base2.vertex_groups.new(name="corrective_smooth_mask")
smooth_vg.add(list(range(len(base2.data.vertices))), 1.0, 'REPLACE')

exclude_keywords = ['hand', 'pinky', 'ring', 'middle', 'index',
                    'thumb', 'head', 'neck']
for v in base2.data.vertices:
    for g in v.groups:
        vn = base2.vertex_groups[g.group].name
        if vn == "corrective_smooth_mask": continue
        if any(kw in vn for kw in exclude_keywords) and g.weight > 0.3:
            smooth_vg.add([v.index], 0.0, 'REPLACE')
            break

# モディファイア追加（Armatureの後に配置）
cs = base2.modifiers.new(name="CorrectiveSmooth", type='CORRECTIVE_SMOOTH')
cs.factor = 0.8
cs.iterations = 8
cs.smooth_type = 'LENGTH_WEIGHTED'
cs.use_only_smooth = True
cs.use_pin_boundary = True
cs.vertex_group = "corrective_smooth_mask"
```

**注意**: Armatureモディファイアの**後**に配置すること。順番が逆だと効果なし。

## トラブルシューティング

| 症状 | 原因 | 対策 |
|------|------|------|
| メッシュがTポーズのまま | Armatureモディファイアがない | `modifiers.new(type='ARMATURE')` で追加 |
| 手/指が崩壊する | ミトン型メッシュに個別指ウェイト | Step 3で指ウェイトをhandに統合 |
| 指がパーのまま | グリップボーンがカールしない | `c_middle1_base`→`c_middle2`に変更（Step 4参照） |
| 指が完全に消える | CorrectiveSmoothが強すぎ | マスク頂点グループで手を除外 |
| 左右の腕の太さが違う | ポーズの非対称性（正常） | 元メッシュ(base)でも同じ傾向を確認 |
| ウェイトが右半身だけ空 | 重心合わせなしのKD-tree | 重心を減算してからKD-tree構築 |
| `matrix_parent_inverse` ずれ | 親子関係設定時のオフセット | `.identity()` でリセット |
| revertで作業が消えた | ファイル保存前にrevert | **revertは最終手段**、個別undoを優先 |

## ARPデフォームボーン一覧（68本）

### 体幹・頭
`root.x`, `spine_01.x`, `spine_02.x`, `spine_03.x`, `neck.x`, `head.x`

### 腕（左右）
`shoulder`, `arm_stretch`, `c_arm_twist_offset`, `forearm_stretch`, `forearm_twist`, `hand`

### 指（左右 × 5本 × 3-4関節）
`c_{finger}1_base`, `{finger}1`, `c_{finger}2`, `c_{finger}3`
（finger = pinky, ring, middle, index, thumb）

### 脚（左右）
`thigh_stretch`, `thigh_twist`, `leg_stretch`, `leg_twist`, `foot`, `toes_01`

## 重要な知見

1. **ボーン位置はbase/base2で完全一致** — 同じARPリグを使用しているため
2. **ウェイト転送の精度は重心合わせが鍵** — オフセット1.2mでもcentroid補正で平均距離0.025m達成
3. **ミトン型メッシュの判別** — レストポーズで手を拡大表示して指の分離を確認
4. **CorrectiveSmoothは手を除外必須** — 手の細かいジオメトリを潰してしまう
5. **revertではなく個別操作でundo** — `bpy.ops.wm.revert_mainfile()` は全作業を失う
