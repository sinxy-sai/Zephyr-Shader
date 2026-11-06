#version 120
varying vec4 zephyrVertexColor;
varying vec3 zephyrNormal;
/* DRAWBUFFERS:012 */

void main() {
    gl_FragData[0] = zephyrVertexColor;
    gl_FragData[1] = vec4(zephyrNormal * 0.5 + 0.5, 1.0);
    gl_FragData[2] = vec4(1.0, 0.0, 0.0, 1.0);
}


