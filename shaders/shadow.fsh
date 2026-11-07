#version 330 compatibility

// Depth-only shadow pass. shadowcolor0 is reserved for coloured transmission
// in a later milestone (see docs/dev/plan/02-pipeline.md).
uniform sampler2D gtexture;

in vec2 texCoord;
in vec4 vertexColor;

void main() {
    vec4 c = texture(gtexture, texCoord) * vertexColor;
    if (c.a < 0.10) discard;
}
