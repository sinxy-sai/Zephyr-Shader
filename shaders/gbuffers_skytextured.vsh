#version 330 compatibility

out vec2 vTexCoord;
out vec2 vLightCoord;
out vec4 vColor;
out vec3 vNormal;

void main() {
    gl_Position  = ftransform();
    vTexCoord    = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLightCoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor       = gl_Color;
    vNormal      = normalize(gl_NormalMatrix * gl_Normal);
}
