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
var _money_label: Label = null
var _debug_vision_btn: Button = null
var _hp_bar: ProgressBar = null
var _crosshair: Control = null
var _crosshair_color: Color = Color.WHITE

## UI要素
var _round_hud: RoundHUD = null

## グレネードエイミングモード
var _is_grenade_aiming: bool = false
var _grenade_target_pos: Vector3 = Vector3.ZERO
var _smoke_grenade_count: int = GameConstants.SMOKE_GRENADE_PER_ROUND

## グレネードUI
var _grenade_btn: TextureButton = null
var _grenade_count_label: Label = null

## レンジインジケーター（SubViewport + Light2D方式 = FoWと同品質）
var _grenade_viewport: SubViewport = null
var _grenade_light: PointLight2D = null
var _grenade_occluder_mgr: OccluderManager = null
var _grenade_mesh: MeshInstance3D = null
var _grenade_mat: ShaderMaterial = null

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
	_setup_money()
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

	# IdleManagerにキャラクターリストを更新
	if game_manager.idle_manager:
		game_manager.idle_manager.set_characters(game_manager.characters)


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

	# マネー（タイマーの下）
	_money_label = Label.new()
	_money_label.name = "MoneyLabel"
	_money_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_money_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_money_label.position = Vector2(-120, 45)
	_money_label.add_theme_font_size_override("font_size", 18)
	_money_label.text = "$0"
	ui_layer.add_child(_money_label)

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
	var vbox := VBoxContainer.new()
	vbox.name = "ActionButtons"
	vbox.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	vbox.position = Vector2(-100, -120)
	vbox.add_theme_constant_override("separation", 16)
	ui_layer.add_child(vbox)

	# Open Door ボタン
	var btn_door_open := _create_icon_button(
		"res://assets/ui/game/controller-door-button.png",
		_on_door_open_pressed
	)
	vbox.add_child(btn_door_open)

	# スモークグレネードボタン + 残数ラベル
	var grenade_container := VBoxContainer.new()
	grenade_container.add_theme_constant_override("separation", 2)
	vbox.add_child(grenade_container)

	_grenade_btn = _create_icon_button(
		"res://assets/ui/game/controller-hand-granade-button.png",
		_on_grenade_btn_pressed
	)
	grenade_container.add_child(_grenade_btn)

	_grenade_count_label = Label.new()
	_grenade_count_label.text = str(_smoke_grenade_count)
	_grenade_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grenade_count_label.add_theme_font_size_override("font_size", 14)
	grenade_container.add_child(_grenade_count_label)

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


func _setup_money() -> void:
	PlayerState.reset_money()
	if not PlayerState.money_changed.is_connected(_on_money_changed):
		PlayerState.money_changed.connect(_on_money_changed)
	_update_money_display()


## ========================================
## UI更新
## ========================================

func _update_money_display() -> void:
	if _money_label:
		_money_label.text = "$%d" % PlayerState.get_money()


## ========================================
## 毎フレーム処理
## ========================================

func _physics_process(delta: float) -> void:
	if game_manager:
		game_manager.process_frame(delta)
	if _tps_controller and not _is_grenade_aiming:
		_tps_controller.process(delta)
	_update_tps_hud()
	if _is_grenade_aiming:
		_update_grenade_light_position()


func _input(event: InputEvent) -> void:
	# グレネードエイミング中: 移動入力をブロックし、タッチ/クリックはターゲット選択のみ
	if _is_grenade_aiming:
		if event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			if touch.pressed:
				_handle_grenade_target_tap(touch.position)
				get_viewport().set_input_as_handled()
				return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_handle_grenade_target_tap(mb.position)
				get_viewport().set_input_as_handled()
				return
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
	_hide_range_indicator()
	if _grenade_btn:
		_grenade_btn.modulate = Color.WHITE


