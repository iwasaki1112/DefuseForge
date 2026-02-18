shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Fog appearance
uniform vec4 fog_color : source_color = vec4(0.1, 0.15, 0.25, 0.5);

// Visibility texture (generated from SubViewport Light2D shadow)
uniform sampler2D visibility_texture : filter_linear, hint_default_black;

// Depth texture for surface world position reconstruction
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

// Map bounds in world coordinates
uniform vec2 map_min = vec2(-20.0, -20.0);
uniform vec2 map_max = vec2(20.0, 20.0);

// Blur settings for smooth edges
uniform float blur_radius : hint_range(0.0, 4.0) = 1.5;
uniform float texture_size = 256.0;
uniform float edge_softness : hint_range(0.0, 0.5) = 0.1;

// OpenGL (Compatibility): true → depth [0,1] remapped to NDC [-1,1]
// Vulkan (Forward+/Mobile): false → depth [0,1] is NDC directly
uniform bool depth_gl_remap = true;

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
		float px = blur_radius / texture_size;

		// 9-point weighted blur for smooth cone edges
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
		// Wall top face (Y>=2.0): always fog
		visibility *= 1.0 - smoothstep(1.9, 1.95, surface_y);
		visibility = smoothstep(0.05, 0.4, visibility);
	}

	ALBEDO = fog_color.rgb;
	ALPHA = fog_color.a * (1.0 - visibility);
}
