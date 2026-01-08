extends Node3D

## 戦闘とリロードのテストシーン
## - プレイヤーの前に敵を配置（正面・左斜め・右斜め）
## - 視界内の敵に自動射撃
## - 弾切れ時に自動リロード
## - 上半身エイミング機能のテスト

@onready var player: CharacterBody3D = $Player
@onready var enemy: CharacterBody3D = $Enemy
@onready var enemy_left: CharacterBody3D = $EnemyLeft
@onready var enemy_right: CharacterBody3D = $EnemyRight
@onready var ui_label: Label = $UI/AmmoLabel
@onready var orbit_camera: Camera3D = $OrbitCamera

var combat_component: Node = null
var all_enemies: Array[CharacterBody3D] = []


func _ready() -> void:
	# プレイヤーにグループを追加
	player.add_to_group("player")

	# 敵リストを作成
	all_enemies = [enemy, enemy_left, enemy_right]

	# 敵の共通セットアップ
	for e in all_enemies:
		# グループ追加
		e.add_to_group("enemies")

		# 武器装備（攻撃させない）
		if e.has_method("set_weapon"):
			e.set_weapon(CharacterSetup.WeaponId.AK47)
		var e_combat = e.get_node_or_null("CombatComponent")
		if e_combat:
			e_combat.auto_attack = false

		# HP設定
		e.health = 250.0

		# 死亡シグナル接続
		if e.has_signal("died"):
			e.died.connect(_on_enemy_died)

	# プレイヤーに武器を装備
	if player.has_method("set_weapon"):
		player.set_weapon(CharacterSetup.WeaponId.AK47)

	# 死亡シグナルを接続
	if player.has_signal("died"):
		player.died.connect(_on_player_died)

	# CombatComponentを取得
	combat_component = player.get_node_or_null("CombatComponent")
	if combat_component:
		combat_component.ammo_changed.connect(_on_ammo_changed)
		combat_component.reload_started.connect(_on_reload_started)
		combat_component.reload_completed.connect(_on_reload_completed)
		combat_component.fired.connect(_on_fired)

		# テスト用にマガジンサイズを小さくする（リロードを確認しやすく）
		combat_component.max_ammo = 5
		combat_component.current_ammo = 5

	# UIを更新
	_update_ui()

	# カメラのターゲットを設定
	if orbit_camera and orbit_camera.has_method("set_target"):
		orbit_camera.set_target(player)

	print("[TestCombatReload] Test scene ready (Upper body aiming test)")
	print("  Player position: %s" % player.global_position)
	print("  Enemy (front): %s" % enemy.global_position)
	print("  Enemy (left):  %s" % enemy_left.global_position)
	print("  Enemy (right): %s" % enemy_right.global_position)
	print("  Test ammo: 5 rounds (for quick reload test)")


func _process(_delta: float) -> void:
	_update_ui()


func _on_ammo_changed(current: int, max_ammo: int) -> void:
	print("[TestCombatReload] Ammo: %d/%d" % [current, max_ammo])


func _on_reload_started() -> void:
	print("[TestCombatReload] >>> RELOAD STARTED <<<")


func _on_reload_completed() -> void:
	print("[TestCombatReload] >>> RELOAD COMPLETED <<<")


func _on_fired(target: Node3D, hit: bool, damage: int) -> void:
	var result = "HIT" if hit else "MISS"
	print("[TestCombatReload] Fired at %s: %s (damage: %d)" % [target.name, result, damage])


func _on_player_died(_killer: Node3D) -> void:
	print("[TestCombatReload] >>> PLAYER DIED <<<")


func _on_enemy_died(_killer: Node3D) -> void:
	print("[TestCombatReload] >>> ENEMY DIED <<<")


func _update_ui() -> void:
	if not ui_label or not combat_component:
		return

	var ammo_text = "Ammo: %d / %d" % [combat_component.current_ammo, combat_component.max_ammo]
	var state_text = ""

	if combat_component._is_reloading:
		state_text = " [RELOADING]"
	elif player.has_method("can_shoot") and not player.can_shoot():
		state_text = " [CANNOT SHOOT]"

	var target_text = ""
	if combat_component.current_target:
		target_text = "\nTarget: %s" % combat_component.current_target.name

	# エイミング角度を表示（公開API使用）
	var aim_text = ""
	if player.has_method("get_aim_rotation_degrees"):
		var aim_deg = player.get_aim_rotation_degrees()
		aim_text = "\nAim Angle: %.1f°" % aim_deg

	var player_health_text = ""
	if player and player.has_method("get_health"):
		player_health_text = "\nPlayer HP: %.0f" % player.get_health()

	# 全敵のHPを表示
	var enemies_health_text = ""
	for e in all_enemies:
		if is_instance_valid(e) and e.has_method("get_health"):
			enemies_health_text += "\n%s HP: %.0f" % [e.name, e.get_health()]

	ui_label.text = ammo_text + state_text + target_text + aim_text + player_health_text + enemies_health_text
