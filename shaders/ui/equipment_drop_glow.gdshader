shader_type canvas_item;
render_mode unshaded;

uniform vec4 glow_color : source_color = vec4(0.35, 0.67, 1.0, 0.7);
uniform float radius_px : hint_range(0.0, 10.0, 0.25) = 3.0;
uniform float strength : hint_range(0.0, 3.0, 0.05) = 1.0;
uniform float pulse_speed : hint_range(0.0, 8.0, 0.1) = 2.4;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec2 step_uv = TEXTURE_PIXEL_SIZE * radius_px;
	float spread = source.a;
	spread = max(spread, texture(TEXTURE, UV + vec2( step_uv.x, 0.0)).a);
	spread = max(spread, texture(TEXTURE, UV + vec2(-step_uv.x, 0.0)).a);
	spread = max(spread, texture(TEXTURE, UV + vec2(0.0,  step_uv.y)).a);
	spread = max(spread, texture(TEXTURE, UV + vec2(0.0, -step_uv.y)).a);
	spread = max(spread, texture(TEXTURE, UV + vec2( step_uv.x,  step_uv.y) * 0.7071).a);
	spread = max(spread, texture(TEXTURE, UV + vec2(-step_uv.x,  step_uv.y) * 0.7071).a);
	spread = max(spread, texture(TEXTURE, UV + vec2( step_uv.x, -step_uv.y) * 0.7071).a);
	spread = max(spread, texture(TEXTURE, UV + vec2(-step_uv.x, -step_uv.y) * 0.7071).a);
	float pulse = 0.78 + 0.22 * sin(TIME * pulse_speed);
	float halo = clamp((spread - source.a) * strength * pulse, 0.0, 1.0);
	vec3 rgb = source.rgb + glow_color.rgb * halo;
	COLOR = vec4(rgb, max(source.a, halo * glow_color.a)) * COLOR;
}
