shader_type spatial;

// 元のマテリアル設定
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;

// FoW用
uniform sampler2D visibility_texture : hint_default_black;  // デフォルトは黒（見えない）
uniform vec2 map_min = vec2(-7.5, -7.5);
uniform vec2 map_max = vec2(7.5, 7.5);
uniform float fog_darkness : hint_range(0.0, 1.0) = 0.15;  // 見えない部分の明るさ

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 元のテクスチャカラー
	vec4 tex_color = texture(albedo_texture, UV);
	vec3 base_color = albedo_color.rgb * tex_color.rgb;

	// ワールド座標からUV計算（XZ平面）
	vec2 uv = (world_position.xz - map_min) / (map_max - map_min);
	uv = clamp(uv, vec2(0.0), vec2(1.0));

	// 視界テクスチャから明るさを取得
	float visibility = texture(visibility_texture, uv).r;

	// 視界外は暗くする
	float brightness = mix(fog_darkness, 1.0, visibility);

	ALBEDO = base_color * brightness;
}
