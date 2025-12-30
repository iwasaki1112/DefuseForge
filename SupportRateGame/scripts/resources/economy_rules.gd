class_name EconomyRules
extends Resource

## 経済ルール設定（Resource）
## CS1.6/CS2スタイルの経済パラメータを一元管理
## 勝敗/連敗ボーナス/設置ボーナス/武器別キル報酬など

# === 基本設定 ===

## 開始時の所持金
@export var starting_money: int = 800

## 最大所持金
@export var max_money: int = 16000

# === 勝利報酬 ===

## 通常勝利
@export var win_reward: int = 3250

## 爆弾解除勝利（CTボーナス）
@export var win_defuse_bonus: int = 250

## 時間切れ勝利
@export var win_time_bonus: int = 0

# === 敗北報酬（連敗ボーナス） ===

## 敗北基本報酬
@export var loss_reward_base: int = 1400

## 連敗ごとの増加額
@export var loss_reward_increment: int = 500

## 連敗報酬の上限
@export var loss_reward_max: int = 3400

## 連敗カウントの上限
@export var loss_streak_max: int = 4

# === 目標ボーナス ===

## 爆弾設置報酬（設置者）
@export var bomb_plant_reward: int = 300

## 爆弾解除報酬（解除者）
@export var bomb_defuse_reward: int = 300

## 人質救出報酬
@export var hostage_rescue_reward: int = 1000

# === キル報酬（武器カテゴリ別） ===

## デフォルトキル報酬
@export var kill_reward_default: int = 300

## ピストルキル報酬
@export var kill_reward_pistol: int = 300

## SMGキル報酬
@export var kill_reward_smg: int = 600

## ライフルキル報酬
@export var kill_reward_rifle: int = 300

## AWPキル報酬（低め）
@export var kill_reward_awp: int = 100

## ショットガンキル報酬
@export var kill_reward_shotgun: int = 900

## ナイフキル報酬（高め）
@export var kill_reward_knife: int = 1500

# === ラウンド設定 ===

## ラウンド時間（秒）
@export var round_time: float = 105.0

## 購入フェーズ時間（秒）
@export var buy_time: float = 15.0

## 爆弾タイマー（秒）
@export var bomb_time: float = 40.0

## 勝利に必要なラウンド数（MR15）
@export var max_rounds: int = 15


## 連敗報酬を計算
func calculate_loss_reward(loss_streak: int) -> int:
	var capped_streak := mini(loss_streak, loss_streak_max)
	return mini(loss_reward_base + (capped_streak * loss_reward_increment), loss_reward_max)


## 武器IDからキル報酬を取得
func get_kill_reward(weapon_id: int) -> int:
	# WeaponIdに対応するカテゴリを判定
	# 実際の武器カテゴリは CharacterSetup.get_weapon_data() から取得するのが理想
	# ここではデフォルト値を返す
	return kill_reward_default


## デフォルト設定を作成
static func create_default() -> Resource:
	var script = load("res://scripts/resources/economy_rules.gd")
	var rules = script.new()
	# デフォルト値は @export で設定済み
	return rules
