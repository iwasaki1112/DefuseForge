shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// フォグの色と透明度
uniform vec4 fog_color : source_color = vec4(0.1, 0.15, 0.25, 0.9);

// 可視性テクスチャ（グリッドベース）
uniform sampler2D visibility_texture : filter_linear, repeat_disable;

// 前フレームの可視性テクスチャ（テンポラル補間用）
uniform sampler2D prev_visibility_texture : filter_linear, repeat_disable;

// テンポラル補間の係数（0.0 = 前フレーム、1.0 = 現フレーム）
uniform float temporal_blend : hint_range(0.0, 1.0) = 0.15;

// エッジのシャープさ（0.0 = ソフト、1.0 = ハード）
uniform float edge_sharpness : hint_range(0.0, 1.0) = 0.8;

// マップの設定
uniform vec2 map_min = vec2(-50.0, -50.0);  // マップの最小座標
uniform vec2 map_max = vec2(50.0, 50.0);    // マップの最大座標

void fragment() {
	// ワールド座標を取得
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// ワールド座標をUV座標に変換（0-1の範囲）
	vec2 uv = (world_pos.xz - map_min) / (map_max - map_min);

	// 範囲外チェック - else構文を使用（returnは使えない）
	float fog_alpha;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		fog_alpha = fog_color.a;
	} else {
		// シンプルサンプリング（軽量）
		float current_visibility = texture(visibility_texture, uv).r;
		float prev_visibility = texture(prev_visibility_texture, uv).r;

		// テンポラル補間（スムーズな遷移）
		float visibility = mix(prev_visibility, current_visibility, temporal_blend);

		// エッジシャープ化（edge_sharpness > 0 の場合のみ）
		if (edge_sharpness > 0.01) {
			float edge_width = max(0.05, 0.4 * (1.0 - edge_sharpness));
			float sharp_visibility = smoothstep(0.5 - edge_width, 0.5 + edge_width, visibility);
			visibility = mix(visibility, sharp_visibility, edge_sharpness);
		}

		// 可視性に基づいてフォグの透明度を計算
		fog_alpha = fog_color.a * (1.0 - visibility);
	}

	ALBEDO = fog_color.rgb;
	ALPHA = fog_alpha;
}
