shader_type canvas_item;
render_mode unshaded;

// Applied only to the back glow label. The foreground glyph and its crisp
// double outline remain native TextServer draws, avoiding font-atlas bleeding.
uniform vec4 glow_color : source_color = vec4(1.0, 0.55, 0.1, 0.55);
uniform float radius_px : hint_range(0.0, 12.0, 0.25) = 3.0;
uniform float strength : hint_range(0.0, 3.0, 0.05) = 0.8;

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
	float halo = clamp((spread - source.a * 0.35) * strength, 0.0, 1.0);
	COLOR = vec4(glow_color.rgb, halo * glow_color.a * COLOR.a);
}
