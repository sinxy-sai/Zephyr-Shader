#version 120
varying vec2 zephyrTexCoord;
varying vec4 zephyrVertexColor;
varying vec3 zephyrNormal;

void main() {
    zephyrTexCoord = gl_MultiTexCoord0.st;
    zephyrVertexColor = gl_Color;
    zephyrNormal = normalize(gl_NormalMatrix * gl_Normal);
    gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;
}


