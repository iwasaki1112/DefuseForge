shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// My0Cents Fog of War approach - depth buffer reconstruction with image blend
// Reference: https://github.com/My0Cents/Fog_Of_War

// Fog appearance
uniform vec4 fog_color : source_color = vec4(0.1, 0.15, 0.25, 0.3);

// Visibility texture (generated from Image.blend_rect())
uniform sampler2D visibility_texture : filter_linear, hint_default_black;

// Map bounds in world coordinates
uniform vec2 map_min = vec2(-20.0, -20.0);
uniform vec2 map_max = vec2(20.0, 20.0);

// Blur settings for smooth edges
uniform float blur_radius : hint_range(0.0, 4.0) = 1.5;
uniform float texture_size = 256.0;

// Edge softness
uniform float edge_softness : hint_range(0.0, 0.5) = 0.1;

// World position from vertex shader (camera-independent)
varying vec3 world_position;

void vertex() {
	// Calculate world position in vertex shader for consistent coordinates
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Use world position from vertex shader (consistent with wall shader)
	vec2 world_xz = world_position.xz;

	// Convert world XZ to UV coordinates (0-1 range)
	vec2 uv = (world_xz - map_min) / (map_max - map_min);

	// Handle out-of-bounds
	float visibility = 0.0;
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		// シンプルサンプリング（ブラーなし）
		visibility = texture(visibility_texture, uv).r;

		// Clamp to prevent ADD blend artifacts at light overlaps
		visibility = min(visibility, 1.0);

		// シャープエッジ: 壁シェーダーと同じ閾値で統一
		visibility = smoothstep(0.1, 0.3, visibility);
	}

	// Apply fog: visible areas are transparent, hidden areas show fog
	ALBEDO = fog_color.rgb;
	ALPHA = fog_color.a * (1.0 - visibility);
}
