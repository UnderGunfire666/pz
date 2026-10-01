shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

// Red stores persistent exploration. Linear multi-sampling softens the visual
// edge while the underlying explored-tile data remains exact.
uniform sampler2D exploration_mask : source_color, filter_linear;
// The current FOV changes often, so it is a texture update rather than a
// rebuilt world-sized mesh.  Exploration remains independent and persistent.
uniform sampler2D visibility_mask : source_color, filter_linear;
uniform vec2 texel_size = vec2(0.004, 0.004);
uniform vec4 memory_color : source_color = vec4(0.055, 0.08, 0.12, 0.22);


float sampled_exploration(vec2 uv) {
	float mask = 0.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			mask += texture(exploration_mask, uv + vec2(float(x), float(y)) * texel_size).r;
		}
	}
	return mask / 25.0;
}


void fragment() {
	float currently_visible = texture(visibility_mask, UV).r;
	float explored = smoothstep(0.12, 0.88, sampled_exploration(UV));
	ALBEDO = mix(vec3(0.0), memory_color.rgb, explored);
	ALPHA = mix(1.0, memory_color.a, explored) * (1.0 - step(0.5, currently_visible));
}
