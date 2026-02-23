shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Fog appearance
uniform vec4 fog_color : source_color = vec4(0.15, 0.15, 0.15, 0.5);

// Visibility texture (generated from SubViewport Light2D shadow)
uniform sampler2D visibility_texture : filter_linear, hint_default_black;

// Depth texture for surface world position reconstruction
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

// Map bounds in world coordinates
uniform vec2 map_min = vec2(-20.0, -20.0);
uniform vec2 map_max = vec2(20.0, 20.0);

// Edge threshold: visibility values above this are visible
uniform float edge_threshold : hint_range(0.0, 1.0) = 0.2;

// Edge sharpness (higher = crisper edge)
uniform float edge_sharpness : hint_range(0.5, 4.0) = 1.5;

// AA band width in screen-pixel units
uniform float edge_aa_pixels : hint_range(0.5, 2.0) = 1.0;

// Visibility texture resolution (square)
uniform float texture_size = 512.0;

// OpenGL (Compatibility): true -> depth [0,1] remapped to NDC [-1,1]
// Vulkan (Forward+/Mobile): false -> depth [0,1] is NDC directly
uniform bool depth_gl_remap = true;

float sample_vis_clamped(vec2 uv, vec2 min_uv, vec2 max_uv) {
	return texture(visibility_texture, clamp(uv, min_uv, max_uv)).r;
}

// Pseudo-SDF edge reconstruction from local gradient (5 taps total)
float visibility_from_pseudo_sdf(vec2 uv) {
	vec2 texel = vec2(1.0 / texture_size, 1.0 / texture_size);
	vec2 min_uv = texel * 0.5;
	vec2 max_uv = vec2(1.0) - texel * 0.5;
	vec2 p = clamp(uv, min_uv, max_uv);

	float c = sample_vis_clamped(p, min_uv, max_uv);
	float r = sample_vis_clamped(p + vec2(texel.x, 0.0), min_uv, max_uv);
	float l = sample_vis_clamped(p - vec2(texel.x, 0.0), min_uv, max_uv);
	float u = sample_vis_clamped(p + vec2(0.0, texel.y), min_uv, max_uv);
	float d = sample_vis_clamped(p - vec2(0.0, texel.y), min_uv, max_uv);

	// Gradient in "value per texel"
	vec2 grad = 0.5 * vec2(r - l, u - d);
	float grad_len = length(grad);

	// Flat area fallback
	if (grad_len < 0.0005) {
		return step(edge_threshold, c);
	}

	// Signed distance to threshold contour in texel units
	float dist_texel = (c - edge_threshold) / grad_len;

	// Screen footprint in texel units (for stable 1px-ish AA band)
	vec2 p_tex = p * texture_size;
	float footprint_texel = max(length(dFdx(p_tex)), length(dFdy(p_tex)));
	float aa_half_width = max(footprint_texel * edge_aa_pixels, 0.35);

	// edge_sharpness > 1 makes transition crisper
	return smoothstep(-aa_half_width, aa_half_width, dist_texel * edge_sharpness);
}

void fragment() {
	// Reconstruct actual surface world position from depth buffer
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	float ndc_z = depth_raw;
	if (depth_gl_remap) {
		ndc_z = depth_raw * 2.0 - 1.0;
	}
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, ndc_z);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	vec3 surface_world = (INV_VIEW_MATRIX * vec4(view_pos.xyz, 1.0)).xyz;

	vec2 uv = (surface_world.xz - map_min) / (map_max - map_min);
	float surface_y = surface_world.y;

	float visibility = 0.0;
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		visibility = visibility_from_pseudo_sdf(uv);

		// Wall top face (Y>=1.9): always visible
		visibility = max(visibility, smoothstep(1.9, 1.95, surface_y));
	}

	ALBEDO = fog_color.rgb;
	ALPHA = fog_color.a * (1.0 - clamp(visibility, 0.0, 1.0));
}
