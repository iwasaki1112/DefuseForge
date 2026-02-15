shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// billboard_particles を使わず手動ビルボードでワールド座標を正確に計算

// スモークの色（元のStandardMaterial3Dのalbedo_colorを再現）
uniform vec4 smoke_color : source_color = vec4(0.85, 0.85, 0.85, 0.8);
// 煙パフテクスチャ（透過PNGで四角さを消す）
uniform sampler2D smoke_texture : filter_linear, hint_default_white;
// ライフサイクル制御（GDScriptから更新）
uniform float smoke_alpha_multiplier : hint_range(0.0, 1.0) = 1.0;
// 壁距離マップ（1D: 64ピクセル、R=正規化距離 0〜1）
uniform sampler2D radius_map : filter_linear, repeat_enable;
// スモーク中心のワールド座標
uniform vec3 smoke_center = vec3(0.0);
// スモーク最大半径
uniform float max_radius = 5.0;
// 現在の有効半径（展開/消滅アニメーション用）
uniform float current_radius = 0.0;
// クリップ境界でのフェード幅（メートル）
uniform float clip_fade_width = 0.5;

// FoW可視性テクスチャ（パーティクル単位のFoWクリッピング用）
uniform sampler2D fow_visibility_texture : filter_linear, hint_default_white;
uniform vec2 fow_map_min = vec2(-20.0, -20.0);
uniform vec2 fow_map_max = vec2(20.0, 20.0);
uniform float fow_enabled = 0.0;

varying vec3 v_world_pos;

void vertex() {
	// パーティクル中心のワールド座標（MODEL_MATRIXの平行移動成分）
	vec3 particle_center = MODEL_MATRIX[3].xyz;

	// パーティクルスケール（MODEL_MATRIXの各軸ベクトル長 = スケール値）
	float scale_x = length(MODEL_MATRIX[0].xyz);
	float scale_y = length(MODEL_MATRIX[1].xyz);

	// カメラの右方向と上方向でビルボード向きを手動計算
	vec3 cam_right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 cam_up = normalize(INV_VIEW_MATRIX[1].xyz);

	// ビルボード頂点のワールド座標
	// VERTEX.xy = QuadMeshのローカル座標（-0.5〜0.5）
	v_world_pos = particle_center
		+ cam_right * VERTEX.x * scale_x
		+ cam_up * VERTEX.y * scale_y;

	// クリップ空間に直接変換（手動ビルボードなのでPOSITIONを上書き）
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(v_world_pos, 1.0);
}

void fragment() {
	// XZ平面上のスモーク中心からのオフセット
	vec2 offset = v_world_pos.xz - smoke_center.xz;
	float dist = length(offset);

	// 方向角を計算（+X=0, +Z=PI/2 → レイキャストと同じ座標系）
	float angle = atan(offset.y, offset.x);
	// fract(angle / TAU) で 0〜1 にラップ（レイキャストのピクセル順と一致）
	float uv_x = fract(angle / (2.0 * 3.14159265));

	// 壁距離を取得（正規化値 × max_radius）
	float wall_dist = texture(radius_map, vec2(uv_x, 0.5)).r * max_radius;

	// 有効クリップ距離 = min(壁距離, 現在の展開半径)
	float clip_dist = min(wall_dist, current_radius);

	// ソフトクリップ（壁際でなめらかにフェードアウト）
	float clip_alpha = 1.0 - smoothstep(clip_dist - clip_fade_width, clip_dist, dist);

	if (clip_alpha < 0.01) {
		discard;
	}

	// 地面近くのフラグメントをフェードアウト（地面の灰色円を防ぐ）
	float height_above_ground = v_world_pos.y - smoke_center.y;
	float height_alpha = smoothstep(0.0, 0.5, height_above_ground);

	// FoW可視性チェック（パーティクル単位: 視界外の煙フラグメントを消す）
	float fow_alpha = 1.0;
	if (fow_enabled > 0.5) {
		vec2 fow_uv = (v_world_pos.xz - fow_map_min) / (fow_map_max - fow_map_min);
		if (fow_uv.x >= 0.0 && fow_uv.x <= 1.0 && fow_uv.y >= 0.0 && fow_uv.y <= 1.0) {
			// smoothstep閾値をfow.gdshaderと統一（境界が一致する）
			float fow_visibility = texture(fow_visibility_texture, fow_uv).r;
			fow_alpha = smoothstep(0.1, 0.3, fow_visibility);
		} else {
			fow_alpha = 0.0;
		}
	}

	// テクスチャサンプリング（UVはQuadMeshの0〜1座標）
	vec4 tex = texture(smoke_texture, UV);
	float tex_alpha = tex.a;

	// 最終アルファ = テクスチャα × 煙色α × パーティクル寿命α × ライフサイクル × 壁クリップ × 高さフェード × FoW
	float alpha = tex_alpha * smoke_color.a * COLOR.a * smoke_alpha_multiplier * clip_alpha * height_alpha * fow_alpha;

	if (alpha < 0.02) {
		discard;
	}

	ALBEDO = smoke_color.rgb * tex.rgb * COLOR.rgb;
	ALPHA = alpha;
}
