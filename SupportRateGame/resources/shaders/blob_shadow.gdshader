shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);
uniform float softness : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	// UV座標を中心基準に変換 (-1 to 1)
	vec2 centered_uv = UV * 2.0 - 1.0;

	// 中心からの距離を計算
	float dist = length(centered_uv);

	// 円形のグラデーション（中心が濃く、端が薄い）
	float alpha = 1.0 - smoothstep(1.0 - softness, 1.0, dist);

	// 円の外側は完全に透明
	if (dist > 1.0) {
		alpha = 0.0;
	}

	ALBEDO = shadow_color.rgb;
	ALPHA = alpha * shadow_color.a;
}
