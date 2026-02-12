extends Node3D
class_name GameScreen
## ゲーム画面（TPS版）
##
## TPS直接操作モード。プレイヤー1体をWASD/ジョイスティックで操作し、
## FoW+自動攻撃で敵と戦う。
## GameModeProviderでモード固有の処理を分離。

## シーン定数
const DEFAULT_ENVIRONMENT_PRESET := "res://data/environment/default.tres"

## ノード参照
@onready var camera: Camera3D = $Camera3D
@onready var map_container: Node3D = $MapContainer
@onready var ui_layer: CanvasLayer = $UILayer
@onready var team_display_label: Label = $UILayer/TeamDisplayLabel

## コアシステム
var game_manager: GameManager = null
var environment_setup: EnvironmentSetup = null

## モードプロバイダー
var _mode_provider: GameModeProvider = null

## TPS制御
var _tps_controller: TPSPlayerController = null
var _player_character: GameCharacter = null

## TPS HUD要素
var _weapon_option: OptionButton = null
var _weapon_list: Array = []
var _timer_label: Label = null
var _debug_vision_btn: Button = null
var _hp_bar: ProgressBar = null
var _crosshair: Control = null
var _crosshair_color: Color = Color.WHITE

## UI要素
var _round_hud: RoundHUD = null

## グレネードエイミングモード
var _is_grenade_aiming: bool = false
var _grenade_target_pos: Vector3 = Vector3.ZERO
var _grenade_start_override: Vector3 = Vector3.ZERO
var _is_near_opening: bool = false
var _smoke_grenade_count: int = GameConstants.SMOKE_GRENADE_PER_ROUND

## グレネードエイミング中の左側タッチ保留（タップ/ドラッグ判定用）
const GRENADE_TAP_DRAG_THRESHOLD := 20.0  # ドラッグ判定の閾値（px）
var _grenade_pending_touch_idx: int = -1
var _grenade_pending_touch_pos: Vector2 = Vector2.ZERO

## グレネードUI
var _grenade_btn: TextureButton = null
var _grenade_count_label: Label = null

## Talking（人質交渉）
var _talking_btn: Button = null
var _is_talking: bool = false
var _talking_elapsed: float = 0.0
var _talking_progress_bar: ProgressBar = null
var _hostage_characters: Array[GameCharacter] = []
var _nearby_hostage: GameCharacter = null

## レンジインジケーター（レイキャスト方式）
var _grenade_viewport: SubViewport = null  # 後方互換（タップ検証用に維持）
var _grenade_light: PointLight2D = null
var _grenade_occluder_mgr: OccluderManager = null
var _grenade_mesh: MeshInstance3D = null
var _grenade_mat: ShaderMaterial = null
var _grenade_map_size: Vector2 = Vector2.ZERO
var _grenade_throwability_tex: ImageTexture = null

## 設定
var _map_id: String = ""

## キャラクター管理
var _network_id_counter: int = 1

## デバッグ
var _vision_debug_enabled: bool = false


func _ready() -> void:
	add_to_group("game_screen")

	# Multiplayerモードでない場合、Trainingモードとして初期化
	if _mode_provider == null:
		_mode_provider = TrainingModeProvider.new()
		_map_id = SettingsManager.get_selected_map()
	_initialize_game()


## Multiplayerモードでセットアップ（LobbyScreenから呼ばれる）
## 注意: add_child()前に呼ぶこと（_ready()で_initialize_game()を一度だけ実行するため）
func setup_multiplayer(net_manager: NetworkManager, map_id: String) -> void:
	_map_id = map_id

	# MultiplayerModeProviderをセットアップ
	var mp_provider := MultiplayerModeProvider.new()
	mp_provider.setup_network(net_manager)
	_mode_provider = mp_provider


## ゲームの初期化（共通処理）
func _initialize_game() -> void:
	_setup_environment()
	_setup_game_manager()

	# Providerを初期化（ネットワーク接続などを行う）
	_mode_provider.initialize(self, game_manager)

	# プレイヤーチームを決定（マルチプレイ: ロビーの割り当て、トレーニング: CT固定）
	_mode_provider.determine_player_team()
	_load_map()
	_setup_grenade_indicator()
	_spawn_characters()
	_setup_tps_hud()
	_setup_round_hud()
	_setup_tps_controller()

	# 視界システムを初期化（FoW ON）
	game_manager.set_vision_enabled(true)

	# ラウンド開始
	if _mode_provider.can_start_round() and game_manager.round_manager:
		game_manager.round_manager.start_round()


## ========================================
## 初期化処理
## ========================================

func _setup_environment() -> void:
	if environment_setup == null:
		environment_setup = EnvironmentSetup.new()
		environment_setup.name = "EnvironmentSetup"
		var preset := load(DEFAULT_ENVIRONMENT_PRESET) as EnvironmentPreset
		if preset:
			environment_setup.preset = preset
		add_child(environment_setup)


func _setup_game_manager() -> void:
	if game_manager == null:
		game_manager = GameManager.new()
		game_manager.name = "GameManager"
		add_child(game_manager)

		# UIコンポーネントをGameScreenが作成してGameManagerに注入
		#_setup_label_manager()  # TODO: 一時的に無効化（頭上ラベル非表示）

		game_manager.setup(camera, self, ui_layer, Vector2(50, 50), map_container)

		# シグナル接続（TPS用: タイマー、ラウンド開始/終了）
		SignalBus.round_timer_updated.connect(_on_round_timer_updated)
		SignalBus.round_ended.connect(_on_round_ended)
		SignalBus.round_started.connect(_on_round_started)


func _load_map() -> void:
	if _map_id.is_empty():
		push_warning("[GameScreen] No map selected - will be set later for multiplayer")
		return

	var map_instance := game_manager.load_map(_map_id, false)
	if not map_instance:
		push_error("[GameScreen] Failed to load map: %s" % _map_id)


