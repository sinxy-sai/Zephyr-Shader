#version 120
uniform sampler2D colortex0;
varying vec2 zephyrTexCoord;
/* DRAWBUFFERS:0 */
void main() {
    vec3 color = texture2D(colortex0, zephyrTexCoord).rgb;
    // S0 receives the default framebuffer color path. Keep this pass neutral
    // until the HDR exposure contract is established in the deferred stage.
    gl_FragData[0] = vec4(clamp(color, 0.0, 1.0), 1.0);
}
