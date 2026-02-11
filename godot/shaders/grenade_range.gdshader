shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Grenade range indicator - solid green fill with binary visibility
uniform vec4 area_color : source_color = vec4(0.2, 0.8, 0.3, 0.5);
uniform vec4 ring_color : source_color = vec4(0.3, 1.0, 0.5, 0.8);
uniform sampler2D visibility_texture : filter_linear, hint_default_black;
uniform vec2 map_min = vec2(-20.0, -20.0);
uniform vec2 map_max = vec2(20.0, 20.0);

// Ring edge parameters (world space)
uniform vec2 char_position = vec2(0.0, 0.0);
uniform float throw_range = 5.0;
uniform float ring_width = 0.12;

// Visibility binarization
uniform float visibility_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float visibility_aa : hint_range(0.0, 0.1) = 0.02;
uniform float shadow_min : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 world_xz = world_position.xz;
	vec2 uv = (world_xz - map_min) / (map_max - map_min);

	float raw_visibility = 0.0;
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		raw_visibility = texture(visibility_texture, uv).r;
	}

	// 二値化: ベタ塗り + 1-2px AA for clean edges
	float aa = max(visibility_aa, fwidth(raw_visibility));
	float visibility = smoothstep(visibility_threshold - aa, visibility_threshold + aa, raw_visibility);

	// 開口部付近時: 影エリアも薄く表示（コーナースロー可能範囲を示す）
	float effective_vis = mix(shadow_min, 1.0, visibility);

	// Ring at throw range boundary
	float dist = length(world_xz - char_position);
	float ring_inner = throw_range - ring_width;
	float ring = smoothstep(ring_inner - ring_width * 0.5, ring_inner, dist)
	           * (1.0 - smoothstep(throw_range - ring_width * 0.2, throw_range, dist));

	// Combine fill + ring（影エリアも含む完全な円）
	float fill_alpha = area_color.a * effective_vis;
	float ring_alpha = ring_color.a * ring * effective_vis;
	float combined_alpha = max(fill_alpha, ring_alpha);

	vec3 color = mix(area_color.rgb, ring_color.rgb, ring * effective_vis);

	ALBEDO = color;
	ALPHA = combined_alpha;
}
