extends Node

## ゲームイベントバス（Autoload）
## systems同士が直接呼び合う代わりにこのバスを介して連携
## 依存関係を減らし、疎結合なアーキテクチャを実現

# === ユニット関連イベント ===

## ユニットが敵を発見
signal unit_spotted(observer: Node3D, target: Node3D)

## ユニットが死亡
signal unit_killed(killer: Node3D, victim: Node3D, weapon_id: int)

## ユニットがダメージを受けた
signal unit_damaged(target: Node3D, damage: float, attacker: Node3D)

## ユニットが移動開始
signal unit_move_started(unit: Node3D, waypoints: Array)

## ユニットが移動完了
signal unit_move_completed(unit: Node3D)

# === 爆弾/目標関連イベント ===

## 爆弾設置
signal bomb_planted(site: String, planter: Node3D)

## 爆弾解除
signal bomb_defused(defuser: Node3D)

## 爆弾爆発
signal bomb_exploded()

# === ラウンド関連イベント ===

## ラウンド開始
signal round_started(round_number: int)

## ラウンド終了
signal round_ended(winner_team: int)  # 0=CT, 1=T

## 購入フェーズ開始
signal buy_phase_started()

## 戦略フェーズ開始（パス描画可能）
signal strategy_phase_started(turn_number: int)

## 実行フェーズ開始（移動実行）
signal execution_phase_started(turn_number: int)

## プレイフェーズ開始（後方互換用、戦略フェーズと同時に発火）
signal play_phase_started()

## ゲーム終了
signal game_over(winner_team: int)

# === 経済イベント ===

## お金変更
signal money_changed(player: Node3D, new_amount: int)

## 武器購入
signal weapon_purchased(player: Node3D, weapon_id: int)

## 報酬付与
signal reward_granted(player: Node3D, amount: int, reason: String)

# === 入力/UI関連イベント ===

## プレイヤー選択変更
signal player_selection_changed(player_data: RefCounted, index: int)

## パス描画開始
signal path_draw_started(world_pos: Vector2)

## パス確定
signal path_confirmed(unit: Node3D, waypoints: Array)

## パスクリア
signal path_cleared(unit: Node3D)

# === 視界関連イベント ===

## 視界更新
signal fog_updated()

## キャラクター可視性変更
signal character_visibility_changed(character: Node3D, is_visible: bool)

# === ネットワーク同期イベント ===

## 視界グリッド差分送信要求（サーバー→クライアント）
## data: PackedByteArray（RLE圧縮済み差分データ）
signal visibility_sync_diff(team_id: int, data: PackedByteArray)

## 視界グリッドフル送信要求（初期同期用）
## data: PackedByteArray（RLE圧縮済みフルデータ）
signal visibility_sync_full(team_id: int, data: PackedByteArray)

## 敵位置フィルタリング済みデータ送信
## positions: Dictionary { enemy_id: Vector3 or null }
signal enemy_positions_filtered(team_id: int, positions: Dictionary)


func _ready() -> void:
	# イベントバスは常に処理
	process_mode = Node.PROCESS_MODE_ALWAYS
