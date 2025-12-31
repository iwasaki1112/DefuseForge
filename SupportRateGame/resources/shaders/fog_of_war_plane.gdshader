shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// 視野マスクテクスチャ（ワールドXZにマッピング）
uniform sampler2D visibility_mask : hint_default_black;

// マップ境界
uniform vec2 map_min = vec2(-40.0, -40.0);
uniform vec2 map_max = vec2(40.0, 40.0);

// フォグ設定
uniform vec4 fog_color : source_color = vec4(0.0, 0.0, 0.0, 0.7);
uniform float blur_radius : hint_range(0.0, 5.0) = 2.0;

// フラグメントのワールド座標
varying vec3 world_position;

void vertex() {
	// モデル行列を使ってワールド座標を計算
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// ボックスブラー
float sample_blurred(sampler2D tex, vec2 uv, vec2 texel_size) {
	float sum = 0.0;
	float weight = 0.0;
	int radius = int(blur_radius);

	for (int x = -radius; x <= radius; x++) {
		for (int y = -radius; y <= radius; y++) {
			vec2 offset = vec2(float(x), float(y)) * texel_size;
			vec2 sample_uv = uv + offset;

			if (sample_uv.x >= 0.0 && sample_uv.x <= 1.0 && sample_uv.y >= 0.0 && sample_uv.y <= 1.0) {
				sum += texture(tex, sample_uv).r;
				weight += 1.0;
			}
		}
	}

	return weight > 0.0 ? sum / weight : 0.0;
}

void fragment() {
	// ワールドXZからUVを計算
	vec2 uv = (world_position.xz - map_min) / (map_max - map_min);

	// デフォルトはフォグ
	ALBEDO = fog_color.rgb;

	// 範囲外判定
	bool out_of_bounds = uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0;

	if (out_of_bounds) {
		// 範囲外はフォグで覆う
		ALPHA = fog_color.a;
	} else {
		// テクセルサイズ
		vec2 tex_size = vec2(textureSize(visibility_mask, 0));
		vec2 texel_size = 1.0 / tex_size;

		// 視野マスクをサンプリング
		float visibility = sample_blurred(visibility_mask, uv, texel_size);

		// 視野内は透明、視野外はフォグ
		ALPHA = fog_color.a * (1.0 - visibility);
	}
}
