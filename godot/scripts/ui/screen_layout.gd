class_name ScreenLayout
extends RefCounted
## 画面UIの共通レイアウト生成ヘルパー

const DEFAULT_BG_COLOR := Color(0.1, 0.1, 0.15, 1.0)


static func add_solid_background(root: Control, color: Color = DEFAULT_BG_COLOR) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = color
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	return bg


static func create_centered_vbox(root: Control, separation: int = 30) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", separation)
	center.add_child(vbox)
	return vbox
