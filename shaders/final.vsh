#version 120
varying vec2 zephyrTexCoord;
void main() {
    zephyrTexCoord = gl_MultiTexCoord0.st;
    gl_Position = ftransform();
}
