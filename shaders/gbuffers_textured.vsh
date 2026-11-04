#version 400 compatibility
out vec2 uv;
out vec2 lightmap_coord;

void main() {
	uv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lightmap_coord = gl_MultiTexCoord1.xy / 240.0;
	gl_Position = ftransform();
}
