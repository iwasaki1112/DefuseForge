# キャラクター追加手順

全キャラクターは同じARPリグを使用。vanguardがアニメーション元となり、他キャラクターはアニメーションを共有。

## 1. GLBファイル配置
```
assets/characters/{character_id}/{character_id}.glb
```

## 2. CharacterResource作成
`assets/characters/{character_id}/{character_id}.tres`を作成：
```gdresource
[gd_resource type="Resource" script_class="CharacterResource" load_steps=2 format=3]
[ext_resource type="Script" path="res://scripts/resources/character_resource.gd" id="1_script"]
[resource]
script = ExtResource("1_script")
character_id = "{character_id}"
character_name = "{表示名}"
model_path = "res://assets/characters/{character_id}/{character_id}.glb"
```

## 3. CharacterRegistry登録
`scripts/registries/character_registry.gd`の`CHARACTER_PATHS`に追加：
```gdscript
const CHARACTER_PATHS := {
    "shade": "res://assets/characters/shade/shade.tres",
    "{character_id}": "res://assets/characters/{character_id}/{character_id}.tres"
}
```

## 4. アニメーション共有設定
`scripts/api/character_api.gd`の`ANIMATION_SOURCE`に追加：
```gdscript
const ANIMATION_SOURCE := {
    "shade": "vanguard",
    "phantom": "vanguard",
    "{character_id}": "vanguard"  # vanguardのアニメーションを使用
}
```

## 5. IK調整（必要に応じて）
キャラクターの腕の長さが異なる場合、`.tres`の`left_hand_ik_offset`を調整

## キャラクターアセット構造
```
assets/characters/
├── shade/shade.glb     # vanguardとアニメーション共有
├── phantom/phantom.glb # vanguardとアニメーション共有
└── vanguard/vanguard.glb # メインキャラクター（アニメーション元）
```
