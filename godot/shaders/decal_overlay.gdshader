shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D decal_texture : source_color, filter_linear, repeat_disable;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float alpha_multiplier : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 tex = texture(decal_texture, UV);
	ALBEDO = tex.rgb;
	ALPHA = tex.a * alpha_multiplier;
	ROUGHNESS = roughness;
}
