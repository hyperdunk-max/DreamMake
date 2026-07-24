shader_type canvas_item;

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV) * COLOR;
	vec3 flash_color = mix(source.rgb, vec3(1.0), flash_amount);
	COLOR = vec4(flash_color, source.a);
}
