# Claude Code Rules (Godot開発)

## プロジェクト情報
- **エンジン**: Godot 4.5.1
- **プロジェクトパス**: `DefuseForge/`
- **言語**: GDScript

## スキル

### プロジェクトスキル
| スキル | 用途 |
|--------|------|
| `/add-weapon` | 武器追加ガイド（Blenderモデル準備→WeaponResource作成→左手IK調整） |
| `/export-character` | BlenderからキャラクターをGLBエクスポート（NLAアニメーション含む）→Godotに配置 |
| `/retarget-animation` | MixamoアニメーションをAuto-Rig Proでリターゲット→NLAトラックにPush Down |
| `/sakurai-review` | 桜井政博氏の哲学に基づくゲーム設計レビュー（リスク/リターン、難易度曲線等） |
| `/difficulty-design` | 難易度設計支援（デコボコ曲線、3分間の法則、救済システム） |
| `/reward-design` | 報酬システム設計（報酬サイクル、数値報酬、コレクション要素） |
| `/game-feel` | ゲームの手触りレビュー（ヒットストップ、攻撃モーション、ジャンプ設計）|

### プラグインスキル
| スキル | 用途 |
|--------|------|
| `/claude-mem:mem-search` | 過去セッションのメモリ検索（「前回どうやった？」等） |
| `/claude-mem:troubleshoot` | claude-memのインストール問題診断・修正 |

## ドキュメント参照
詳細な仕様は以下のドキュメントを参照すること：

| ドキュメント | 内容 |
|------------|------|
| `docs/GAME_DESIGN.md` | ゲーム設計・仕様 |
| `docs/CHARACTER_API.md` | キャラクターAPI（生成・操作） |
| `docs/WEAPON_API.md` | 武器システムAPI |
| `docs/BLENDER_ANIMATION.md` | Blenderアニメーション設定 |

## キャラクター追加（クイックリファレンス）

### コードで生成
```gdscript
# プレイヤー生成（AK-47装備）
var player = CharacterAPI.create("player", CharacterSetup.WeaponId.AK47)
CharacterAPI.spawn(player, self, Vector3(0, 0, 0))

# 敵生成
var enemy = CharacterAPI.create("enemies", CharacterSetup.WeaponId.GLOCK)
CharacterAPI.spawn(enemy, self, Vector3(0, 0, -5), PI)
```

### プリセットシーン使用
```gdscript
var player = preload("res://scenes/characters/player_base.tscn").instantiate()
add_child(player)
player.set_weapon(CharacterSetup.WeaponId.AK47)
```

### 利用可能なプリセット
| シーン | 用途 |
|--------|------|
| `scenes/characters/player_base.tscn` | プレイヤーキャラクター |
| `scenes/characters/enemy_base.tscn` | 敵キャラクター |

### 自動セットアップ内容
- CharacterBase（移動、アニメーション、HP管理）
- CombatComponent（自動攻撃、弾数管理、リロード）
- AnimationTree（上半身/下半身ブレンド）
- 武器装着（右手ボーン）
- 死亡アニメーション

## Tool Priority
1. **Godot MCP** (優先) - シーン作成・編集・プロジェクト実行
2. **ファイル操作** (フォールバック) - スクリプト編集・シーンファイル直接編集

## よく使うコマンド
```bash
# Godotエディタを開く
"/Users/iwasakishungo/Downloads/Godot.app/Contents/MacOS/Godot" --path DefuseForge --editor

# プロジェクトを実行
"/Users/iwasakishungo/Downloads/Godot.app/Contents/MacOS/Godot" --path DefuseForge
```

## iOS実機ビルド
**必ず専用スクリプトを使用すること！**
```bash
./scripts/ios_build.sh --export
```
※ `--export`オプション必須。Godotの`--export-debug`を直接実行しないこと。

## Error handling
- シーンが読み込めない → UIDを確認
- スクリプトエラー → Godotコンソール確認（`get_debug_output`）
- 影が表示されない → マテリアルがPBR（shading_mode=1）か確認
