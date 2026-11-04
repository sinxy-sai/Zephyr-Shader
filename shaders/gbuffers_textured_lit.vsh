#version 400 compatibility
out vec2 uv;
out vec2 lightmap_coord;
out vec3 normal_world;

uniform mat4 gbufferModelViewInverse;

void main() {
	uv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lightmap_coord = gl_MultiTexCoord1.xy / 240.0;
	normal_world = normalize(mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal));
	gl_Position = ftransform();
}
