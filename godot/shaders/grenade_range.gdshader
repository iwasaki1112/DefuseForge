shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 area_color : source_color = vec4(0.9, 0.2, 0.2, 0.6);
uniform sampler2D visibility_texture : filter_linear, hint_default_black;
uniform vec2 map_min = vec2(-20.0, -20.0);
uniform vec2 map_max = vec2(20.0, 20.0);
uniform vec2 char_position = vec2(0.0, 0.0);
uniform float throw_range = 5.0;
uniform float visibility_threshold : hint_range(0.0, 1.0) = 0.5;

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

	// エッジグラデーション: 閾値を上げて内側に寄せ、控えめに表示
	float visibility = smoothstep(0.4, 0.9, raw_visibility);

	// 投擲範囲を内側にオフセットしてグラデーション
	float dist = length(world_xz - char_position);
	float range_mask = 1.0 - smoothstep(throw_range - 1.5, throw_range - 0.6, dist);

	ALBEDO = area_color.rgb;
	ALPHA = area_color.a * visibility * range_mask;
}
