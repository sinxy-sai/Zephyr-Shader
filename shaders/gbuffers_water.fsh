#version 330 compatibility

#include "/lib/config.glsl"
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

/* RENDERTARGETS: 0,1,2 */
layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outData;
layout(location = 2) out vec4 outNormal;

#include "/lib/gbuffer_body.glsl"

uniform sampler2D gtexture;

in vec2 vTexCoord;
in vec2 vLightCoord;
in vec4 vColor;
in vec3 vNormal;
flat in float zBlockId;

void main() {
    vec4 c = texture(gtexture, vTexCoord) * vColor;
    // Iris 1.21 sends the WHOLE translucent layer (water, ice, glass, stained
    // glass, honey, slime) through this one program. Only real water (11000)
    // gets MAT_WATER: everything else must not inherit water absorption,
    // Fresnel reflection, wave normals or SSR (composite.fsh / deferred.fsh
    // both gate those on matId in [0.5, 1.5]).
    bool isWater = (zBlockId > 10999.5 && zBlockId < 11000.5);
    float matId = isWater ? MAT_WATER : MAT_TRANSLUCENT;
    float rough = isWater ? 0.06 : 0.18;
    writeTranslucent(c, vLightCoord, matId, rough, vNormal);
}
