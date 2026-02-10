shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Grenade range indicator - same technique as FoW but shows throwable area
uniform vec4 area_color : source_color = vec4(0.2, 0.9, 0.4, 0.25);
uniform sampler2D visibility_texture : filter_linear, hint_default_black;
uniform vec2 map_min = vec2(-20.0, -20.0);
uniform vec2 map_max = vec2(20.0, 20.0);
uniform float edge_softness : hint_range(0.0, 0.5) = 0.15;

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

	// Visible areas show green overlay, hidden areas are transparent
	ALBEDO = area_color.rgb;
	ALPHA = area_color.a * visibility;
}
