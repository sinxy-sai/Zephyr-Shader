#version 330 compatibility

#include "/lib/config.glsl"
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

in vec2 texCoord;

uniform sampler2D colortex3;
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex8;   // M17: dedicated stained-glass layer
uniform sampler2D depthtex0;

/* RENDERTARGETS: 4 */
layout(location = 0) out vec4 outColor;

vec3 zephyr_worldRay(vec2 uv) {
    vec4 clip = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
    float w = abs(clip.w) < 1e-5 ? 1e-5 : clip.w;
    return normalize(mat3(gbufferModelViewInverse) * normalize(clip.xyz / w));
}

// Height-resolved cloud density. A storm swaps in a lower, thicker deck with a
// broader weather map, so the overcast reads as a continuous ceiling rather
// than the same cumulus field with a lower coverage threshold.
float zephyr_cloudDensity(vec3 p) {
    float storm = zephyr_storm();
    float freq = mix(0.0032, STORM_CLOUD_FREQ, storm);
    vec2 uv = p.xz * freq
            + vec2(frameTimeCounter * 0.0060, frameTimeCounter * 0.0022);
    float base = zephyr_fbm(uv);

    float lowFreq = zephyr_valueNoise(uv * 0.42 + vec2(11.3, 5.7));
    float detail = zephyr_valueNoise(uv * 3.10 + vec2(19.7, 3.1));
    base = mix(base, max(base * 0.72, lowFreq), storm * 0.55);
    base = mix(base, base * (0.78 + 0.34 * detail), storm * 0.45);

    float alt = zephyr_cloudBase();
    float thick = zephyr_cloudThickness();
    float h = clamp((p.y - alt) / thick, 0.0, 1.0);
    float shape = smoothstep(0.0, mix(0.22, 0.10, storm), h)
                * (1.0 - smoothstep(mix(0.58, 0.78, storm), 1.0, h));

    float coverage = mix(CLOUD_COVERAGE, STORM_CLOUD_COVERAGE, storm);
    float band = mix(0.13, 0.22, storm);
    float cover = smoothstep(coverage, coverage + band, base);
    return cover * shape * mix(CLOUD_DENSITY, STORM_CLOUD_DENSITY, storm);
}

// Beer-Lambert transmittance towards the sun; this is the cloud self-shadow.
float zephyr_cloudSunTransmittance(vec3 p, vec3 L) {
    float optical = 0.0;
    float stepL = zephyr_cloudThickness() * 0.45;
    for (int i = 1; i <= CLOUD_SUN_STEPS; ++i) {
        optical += zephyr_cloudDensity(p + L * (float(i) * stepL));
    }
    return exp(-optical * mix(1.50, STORM_CLOUD_SUN_ABSORB, zephyr_storm()));
}

