shader_type canvas_item;

// Silhouette edge detection shader
// Based on Fake Stencil approach by Sithoid/Leafshade/Mark Raynsford

uniform float line_width : hint_range(1.0, 20.0) = 4.0;
uniform vec4 outline_color : source_color = vec4(0.0, 0.8, 1.0, 1.0);
uniform float emission_energy : hint_range(0.0, 10.0) = 3.0;
uniform sampler2D mask_texture : hint_default_black;

void fragment() {
	vec2 tex_size = vec2(textureSize(mask_texture, 0));
	float dx = line_width / tex_size.x;
	float dy = line_width / tex_size.y;

	// Sample mask at current and neighboring pixels
	float center = texture(mask_texture, UV).r;
	float top = texture(mask_texture, UV + vec2(0.0, -dy)).r;
	float bottom = texture(mask_texture, UV + vec2(0.0, dy)).r;
	float left = texture(mask_texture, UV + vec2(-dx, 0.0)).r;
	float right = texture(mask_texture, UV + vec2(dx, 0.0)).r;
	float top_left = texture(mask_texture, UV + vec2(-dx, -dy)).r;
	float top_right = texture(mask_texture, UV + vec2(dx, -dy)).r;
	float bottom_left = texture(mask_texture, UV + vec2(-dx, dy)).r;
	float bottom_right = texture(mask_texture, UV + vec2(dx, dy)).r;

	// Sobel edge detection
	float edge_h = abs(top_left - bottom_left) + 2.0 * abs(top - bottom) + abs(top_right - bottom_right);
	float edge_v = abs(top_left - top_right) + 2.0 * abs(left - right) + abs(bottom_left - bottom_right);
	float edge = sqrt(edge_h * edge_h + edge_v * edge_v);

	// Output outline with emission
	if (edge > 0.1) {
		COLOR = vec4(outline_color.rgb * emission_energy, outline_color.a);
	} else {
		COLOR = vec4(0.0);
	}
}
