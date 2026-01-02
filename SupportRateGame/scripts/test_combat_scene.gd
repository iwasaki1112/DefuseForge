extends Node3D

## テスト用シーン
## CombatComponentの動作確認用
## - 射撃アニメーション（上半身ブレンド）
## - マズルフラッシュ
## - 死亡アニメーション

var player: Node3D
var enemy: Node3D
var test_started: bool = false

func _ready() -> void:
	print("=== Combat Test Scene ===")

	# ゲーム状態を強制的にPLAYINGに設定
	GameManager.current_state = GameManager.GameState.PLAYING
	print("[Test] GameState set to PLAYING")

	# プレイヤーと敵を取得
	player = $Player
	enemy = $Enemy

	# 敵を最初は非表示・戦闘無効化
	enemy.visible = false
	var enemy_combat = enemy.get_node_or_null("CombatComponent")
	if enemy_combat:
		enemy_combat.auto_attack = false  # 敵は撃ち返さない

	# プレイヤーの自動攻撃も一時無効化（敵出現まで）
	var player_combat = player.get_node_or_null("CombatComponent")
	if player_combat:
		player_combat.auto_attack = false
	print("[Test] Auto-attack disabled until enemy appears")

	# プレイヤーに武器を装備
	await get_tree().create_timer(0.3).timeout
	player.set_weapon(CharacterSetup.WeaponId.AK47)
	print("[Test] Player equipped AK-47")

	# 1秒後に敵を表示
	print("[Test] Enemy will appear in 1 second...")
	await get_tree().create_timer(1.0).timeout

	# 敵を表示
	enemy.visible = true
	print("[Test] Enemy appeared! Watching for:")
	print("[Test] - Shooting animation (upper body blend)")
	print("[Test] - Muzzle flash")
	print("[Test] - Death animation")

	# プレイヤーの自動攻撃を有効化
	var player_combat_enable = player.get_node_or_null("CombatComponent")
	if player_combat_enable:
		player_combat_enable.auto_attack = true
	print("[Test] Player auto-attack enabled - combat starting!")

	test_started = true


func _process(_delta: float) -> void:
	if not test_started:
		return

	# 毎秒状態を出力
	if Engine.get_process_frames() % 30 == 0:  # 0.5秒ごと
		var player_combat = player.get_node_or_null("CombatComponent") if player else null
		if player_combat and enemy:
			var shooting_state = player.is_shooting if "is_shooting" in player else false
			var blend_amount = player._shooting_blend if "_shooting_blend" in player else 0.0
			print("[Test] Frame %d - Shooting: %s, Blend: %.2f, Target: %s, HP: %.0f, Alive: %s" % [
				Engine.get_process_frames(),
				shooting_state,
				blend_amount,
				player_combat.current_target.name if player_combat.current_target else "none",
				enemy.health if enemy else 0,
				enemy.is_alive if enemy else false
			])
