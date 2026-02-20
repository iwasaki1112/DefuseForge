shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_opaque;

uniform vec4 trail_color : source_color = vec4(1.0, 0.9, 0.65, 0.35);
uniform float edge_softness : hint_range(0.0, 2.0) = 0.5;
uniform float tip_roundness : hint_range(0.0, 0.5) = 0.18;
uniform float fade_start : hint_range(0.0, 1.0) = 0.0;
uniform float fade_end : hint_range(0.0, 1.0) = 0.5;
uniform float glow_intensity : hint_range(0.0, 3.0) = 0.8;
uniform float core_brightness : hint_range(0.0, 3.0) = 1.5;
uniform float overall_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// UV.x: 横方向 (0.0 = 左端, 1.0 = 右端), UV.y: 縦方向 (0.0 = 末端, 1.0 = 先端)
	vec2 uv = UV;

	// 横方向のソフトエッジ（中央が1.0、端が0.0へのグラデーション）
	float center_dist = abs(uv.x - 0.5) * 2.0;  // 0.0(中央) ~ 1.0(端)
	float edge_alpha = 1.0 - smoothstep(1.0 - edge_softness * 2.0, 1.0, center_dist);

	// 先端の丸み処理
	float tip_factor = 1.0;
	if (uv.y > (1.0 - tip_roundness)) {
		// 先端領域：楕円形のキャップを作成
		float tip_progress = (uv.y - (1.0 - tip_roundness)) / tip_roundness;
		float tip_width = sqrt(1.0 - tip_progress * tip_progress);  // 円の方程式
		float tip_center_dist = abs(uv.x - 0.5) * 2.0;
		tip_factor = 1.0 - smoothstep(tip_width - edge_softness, tip_width, tip_center_dist);
	}

	// 末端のフェードアウト（UV.y = 0.0が末端）
	float fade_alpha = smoothstep(fade_start, fade_end, uv.y);

	// 最終アルファ
	float final_alpha = edge_alpha * tip_factor * fade_alpha * overall_alpha;

	// コア/グロー効果（中央ほど明るく、端に向かって自然に減衰）
	float core = exp(-center_dist * center_dist * 3.0) * core_brightness;
	float glow = (1.0 - center_dist * 0.7) * glow_intensity;
	vec3 final_color = trail_color.rgb * (core + glow);

	ALBEDO = final_color;
	ALPHA = final_alpha * trail_color.a;
}
