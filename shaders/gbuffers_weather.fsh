#version 400 compatibility

#include "/settings.glsl"
in vec2 uv;

uniform sampler2D gtexture;
uniform vec3 sunPosition;
uniform mat4 gbufferModelViewInverse;
uniform float rainStrength;

#include "/include/zephyr/math.glsl"

/* RENDERTARGETS: 0 */
layout (location = 0) out vec4 color;

void main() {
	vec4 tex = texture(gtexture, uv);
	if (tex.a < 0.1) discard;

	float elev = normalize(mat3(gbufferModelViewInverse) * sunPosition).y;
	vec3 tint = mix(vec3(0.72, 0.78, 0.88), vec3(1.0, 0.96, 0.90), smoothstep(-0.1, 0.3, elev));

	color = vec4(tint * tex.rgb, tex.a * 0.35);
}