void main() {
    float depth = texture(depthtex0, texCoord).r;
    float dist = depth < 0.9999 ? zephyr_linearDepth(depth) : 1.0e6;
    vec3 color = max(texture(colortex3, texCoord).rgb, vec3(0.0));

    vec3 rd = zephyr_worldRay(texCoord);
    vec3 sunDirWorld = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
    float dayAmount = zephyr_dayAmount(sunDirWorld.y);
    float rain = clamp(rainStrength, 0.0, 1.0);
    float mu = max(dot(rd, sunDirWorld), 0.0);

#if SSR_ENABLED
    // Screen-space reflections for water AND rain puddles. This runs here (not
    // in deferred) because deferred writes colortex3 and cannot sample it back.
    float matId = texture(colortex1, texCoord).a;
    if (depth < 0.9999) {
        vec4 vClip = gbufferProjectionInverse * vec4(texCoord * 2.0 - 1.0,
                                                     depth * 2.0 - 1.0, 1.0);
        float vw = abs(vClip.w) < 1e-5 ? 1e-5 : vClip.w;
        vec3 viewPos = vClip.xyz / vw;
        vec3 V = normalize(-viewPos);
        vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;

        bool isWater = (matId > 0.5 && matId < 1.5);
        vec3 N;
        float puddle = 0.0;
        vec2 rippleUv = vec2(0.0);

        if (isWater) {
            float waveAmp = WAVE_AMPLITUDE * (1.0 + rain * 0.90);
            float wx = sin(worldPos.x * 0.85 + frameTimeCounter * 1.25)
                     * cos(worldPos.z * 0.62 - frameTimeCounter * 0.85);
            float wz = sin(worldPos.z * 1.05 - frameTimeCounter * 1.45)
                     * cos(worldPos.x * 0.55 + frameTimeCounter * 0.75);
            N = normalize(mat3(gbufferModelView)
                         * normalize(vec3(wx * waveAmp, 1.0, wz * waveAmp)));
        } else {
            vec3 Nv = zephyr_decodeNormal(texture(colortex2, texCoord).rgb);
            vec3 Nw = normalize(mat3(gbufferModelViewInverse) * Nv);
            puddle = zephyr_puddleMask(worldPos, Nw,
                                       texture(colortex1, texCoord).g, rain);
            float ripple = sin(worldPos.x * 3.3 + frameTimeCounter * 5.0)
                         * sin(worldPos.z * 2.9 - frameTimeCounter * 4.1);
            N = normalize(Nv + vec3(ripple, 0.0, ripple * 0.7)
                              * PUDDLE_RIPPLE * puddle);
            rippleUv = vec2(ripple, ripple * 0.7) * 0.004 * puddle;
        }

        if (isWater || puddle > 0.02) {
            vec3 R = normalize(reflect(-V, N));
            float march = SSR_STEP_LENGTH;
            vec3 p = viewPos + N * 0.06;
            vec2 hitUv = vec2(-1.0);
            for (int i = 0; i < SSR_STEPS; ++i) {
                p += R * march;
                march *= 1.10;
                vec4 cp = gbufferProjection * vec4(p, 1.0);
                if (abs(cp.w) < 1e-5) break;
                vec2 uv = cp.xy / cp.w * 0.5 + 0.5;
                if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;
                float d = texture(depthtex0, uv).r;
                if (d >= 0.9999) continue;
                float diff = (-p.z) - zephyr_linearDepth(d);
                if (diff > 0.0 && diff < SSR_THICKNESS) {
                    hitUv = uv;
                    break;
                }
            }
            if (hitUv.x >= 0.0) {
                float edge = smoothstep(0.0, 0.06, hitUv.x)
                           * (1.0 - smoothstep(0.94, 1.0, hitUv.x))
                           * smoothstep(0.0, 0.06, hitUv.y)
                           * (1.0 - smoothstep(0.94, 1.0, hitUv.y));
                vec3 refl = max(texture(colortex3, hitUv + rippleUv).rgb, vec3(0.0));
                float weight = isWater
                    ? clamp((WATER_F0 + (1.0 - WATER_F0)
                             * pow(clamp(1.0 - max(dot(V, N), 0.0), 0.0, 1.0), 5.0))
                            * 2.0 + 0.45, 0.0, 0.90) * SSR_STRENGTH
                    : PUDDLE_STRENGTH * puddle;
                color = mix(color, refl, weight * edge * (1.0 + rain * 0.30));
            }
        }
    }
#endif

#if CLOUD_ENABLED
    float cloudBaseY = zephyr_cloudBase();
    float cloudThick = zephyr_cloudThickness();
    float extinction = zephyr_cloudExtinction();
    float bolt = zephyr_lightning();
    if (rd.y > 0.01) {
        float t0 = max((cloudBaseY - cameraPosition.y) / rd.y, 0.0);
        float t1 = min((cloudBaseY + cloudThick - cameraPosition.y) / rd.y,
                       min(dist, 9000.0));
        if (t1 > t0) {
            float stepLen = (t1 - t0) / float(CLOUD_STEPS);
            vec3 L = normalize(vec3(sunDirWorld.x, max(sunDirWorld.y, 0.10), sunDirWorld.z));
            float warmC = zephyr_warmMix(sunDirWorld.y);
            vec3 cloudAmbient = mix(vec3(0.10, 0.13, 0.20), vec3(0.58, 0.66, 0.80), dayAmount)
                              * mix(1.0, 0.55, rain);
            vec3 sunColor = mix(vec3(1.45, 0.58, 0.24), vec3(1.20, 1.12, 0.98), warmC);
            float phaseC = 0.55 + 0.45 * pow(mu, 4.0);
            float silver = pow(mu, 16.0);

            float T = 1.0;
            vec3 scattered = vec3(0.0);
            for (int i = 0; i < CLOUD_STEPS; ++i) {
                vec3 p = cameraPosition + rd * (t0 + (float(i) + 0.5) * stepLen);
                float d = zephyr_cloudDensity(p);
                if (d < 0.002) continue;
                float h = clamp((p.y - cloudBaseY) / cloudThick, 0.0, 1.0);
                float sunT = zephyr_cloudSunTransmittance(p, L);
                vec3 lit = cloudAmbient * (0.28 + 0.72 * h)
                         + sunColor * sunT * phaseC * dayAmount * 1.15
                         + sunColor * silver * sunT * dayAmount * 0.55;
#if LIGHTNING_ENABLED
                lit += vec3(0.55, 0.65, 0.95) * bolt * rain
                     * LIGHTNING_INTENSITY * 0.85 * (0.35 + 0.65 * sunT);
#endif
                float a = 1.0 - exp(-d * stepLen * extinction);
                scattered += T * a * lit;
                T *= 1.0 - a;
                if (T < 0.02) break;
            }
            vec3 clouded = color * T + scattered;
            color = mix(color, clouded, smoothstep(0.01, 0.12, rd.y));
        }
    }
#endif

    // M17: stained glass is composited HERE - after clouds/SSR but BEFORE fog
    // and BEFORE composite2's TAA. Doing it in final.fsh skipped the
    // atmosphere (glass looked sharp/haze-free next to the hazy city) and
    // skipped the temporal filter (far glass edges shimmered). colortex8 is a
    // dedicated layer only gbuffers_water writes, so rain cannot erase it.
    vec4 glassLayer = texture(colortex8, texCoord);
    float glassA = glassLayer.a;
    if (glassA > 0.01 && glassA < 0.999) {
        // M20: use the texture colour AS the transmittance (already
        // [0,1] after sRGB->linear). M17 divided by the peak channel to
        // keep only the hue, which erased DENSITY: white / black / tinted
        // glass all became (1,1,1) and looked like clear air. Every
        // reference pack uses the colour directly. Still only attenuates.
        vec3 glassCol = clamp(glassLayer.rgb, 0.0, 1.0);
        vec3 transmittance = mix(vec3(1.0), glassCol, GLASS_ABSORPTION);
        // Fog now runs AFTER this stage and washes part of the tint away, so
        // allow the strength to exceed 1 and clamp the mix weight. Only the
        // weight is clamped: transmittance itself is <= 1 per channel, so the
        // filter still only ATTENUATES light and can never clip highlights.
        float tintWeight = clamp(glassA * TRANSLUCENT_TINT_STRENGTH, 0.0, 1.0);
        color *= mix(vec3(1.0), transmittance, tintWeight);

        // Fresnel rim, no screen-space derivatives (TAA-safe).
        vec3 glassN = zephyr_decodeNormal(texture(colortex2, texCoord).rgb);
        float fresnel = pow(1.0 - clamp(abs(glassN.z), 0.0, 1.0), 3.0);
        // M20: colourless / low-chroma panes need a visible SURFACE even
        // when their transmittance is near 1 (Complementary: min alpha
        // 0.25 + Fresnel). Add neutral sky-tinted reflection by chroma.
        float chroma = max(glassCol.r, max(glassCol.g, glassCol.b))
                     - min(glassCol.r, min(glassCol.g, glassCol.b));
        float neutral = 1.0 - smoothstep(0.04, 0.25, chroma);
        // M23: buffer-space edge of the coverage mask. M17 removed a dFdx
        // rim because screen derivatives re-roll with TAA jitter; sampling the
        // G-buffer at fixed texel offsets is deterministic, so the highlight
        // converges. A white pane has almost no chroma and nearly unit
        // transmittance - the EDGE is what tells the eye a pane is there.
        // M23: colortex8.a IS the pane coverage mask - >0 inside the held /
        // placed pane, 0 outside. Its gradient traces the pane OUTLINE even
        // when the glass texture itself is almost perfectly transparent
        // (white stained glass). colortex0.a cannot do this: the blended alpha
        // of a clear pane is ~0 both inside and outside the silhouette.
        vec2 gtexel = 1.0 / vec2(viewWidth, viewHeight);
        float eL = texture(colortex8, texCoord - vec2(gtexel.x, 0.0)).a;
        float eR = texture(colortex8, texCoord + vec2(gtexel.x, 0.0)).a;
        float eD = texture(colortex8, texCoord - vec2(0.0, gtexel.y)).a;
        float eU = texture(colortex8, texCoord + vec2(0.0, gtexel.y)).a;
        float edge = clamp((abs(eR - eL) + abs(eU - eD)) * GLASS_EDGE_GAIN,
                           0.0, 1.0);
        // M23: an all-over ADDITIVE reflection just made colourless panes
        // brighter, which is still "invisible". A neutral frosted veil gives
        // them a readable surface: desaturate + gently darken what is behind,
        // then keep the cool specular only at the rim / pane edges.
        float veil = neutral * glassA * GLASS_NEUTRAL_VEIL;
        color = mix(color, vec3(zephyr_luma(color)) * 0.62, veil);
        color += vec3(0.62, 0.75, 0.95) * zephyr_luma(color)
               * glassA * (fresnel * GLASS_RIM_STRENGTH
                           + neutral * (GLASS_NEUTRAL_REFLECT
                                        + edge * GLASS_EDGE_STRENGTH));
    }

#if WATER_VOLUME_ENABLED
    bool underwaterView = (isEyeInWater == 1);
#else
    bool underwaterView = false;
#endif

#if WATER_VOLUME_ENABLED
    if (underwaterView) {
        // M31: Beer-Lambert underwater fog. The eye-to-surface path is the
        // linear view distance; wavelength-dependent extinction turns distant
        // geometry cyan-green instead of just dimming it.
        vec3 sigmaA = WATER_ABSORB_RGB * WATER_FOG_DENSITY;
        float waterPath = min(dist, 160.0);
        vec3 Tw = exp(-sigmaA * waterPath);
        vec3 ambientUnder = mix(vec3(0.05, 0.11, 0.17),
                                vec3(0.26, 0.52, 0.58), dayAmount);
        vec3 inScatter = WATER_SCATTER_RGB * ambientUnder
                       * WATER_INSCATTER * (0.65 + 0.35 * mu);
        color = color * Tw + inScatter * (1.0 - Tw);

#if WATER_PARTICLE_ENABLED
        // M31: raymarch suspended motes along the view ray in WORLD space and
        // attenuate each sample by the SAME transmittance as the water fog.
        // Sharing the coefficient keeps the particles physically embedded in
        // the volume rather than floating on top of it.
        float maxT = min(dist, WATER_PARTICLE_RANGE);
        float stepLen = maxT / float(WATER_PARTICLE_STEPS);
        vec3 motes = vec3(0.0);
        for (int i = 0; i < WATER_PARTICLE_STEPS; ++i) {
            float t = (float(i) + 0.5) * stepLen;
            float m = zephyr_waterMote(cameraPosition + rd * t);
            if (m > 0.0) motes += WATER_PARTICLE_COLOR * m * exp(-sigmaA * t);
        }
        color += motes * (WATER_PARTICLE_BRIGHTNESS
                          / float(WATER_PARTICLE_STEPS))
               * (0.30 + 0.70 * dayAmount);
#endif
    }
#endif

    if (!underwaterView && depth < 0.9999) {
        vec3 worldPos = cameraPosition + rd * dist;
        float sigma = FOG_DENSITY * exp(-max(worldPos.y - 64.0, 0.0) * FOG_HEIGHT_FALLOFF);
        // Keep rain fog strong but stop it from flattening all local contrast.
        sigma *= 1.0 + rain * 0.95;
        // Shaping the fog distance in rain keeps far structures readable
        // instead of washing the whole frame into one flat grey.
        float fogDist = mix(dist, pow(max(dist, 1.0), RAIN_FOG_DIST_POW), rain);
        float T = exp(-clamp(sigma * fogDist, 0.0, 40.0));

        vec3 fogRay = normalize(vec3(rd.x, max(rd.y, 0.02), rd.z));
        vec3 fogColor = zephyr_atmosphere(fogRay, sunDirWorld, dayAmount, rain);
        fogColor *= 0.80 + FOG_INSCATTER_BOOST * pow(mu, 4.0) * dayAmount;

        color = color * T + fogColor * (1.0 - T);
    }

    outColor = vec4(clamp(color, 0.0, 65504.0), 1.0);
}
