shader_type spatial;
render_mode unshaded, cull_disabled;

// パス用ドットラインシェーダー
// 流れる丸ドットアニメーション付き

uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 0.9);
uniform float dot_radius : hint_range(0.05, 0.5) = 0.12;
uniform float dot_spacing : hint_range(0.3, 3.0) = 0.5;
uniform float flow_speed : hint_range(0.0, 5.0) = 1.5;
uniform float emission_strength : hint_range(0.0, 3.0) = 1.5;
uniform float line_width_world : hint_range(0.01, 1.0) = 0.1;
uniform float path_offset : hint_range(0.0, 1000.0) = 0.0;  // 通過した距離（アニメーション連続性用）

void fragment() {
	// UV.x = パスに沿った距離（ワールド単位）
	// UV.y = 幅方向（0-1）
	float path_distance = UV.x + path_offset;  // オフセットを加算して絶対距離に
	float width_pos = (UV.y - 0.5) * line_width_world;  // 中心からの距離（ワールド単位）

	// 流れるアニメーション
	float animated_distance = path_distance - TIME * flow_speed;

	// 最も近いドット中心を見つける
	float dot_center = round(animated_distance / dot_spacing) * dot_spacing;

	// ドット中心からの距離（2D、ワールド単位）
	float dx = animated_distance - dot_center;
	float dy = width_pos;
	float dist_from_dot = sqrt(dx * dx + dy * dy);

	// 円形ドット（スムーズエッジ）
	float dot = 1.0 - smoothstep(dot_radius * 0.7, dot_radius, dist_from_dot);

	// 透明度が低すぎる部分は破棄
	if (dot < 0.05) {
		discard;
	}

	ALBEDO = line_color.rgb;
	ALPHA = dot * line_color.a;
	EMISSION = line_color.rgb * emission_strength;
}