func _spawn_characters() -> void:
	# モードプロバイダーがキャラクタースポーンを処理する場合
	if _mode_provider.spawn_characters(self, game_manager):
		# マルチプレイ: ローカルプレイヤーのキャラクターを特定
		_find_local_player_character()
		# 人質スポーン（マルチプレイでも共通）
		_spawn_hostages()
		return

	# デフォルトのスポーン処理
	if not game_manager.has_map():
		push_warning("[GameScreen] Cannot spawn characters - no map loaded yet")
		return

	var preset = game_manager.get_current_map_preset()
	if not preset:
		push_error("[GameScreen] Cannot spawn characters - no map preset")
		return

	# CT: 1体のみ（alpha）— TPS操作対象
	var alpha_preset = CharacterRegistry.get_preset("alpha")
	var ct_spawns = preset.spawn_points_ct
	var ct_rotations = preset.spawn_rotations_ct
	if alpha_preset and ct_spawns.size() > 0:
		var character = CharacterRegistry.create_character(alpha_preset.id, ct_spawns[0])
		if character:
			character.team = GameCharacter.Team.COUNTER_TERRORIST
			character.marker_name = "alpha"
			if ct_rotations.size() > 0:
				var dir = Vector3(sin(ct_rotations[0]), 0, cos(ct_rotations[0]))
				character.set_initial_facing(dir)
			game_manager.get_character_parent().add_child(character)
			_mode_provider.register_character(game_manager, character, _network_id_counter)
			_network_id_counter += 1
			_player_character = character

	# T: 全敵スポーン（ares preset）
	var ares_preset = CharacterRegistry.get_preset("ares")
	var t_spawns = preset.spawn_points_t
	var t_rotations = preset.spawn_rotations_t
	if ares_preset:
		for i in range(t_spawns.size()):
			var enemy = CharacterRegistry.create_character(ares_preset.id, t_spawns[i])
			if enemy:
				enemy.team = GameCharacter.Team.TERRORIST
				if i < t_rotations.size():
					var dir = Vector3(sin(t_rotations[i]), 0, cos(t_rotations[i]))
					enemy.set_initial_facing(dir)
				game_manager.get_character_parent().add_child(enemy)
				_mode_provider.register_character(game_manager, enemy, _network_id_counter)
				_network_id_counter += 1

	# 人質スポーン
	_spawn_hostages()

	# IdleManagerにキャラクターリストを更新
	if game_manager.idle_manager:
		game_manager.idle_manager.set_characters(game_manager.characters)


## マッププリセットから人質をスポーン
func _spawn_hostages() -> void:
	if not game_manager.has_map():
		return
	var preset = game_manager.get_current_map_preset()
	if not preset:
		return
	var hostage_spawns = preset.spawn_points_hostage
	var hostage_rotations = preset.spawn_rotations_hostage
	for i in range(hostage_spawns.size()):
		var rot = hostage_rotations[i] if i < hostage_rotations.size() else 0.0
		_spawn_hostage_character("hostage_lucas", hostage_spawns[i], rot)


## ホステージキャラクターをスポーン（視界・戦闘・武器なし、アニメーションのみ）
func _spawn_hostage_character(preset_id: String, spawn_pos: Vector3, y_rotation: float) -> void:
	var preset = CharacterRegistry.get_preset(preset_id)
	if not preset or not preset.model_scene:
		push_warning("[GameScreen] Hostage preset not found: %s" % preset_id)
		return

	# GameCharacter + model + collision を直接構築（AnimationTree/Controller不要）
	var character := GameCharacter.new()
	character.name = preset_id
	character.character_preset_id = preset_id
	character.max_health = preset.max_health
	character.team = GameCharacter.Team.NONE
	character.is_invulnerable = true
	character.position = spawn_pos

	# 向き設定
	var dir := Vector3(sin(y_rotation), 0, cos(y_rotation))
	character.set_initial_facing(dir)

	# モデル追加（共通スケール適用 + 地面めり込み補正）
	var model: Node3D = preset.model_scene.instantiate() as Node3D
	model.name = "CharacterModel"
	model.scale = Vector3.ONE * GameConstants.CHARACTER_MODEL_SCALE
	model.position.y = 0.15  # モデル原点が足元より上にあるため補正
	character.add_child(model)

	# コリジョン（壁・床との衝突用）
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	character.add_child(collision)
	character.collision_mask = 3

	# シーンに追加
	game_manager.get_character_parent().add_child(character)

	# AnimationPlayerに共有ライブラリを設定し、Hostageアニメーションをループ再生
	var anim_player := model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if not anim_player:
		anim_player = AnimationPlayer.new()
		anim_player.name = "AnimationPlayer"
		model.add_child(anim_player)

	# 共有ライブラリからHostageアニメーションだけをduplicate（共有インスタンス汚染を防ぐ）
	var shared_lib := CharacterRegistry.get_animation_library()
	if shared_lib and shared_lib.has_animation("Hostage"):
		var hostage_anim := shared_lib.get_animation("Hostage").duplicate()
		hostage_anim.loop_mode = Animation.LOOP_LINEAR
		var hostage_lib := AnimationLibrary.new()
		hostage_lib.add_animation("Hostage", hostage_anim)
		if anim_player.has_animation_library(""):
			anim_player.remove_animation_library("")
		anim_player.add_animation_library("", hostage_lib)
		anim_player.play("Hostage")

	# hostageグループに追加（識別用）
	character.add_to_group("hostages")
	_hostage_characters.append(character)

	# EnemyVisibilitySystemに登録してFoWで可視性を制御（初期状態は非表示）
	character.visible = false
	if game_manager and game_manager.enemy_visibility_system:
		game_manager.enemy_visibility_system.register_character(character)


## マルチプレイ時にローカルプレイヤーのキャラクターを特定
func _find_local_player_character() -> void:
	var local_peer_id := PlayerState.get_local_peer_id()
	var my_characters := game_manager.find_characters_by_owner(local_peer_id)
	if my_characters.size() > 0:
		_player_character = my_characters[0]
	else:
		push_warning("[GameScreen] No characters found for local peer %d" % local_peer_id)


func _setup_tps_controller() -> void:
	if not _player_character:
		push_error("[GameScreen] Cannot setup TPS controller - no player character")
		return
	_tps_controller = TPSPlayerController.new()
	_tps_controller.name = "TPSPlayerController"
	add_child(_tps_controller)
	_tps_controller.setup(_player_character, camera, ui_layer)

	# グレネード投擲シグナル接続
	if _player_character.anim_ctrl:
		_player_character.anim_ctrl.throw_release.connect(_on_throw_release)
		_player_character.anim_ctrl.throw_finished.connect(_on_throw_finished)


func _setup_tps_hud() -> void:
	# 武器セレクター（左上）— 一旦非表示
	var hbox := HBoxContainer.new()
	hbox.name = "WeaponSelector"
	hbox.position = Vector2(10, 10)
	hbox.visible = false
	ui_layer.add_child(hbox)

	var label := Label.new()
	label.text = "Weapon: "
	hbox.add_child(label)

	_weapon_option = OptionButton.new()
	_weapon_option.custom_minimum_size.x = 160
	hbox.add_child(_weapon_option)

	_weapon_list = WeaponRegistry.get_all()
	var default_idx := 0
	for i in range(_weapon_list.size()):
		var w: WeaponPreset = _weapon_list[i]
		_weapon_option.add_item(w.display_name, i)
		if w.id == "ak47":
			default_idx = i
	_weapon_option.selected = default_idx
	_weapon_option.item_selected.connect(_on_weapon_selected)

	# タイマー（右上）
	_timer_label = Label.new()
	_timer_label.name = "TimerLabel"
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_timer_label.position = Vector2(-120, 10)
	_timer_label.add_theme_font_size_override("font_size", 24)
	_timer_label.text = "2:00"
	ui_layer.add_child(_timer_label)

	# アクションボタン（右中央）
	_create_action_buttons()

	# HPバー（左下、ジョイスティックの上）
	#_create_hp_bar()  # TODO: 一時的に無効化

	# クロスヘア（画面中央）
	#_create_crosshair()  # TODO: 一時的に無効化


