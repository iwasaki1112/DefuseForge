shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// My0Cents Fog of War approach - depth buffer reconstruction with image blend
// Reference: https://github.com/My0Cents/Fog_Of_War

// Fog appearance
uniform vec4 fog_color : source_color = vec4(0.1, 0.15, 0.25, 0.85);

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

void fragment() {
	// Reconstruct world position from vertex
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 world_xz = world_pos.xz;

	// Convert world XZ to UV coordinates (0-1 range)
	vec2 uv = (world_xz - map_min) / (map_max - map_min);

	// Handle out-of-bounds
	float visibility = 0.0;
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		// Apply Gaussian blur for smooth edges
		vec2 texel = 1.0 / vec2(texture_size);
		float radius = blur_radius;

		if (radius > 0.01) {
			// 5x5 Gaussian kernel (sigma = 1.0)
			float weights[25] = float[](
				0.003765, 0.015019, 0.023792, 0.015019, 0.003765,
				0.015019, 0.059912, 0.094907, 0.059912, 0.015019,
				0.023792, 0.094907, 0.150342, 0.094907, 0.023792,
				0.015019, 0.059912, 0.094907, 0.059912, 0.015019,
				0.003765, 0.015019, 0.023792, 0.015019, 0.003765
			);

			float blurred = 0.0;
			int idx = 0;
			for (int y = -2; y <= 2; y++) {
				for (int x = -2; x <= 2; x++) {
					vec2 offset = vec2(float(x), float(y)) * texel * radius;
					blurred += texture(visibility_texture, uv + offset).r * weights[idx];
					idx++;
				}
			}
			visibility = blurred;
		} else {
			visibility = texture(visibility_texture, uv).r;
		}

		// Clamp to prevent ADD blend artifacts at light overlaps
		visibility = min(visibility, 1.0);

		// Smooth transition at edges (lower threshold to reduce seams at overlaps)
		visibility = smoothstep(0.15 - edge_softness, 0.15 + edge_softness, visibility);
	}

	// Apply fog: visible areas are transparent, hidden areas show fog
	ALBEDO = fog_color.rgb;
	ALPHA = fog_color.a * (1.0 - visibility);
}
