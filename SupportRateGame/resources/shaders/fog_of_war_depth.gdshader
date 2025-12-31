shader_type canvas_item;

// 画面テクスチャ
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// 深度テクスチャ - 各ピクセルの深度情報
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
// 視野マスクテクスチャ（ワールドXZ平面にマッピング）
uniform sampler2D visibility_texture : hint_default_black;

// カメラ行列（GDScriptから設定）
uniform mat4 inv_projection_matrix;
uniform mat4 inv_view_matrix;

// マップ境界（ワールド座標）
uniform vec2 map_min = vec2(-50.0, -50.0);
uniform vec2 map_max = vec2(50.0, 50.0);

// フォグ設定
uniform float fog_brightness : hint_range(0.0, 1.0) = 0.3;
uniform float blur_radius : hint_range(0.0, 5.0) = 2.0;

// 深度からワールド座標を復元
vec3 depth_to_world_position(vec2 screen_uv, float depth) {
	// スクリーンUVをNDC（-1〜1）に変換
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth);

	// NDCからビュー空間に逆投影
	vec4 view_pos = inv_projection_matrix * vec4(ndc, 1.0);
	view_pos /= view_pos.w;

	// ビュー空間からワールド空間に変換
	vec4 world_pos = inv_view_matrix * view_pos;

	return world_pos.xyz;
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

			if (sample_uv.x >= 0.0 && sample_uv.x <= 1.0 && sample_uv.y >= 0.0 && sample_uv.y <= 1.0) {
				sum += texture(tex, sample_uv).r;
				weight += 1.0;
			}
		}
	}

	return weight > 0.0 ? sum / weight : 0.0;
}

void fragment() {
	// 画面色をサンプリング
	vec4 screen_color = texture(screen_texture, SCREEN_UV);

	// 深度をサンプリング
	float depth = texture(depth_texture, SCREEN_UV).r;

	// 空（深度=1.0）の場合は元の色をそのまま使用
	if (depth >= 0.9999) {
		COLOR = screen_color;
		return;
	}

	// 深度からワールド座標を復元
	vec3 world_pos = depth_to_world_position(SCREEN_UV, depth);

	// ワールドXZを視野テクスチャUVに変換
	vec2 vis_uv = (world_pos.xz - map_min) / (map_max - map_min);

	// 視野をサンプリング（範囲外はデフォルトで暗い）
	float visibility = 0.0;
	if (vis_uv.x >= 0.0 && vis_uv.x <= 1.0 && vis_uv.y >= 0.0 && vis_uv.y <= 1.0) {
		vec2 tex_size = vec2(textureSize(visibility_texture, 0));
		vec2 texel_size = 1.0 / tex_size;
		visibility = sample_blurred(visibility_texture, vis_uv, texel_size);
	}

	// フォグ適用
	float brightness = mix(fog_brightness, 1.0, visibility);
	COLOR = vec4(screen_color.rgb * brightness, 1.0);
}