func _create_hp_bar() -> void:
	_hp_bar = ProgressBar.new()
	_hp_bar.name = "HPBar"
	_hp_bar.custom_minimum_size = Vector2(200, 16)
	_hp_bar.size = Vector2(200, 16)
	_hp_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hp_bar.position = Vector2(40, -220)
	_hp_bar.min_value = 0.0
	_hp_bar.max_value = 1.0
	_hp_bar.value = 1.0
	_hp_bar.show_percentage = false
	# スタイル設定
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.2, 0.8, 0.2)
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3
	_hp_bar.add_theme_stylebox_override("fill", fill_style)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.2, 0.2, 0.2, 0.6)
	bg_style.corner_radius_top_left = 3
	bg_style.corner_radius_top_right = 3
	bg_style.corner_radius_bottom_left = 3
	bg_style.corner_radius_bottom_right = 3
	_hp_bar.add_theme_stylebox_override("background", bg_style)
	ui_layer.add_child(_hp_bar)


func _create_crosshair() -> void:
	_crosshair = Control.new()
	_crosshair.name = "Crosshair"
	_crosshair.custom_minimum_size = Vector2(12, 12)
	_crosshair.size = Vector2(12, 12)
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.position = Vector2(-6, -6)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair_color = Color.WHITE
	_crosshair.draw.connect(func():
		# 小さなドット
		_crosshair.draw_circle(Vector2.ZERO, 3.0, _crosshair_color)
		# 外側リング
		_crosshair.draw_arc(Vector2.ZERO, 6.0, 0, TAU, 24, Color(_crosshair_color, 0.5), 1.0)
	)
	ui_layer.add_child(_crosshair)


func _create_action_buttons() -> void:
	# シーンからアクションボタンを読み込み（Godotエディタで位置調整可能）
	var action_scene := load("res://scenes/ui/action_buttons.tscn")
	var vbox: VBoxContainer = action_scene.instantiate()
	ui_layer.add_child(vbox)

	# ボタン参照を取得してシグナル接続
	var btn_door_open: TextureButton = vbox.get_node("DoorOpenBtn")
	btn_door_open.pressed.connect(_on_door_open_pressed)
	ButtonAnimator.setup(btn_door_open)

	_grenade_btn = vbox.get_node("GrenadeContainer/GrenadeBtn")
	_grenade_btn.pressed.connect(_on_grenade_btn_pressed)
	ButtonAnimator.setup(_grenade_btn)

	_grenade_count_label = vbox.get_node("GrenadeContainer/GrenadeCountLabel")
	_grenade_count_label.text = str(_smoke_grenade_count)

	# Talkingボタン
	_talking_btn = vbox.get_node("TalkingBtn")
	_talking_btn.pressed.connect(_on_talking_btn_pressed)
	ButtonAnimator.setup(_talking_btn)

	if Debug.enabled:
		_debug_vision_btn = Button.new()
		_debug_vision_btn.text = "Debug Vision"
		_debug_vision_btn.toggle_mode = true
		_debug_vision_btn.custom_minimum_size = Vector2(80, 30)
		_debug_vision_btn.toggled.connect(_on_debug_vision_toggled)
		ui_layer.add_child(_debug_vision_btn)
		_debug_vision_btn.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		_debug_vision_btn.position = Vector2(-180, -140)


## アイコン付きTextureButtonを生成
func _create_icon_button(icon_path: String, callback: Callable) -> TextureButton:
	var btn := TextureButton.new()
	var tex := load(icon_path) as Texture2D
	if tex:
		btn.texture_normal = tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.custom_minimum_size = Vector2(80, 80)
	btn.pressed.connect(callback)
	ButtonAnimator.setup(btn)
	return btn


func _setup_round_hud() -> void:
	if _round_hud == null:
		_round_hud = RoundHUD.new()
		_round_hud.name = GameConstants.NODE_ROUND_HUD
		ui_layer.add_child(_round_hud)

		SignalBus.survivor_count_changed.connect(_round_hud.update_survivor_counts)
		SignalBus.round_ended.connect(_round_hud.show_result)


func _setup_label_manager() -> void:
	var lm := CharacterLabelManager.new()
	lm.name = GameConstants.NODE_LABEL_MANAGER
	game_manager.add_child(lm)
	game_manager.set_label_manager(lm)


## ========================================
## 毎フレーム処理
## ========================================

func _physics_process(delta: float) -> void:
	if game_manager:
		game_manager.process_frame(delta)
	if _tps_controller and not _is_grenade_aiming and not _is_talking:
		_tps_controller.process(delta)
	_update_tps_hud()
	if _is_grenade_aiming:
		_update_grenade_light_position()
	if _is_talking:
		_update_talking(delta)
	else:
		_update_hostage_proximity()


func _input(event: InputEvent) -> void:
	# グレネードエイミング中: 左側タッチはドラッグ判定で競合回避
	if _is_grenade_aiming:
		var screen_half_x := get_viewport().get_visible_rect().size.x * 0.5
		if event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			if touch.pressed:
				if touch.position.x < screen_half_x:
					# 左側: タップかドラッグか判定するため保留
					_grenade_pending_touch_idx = touch.index
					_grenade_pending_touch_pos = touch.position
				else:
					# 右側: 即座にターゲット選択
					_handle_grenade_target_tap(touch.position)
			else:
				# リリース: 保留中タッチならドラッグなし=タップとしてターゲット選択
				if touch.index == _grenade_pending_touch_idx:
					_handle_grenade_target_tap(_grenade_pending_touch_pos)
					_grenade_pending_touch_idx = -1
			get_viewport().set_input_as_handled()
			return
		if event is InputEventScreenDrag:
			var drag := event as InputEventScreenDrag
			if drag.index == _grenade_pending_touch_idx:
				var drag_dist := drag.position.distance_to(_grenade_pending_touch_pos)
				if drag_dist > GRENADE_TAP_DRAG_THRESHOLD:
					# ドラッグ判定 → ジョイスティック操作意図 → エイミングキャンセル
					_grenade_pending_touch_idx = -1
					_exit_grenade_aiming()
					# キャンセル後、ドラッグイベントをTPSコントローラーに渡さない
					# （ジョイスティック状態は次のタッチで開始される）
					get_viewport().set_input_as_handled()
					return
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_handle_grenade_target_tap(mb.position)
				get_viewport().set_input_as_handled()
				return
		# WASD入力チェック（キーイベント）
		if event is InputEventKey:
			var key := event as InputEventKey
			if key.pressed and _is_wasd_key(key.keycode):
				_exit_grenade_aiming()
				get_viewport().set_input_as_handled()
				return
		get_viewport().set_input_as_handled()
		return

	# Talk中: 移動入力でキャンセル（タッチイベントはTPSコントローラに渡す）
	if _is_talking:
		if _tps_controller:
			_tps_controller.handle_input(event)
		# WASD入力でキャンセル
		if event is InputEventKey:
			var key := event as InputEventKey
			if key.pressed and _is_wasd_key(key.keycode):
				_cancel_talking()
		get_viewport().set_input_as_handled()
		return

	if _tps_controller:
		_tps_controller.handle_input(event)


