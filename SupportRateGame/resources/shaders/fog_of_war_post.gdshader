shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled;

// スクリーンテクスチャと深度テクスチャ
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

// 視野マスクテクスチャ（ワールドXZにマッピング）
uniform sampler2D visibility_mask : hint_default_black;

// マップ境界（ワールド座標）
uniform vec2 map_min = vec2(-40.0, -40.0);
uniform vec2 map_max = vec2(40.0, 40.0);

// フォグ設定
uniform float fog_brightness : hint_range(0.0, 1.0) = 0.3;
uniform float blur_radius : hint_range(0.0, 5.0) = 2.0;

// 深度から線形深度を取得
float get_linear_depth(float log_depth, vec2 screen_uv, mat4 inv_proj_mat) {
	vec4 ndc = vec4(screen_uv * 2.0 - 1.0, log_depth, 1.0);
	vec4 upos = inv_proj_mat * ndc;
	vec3 pixel_pos = upos.xyz / upos.w;
	return -pixel_pos.z;
}

// 深度からワールド座標を復元
vec3 get_world_position(vec2 screen_uv, float depth, mat4 inv_view_mat, mat4 inv_proj_mat) {
	vec4 ndc = vec4(screen_uv * 2.0 - 1.0, depth, 1.0);
	vec4 view_pos = inv_proj_mat * ndc;
	view_pos.xyz /= view_pos.w;
	vec4 world_pos = inv_view_mat * vec4(view_pos.xyz, 1.0);
	return world_pos.xyz;
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

void vertex() {
	// フルスクリーンクワッドとして配置
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	// スクリーン色を取得
	vec4 screen_color = textureLod(screen_texture, SCREEN_UV, 0.0);

	// 深度を取得
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;

	// 空（深度が最大）の場合はそのまま表示
	if (depth >= 0.9999) {
		ALBEDO = screen_color.rgb;
		ALPHA = 1.0;
	} else {
		// 深度からワールド座標を復元
		vec3 world_pos = get_world_position(SCREEN_UV, depth, INV_VIEW_MATRIX, INV_PROJECTION_MATRIX);

		// ワールドXZを視野テクスチャUVに変換
		vec2 vis_uv = (world_pos.xz - map_min) / (map_max - map_min);

		// 視野をサンプリング
		float visibility = 0.0;
		if (vis_uv.x >= 0.0 && vis_uv.x <= 1.0 && vis_uv.y >= 0.0 && vis_uv.y <= 1.0) {
			vec2 tex_size = vec2(textureSize(visibility_mask, 0));
			vec2 texel_size = 1.0 / tex_size;
			visibility = sample_blurred(visibility_mask, vis_uv, texel_size);
		}

		// フォグ適用（視野内は明るく、視野外は暗く）
		float brightness = mix(fog_brightness, 1.0, visibility);
		ALBEDO = screen_color.rgb * brightness;
		ALPHA = 1.0;
	}
}
