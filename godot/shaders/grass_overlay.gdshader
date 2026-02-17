shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform sampler2D grass_texture : source_color, filter_linear, repeat_disable;

void fragment() {
	vec4 tex = texture(grass_texture, UV);
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
}
