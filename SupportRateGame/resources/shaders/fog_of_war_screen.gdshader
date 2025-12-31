shader_type canvas_item;

// 画面テクスチャ
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// 視野マスク（スクリーンスペースで描画済み）
uniform sampler2D visibility_mask : hint_default_black;

// フォグ設定
uniform float fog_brightness : hint_range(0.0, 1.0) = 0.3;
uniform float blur_radius : hint_range(0.0, 5.0) = 2.0;

// ボックスブラーでエッジをぼかす
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
	// 画面色を取得
	vec4 screen_color = texture(screen_texture, SCREEN_UV);

	// 視野マスクをサンプリング（既にスクリーンスペースで描画されている）
	vec2 tex_size = vec2(textureSize(visibility_mask, 0));
	vec2 texel_size = 1.0 / tex_size;
	float visibility = sample_blurred(visibility_mask, SCREEN_UV, texel_size);

	// 視野内は明るく、視野外は暗く
	float brightness = mix(fog_brightness, 1.0, visibility);
	COLOR = vec4(screen_color.rgb * brightness, 1.0);
}
