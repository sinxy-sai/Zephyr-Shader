#version 330 compatibility

#include "/lib/config.glsl"
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

/* RENDERTARGETS: 0,1,2,8,9 */
layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outData;
layout(location = 2) out vec4 outNormal;
layout(location = 3) out vec4 outGlass;
layout(location = 4) out vec4 outVelocity;

in vec2 vWaveVelocity;

#include "/lib/gbuffer_body.glsl"

uniform sampler2D gtexture;

in vec2 vTexCoord;
in vec2 vLightCoord;
in vec4 vColor;
in vec3 vNormal;
flat in float zBlockId;

void main() {
    outVelocity = vec4(vWaveVelocity, 0.0, 1.0);
    vec4 c = texture(gtexture, vTexCoord) * vColor;
    // Iris 1.21 sends the WHOLE translucent layer (water, ice, glass, stained
    // glass, honey, slime) through this one program. Only real water (11000)
    // gets MAT_WATER: everything else must not inherit water absorption,
    // Fresnel reflection, wave normals or SSR (composite.fsh / deferred.fsh
    // both gate those on matId in [0.5, 1.5]).
    bool isWater = (zBlockId > 10999.5 && zBlockId < 11000.5);
    float matId = isWater ? MAT_WATER : MAT_TRANSLUCENT;
    float rough = isWater ? 0.06 : 0.18;
    float glassA = isWater ? 0.0
                 : clamp(max(c.a, TRANSLUCENT_MIN_ALPHA), 0.0, 0.95);
    // Real alpha goes to colortex0.a and Iris blends it there; the dedicated
    // glass layer keeps the PURE glass colour plus a rain-proof coverage mask.
    writeBlended(c, vLightCoord, matId, rough, vNormal,
                 isWater ? 0.0 : TRANSLUCENT_MIN_ALPHA);
    // M20: low-chroma panes need explicit density (see settings.glsl).
    float absorb = GLASS_MIN_ABSORB;
    if (zBlockId > 11004.5 && zBlockId < 11005.5) absorb = GLASS_WHITE_ABSORB;
    else if (zBlockId > 11005.5 && zBlockId < 11006.5) absorb = GLASS_BLACK_ABSORB;
    else if (zBlockId > 11006.5 && zBlockId < 11007.5) absorb = GLASS_TINTED_ABSORB;
    outGlass = vec4(zephyr_srgbToLinear(c.rgb) * (1.0 - absorb), glassA);
    // M42: measured on this build - depthtex0 is the WATER SURFACE (22.1 m)
    // and depthtex1 is the SEABED (32.4 m), i.e. the opposite of the usual
    // OptiFine naming. No custom depth is needed here; .b is the marker only.
    if (isWater) outGlass.b = 2.0;
    // M40: keep the surface mostly transparent so colortex0 retains the
    // seabed through the alpha blend (iterationT writes tex.a = 0 for water).
    if (isWater) outAlbedo.a = 0.12;
}
