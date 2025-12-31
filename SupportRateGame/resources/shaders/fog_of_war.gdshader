shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

// フォグの色と透明度
uniform vec4 fog_color : source_color = vec4(0.0, 0.0, 0.0, 0.7);
// 視野マスクテクスチャ（白=視野内、黒=視野外）
uniform sampler2D visibility_mask : hint_default_white;
// マップの境界（ワールド座標）
uniform vec2 map_min = vec2(-100.0, -100.0);
uniform vec2 map_max = vec2(100.0, 100.0);
// エッジのぼかし半径（ピクセル単位）
uniform float blur_radius : hint_range(0.0, 10.0) = 2.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// ボックスブラーでテクスチャをサンプリング
float sample_blurred(sampler2D tex, vec2 uv, vec2 texel_size) {
	float sum = 0.0;
	float weight = 0.0;
	int radius = int(blur_radius);

	for (int x = -radius; x <= radius; x++) {
		for (int y = -radius; y <= radius; y++) {
			vec2 offset = vec2(float(x), float(y)) * texel_size;
			vec2 sample_uv = uv + offset;

			// UV範囲内のみサンプリング
			if (sample_uv.x >= 0.0 && sample_uv.x <= 1.0 && sample_uv.y >= 0.0 && sample_uv.y <= 1.0) {
				sum += texture(tex, sample_uv).r;
				weight += 1.0;
			}
		}
	}

	return weight > 0.0 ? sum / weight : 0.0;
}

void fragment() {
	// ワールド座標をUV座標に変換
	vec2 uv = (world_position.xz - map_min) / (map_max - map_min);

	// デフォルトはフォグ
	ALBEDO = fog_color.rgb;

	// UV範囲外はフォグで覆う
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		ALPHA = fog_color.a;
	} else {
		// テクセルサイズを計算
		vec2 tex_size = vec2(textureSize(visibility_mask, 0));
		vec2 texel_size = 1.0 / tex_size;

		// ぼかしを適用した視野マスクを読み取り
		float visibility = sample_blurred(visibility_mask, uv, texel_size);

		// 視野内は透明、視野外はフォグ
		ALPHA = fog_color.a * (1.0 - visibility);
	}
}
