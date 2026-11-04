#version 400 compatibility

#include "/settings.glsl"
in vec2 uv;
in vec2 lightmap_coord;

uniform sampler2D gtexture;

/* RENDERTARGETS: 0 */
layout (location = 0) out vec4 color;

void main() {
	vec4 albedo = texture(gtexture, uv);
	if (albedo.a < 0.1) discard;
	color = vec4(albedo.rgb * (0.35 + 0.65 * lightmap_coord.y), albedo.a);
}