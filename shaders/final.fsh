#version 400 compatibility

#include "/settings.glsl"
in vec2 uv;

uniform sampler2D colortex0;

#include "/include/zephyr/math.glsl"

void main() {
	vec3 c = texture(colortex0, uv).rgb;
	c = zephyr_srgb_encode(c);
	c = zephyr_dither_8bit(c, gl_FragCoord.xy);
	gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}

#include "/include/buffers.glsl"