#version 120
varying vec4 zephyrVertexColor;
/* DRAWBUFFERS:012 */

void main() {
    vec4 color = zephyrVertexColor;
    if (color.a < 0.1) discard;
    gl_FragData[0] = color;
    gl_FragData[1] = vec4(0.5, 0.5, 1.0, 1.0);
    gl_FragData[2] = vec4(1.0, 0.0, 0.0, 1.0);
}
