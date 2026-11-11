#version 330 compatibility

#include "/lib/config.glsl"
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

/* RENDERTARGETS: 0,1,2,9 */
layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outData;
layout(location = 2) out vec4 outNormal;
layout(location = 3) out vec4 outVelocity;

in vec2 vWaveVelocity;

#include "/lib/gbuffer_body.glsl"

in vec4 vTexCoordAM;

uniform sampler2D gtexture;

in vec2 vTexCoord;
in vec2 vLightCoord;
in vec4 vColor;
in vec3 vNormal;
flat in float zBlockId;

void main() {
    outVelocity = vec4(vWaveVelocity, 0.0, 1.0);
    vec2 zUv = zephyr_parallaxUV(gtexture, vTexCoord, vNormal, vTexCoordAM);
    vec4 c = texture(gtexture, zUv) * vColor;
    // M23: torches / fire / amethyst are cutout geometry and arrive HERE, not
    // in the terrain program. Keep the thin-surface flag only for foliage.
    if (zBlockId > 11999.5 && zBlockId < 12000.5) {
        writeEmissive(c, EMISSIVE_BLOCK_GAIN);
    } else {
        writeSolid(c, vLightCoord, MAT_SOLID, 0.55, zephyr_parallaxNormal(gtexture, zUv, vNormal));
        // M34: colortex2.a means "foliage thin lamina", NOT "any cutout".
        // block.10000..10004 are the vegetation IDs (the same range
        // WAVE_CODE uses). Torches, glass panes, rails, webs and fire must
        // NOT inherit the chlorophyll tint of F26's leaf SSS.
        bool isFoliage = (zBlockId > 9999.5 && zBlockId < 10004.5);
        outNormal.a = isFoliage ? 1.0 : 0.0;
    }
}
