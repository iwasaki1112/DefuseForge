shader_type spatial;

// 元のマテリアル設定
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;

// FoW用
uniform sampler2D visibility_texture : hint_default_black;  // デフォルトは黒（見えない）
uniform vec2 map_min = vec2(-7.5, -7.5);
uniform vec2 map_max = vec2(7.5, 7.5);
uniform float fog_darkness : hint_range(0.0, 1.0) = 0.15;  // 見えない部分の明るさ
uniform bool debug_mode = false;  // デバッグモード
uniform float wall_offset : hint_range(0.0, 2.0) = 0.5;  // 壁の厚みオフセット

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// 法線をワールド座標系に変換
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// 元のテクスチャカラー
	vec4 tex_color = texture(albedo_texture, UV);
	vec3 base_color = albedo_color.rgb * tex_color.rgb;

	// 壁の法線方向にオフセットして、壁の表面座標を取得
	// 法線のXZ成分を使って、壁の厚みを考慮
	vec2 normal_xz = normalize(vec2(world_normal.x, world_normal.z) + vec2(0.001));
	vec2 surface_pos = world_position.xz + normal_xz * wall_offset;

	// ワールド座標からUV計算（XZ平面）
	vec2 uv = (surface_pos - map_min) / (map_max - map_min);
	uv = clamp(uv, vec2(0.0), vec2(1.0));

	// 視界テクスチャから明るさを取得
	float visibility = texture(visibility_texture, uv).r;

	// Clamp to prevent ADD blend artifacts at light overlaps
	visibility = min(visibility, 1.0);

	// Smooth threshold to reduce seams at light overlaps
	visibility = smoothstep(0.1, 0.3, visibility);

	// デバッグモード: visibility値を色で表示
	if (debug_mode) {
		// 赤=visibility値（明るいほど見える）、緑=UV.x、青=UV.y
		ALBEDO = vec3(visibility, uv.x, uv.y);
	} else {
		// 視界外は暗くする
		float brightness = mix(fog_darkness, 1.0, visibility);
		ALBEDO = base_color * brightness;
	}
}
