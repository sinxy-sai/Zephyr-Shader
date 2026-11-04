#version 400 compatibility

#include "/settings.glsl"
in vec2 uv;

#include "/include/zephyr/sky.glsl"

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform float rainStrength;

/* RENDERTARGETS: 0 */
layout (location = 0) out vec4 color;

void main() {
	vec4 view_pos = gbufferProjectionInverse * vec4(vec3(uv, 1.0) * 2.0 - 1.0, 1.0);
	vec3 dir_view = normalize(view_pos.xyz / view_pos.w);
	vec3 dir_world = normalize(mat3(gbufferModelViewInverse) * dir_view);
	vec3 sun_dir = normalize(mat3(gbufferModelViewInverse) * sunPosition);

	color = vec4(zephyr_sky_radiance(dir_world, sun_dir, rainStrength), 1.0);
}