func _setup_grenade_indicator() -> void:
	var fow: Node3D = game_manager.fog_of_war_system if game_manager else null
	if not fow:
		return

	var fow_map_size: Vector2 = fow.map_size
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
	_grenade_light.shadow_filter = q["shadow_filter"]
	_grenade_light.shadow_filter_smooth = q["shadow_smooth"]
	_grenade_light.shadow_item_cull_mask = 1
	_grenade_light.range_item_cull_mask = 1
	_grenade_light.texture = FovTextureGenerator.generate_circular_texture(resolution, 0.8)
	_grenade_viewport.add_child(_grenade_light)

	# ライトスケール（VisionLightと同じ計算式）
	var max_dimension := maxf(fow_map_size.x, fow_map_size.y)
	var scale_factor := float(resolution) / max_dimension
	var light_diameter := throw_range * scale_factor * 2.0
	_grenade_light.texture_scale = light_diameter / float(resolution)
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
	_grenade_mat.set_shader_parameter("visibility_texture", _grenade_viewport.get_texture())
	_grenade_mat.set_shader_parameter("map_min", Vector2(-fow_map_size.x / 2.0, -fow_map_size.y / 2.0))
	_grenade_mat.set_shader_parameter("map_max", Vector2(fow_map_size.x / 2.0, fow_map_size.y / 2.0))
	_grenade_mesh.material_override = _grenade_mat
	_grenade_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grenade_mesh.visible = false
	add_child(_grenade_mesh)


func _show_range_indicator() -> void:
	if _grenade_mesh:
		_grenade_mesh.visible = true
		_update_grenade_light_position()


func _hide_range_indicator() -> void:
	if _grenade_mesh:
		_grenade_mesh.visible = false
	if _grenade_viewport:
		_grenade_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


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

	# 視線チェック（壁の向こうには投げられない）
	var space_state := _player_character.get_world_3d().direct_space_state
	if space_state:
		var eye_pos := char_pos + Vector3(0, GameConstants.GRENADE_START_HEIGHT, 0)
		var target_eye := ground_point + Vector3(0, 0.5, 0)
		var query := PhysicsRayQueryParameters3D.create(eye_pos, target_eye, 2)  # mask=2: 壁レイヤー
		query.exclude = [_player_character.get_rid()]
		var result := space_state.intersect_ray(query)
		if not result.is_empty():
			return  # 壁に遮られている

	# エイミングモード終了
	_exit_grenade_aiming()

	# キャラクターをターゲット方向に向ける
	var facing_dir := to_target.normalized()
	_player_character.set_facing_direction_vec(facing_dir)

	# ターゲット位置を保存
	_grenade_target_pos = ground_point

	# 距離で近投/遠投を自動選択
	if distance <= GameConstants.GRENADE_THROW_CLOSE_THRESHOLD:
		_player_character.anim_ctrl.play_throw_close()
	else:
		_player_character.anim_ctrl.play_throw_far()


func _on_throw_release() -> void:
	if not _player_character or not _player_character.is_alive:
		return
	if not game_manager or _grenade_target_pos == Vector3.ZERO:
		return

	var start_pos := _player_character.global_position + Vector3(0, GameConstants.GRENADE_START_HEIGHT, 0)
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
## シグナルハンドラ
## ========================================

func _on_money_changed(_new_amount: int) -> void:
	_update_money_display()


func _on_round_timer_updated(time: float) -> void:
	if _timer_label:
		var minutes := int(time) / 60
		var seconds := int(time) % 60
		_timer_label.text = "%d:%02d" % [minutes, seconds]


func _on_round_started() -> void:
	_smoke_grenade_count = GameConstants.SMOKE_GRENADE_PER_ROUND
	_update_grenade_count_ui()
	_exit_grenade_aiming()


func _on_round_ended(winner: int, reason: int) -> void:
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

	# PlayerStateのシグナル切断
	if PlayerState.money_changed.is_connected(_on_money_changed):
		PlayerState.money_changed.disconnect(_on_money_changed)

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
