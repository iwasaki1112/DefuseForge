shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// 煙の色と全体アルファ
uniform vec4 smoke_color : source_color = vec4(0.92, 0.92, 0.92, 0.6);
// ライフサイクル制御用アルファ乗数（GDScriptから更新）
uniform float smoke_alpha_multiplier : hint_range(0.0, 1.0) = 1.0;
// レイヤーごとのノイズオフセット（レイヤー間で異なるパターンを生成）
uniform vec2 layer_noise_offset = vec2(0.0, 0.0);

varying vec3 local_pos;
varying float vertex_alpha;

// Gradient noise
vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(dot(hash22(i), f),
		    dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
		mix(dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
		    dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}

// FBM（オクターブ数を引数で制御）
float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 2; i++) {
		v += a * noise(p);
		p = rot * p * 2.0;
		a *= 0.5;
	}
	return v;
}

float fbm4(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = rot * p * 2.0;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	local_pos = VERTEX;
	vertex_alpha = COLOR.a;
}

void fragment() {
	// 大きなパフ形状（低周波・2オクターブ）→ モクモクの塊
	vec2 uv_puff = local_pos.xz * 0.2 + vec2(TIME * 0.06, TIME * 0.04) + layer_noise_offset;
	float puffs = fbm2(uv_puff);

	// 細かいディテール（高周波・4オクターブ）→ 煙の質感
	vec2 uv_detail = local_pos.xz * 0.5 + vec2(-TIME * 0.03, TIME * 0.05) + layer_noise_offset * 2.0;
	float detail = fbm4(uv_detail);

	// 合成: パフが主、ディテールが副
	float n = puffs * 0.6 + detail * 0.4;
	n = 0.5 + 0.5 * n;

	// コントラスト強調 → パフの境界をくっきり（モクモク感の鍵）
	n = smoothstep(0.25, 0.7, n);

	// 頂点アルファ × ノイズ × ライフサイクル
	float alpha = smoke_color.a * n * vertex_alpha * smoke_alpha_multiplier;

	if (alpha < 0.02) {
		discard;
	}

	ALBEDO = smoke_color.rgb;
	ALPHA = alpha;
}
