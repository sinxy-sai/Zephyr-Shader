#version 120
uniform sampler2D colortex0;
varying vec2 zephyrTexCoord;
/* DRAWBUFFERS:0 */
void main() {
    vec3 color = texture2D(colortex0, zephyrTexCoord).rgb;
    color = color / (1.0 + color);
    color = pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));
    gl_FragData[0] = vec4(color, 1.0);
}
