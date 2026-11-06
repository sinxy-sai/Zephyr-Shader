#version 120
uniform sampler2D gtexture;
varying vec2 zephyrTexCoord;
varying vec4 zephyrVertexColor;
varying vec3 zephyrNormal;
/* DRAWBUFFERS:012 */

void main() {
    vec4 texel = texture2D(gtexture, zephyrTexCoord) * zephyrVertexColor;
    if (texel.a < 0.1) discard;
    gl_FragData[0] = vec4(texel.rgb, 1.0);
    gl_FragData[1] = vec4(zephyrNormal * 0.5 + 0.5, 1.0);
    gl_FragData[2] = vec4(1.0, 0.0, 0.0, 1.0);
}


