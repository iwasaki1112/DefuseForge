# Claude Code Rules (Godot開発)

## プロジェクト情報
- **エンジン**: Godot 4.5.1
- **プロジェクトパス**: `DefuseForge/`
- **言語**: GDScript
- **メインシーン**: `scenes/tests/test_animation_viewer.tscn`

## 現在の状態
プロジェクトは開発途中で、現在は **test_animation_viewer** のみが稼働しています。
ゲーム本体のシーン（title, game, lobby等）は削除済みです。

## スキル

### プロジェクトスキル
| スキル | 用途 |
|--------|------|
| `/add-weapon` | 武器追加ガイド（Blenderモデル準備→WeaponResource作成→左手IK調整） |
| `/export-character` | BlenderからキャラクターをGLBエクスポート（NLAアニメーション含む）→Godotに配置 |
| `/organize-arp-collection` | ARPでRig&Bind後のコレクション構造を整理。character1→キャラクター名にリネーム、csコレクションを非表示に設定。 |
| `/retarget-animation` | 外部アニメーションをAuto-Rig Proでリターゲット→NLAトラックにPush Down |
| `/sakurai-review` | 桜井政博氏の哲学に基づくゲーム設計レビュー（リスク/リターン、難易度曲線等） |
| `/difficulty-design` | 難易度設計支援（デコボコ曲線、3分間の法則、救済システム） |
| `/reward-design` | 報酬システム設計（報酬サイクル、数値報酬、コレクション要素） |
| `/game-feel` | ゲームの手触りレビュー（ヒットストップ、攻撃モーション、ジャンプ設計）|

### プラグインスキル
| スキル | 用途 |
|--------|------|
| `/claude-mem:mem-search` | 過去セッションのメモリ検索（「前回どうやった？」等） |
| `/claude-mem:troubleshoot` | claude-memのインストール問題診断・修正 |

## プロジェクト構造

### シーン
```
scenes/
├── tests/test_animation_viewer.tscn  # メインシーン（アニメーション確認用）
├── weapons/
│   ├── ak47.tscn
│   └── m4a1.tscn
└── effects/muzzle_flash.tscn
```

### スクリプト
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

## キャラクターアセット
```
assets/characters/
├── shade/shade.glb     # vanguardとアニメーション共有
├── phantom/phantom.glb # vanguardとアニメーション共有
└── vanguard/vanguard.glb # メインキャラクター（アニメーション元）
```

## キャラクター追加手順

全キャラクターは同じARPリグを使用。vanguardがアニメーション元となり、他キャラクターはアニメーションを共有。

### 1. GLBファイル配置
```
assets/characters/{character_id}/{character_id}.glb
```

### 2. CharacterResource作成
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

### 3. CharacterRegistry登録
`scripts/registries/character_registry.gd`の`CHARACTER_PATHS`に追加：
```gdscript
const CHARACTER_PATHS := {
    "shade": "res://assets/characters/shade/shade.tres",
    "{character_id}": "res://assets/characters/{character_id}/{character_id}.tres"
}
```

### 4. アニメーション共有設定
`scripts/api/character_api.gd`の`ANIMATION_SOURCE`に追加：
```gdscript
const ANIMATION_SOURCE := {
    "shade": "vanguard",
    "phantom": "vanguard",
    "{character_id}": "vanguard"  # vanguardのアニメーションを使用
}
```

### 5. IK調整（必要に応じて）
キャラクターの腕の長さが異なる場合、`.tres`の`left_hand_ik_offset`を調整

## Tool Priority
1. **Godot MCP** (優先) - シーン作成・編集・プロジェクト実行
2. **ファイル操作** (フォールバック) - スクリプト編集・シーンファイル直接編集

## よく使うコマンド
```bash
# Godotエディタを開く
"/Applications/Godot.app/Contents/MacOS/Godot" --path DefuseForge --editor

# プロジェクトを実行
"/Applications/Godot.app/Contents/MacOS/Godot" --path DefuseForge
```

## Error handling
- シーンが読み込めない → UIDを確認
- スクリプトエラー → Godotコンソール確認（`get_debug_output`）
- 影が表示されない → マテリアルがPBR（shading_mode=1）か確認

## 技術ドキュメント
詳細な実装パターンは `docs/` を参照：
- `docs/godot/skeleton-modifier-patterns.md` - SkeletonModifier3D、上半身回転、IK実行順序
