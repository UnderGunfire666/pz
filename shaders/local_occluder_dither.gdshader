shader_type spatial;
render_mode cull_disabled;

uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, hint_default_white;
uniform vec4 reveal_rect = vec4(0.0);

void fragment() {
	vec4 color = base_color * texture(base_texture, UV);
	ALBEDO = color.rgb;
	ROUGHNESS = 0.9;
	vec2 radius = max(reveal_rect.zw * 0.7, vec2(0.0001));
	float local_mask = 1.0 - smoothstep(0.8, 1.0, length((SCREEN_UV - reveal_rect.xy) / radius));
	float noise = fract(52.9829189 * fract(dot(floor(FRAGCOORD.xy), vec2(0.06711056, 0.00583715))));
	if (noise < local_mask * 0.9 || color.a < 0.1) {
		discard;
	}
}
