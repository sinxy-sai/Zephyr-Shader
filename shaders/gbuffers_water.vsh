#version 120
varying vec2 zephyrTexCoord;
varying vec4 zephyrVertexColor;

void main() {
    zephyrTexCoord = gl_MultiTexCoord0.st;
    zephyrVertexColor = gl_Color;
    gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;
}
