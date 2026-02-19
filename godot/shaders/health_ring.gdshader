shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled;

uniform float health_ratio : hint_range(0.0, 1.0) = 1.0;
uniform float ring_radius : hint_range(0.0, 1.0) = 0.80;
uniform float ring_width : hint_range(0.0, 0.3) = 0.12;
uniform vec4 color_high : source_color = vec4(0.2, 0.85, 0.3, 0.9);
uniform vec4 color_mid : source_color = vec4(0.95, 0.75, 0.1, 0.9);
uniform vec4 color_low : source_color = vec4(0.95, 0.2, 0.15, 0.9);
uniform vec4 bg_color : source_color = vec4(0.12, 0.12, 0.12, 0.35);

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);

	// Ring mask with smooth edges
	float inner = ring_radius - ring_width * 0.5;
	float outer = ring_radius + ring_width * 0.5;
	float ring_mask = smoothstep(inner - 0.02, inner + 0.02, dist)
	                 * (1.0 - smoothstep(outer - 0.02, outer + 0.02, dist));

	if (ring_mask < 0.01) {
		discard;
	}

	// Angle: 0 at top, clockwise, 0-1 range
	float angle = atan(uv.x, uv.y);
	float normalized_angle = fract(angle / (2.0 * PI));

	// Health fill with smooth edge
	float fill = 1.0 - smoothstep(health_ratio - 0.008, health_ratio + 0.008, normalized_angle);

	// Determine HP color based on ratio
	vec4 hp_color;
	if (health_ratio > 0.5) {
		hp_color = color_high;
	} else if (health_ratio > 0.25) {
		hp_color = color_mid;
	} else {
		hp_color = color_low;
	}

	// Combine: filled portion uses HP color, rest uses background
	vec4 final_color = mix(bg_color, hp_color, fill);

	ALBEDO = final_color.rgb;
	ALPHA = ring_mask * final_color.a;
}