## ========================================
## TPS HUD更新
## ========================================

func _update_tps_hud() -> void:
	if not _player_character:
		return

	# HPバー更新
	if _hp_bar:
		var ratio := _player_character.get_health_ratio()
		_hp_bar.value = ratio
		# HP割合に応じて色変更
		var fill := _hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill:
			if ratio > 0.5:
				fill.bg_color = Color(0.2, 0.8, 0.2)  # 緑
			elif ratio > 0.25:
				fill.bg_color = Color(0.9, 0.7, 0.1)  # 黄色
			else:
				fill.bg_color = Color(0.9, 0.2, 0.2)  # 赤

	# クロスヘア色更新（敵追跡中は赤）
	if _crosshair and _player_character.combat_awareness:
		var new_color: Color
		if _player_character.combat_awareness.is_tracking_enemy():
			new_color = Color(1.0, 0.2, 0.2)
		else:
			new_color = Color.WHITE
		if new_color != _crosshair_color:
			_crosshair_color = new_color
			_crosshair.queue_redraw()


## ========================================
## TPS HUDコールバック
## ========================================

func _on_weapon_selected(idx: int) -> void:
	if not _player_character or idx < 0 or idx >= _weapon_list.size():
		return
	var weapon: WeaponPreset = _weapon_list[idx]
	_player_character.equip_weapon(weapon)


func _on_grenade_btn_pressed() -> void:
	if _is_grenade_aiming:
		_exit_grenade_aiming()
		return
	if _smoke_grenade_count <= 0:
		return
	if not _player_character or not _player_character.is_alive:
		return
	_enter_grenade_aiming()


func _enter_grenade_aiming() -> void:
	_is_grenade_aiming = true
	_show_range_indicator()
	if _grenade_btn:
		_grenade_btn.modulate = Color(1.0, 0.6, 0.3)


func _exit_grenade_aiming() -> void:
	_is_grenade_aiming = false
	_grenade_pending_touch_idx = -1
	_hide_range_indicator()
	if _grenade_btn:
		_grenade_btn.modulate = Color.WHITE


func _setup_grenade_indicator() -> void:
	var fow: Node3D = game_manager.fog_of_war_system if game_manager else null
	if not fow:
		return

	var fow_map_size: Vector2 = fow.map_size
	_grenade_map_size = fow_map_size
	var q: Dictionary = fow.get_quality_settings()
	var resolution: int = q["resolution"]
	var throw_range := GameConstants.GRENADE_THROW_MAX_DISTANCE

	# --- SubViewport（FoWと同じ構成） ---
	_grenade_viewport = SubViewport.new()
	_grenade_viewport.name = "GrenadeRangeViewport"
	_grenade_viewport.size = Vector2i(resolution, resolution)
	_grenade_viewport.transparent_bg = false
	_grenade_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_grenade_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_grenade_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	_grenade_viewport.disable_3d = true
	add_child(_grenade_viewport)

	# CanvasModulate（暗い背景）
	var canvas_mod := CanvasModulate.new()
	canvas_mod.color = Color(0, 0, 0, 1)
	_grenade_viewport.add_child(canvas_mod)

	# 白い背景（Light2Dで照らされる）
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 1)
	bg.size = Vector2(resolution, resolution)
	bg.z_index = -100
	bg.light_mask = 1
	_grenade_viewport.add_child(bg)

	# --- OccluderManager（壁の遮蔽、FoWと同じ方式） ---
	_grenade_occluder_mgr = OccluderManager.new()
	_grenade_occluder_mgr.name = "GrenadeOccluderManager"
	add_child(_grenade_occluder_mgr)
	_grenade_occluder_mgr.setup(_grenade_viewport, fow_map_size, resolution)
	_grenade_occluder_mgr.extract_occluders_from_map(map_container)

	# --- PointLight2D（360°円形、シャドウ有効） ---
	_grenade_light = PointLight2D.new()
	_grenade_light.name = "GrenadeRangeLight"
	_grenade_light.enabled = true
	_grenade_light.color = Color(1, 1, 1, 1)
	_grenade_light.energy = 1.0
	_grenade_light.blend_mode = Light2D.BLEND_MODE_ADD
	_grenade_light.shadow_enabled = true
	_grenade_light.shadow_filter = Light2D.SHADOW_FILTER_NONE
	_grenade_light.shadow_filter_smooth = 0.0
	_grenade_light.shadow_item_cull_mask = 1
	_grenade_light.range_item_cull_mask = 1
	_grenade_light.texture = FovTextureGenerator.generate_peripheral_texture(resolution)
	_grenade_viewport.add_child(_grenade_light)

	# ライトスケール（VisionLightと同じ計算式）
	var max_dimension := maxf(fow_map_size.x, fow_map_size.y)
	var scale_factor := float(resolution) / max_dimension
	var light_diameter := throw_range * scale_factor * 2.0
	_grenade_light.texture_scale = light_diameter / float(resolution) * (1.0 / 0.9)
	# アスペクト比補正
	var aspect_scale := Vector2(1.0, 1.0)
	if fow_map_size.x > fow_map_size.y:
		aspect_scale.y = fow_map_size.x / fow_map_size.y
	elif fow_map_size.y > fow_map_size.x:
		aspect_scale.x = fow_map_size.y / fow_map_size.x
	_grenade_light.scale = aspect_scale

	# --- 3Dメッシュ + シェーダー（地面に投影） ---
	_grenade_mesh = MeshInstance3D.new()
	_grenade_mesh.name = "GrenadeRangeMesh"
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = fow_map_size
	_grenade_mesh.mesh = plane_mesh
	_grenade_mesh.position.y = fow.fog_height + 0.01

	var shader: Shader = load("res://shaders/grenade_range.gdshader")
	_grenade_mat = ShaderMaterial.new()
	_grenade_mat.shader = shader
	# visibility_textureはレイキャスト結果のImageTextureを後で設定
	# SubViewportテクスチャはタップ検証用に維持
	_grenade_mat.set_shader_parameter("map_min", Vector2(-fow_map_size.x / 2.0, -fow_map_size.y / 2.0))
	_grenade_mat.set_shader_parameter("map_max", Vector2(fow_map_size.x / 2.0, fow_map_size.y / 2.0))
	_grenade_mat.set_shader_parameter("throw_range", throw_range)
	_grenade_mesh.material_override = _grenade_mat
	_grenade_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grenade_mesh.visible = false
	add_child(_grenade_mesh)


func _show_range_indicator() -> void:
	if _grenade_mesh:
		_grenade_mesh.visible = true
		_check_near_opening()
		_update_grenade_light_position()
		_generate_throwability_mask()


func _hide_range_indicator() -> void:
	if _grenade_mesh:
		_grenade_mesh.visible = false
	if _grenade_viewport:
		_grenade_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_is_near_opening = false


