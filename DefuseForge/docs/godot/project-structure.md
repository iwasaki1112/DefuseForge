# プロジェクト構造

## シーン
```
scenes/
├── tests/test_animation_viewer.tscn  # メインシーン（アニメーション確認用）
├── weapons/
│   ├── ak47.tscn
│   └── m4a1.tscn
└── effects/muzzle_flash.tscn
```

## スクリプト
```
scripts/
├── api/character_api.gd              # キャラクター操作API
├── characters/
│   ├── character_base.gd             # キャラクター基底クラス
│   └── components/
│       ├── animation_component.gd
│       ├── health_component.gd
│       ├── movement_component.gd
│       └── weapon_component.gd
├── registries/
│   ├── character_registry.gd
│   └── weapon_registry.gd
├── resources/
│   ├── action_state.gd
│   ├── character_resource.gd
│   └── weapon_resource.gd
├── tests/
│   ├── test_animation_viewer.gd
│   └── orbit_camera.gd
├── effects/muzzle_flash.gd
└── utils/two_bone_ik_3d.gd           # 左手IK
```

## アセット
```
assets/
├── characters/
│   ├── shade/shade.glb
│   ├── phantom/phantom.glb
│   └── vanguard/vanguard.glb
└── weapons/
    ├── ak47/
    └── m4a1/
```
