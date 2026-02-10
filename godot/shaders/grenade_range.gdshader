shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Grenade range indicator - same technique as FoW but shows throwable area
uniform vec4 area_color : source_color = vec4(0.2, 0.9, 0.4, 0.25);
uniform vec4 ring_color : source_color = vec4(0.3, 1.0, 0.5, 0.7);
uniform sampler2D visibility_texture : filter_linear, hint_default_black;
uniform vec2 map_min = vec2(-20.0, -20.0);
uniform vec2 map_max = vec2(20.0, 20.0);
uniform float edge_softness : hint_range(0.0, 0.5) = 0.15;

// Ring edge parameters (world space)
uniform vec2 char_position = vec2(0.0, 0.0);
uniform float throw_range = 5.0;
uniform float ring_width = 0.12;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 world_xz = world_position.xz;
	vec2 uv = (world_xz - map_min) / (map_max - map_min);

	float visibility = 0.0;
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		visibility = texture(visibility_texture, uv).r;
		visibility = min(visibility, 1.0);
		// smoothstep for soft edges (same as FoW)
		visibility = smoothstep(0.1, 0.3 + edge_softness, visibility);
	}

	// Ring at throw range boundary
	float dist = length(world_xz - char_position);
	float ring_inner = throw_range - ring_width;
	float ring = smoothstep(ring_inner - ring_width * 0.5, ring_inner, dist)
	           * (1.0 - smoothstep(throw_range - ring_width * 0.2, throw_range, dist));

	// Combine fill + ring (ring only where visible)
	float fill_alpha = area_color.a * visibility;
	float ring_alpha = ring_color.a * ring * visibility;
	float combined_alpha = max(fill_alpha, ring_alpha);

	vec3 color = mix(area_color.rgb, ring_color.rgb, ring * visibility);

	ALBEDO = color;
	ALPHA = combined_alpha;
}
