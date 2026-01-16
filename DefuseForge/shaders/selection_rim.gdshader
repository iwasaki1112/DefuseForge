shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_back;

// Rim light selection effect - glows on silhouette edges only
uniform vec4 rim_color : source_color = vec4(0.0, 1.0, 0.8, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 2.0;
uniform float rim_intensity : hint_range(0.0, 10.0) = 3.0;
uniform float rim_threshold : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	// Calculate rim based on view angle
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	rim = pow(rim, rim_power);

	// Only show rim above threshold (outer edges)
	if (rim < rim_threshold) {
		discard;
	}

	ALBEDO = rim_color.rgb;
	ALPHA = rim * rim_color.a;
	EMISSION = rim_color.rgb * rim_intensity * rim;
}