func _update_grenade_light_position() -> void:
	if not _grenade_light or not _grenade_viewport or not _player_character:
		return
	var fow: Node3D = game_manager.fog_of_war_system if game_manager else null
	if not fow:
		return

	# ワールド座標 → SubViewportピクセル座標（FoWと同じ変換式）
	var fow_map_size: Vector2 = fow.map_size
	var char_pos := _player_character.global_position
	var half_map := fow_map_size / 2.0
	var uv_x := (char_pos.x + half_map.x) / fow_map_size.x
	var uv_y := (char_pos.z + half_map.y) / fow_map_size.y
	_grenade_light.position = Vector2(uv_x * _grenade_viewport.size.x, uv_y * _grenade_viewport.size.y)

	# シェーダーにキャラクター位置を渡す（リングエッジ描画用）
	if _grenade_mat:
		_grenade_mat.set_shader_parameter("char_position", Vector2(char_pos.x, char_pos.z))

	# SubViewportを1フレーム更新
	_grenade_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _handle_grenade_target_tap(screen_pos: Vector2) -> void:
	if not camera or not _player_character:
		return

	# スクリーン座標 → 地面位置（レイキャスト）
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_normal := camera.project_ray_normal(screen_pos)
	if absf(ray_normal.y) < 0.001:
		return
	var t := (0.0 - ray_origin.y) / ray_normal.y
	if t <= 0:
		return
	var ground_point := ray_origin + ray_normal * t

	# 距離チェック & クランプ
	var char_pos := _player_character.global_position
	var to_target := ground_point - char_pos
	to_target.y = 0.0
	var distance := to_target.length()
	if distance < 0.5:
		return  # 近すぎる
	var max_dist := GameConstants.GRENADE_THROW_MAX_DISTANCE
	if distance > max_dist:
		to_target = to_target.normalized() * max_dist
		ground_point = char_pos + to_target
		distance = max_dist

	# visibility textureでグリーン領域内かチェック
	if _grenade_viewport and _grenade_map_size != Vector2.ZERO:
		var img := _grenade_viewport.get_texture().get_image()
		if img:
			var half := _grenade_map_size / 2.0
			var uv_x := (ground_point.x + half.x) / _grenade_map_size.x
			var uv_y := (ground_point.z + half.y) / _grenade_map_size.y
			if uv_x >= 0.0 and uv_x <= 1.0 and uv_y >= 0.0 and uv_y <= 1.0:
				var px := int(uv_x * float(img.get_width() - 1))
				var py := int(uv_y * float(img.get_height() - 1))
				var vis := img.get_pixel(px, py).r
				print("[GRENADE] vis=%.2f near_opening=%s" % [vis, _is_near_opening])
				if vis < 0.5:
					# 影の領域 → 開口部付近でのみコーナースロー可能
					if not _is_near_opening:
						print("[GRENADE] BLOCKED: not near opening")
						return
					if not _has_ground_at(ground_point):
						print("[GRENADE] BLOCKED: no ground at target")
						return
					var corner_info := _find_corner_throw(char_pos, ground_point)
					if corner_info.is_empty():
						print("[GRENADE] BLOCKED: no corner throw route")
						return
					_grenade_start_override = corner_info.start
					# キャラは開口部方向に向けてアニメーション（タップ方向ではない）
					to_target = corner_info.opening_dir
					print("[GRENADE] CORNER THROW: facing=%s target=%s start=%s opening=%s" % [to_target, ground_point, corner_info.start, corner_info.opening_dir])
					# 距離はスタート→ターゲットの実飛行距離
					var start_xz := Vector3(corner_info.start.x, 0.0, corner_info.start.z)
					var target_xz := Vector3(ground_point.x, 0.0, ground_point.z)
					distance = start_xz.distance_to(target_xz)
			else:
				return  # マップ範囲外

	# エイミングモード終了
	_exit_grenade_aiming()

	# キャラクターをターゲット方向に向ける（TPSコントローラの向き更新をロック）
	var facing_dir := to_target.normalized()
	print("[GRENADE] lock_facing dir=%s has_controller=%s" % [facing_dir, _tps_controller != null])
	if _tps_controller:
		_tps_controller.lock_facing(facing_dir)
	else:
		_player_character.set_facing_direction_vec(facing_dir)

	# ターゲット位置を保存
	_grenade_target_pos = ground_point

	# 距離で近投/遠投を自動選択
	if distance <= GameConstants.GRENADE_THROW_CLOSE_THRESHOLD:
		_player_character.anim_ctrl.play_throw_close()
	else:
		_player_character.anim_ctrl.play_throw_far()


func _has_ground_at(pos: Vector3) -> bool:
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		pos + Vector3.UP * 2.0,
		pos - Vector3.UP * 2.0
	)
	query.collision_mask = 1  # Ground layer only
	return not space_state.intersect_ray(query).is_empty()


## 開口部付近の壁際にいるかチェック（コーナースロー判定用）
func _check_near_opening() -> void:
	_is_near_opening = false
	if not _player_character:
		return

	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return

	var char_pos := _player_character.global_position
	var char_h := Vector3(char_pos.x, 1.0, char_pos.z)

	# 1.0m以内に壁があるか確認
	var has_wall := false
	for i in range(12):
		var angle := deg_to_rad(float(i) * 30.0)
		var dir := Vector3(sin(angle), 0.0, cos(angle))
		var q := PhysicsRayQueryParameters3D.create(char_h, char_h + dir * 1.0)
		q.collision_mask = 2
		if not space_state.intersect_ray(q).is_empty():
			has_wall = true
			break

	if has_wall:
		for i in range(24):
			var angle := deg_to_rad(float(i) * 15.0)
			var dir := Vector3(sin(angle), 0.0, cos(angle))
			var q := PhysicsRayQueryParameters3D.create(char_h, char_h + dir * 2.5)
			q.collision_mask = 2
			if space_state.intersect_ray(q).is_empty():
				if _has_ground_at(Vector3(char_h.x + dir.x * 2.0, 0.0, char_h.z + dir.z * 2.0)):
					_is_near_opening = true
					break


## 開口部（壁の隙間）にのみコーナー投擲起点を配置
## 壁に隣接する開放方向のみ = ドア/窓の位置
func _get_corner_origins(char_pos: Vector3) -> Array[Vector3]:
	var origins: Array[Vector3] = []
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return origins

	var char_h := Vector3(char_pos.x, 1.0, char_pos.z)

	# 36方向スキャンで壁マップを作成
	var scan_count := 36
	var wall_hits: Array[bool] = []
	var scan_dirs: Array[Vector3] = []
	for i in range(scan_count):
		var angle := deg_to_rad(float(i) * 10.0)
		var dir := Vector3(sin(angle), 0.0, cos(angle))
		scan_dirs.append(dir)
		var q := PhysicsRayQueryParameters3D.create(char_h, char_h + dir * 1.5)
		q.collision_mask = 2
		wall_hits.append(not space_state.intersect_ray(q).is_empty())

	# 開口部のみ: 壁に隣接する開放方向（±20°以内に壁あり）
	for i in range(scan_count):
		if wall_hits[i]:
			continue

		var has_adjacent_wall := false
		for offset in range(1, 3):
			var prev_idx := (i - offset + scan_count) % scan_count
			var next_idx := (i + offset) % scan_count
			if wall_hits[prev_idx] or wall_hits[next_idx]:
				has_adjacent_wall = true
				break

		if not has_adjacent_wall:
			continue  # 周囲に壁なし = 開けた空間、開口部ではない

		var candidate := char_h + scan_dirs[i] * 1.0
		if _has_ground_at(Vector3(candidate.x, 0.0, candidate.z)):
			origins.append(candidate)

	print("[GRENADE] corner_origins: %d candidates (openings only)" % origins.size())
	return origins


