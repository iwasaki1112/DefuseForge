shader_type spatial;
render_mode unshaded, cull_front;

// Next Pass用アウトラインシェーダー
// Based on: https://github.com/anunknowperson/Godot4SimpleOutline
uniform vec4 outline_color : source_color = vec4(0.0, 0.8, 1.0, 1.0);
uniform float outline_thickness : hint_range(0.0, 0.1) = 0.02;

void vertex() {
	// オブジェクト中心から外側に膨らませる
	VERTEX += normalize(VERTEX) * outline_thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	EMISSION = outline_color.rgb * 2.0;
}
