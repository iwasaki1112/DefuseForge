extends CanvasLayer

## ゲームUIの管理

@onready var score_label: Label = $MarginContainer/VBoxContainer/ScoreLabel
@onready var timer_label: Label = $MarginContainer/VBoxContainer/TimerLabel
@onready var support_rate_label: Label = $MarginContainer/VBoxContainer/SupportRateLabel
@onready var game_over_panel: Panel = $GameOverPanel
@onready var final_score_label: Label = $GameOverPanel/VBoxContainer/FinalScoreLabel
@onready var final_message_label: Label = $GameOverPanel/VBoxContainer/FinalMessageLabel
@onready var restart_button: Button = $GameOverPanel/VBoxContainer/RestartButton


func _ready() -> void:
	game_over_panel.visible = false
	restart_button.pressed.connect(_on_restart_button_pressed)

	# GameManagerのシグナルに接続
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.time_changed.connect(_on_time_changed)
	GameManager.support_rate_changed.connect(_on_support_rate_changed)
	GameManager.game_over.connect(_on_game_over)


func _on_score_changed(new_score: int) -> void:
	score_label.text = "支持率ポイント: %d" % new_score


func _on_time_changed(remaining_time: float) -> void:
	var minutes := int(remaining_time) / 60
	var seconds := int(remaining_time) % 60
	timer_label.text = "残り時間: %02d:%02d" % [minutes, seconds]


func _on_support_rate_changed(rate: float) -> void:
	support_rate_label.text = "支持率: %.1f%%" % rate


func _on_game_over(final_score: int, coins_collected: int, support_rate: float) -> void:
	game_over_panel.visible = true
	final_score_label.text = "最終スコア: %d\n取得コイン: %d/%d\n最終支持率: %.1f%%" % [
		final_score,
		coins_collected,
		GameManager.TOTAL_COINS,
		support_rate
	]
	final_message_label.text = GameManager.get_result_message()


func _on_restart_button_pressed() -> void:
	get_tree().reload_current_scene()