## レイキャストで投擲可否マスクを生成（Light2Dに依存しない正確な表示）
func _generate_throwability_mask() -> void:
	if not _player_character or not _grenade_mat:
		return
	var fow: Node3D = game_manager.fog_of_war_system if game_manager else null
	if not fow:
		return

	var char_pos := _player_character.global_position
	var char_h := Vector3(char_pos.x, 1.0, char_pos.z)
	var throw_range := GameConstants.GRENADE_THROW_MAX_DISTANCE

	# 投擲起点: キャラ位置 + 開口部のみのコーナー起点
	var origins: Array[Vector3] = [char_h]
	if _is_near_opening:
		origins.append_array(_get_corner_origins(char_pos))

	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return

	# グリッドを投擲範囲に集中（64x64 → レイキャスト軽量、後でアップスケールで滑らか化）
	var grid_size := 64
	var margin := throw_range * 1.1
	var area_min := Vector2(char_pos.x - margin, char_pos.z - margin)
	var area_max := Vector2(char_pos.x + margin, char_pos.z + margin)
	var area_size := area_max - area_min

	var img := Image.create(grid_size, grid_size, false, Image.FORMAT_L8)
	var throwable_count := 0

	for py in range(grid_size):
		for px in range(grid_size):
			var uv_x := (float(px) + 0.5) / float(grid_size)
			var uv_y := (float(py) + 0.5) / float(grid_size)
			var world_x := area_min.x + uv_x * area_size.x
			var world_z := area_min.y + uv_y * area_size.y

			var dx := world_x - char_pos.x
			var dz := world_z - char_pos.z
			var dist_sq := dx * dx + dz * dz
			if dist_sq > throw_range * throw_range or dist_sq < 0.25:
				img.set_pixel(px, py, Color(0, 0, 0))
				continue

			var target := Vector3(world_x, 1.0, world_z)

			var throwable := false
			for origin in origins:
				var q := PhysicsRayQueryParameters3D.create(origin, target)
				q.collision_mask = 2
				if space_state.intersect_ray(q).is_empty():
					throwable = true
					break

			if throwable:
				img.set_pixel(px, py, Color(1, 1, 1))
				throwable_count += 1
			else:
				img.set_pixel(px, py, Color(0, 0, 0))

	# エッジ滑らか化（壁裏への漏れ防止付き）
	var mask := img.duplicate()  # 元のバイナリマスクを保存
	img.resize(16, 16, Image.INTERPOLATE_BILINEAR)   # ダウンスケールでブラー
	img.resize(64, 64, Image.INTERPOLATE_BILINEAR)    # 元解像度に戻す
	# 元が非投擲のセルはブラー後も0に戻す（壁裏への漏れ防止）
	for y in range(64):
		for x in range(64):
			if mask.get_pixel(x, y).r < 0.5:
				img.set_pixel(x, y, Color(0, 0, 0))
	img.resize(256, 256, Image.INTERPOLATE_BILINEAR)  # アップスケールで滑らか化

	_grenade_throwability_tex = ImageTexture.create_from_image(img)
	_grenade_mat.set_shader_parameter("visibility_texture", _grenade_throwability_tex)
	_grenade_mat.set_shader_parameter("map_min", area_min)
	_grenade_mat.set_shader_parameter("map_max", area_max)
	print("[GRENADE] throwability mask: %d/%d throwable, origins=%d, cell=%.2fm" % [throwable_count, grid_size * grid_size, origins.size(), area_size.x / grid_size])


## 壁の角から内側に投げ込むためのスタート位置と開口部方向を探す
## Returns: {start: Vector3, opening_dir: Vector3} or empty dict
func _find_corner_throw(char_pos: Vector3, target_pos: Vector3) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return {}

	var char_h := Vector3(char_pos.x, 1.0, char_pos.z)
	var target_h := Vector3(target_pos.x, 1.0, target_pos.z)
	var target_dir := (Vector3(target_pos.x, 0.0, target_pos.z) - Vector3(char_pos.x, 0.0, char_pos.z)).normalized()

	# キャラ→ターゲット間に壁があるか確認
	var wall_q := PhysicsRayQueryParameters3D.create(char_h, target_h)
	wall_q.collision_mask = 2  # Wall layer
	var wall_r := space_state.intersect_ray(wall_q)
	if wall_r.is_empty():
		return {}  # 壁なし

	# 壁が近い（1.5m以内）か確認 — 角にいる条件
	if char_h.distance_to(wall_r.position) > 1.5:
		return {}  # 壁が遠い

	# === Step 1: 36方向スキャンで壁の有無マップを作成 ===
	var scan_count := 36  # 10度刻み
	var wall_hits: Array[bool] = []
	var scan_dirs: Array[Vector3] = []
	for i in range(scan_count):
		var angle := deg_to_rad(float(i) * 10.0)
		var dir := Vector3(sin(angle), 0.0, cos(angle))
		scan_dirs.append(dir)
		var q := PhysicsRayQueryParameters3D.create(char_h, char_h + dir * 1.5)
		q.collision_mask = 2
		wall_hits.append(not space_state.intersect_ray(q).is_empty())

	# === Step 2: 投擲スタート位置を探索（壁なし＋ターゲットまで見通しあり）===
	var best_point := Vector3.ZERO
	var best_score := -1.0
	for i in range(scan_count):
		if wall_hits[i]:
			continue  # 壁がある方向はスキップ
		var candidate := char_h + scan_dirs[i] * 1.0

		# candidateからターゲットへの直線に壁がないか
		var scan_q := PhysicsRayQueryParameters3D.create(candidate, target_h)
		scan_q.collision_mask = 2
		if not space_state.intersect_ray(scan_q).is_empty():
			continue

		# candidateにフロアがあるか
		if not _has_ground_at(Vector3(candidate.x, 0.0, candidate.z)):
			continue

		# ターゲット方向との一致度でスコアリング
		var score := scan_dirs[i].dot(target_dir)
		if score > best_score:
			best_score = score
			best_point = candidate

	if best_point == Vector3.ZERO:
		return {}

	# === Step 3: 開口部方向を算出（壁面に沿ってスタート側を向く）===
	# 壁の法線から壁面方向（2つ）を求め、throw_start側を選ぶ
	var wall_normal: Vector3 = wall_r.normal
	var face_a := Vector3(-wall_normal.z, 0.0, wall_normal.x)   # 法線を90°回転
	var face_b := Vector3(wall_normal.z, 0.0, -wall_normal.x)   # 法線を-90°回転
	var start_dir: Vector3 = (best_point - char_h).normalized()
	var opening_dir: Vector3 = face_a if face_a.dot(start_dir) > face_b.dot(start_dir) else face_b

	print("[GRENADE] char=%s wall_hit=%s start=%s opening_dir=%s" % [char_h, wall_r.position, best_point, opening_dir])
	return {start = best_point, opening_dir = opening_dir}


