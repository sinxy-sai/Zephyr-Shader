#version 400 compatibility

#include "/settings.glsl"
in vec2 uv;
in vec2 lightmap_coord;
in vec3 normal_world;

uniform sampler2D gtexture;

#include "/include/zephyr/lighting.glsl"

/* RENDERTARGETS: 0 */
layout (location = 0) out vec4 color;

void main() {
	vec4 albedo = texture(gtexture, uv);
	if (albedo.a < 0.1) discard;
	color = vec4(zephyr_light(albedo.rgb, normalize(normal_world), lightmap_coord), albedo.a);
}