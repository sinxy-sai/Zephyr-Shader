#version 400 compatibility

#include "/settings.glsl"
in vec2 uv;
in vec2 lightmap_coord;
in vec3 normal_world;
in vec3 position_world;

#include "/include/zephyr/lighting.glsl"
#include "/include/zephyr/math.glsl"

/* RENDERTARGETS: 0 */
layout (location = 0) out vec4 color;

uniform float frameTimeCounter;
uniform vec3 cameraPosition;

void main() {
	vec3 n = normalize(normal_world);

	// own waves: two directional sines
	float w1 = sin(dot(position_world.xz, vec2(0.9, 0.4)) * 1.2 + frameTimeCounter * 1.1);
	float w2 = sin(dot(position_world.xz, vec2(-0.5, 0.8)) * 2.1 + frameTimeCounter * 1.7);
	n = normalize(n + vec3(w1, 0.0, w2) * 0.06);

	vec3 lit = zephyr_light(vec3(0.04, 0.16, 0.22), n, lightmap_coord);
	vec3 view_dir = normalize(cameraPosition - position_world);

	// fresnel + sky-ish reflection tint
	float fresnel = pow(1.0 - clamp(abs(dot(n, view_dir)), 0.0, 1.0), 4.0);
	vec3 reflection = zephyr_sun_color(normalize(mat3(gbufferModelViewInverse) * sunPosition).y) * 0.20 * fresnel;

	color = vec4(lit + reflection, 0.92);
}