func _on_throw_release() -> void:
	if not _player_character or not _player_character.is_alive:
		return
	if not game_manager or _grenade_target_pos == Vector3.ZERO:
		return

	# 左手ボーン位置からグレネードを生成（フォールバック: 胴体高さ）
	var start_pos := _player_character.anim_ctrl.get_bone_global_position(GameConstants.BONE_LEFT_HAND)
	if start_pos == Vector3.ZERO:
		start_pos = _player_character.global_position + Vector3(0, GameConstants.GRENADE_START_HEIGHT, 0)
	# コーナースロー時はスタート位置を角の向こう側にオーバーライド
	if _grenade_start_override != Vector3.ZERO:
		start_pos = _grenade_start_override
		_grenade_start_override = Vector3.ZERO
	var target_pos := _grenade_target_pos
	target_pos.y = 0.0

	# スモークグレネードをスポーン
	var result: Array = game_manager._spawn_and_throw_smoke_grenade(
		start_pos, target_pos, Vector3.ZERO, _player_character
	)

	# ネットワーク同期
	if result[0] != null:
		game_manager._emit_grenade_network_event(
			start_pos, result[1], true, result[2]
		)

	# インベントリ消費 + UI更新
	_smoke_grenade_count -= 1
	_update_grenade_count_ui()
	_grenade_target_pos = Vector3.ZERO


func _on_throw_finished() -> void:
	_grenade_target_pos = Vector3.ZERO
	_grenade_start_override = Vector3.ZERO
	if _tps_controller:
		_tps_controller.unlock_facing()


func _update_grenade_count_ui() -> void:
	if _grenade_count_label:
		_grenade_count_label.text = str(_smoke_grenade_count)
	if _grenade_btn:
		_grenade_btn.modulate.a = 1.0 if _smoke_grenade_count > 0 else 0.4


func _on_door_open_pressed() -> void:
	if _player_character and _player_character.anim_ctrl:
		_player_character.anim_ctrl.play_door_open()


func _on_debug_vision_toggled(enabled: bool) -> void:
	if game_manager and game_manager.vision_service:
		game_manager.vision_service.set_debug_draw(enabled)


## ========================================
## Talking（人質交渉）
## ========================================

## ホステージとの近接チェック（毎フレーム）
func _update_hostage_proximity() -> void:
	if not _player_character or not _player_character.is_alive:
		if _talking_btn and _talking_btn.visible:
			_talking_btn.visible = false
		return

	# CT側のみ人質交渉可能
	if _player_character.team != GameCharacter.Team.COUNTER_TERRORIST:
		if _talking_btn and _talking_btn.visible:
			_talking_btn.visible = false
		return

	var player_pos := _player_character.global_position
	_nearby_hostage = null

	for hostage in _hostage_characters:
		if not is_instance_valid(hostage):
			continue
		# 視界が通っていない（FoWで非表示の）ホステージは対象外
		if not hostage.visible:
			continue
		var dist := player_pos.distance_to(hostage.global_position)
		if dist <= GameConstants.HOSTAGE_TALK_DISTANCE:
			_nearby_hostage = hostage
			break

	if _talking_btn:
		_talking_btn.visible = _nearby_hostage != null


## Talkingボタン押下
func _on_talking_btn_pressed() -> void:
	if not _player_character or not _player_character.is_alive:
		return
	if not _nearby_hostage:
		return
	if _is_talking:
		return

	_is_talking = true
	_talking_elapsed = 0.0

	# ホステージの方を向く
	var dir_to_hostage := (_nearby_hostage.global_position - _player_character.global_position).normalized()
	dir_to_hostage.y = 0.0
	_player_character.set_facing_direction_vec(dir_to_hostage)

	# Talkingアニメーション開始
	if _player_character.anim_ctrl:
		_player_character.anim_ctrl.play_talking()

	# 武器を非表示
	var weapon_socket := _player_character.get_weapon_socket()
	if weapon_socket:
		weapon_socket.visible = false

	# 自動射撃を無効化
	if _player_character.combat_awareness:
		_player_character.combat_awareness.disable_firing()

	# プログレスバー作成
	_create_talking_progress_bar()

	# Talkingボタンを非表示
	if _talking_btn:
		_talking_btn.visible = false


## Talking中の毎フレーム更新
func _update_talking(delta: float) -> void:
	if not _is_talking:
		return

	# プレイヤー死亡チェック
	if not _player_character or not _player_character.is_alive:
		_cancel_talking()
		return

	# ホステージが視界外になったらキャンセル
	if _nearby_hostage and not _nearby_hostage.visible:
		_cancel_talking()
		return

	# 移動入力でキャンセル（左スティック or WASD）
	if _tps_controller and _tps_controller.has_move_input():
		_cancel_talking()
		return

	# タイマー進行
	_talking_elapsed += delta

	# プログレスバー更新
	if _talking_progress_bar:
		_talking_progress_bar.value = _talking_elapsed / GameConstants.HOSTAGE_TALK_DURATION

		# キャラ頭上の3D位置を2D座標に変換
		if camera and _player_character:
			var head_pos := _player_character.global_position + Vector3(0, 2.2, 0)
			var screen_pos := camera.unproject_position(head_pos)
			_talking_progress_bar.position = screen_pos - Vector2(_talking_progress_bar.size.x / 2.0, 20)

	# 完了判定
	if _talking_elapsed >= GameConstants.HOSTAGE_TALK_DURATION:
		_complete_talking()


## Talking完了（CT勝利）
func _complete_talking() -> void:
	_is_talking = false

	# アニメーション停止
	if _player_character and _player_character.anim_ctrl:
		_player_character.anim_ctrl.stop_talking()

	# 武器を再表示
	_restore_weapon_visibility()

	# 自動射撃を再有効化
	if _player_character and _player_character.combat_awareness:
		_player_character.combat_awareness.enable_firing()

	# プログレスバー削除
	_remove_talking_progress_bar()

	# CT勝利
	if game_manager and game_manager.round_manager:
		game_manager.round_manager.end_round(
			GameCharacter.Team.COUNTER_TERRORIST,
			RoundManager.EndReason.HOSTAGE_RESCUED
		)


## Talkingキャンセル（死亡時）
func _cancel_talking() -> void:
	_is_talking = false

	# アニメーション停止
	if _player_character and _player_character.anim_ctrl:
		_player_character.anim_ctrl.stop_talking()

	# 武器を再表示
	_restore_weapon_visibility()

	# 自動射撃を再有効化
	if _player_character and _player_character.combat_awareness:
		_player_character.combat_awareness.enable_firing()

	# プログレスバー削除
	_remove_talking_progress_bar()


