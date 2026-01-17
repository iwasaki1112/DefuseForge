shader_type spatial;
render_mode unshaded;

// Simple mask shader - renders object as solid white
void fragment() {
	ALBEDO = vec3(1.0);
}
