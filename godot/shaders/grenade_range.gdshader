shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 area_color : source_color = vec4(0.9, 0.2, 0.2, 0.6);
uniform sampler2D visibility_texture : filter_linear, hint_default_black;
uniform vec2 map_min = vec2(-20.0, -20.0);
uniform vec2 map_max = vec2(20.0, 20.0);
uniform vec2 char_position = vec2(0.0, 0.0);
uniform float throw_range = 5.0;

// Blur settings for smooth edges (same as fow.gdshader)
uniform float blur_radius : hint_range(0.0, 4.0) = 1.5;
uniform float texture_size = 256.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 world_xz = world_position.xz;
	vec2 uv = (world_xz - map_min) / (map_max - map_min);

	float visibility = 0.0;
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		float px = blur_radius / texture_size;

		// 9-point weighted blur for smooth edges (same as fow.gdshader)
		// Center (weight 4) + cross (weight 2 each) + diagonals (weight 1 each) = 16
		visibility = texture(visibility_texture, uv).r * 4.0;
		visibility += texture(visibility_texture, uv + vec2(px, 0.0)).r * 2.0;
		visibility += texture(visibility_texture, uv - vec2(px, 0.0)).r * 2.0;
		visibility += texture(visibility_texture, uv + vec2(0.0, px)).r * 2.0;
		visibility += texture(visibility_texture, uv - vec2(0.0, px)).r * 2.0;
		visibility += texture(visibility_texture, uv + vec2(px, px)).r;
		visibility += texture(visibility_texture, uv + vec2(-px, px)).r;
		visibility += texture(visibility_texture, uv + vec2(px, -px)).r;
		visibility += texture(visibility_texture, uv + vec2(-px, -px)).r;
		visibility /= 16.0;

		visibility = min(visibility, 1.0);
		visibility = smoothstep(0.05, 0.4, visibility);
	}

	// 投擲範囲を内側にオフセットしてグラデーション
	float dist = length(world_xz - char_position);
	float range_mask = 1.0 - smoothstep(throw_range - 1.5, throw_range - 0.6, dist);

	ALBEDO = area_color.rgb;
	ALPHA = area_color.a * visibility * range_mask;
}