## プログレスバー作成
func _create_talking_progress_bar() -> void:
	_remove_talking_progress_bar()

	_talking_progress_bar = ProgressBar.new()
	_talking_progress_bar.name = "TalkingProgressBar"
	_talking_progress_bar.custom_minimum_size = Vector2(100, 10)
	_talking_progress_bar.size = Vector2(100, 10)
	_talking_progress_bar.min_value = 0.0
	_talking_progress_bar.max_value = 1.0
	_talking_progress_bar.value = 0.0
	_talking_progress_bar.show_percentage = false

	# 緑色のfillスタイル
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.2, 0.8, 0.2)
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3
	_talking_progress_bar.add_theme_stylebox_override("fill", fill_style)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.2, 0.2, 0.2, 0.6)
	bg_style.corner_radius_top_left = 3
	bg_style.corner_radius_top_right = 3
	bg_style.corner_radius_bottom_left = 3
	bg_style.corner_radius_bottom_right = 3
	_talking_progress_bar.add_theme_stylebox_override("background", bg_style)

	_talking_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(_talking_progress_bar)


## 武器を再表示
func _restore_weapon_visibility() -> void:
	if _player_character:
		var weapon_socket := _player_character.get_weapon_socket()
		if weapon_socket:
			weapon_socket.visible = true


## プログレスバー削除
func _remove_talking_progress_bar() -> void:
	if _talking_progress_bar and is_instance_valid(_talking_progress_bar):
		_talking_progress_bar.queue_free()
		_talking_progress_bar = null


## ========================================
## シグナルハンドラ
## ========================================

func _on_round_timer_updated(time: float) -> void:
	if _timer_label:
		var total_seconds := int(time)
		var minutes := total_seconds / 60
		var seconds := total_seconds % 60
		_timer_label.text = "%d:%02d" % [minutes, seconds]


func _on_round_started() -> void:
	_smoke_grenade_count = GameConstants.SMOKE_GRENADE_PER_ROUND
	_update_grenade_count_ui()
	_exit_grenade_aiming()
	# Talking状態リセット
	if _is_talking:
		_cancel_talking()


func _on_round_ended(winner: int, reason: int) -> void:
	# Talking中ならキャンセル
	if _is_talking:
		_cancel_talking()
	_mode_provider.on_round_ended(winner, reason)

	# 3秒後に遷移
	await get_tree().create_timer(3.0).timeout

	# クリーンアップ
	_cleanup_before_transition()

	# モードによって遷移先を変える
	var next_scene: String
	if _mode_provider.get_mode_name() == "multiplayer":
		next_scene = "res://scenes/screens/main_menu.tscn"
	else:
		next_scene = "res://scenes/screens/map_selection.tscn"

	get_tree().change_scene_to_file(next_scene)
	# GameScreenはroot.add_child()で追加されているため、change_scene_to_fileでは破棄されない
	queue_free()


## ========================================
## 外部API
## ========================================

func get_smoke_area_manager() -> SmokeAreaManager:
	if game_manager:
		return game_manager.smoke_area_manager
	return null


func get_vision_service() -> VisionService:
	if game_manager:
		return game_manager.vision_service
	return null


func cleanup() -> void:
	_cleanup_before_transition()


var _cleanup_done: bool = false

func _cleanup_before_transition() -> void:
	if _cleanup_done:
		return
	_cleanup_done = true

	# マップとキャラクターのクリーンアップ
	if game_manager:
		game_manager.unload_map(true)
		if Debug.enabled: print("[GameScreen] Map and characters cleaned up")

	# 安全策: "characters" グループに残っているノードを全て削除
	# game_manager.characters 配列に入っていない孤立ノードも確実に削除する
	for node in get_tree().get_nodes_in_group(GameConstants.GROUP_CHARACTERS):
		if is_instance_valid(node):
			node.queue_free()

	# MapContainer の全子ノードを削除（死体、エフェクト等の残留防止）
	if map_container:
		for child in map_container.get_children():
			if is_instance_valid(child):
				child.queue_free()

	# Talking中ならキャンセル
	if _is_talking:
		_cancel_talking()

	# グレネードエイミングモードを解除
	_exit_grenade_aiming()

	# SignalBusのシグナル切断
	if SignalBus.round_timer_updated.is_connected(_on_round_timer_updated):
		SignalBus.round_timer_updated.disconnect(_on_round_timer_updated)
	if SignalBus.round_ended.is_connected(_on_round_ended):
		SignalBus.round_ended.disconnect(_on_round_ended)
	if SignalBus.round_started.is_connected(_on_round_started):
		SignalBus.round_started.disconnect(_on_round_started)

	# グレネード投擲シグナル切断
	if _player_character and _player_character.anim_ctrl:
		if _player_character.anim_ctrl.throw_release.is_connected(_on_throw_release):
			_player_character.anim_ctrl.throw_release.disconnect(_on_throw_release)
		if _player_character.anim_ctrl.throw_finished.is_connected(_on_throw_finished):
			_player_character.anim_ctrl.throw_finished.disconnect(_on_throw_finished)

	# グレネードレンジインジケーターのクリーンアップ
	if _grenade_mesh and is_instance_valid(_grenade_mesh):
		_grenade_mesh.queue_free()
		_grenade_mesh = null
	if _grenade_viewport and is_instance_valid(_grenade_viewport):
		_grenade_viewport.queue_free()
		_grenade_viewport = null
	if _grenade_occluder_mgr and is_instance_valid(_grenade_occluder_mgr):
		_grenade_occluder_mgr.queue_free()
		_grenade_occluder_mgr = null
	_grenade_light = null
	_grenade_mat = null
	if _round_hud:
		if SignalBus.survivor_count_changed.is_connected(_round_hud.update_survivor_counts):
			SignalBus.survivor_count_changed.disconnect(_round_hud.update_survivor_counts)
		if SignalBus.round_ended.is_connected(_round_hud.show_result):
			SignalBus.round_ended.disconnect(_round_hud.show_result)

	# HUDを明示的に削除
	if _round_hud and is_instance_valid(_round_hud):
		_round_hud.queue_free()
		_round_hud = null

	# TPS制御のクリーンアップ
	_tps_controller = null
	_player_character = null

	# Providerのクリーンアップ（WebSocket切断含む）
	if _mode_provider:
		_mode_provider.cleanup()
		if Debug.enabled: print("[GameScreen] Network cleanup completed")


func _exit_tree() -> void:
	_cleanup_before_transition()


## ========================================
## デバッグ入力
## ========================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_vision_debug_enabled = not _vision_debug_enabled
			game_manager.set_vision_debug_draw(_vision_debug_enabled)
			if Debug.enabled: print("[DEBUG] Vision debug draw: %s" % ("ON" if _vision_debug_enabled else "OFF"))


## WASDキーかどうか判定
func _is_wasd_key(keycode: Key) -> bool:
	return keycode == KEY_W or keycode == KEY_A or keycode == KEY_S or keycode == KEY_D
