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
uniform sampler2D depthtex1;   // M42: SEABED on this build

/* RENDERTARGETS: 4 */
layout(location = 0) out vec4 outColor;

vec3 zephyr_worldRay(vec2 uv) {
    vec4 clip = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
    float w = abs(clip.w) < 1e-5 ? 1e-5 : clip.w;
    return normalize(mat3(gbufferModelViewInverse) * normalize(clip.xyz / w));
}

// M54: vertical distance from the eye to the water plane, recovered from a
// few fixed probes on the upper part of the frame. A hard-coded eye depth
// made the interface sit at the wrong height as soon as the player dived.
// Iris packs differ in whether gbufferModelViewInverse already carries the
// camera translation, so accept both conventions (see the fallback below).
float zephyr_uwEyeDepth() {
    float sum = 0.0;
    float cnt = 0.0;
    for (int i = 0; i < 3; ++i) {
        vec2 uv = vec2(0.22 + 0.28 * float(i), 0.82);
        vec4 m = textureLod(colortex8, uv, 0.0);
        float d = textureLod(depthtex0, uv, 0.0).r;
        if (m.b > 1.5 && m.a < 0.01 && d < 0.9999) {
            vec4 clip = gbufferProjectionInverse
                      * vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
            vec3 vp = clip.xyz / max(abs(clip.w), 1e-5);
            float wy = (gbufferModelViewInverse * vec4(vp, 1.0)).y;
            float h = wy - cameraPosition.y;
            if (h < 0.05 || h > 16.0) h = wy;
            sum += clamp(h, 0.15, 12.0);
            cnt += 1.0;
        }
    }
    return cnt > 0.0 ? sum / cnt : WATER_UW_EYE_DEPTH;
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
    // M42: colortex1.a is reused/cleared by this stage (a probe marked ~96% of
    // the frame as water), so use Zephyr's dedicated water marker.
    vec4 ssrMark = texture(colortex8, texCoord);
    bool ssrWater = (ssrMark.b > 1.5 && ssrMark.a < 0.01);
    // M42: this march produced a hard-edged rectangular reflection patch on the
    // water (its hit boundary has no falloff). M41's mirror reflection has no
    // such seam, so water is excluded here and this block serves puddles only.
    if (depth < 0.9999 && !ssrWater) {
        vec4 vClip = gbufferProjectionInverse * vec4(texCoord * 2.0 - 1.0,
                                                     depth * 2.0 - 1.0, 1.0);
        float vw = abs(vClip.w) < 1e-5 ? 1e-5 : vClip.w;
        vec3 viewPos = vClip.xyz / vw;
        vec3 V = normalize(-viewPos);
        vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;

        bool isWater = false;   // M42: water reflection now lives in M41
        vec3 N;
        float puddle = 0.0;
        vec2 rippleUv = vec2(0.0);

        if (isWater) {
            vec2 wSlope = zephyr_waterWaves(worldPos, frameTimeCounter);
            N = normalize(mat3(gbufferModelView)
                         * normalize(vec3(-wSlope.x, 1.0, -wSlope.y)));
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
    // M54: an underwater eye must never see the atmospheric cloud deck
    // directly. The water/air interface below handles all up-facing rays.
    if (rd.y > 0.01 && isEyeInWater == 0) {
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

    // M40 -----------------------------------------------------------------
    // iterationT-style water body, above-water view only.
    // `colortex8.b > 1.5 && colortex8.a < 0.01` is Zephyr's dedicated WATER
    // marker (gbuffers_water writes 2.0 into .b for real water). matId in
    // colortex1.a is NOT reliable at this stage (a probe marked ~96% of the
    // frame as water), and Iris's depthtex1 carries no translucent surface
    // depth in this pack, so the water path is approximated from `dist`.
#if WATER_BODY_ENABLED
    vec4 wmark = texture(colortex8, texCoord);
    if (wmark.b > 1.5 && wmark.a < 0.01
        && depth < 0.9999 && isEyeInWater == 0) {
        vec3 wPos = cameraPosition + rd * dist;
        vec2 slope = zephyr_waterWaves(wPos, frameTimeCounter);

        // Screen-space refraction: offset the lookup by the wave slope and
        // reject samples that land in front of the surface (iterationT's
        // refractDepth < currentDepth guard).
        vec2 refUv = texCoord - slope * WATER_REFRACT_STRENGTH
                     / (1.0 + dist * 0.05);
        refUv = clamp(refUv, vec2(0.002), vec2(0.998));
        if (texture(depthtex0, refUv).r < depth) refUv = texCoord;
        // The water surface is alpha-blended into colortex0, so the albedo
        // still carries the SEABED texture. Recovering it is what makes
        // iterationT's near field read as bright neutral stone rather than
        // a flat blue sheet; a constant "shallow glow" only erases detail.
        vec3 bottomAlbedo = zephyr_srgbToLinear(
            max(texture(colortex0, refUv).rgb, vec3(0.0)));
        vec3 skyAmb = zephyr_atmosphere(vec3(0.0, 1.0, 0.0),
                                        sunDirWorld, dayAmount, rain);
        vec3 litBottom = bottomAlbedo
                       * (0.20 + WATER_BOTTOM_LIGHT * zephyr_luma(skyAmb));
        vec3 shaded = max(texture(colortex3, refUv).rgb, vec3(0.0));
        vec3 behind = mix(shaded, litBottom, WATER_BOTTOM_MIX);

        // Water path proxy. `wPath` is deliberately kept unchanged for the
        // M57 shoreline foam below: its gradient / coast test is calibrated
        // on this exact value.
#if WATER_PATH_REAL
        // M42: real optical path. Measured on this build: depthtex0 = water
        // SURFACE (22.1 m), depthtex1 = SEABED (32.4 m) - the opposite of the
        // usual OptiFine naming, which is why the old proxy never worked.
        float surfDist = dist;                                  // depthtex0
        float seabedDist = zephyr_linearDepth(texture(depthtex1, texCoord).r);
        float wPath = clamp(seabedDist - surfDist, 0.0, WATER_PATH_MAX);
#else
        float wPath = clamp(dist * WATER_PATH_SCALE, 0.0,
                            WATER_PATH_MAX);
#endif

        // M61 -------------------------------------------------------------
        // iterationT composite1.fsh:103-104,128-129,44-47,78-87. The water
        // path is the RADIAL ray length between the water surface (depthtex0)
        // and the opaque seabed (depthtex1); the slant is implicit because
        // both points lie on the same view ray. Probe z_m61_depth.png
        // measured 5.1 m near / 9.0 m mid / >20 m far on this exact view -
        // the depth pair ALREADY carries the near/far gradient. All M59/M60
        // dist / slant / submergence proxies were compensating for using the
        // axial linearDepth difference; they are gone.
        float dW = texture(depthtex0, texCoord).r;
        float dL = texture(depthtex1, texCoord).r;
        vec4 cW = gbufferProjectionInverse
                * vec4(texCoord * 2.0 - 1.0, dW * 2.0 - 1.0, 1.0);
        vec4 cL = gbufferProjectionInverse
                * vec4(texCoord * 2.0 - 1.0, dL * 2.0 - 1.0, 1.0);
        vec3 vW = cW.xyz / max(abs(cW.w), 1e-5);
        vec3 vL = cL.xyz / max(abs(cL.w), 1e-5);
        float waterPath = clamp(length(vL) - length(vW),
                                0.0, WATER_OPTICAL_MAX);

        // M61: caustics on the SEABED. iterationT composite.fsh:158,326-327
        // reconstructs worldPos from depthtex1 (the opaque layer) and gates
        // on the water-surface mask. Applying it to the recovered bottom
        // colour here keeps it visible from shore despite WATER_BOTTOM_MIX,
        // and CAUSTICS_ABOVE_GAIN = 0 turns it off.
#if CAUSTICS_ENABLED
        vec3 bedWorld = (gbufferModelViewInverse * vec4(vL, 1.0)).xyz
                      + cameraPosition;
        float caus = zephyr_caustics(bedWorld,
                        frameTimeCounter * CAUSTICS_SPEED);
        float causFade = exp(-waterPath * 0.10);
        litBottom += litBottom * caus * CAUSTICS_STRENGTH
                   * CAUSTICS_ABOVE_GAIN * causFade * dayAmount;
        behind = mix(shaded, litBottom, WATER_BOTTOM_MIX);
#endif

        // M61: iterationT's DOUBLE extinction (composite1.fsh:78-87),
        // recalibrated on the measured radial path: full reference constants
        // already swallowed the NEAR field on this shallow pond (M61 v1:
        // near luma 154 -> 93), so the slider defaults map to half strength.
        behind *= pow(WATER_ATTEN_RGB,
                      vec3(waterPath * WATER_ATTEN_RATE * 0.3125));
        float visibility = exp2(-waterPath * WATER_SCATTER_RATE * 3.625);
        // WATER_DEEP_SCATTER = 0 keeps the neutral near-field water colour,
        // 1 uses the deep cyan-blue that hides the far bank.
        vec3 waterFogColor = mix(WATER_SCATTER_SURF, WATER_SCATTER_DEEP,
                                 clamp(WATER_DEEP_SCATTER, 0.0, 1.0))
                           * (0.20 + 0.40 * min(zephyr_luma(skyAmb), 1.0));
        behind = mix(waterFogColor, behind, visibility);

        // M61: the near/far lift follows the REAL water path, not a screen
        // distance proxy. Short path = bright neutral shallow; long path =
        // no artificial lift, so the deep cyan-blue survives.
        float depthT = smoothstep(WATER_NEAR_PATH, WATER_FAR_PATH, waterPath);
        float sat = mix(WATER_NEAR_SAT, 1.0, depthT);
        float gain = mix(WATER_NEAR_GAIN, 1.0, depthT);
        float bLum = zephyr_luma(behind);
        behind = mix(vec3(bLum), behind, sat) * gain;

        // Facet highlights from the wave slope break up the flat tile look.
        behind *= 1.0 + (slope.x + slope.y) * WATER_FACET_GAIN;

#if WATER_FOAM_ENABLED
        // M53: shoreline foam. `wPath` is the SLANT optical path, so it is
        // small over the shallow shelf and grows toward deep water; a broken
        // white band there is the cheapest reliable cue that reads as "water"
        // rather than "blue plastic".
        // Absolute depth alone does not work here: this pool is uniformly
        // shallow (wPath ~1.6 m everywhere) so foam would either cover
        // everything or nothing. What actually marks a shoreline is the
        // SCREEN-SPACE GRADIENT of the water path - it jumps where the bed
        // meets the bank.
        // M57: z113 showed dotted WHITE LINES along every near-field seabed
        // block edge. wPath = seabedDist - surfDist JUMPS at any submerged
        // step, so the plain gradient test treated those steps as a shore.
        // Fix 1: a real coast is where the WATER SURFACE ends. Sample the
        // dedicated water marker (colortex8.b) a few texels away; at a
        // submerged block edge every neighbour is still water, so coast = 0.
        // Fix 2: the user only wants foam on the FAR bank, so fade the whole
        // effect in with distance. The soft shallow-shelf band (foamDepth)
        // survives on the far bank; the near-field white haze does not.
        vec2 foamTexel = 1.0 / vec2(viewWidth, viewHeight);
        float nbL = step(1.5, texture(colortex8,
                          texCoord - vec2(3.0 * foamTexel.x, 0.0)).b);
        float nbR = step(1.5, texture(colortex8,
                          texCoord + vec2(3.0 * foamTexel.x, 0.0)).b);
        float nbD = step(1.5, texture(colortex8,
                          texCoord - vec2(0.0, 3.0 * foamTexel.y)).b);
        float nbU = step(1.5, texture(colortex8,
                          texCoord + vec2(0.0, 3.0 * foamTexel.y)).b);
        float coast = 1.0 - min(min(nbL, nbR), min(nbD, nbU));
        float foamFar = smoothstep(WATER_FOAM_NEAR_DIST,
                                   WATER_FOAM_FAR_DIST, dist);
        float foamDepth = (1.0 - smoothstep(WATER_FOAM_DEPTH * 0.25,
                                            WATER_FOAM_DEPTH, wPath)) * foamFar;
        float shoreGrad = abs(dFdx(wPath)) + abs(dFdy(wPath));
        float shore = smoothstep(WATER_FOAM_EDGE * 0.35,
                                 WATER_FOAM_EDGE, shoreGrad)
                    * coast * foamDepth;
        float foamN = texture(noisetex,
                              wPos.xz * WATER_FOAM_SCALE
                              + vec2(frameTimeCounter * 0.015,
                                     -frameTimeCounter * 0.011)).r;
        float foam = smoothstep(1.0 - WATER_FOAM_COVERAGE, 1.0,
                                foamN * 0.65 + shore * 0.55 + foamDepth * 0.20)
                   * max(shore, foamDepth * 0.45);
        behind = mix(behind,
                     vec3(0.92, 0.96, 1.00) * WATER_FOAM_BRIGHT,
                     clamp(foam, 0.0, 1.0) * WATER_FOAM_STRENGTH);
#endif

        color = mix(color, behind, WATER_BODY_MIX);

#if WATER_REFL_ENABLED
        // M41: mirror the scene above the water line. A near-horizontal
        // reflector maps a screen pixel at y to roughly 1-y; the wave slope
        // shifts that lookup so buildings/sky are broken into ripples. This
        // is far more reliable than the SSR march, which starts from the
        // SEABED depth (depthtex0) and almost never hits anything.
        vec3 waveN = normalize(vec3(-slope.x * WATER_REFL_WAVE_N,
                                    1.0,
                                    -slope.y * WATER_REFL_WAVE_N));
        vec3 Rw = normalize(reflect(rd, waveN));

        // M43: a mirror about the screen mid-line maps y to 1-y, which for a
        // pool sitting AT mid-screen samples the water itself - the blend then
        // changes nothing (measured: gain 6.5 -> 14 changed RGB by 2/255).
        // What a water plane actually mirrors is the shoreline ABOVE it, so
        // lift the lookup upward by a fixed fraction of the screen.
        vec2 envUv = clamp(vec2(texCoord.x + slope.x * WATER_REFL_WAVE_UV,
                                texCoord.y + WATER_REFL_LIFT
                                + slope.y * WATER_REFL_WAVE_UV),
                           vec2(0.002), vec2(0.998));
        vec3 envR = max(texture(colortex3, envUv).rgb, vec3(0.0));
        vec3 skyR = zephyr_atmosphere(Rw, sunDirWorld, dayAmount, rain);

#if CLOUD_ENABLED
        // Reuse the SAME cloud field that shades the sky, so reflected clouds
        // line up with the real ones instead of being a random overlay.
        float clT = (zephyr_cloudBase() + zephyr_cloudThickness() * 0.5
                     - cameraPosition.y) / max(Rw.y, 0.06);
        vec3 clP = cameraPosition + Rw * max(clT, 0.0);
        float clD = zephyr_cloudDensity(clP);
        skyR += vec3(0.92, 0.96, 1.00) * clD
              * WATER_REFL_CLOUD * (0.6 + 0.4 * dayAmount);
#endif

        vec3 refl = mix(skyR, envR, WATER_REFL_ENV_MIX);

        // M46: real screen-space reflection for the water plane. The fixed
        // "+LIFT" lookup above can only guess where the shoreline is, so the
        // reflection drifts as the camera turns. This march starts from the
        // WATER depth (depthtex0 is the surface on this build, see M42), walks
        // along the reflected view vector and samples the scene where the ray
        // actually lands. Falls back to the sky/LIFT estimate when it misses,
        // which is what keeps it seam-free (the M42 rectangle came from a hard
        // hit boundary with no fallback).
#if SSR_ENABLED
        vec3 Rv = normalize(mat3(gbufferModelView) * Rw);
        vec4 refClip = gbufferProjectionInverse
                     * vec4(texCoord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
        vec3 refPos = refClip.xyz / max(abs(refClip.w), 1e-5);
        refPos += mat3(gbufferModelView) * waveN * 0.10;
        float refStep = SSR_STEP_LENGTH * 2.5;
        vec2 refHit = vec2(-1.0);
        float refT = 0.0;
        for (int i = 0; i < SSR_STEPS; ++i) {
            refPos += Rv * refStep;
            refStep *= 1.10;
            vec4 cp = gbufferProjection * vec4(refPos, 1.0);
            if (abs(cp.w) < 1e-5) break;
            vec2 uv = cp.xy / cp.w * 0.5 + 0.5;
            if (uv.x < 0.002 || uv.x > 0.998
                || uv.y < 0.002 || uv.y > 0.998) break;
            float d = texture(depthtex0, uv).r;
            if (d >= 0.9999) continue;
            float diff = (-refPos.z) - zephyr_linearDepth(d);
            if (diff > 0.0 && diff < SSR_THICKNESS * 2.5) {
                refHit = uv;
                refT = float(i + 1) / float(SSR_STEPS);
                break;
            }
        }
        float refW = 0.0;
        if (refHit.x >= 0.0) {
            vec2 ruv = clamp(refHit + slope * WATER_REFL_WAVE_UV * 0.55,
                             vec2(0.002), vec2(0.998));
            // Fade toward the screen border so a hit never ends on a hard edge.
            float edge = smoothstep(0.0, 0.10, refHit.x)
                       * (1.0 - smoothstep(0.90, 1.0, refHit.x))
                       * smoothstep(0.0, 0.10, refHit.y)
                       * (1.0 - smoothstep(0.90, 1.0, refHit.y));
            vec3 ssrCol = max(texture(colortex3, ruv).rgb, vec3(0.0));
            refl = mix(refl, ssrCol, edge * WATER_SSR_MIX * (1.0 - refT * 0.30));
            refW = edge;
        }
#endif

        refl *= WATER_REFLECT_TINT;
        float cosI = clamp(dot(-rd, waveN), 0.0, 1.0);
        float fres = WATER_F0 + (1.0 - WATER_F0)
                   * pow(1.0 - cosI, 5.0);
        // Narrow sun glint riding on the wave facets.
        float glint = pow(max(dot(Rw, sunDirWorld), 0.0),
                          WATER_REFL_SUN_POWER);
        refl += vec3(1.00, 0.94, 0.82) * glint
              * WATER_REFL_SUN_GAIN * dayAmount;
        float reflWeight = clamp(fres * WATER_REFL_GAIN,
                                 0.0, WATER_REFL_MAX);
        // A near-vertical view should still show the bottom. Without this
        // fade a strong gain turns the whole pool into a mirror (M41 V2/V3);
        // real water keeps shallow near-field translucency and mirrors the
        // skyline only toward the grazing far field.
        reflWeight *= mix(WATER_REFL_NEAR_KEEP, 1.0,
                          smoothstep(0.12, 0.52, texCoord.y));
        // M60: a long slant path means the ray travels THROUGH the water
        // body, so the SURFACE mirror must give way to the volume. In M59
        // this weight sat near WATER_REFL_MAX in the far field with GAIN=16
        // and overwrote every bit of the extinction / in-scattering above
        // (A/B: far-field luma 96.5 -> 96.1, i.e. no change at all).
        // WATER_REFL_PATH_FADE = 0 restores the M59 reflection exactly.
        float reflPathFade = smoothstep(WATER_REFL_PATH_START,
                                        WATER_REFL_PATH_END, waterPath);
        reflWeight *= 1.0 - clamp(WATER_REFL_PATH_FADE, 0.0, 1.0)
                            * reflPathFade;
        color = mix(color, refl, reflWeight);
#endif
    }
#endif
    // ---------------------------------------------------------------------

#if WATER_VOLUME_ENABLED
    bool underwaterView = (isEyeInWater == 1);
#else
    bool underwaterView = false;
#endif

#if WATER_VOLUME_ENABLED
    if (underwaterView) {
        // M31: Beer-Lambert underwater fog. Wavelength-dependent extinction
        // turns distant geometry deep blue instead of merely dimming it.
        // M54: the ambient term is blue-dominant now; continuum's reference
        // mid-field is (5,100,146), i.e. blue > green, not cyan-green.
        vec3 sigmaA = WATER_ABSORB_RGB * WATER_FOG_DENSITY;
        float waterPath = min(dist, 160.0);
        vec3 Tw = exp(-sigmaA * waterPath);
        vec3 ambientUnder = mix(vec3(0.03, 0.07, 0.14),
                                vec3(0.18, 0.36, 0.60), dayAmount);
        vec3 inScatter = WATER_SCATTER_RGB * ambientUnder
                       * WATER_INSCATTER * (0.65 + 0.35 * mu);
        color = color * Tw + inScatter * (1.0 - Tw);

        // M56: ONE eye->surface estimate shared by the interface, the shafts
        // and the particles. The participating medium ends at whichever is
        // nearer: solid geometry, or the water surface. A sky pixel used to
        // report dist = 1e6, so the shaft march ran all 8 slabs through
        // "22 m of water" that is not there - that is the pale horizontal
        // band in z110. Down-facing rays have no interface overhead.
        float uwEyeDepth = zephyr_uwEyeDepth();
        float tIface = clamp(uwEyeDepth / max(rd.y, 0.045), 0.0, 160.0);
        float mediumEnd = min(min(dist, 160.0),
                              rd.y > 0.02 ? tIface : 160.0);

        // M54 -------------------------------------------------------------
        // The water/air interface seen FROM BELOW.
        //
        // M50 shaded only water-MARKED pixels, which ends the plane on a
        // razor-straight screen-space horizon; it also sampled the wave field
        // at cameraPosition + rd * dist (dist jumps between the surface, the
        // sky and the seabed), used IOR 1.20 and a 6x wave normal that swept
        // the 12..14 radiance sun disc over the frame as white shards.
        //
        // Here the interface is a CONTINUOUS analytic plane: every up-facing
        // ray hits it, the incidence angle alone decides between the Snell
        // window (transmitted sky) and total internal reflection (a mirror of
        // the underwater scene), and the eye->surface path fades the whole
        // thing into the same water fog so no hard line can survive.
        vec2 uwTexel = 1.0 / vec2(viewWidth, viewHeight);
        vec4 uwMark = texture(colortex8, texCoord);
        float mark = step(1.5, uwMark.b) * (1.0 - step(0.01, uwMark.a));
        mark += step(1.5, texture(colortex8,
                          texCoord + vec2( 4.0 * uwTexel.x, 0.0)).b);
        mark += step(1.5, texture(colortex8,
                          texCoord + vec2(-4.0 * uwTexel.x, 0.0)).b);
        mark += step(1.5, texture(colortex8,
                          texCoord + vec2(0.0,  4.0 * uwTexel.y)).b);
        mark += step(1.5, texture(colortex8,
                          texCoord + vec2(0.0, -4.0 * uwTexel.y)).b);
        mark *= 0.20;
        // Angle-driven coverage, NOT a marker-driven one. The small floor
        // outside the marked region keeps a camera bobbing at the surface
        // from flipping the whole sky into a mirror on a single frame.
        // M55: a 6-degree transition left a visible horizontal brightness
        // step at the horizon (z107). Widen it to ~17 degrees so the mirror
        // and the water fog cross-fade instead of meeting on a line.
        float surfaceMask = smoothstep(-0.06, 0.24, rd.y)
                          * mix(WATER_UW_NO_MARK, 1.0, mark);

        if (surfaceMask > 0.001) {
            float tSurf = tIface;
            vec3 surfPos = cameraPosition + rd * tSurf;
            vec2 uwSlope = zephyr_waterWaves(surfPos, frameTimeCounter);
            // Seen from below the geometric normal points DOWN into the water.
            vec3 Ndown = normalize(vec3(-uwSlope.x * WATER_UW_WAVE_N,
                                        -1.0,
                                        -uwSlope.y * WATER_UW_WAVE_N));

            // Snell's law, water (1.333) -> air (1.0). k <= 0 is TIR; using
            // k for the blend gives a soft, WAVE-PERTURBED window rim instead
            // of a binary refract() test (the critical angle is 48.6 deg).
            float eta = WATER_UW_IOR;
            float cosI = clamp(-dot(rd, Ndown), 0.0, 1.0);
            float k = 1.0 - eta * eta * (1.0 - cosI * cosI);
            float window = smoothstep(0.0, WATER_UW_EDGE, k);
            vec3 refrDir = k > 0.0
                ? normalize(eta * rd
                            + (eta * cosI - sqrt(max(k, 0.0))) * Ndown)
                : normalize(vec3(rd.x, 0.85, rd.z));

            // Inside the window: analytic sky, with the sun DISC capped. The
            // uncapped disc (radiance 12..14) is what M50 smeared into white
            // shards; a soft glow replaces it. Fresnel darkens the rim.
            vec3 refrSky = zephyr_atmosphere(refrDir, sunDirWorld,
                                             dayAmount, rain);
            refrSky = min(refrSky, vec3(WATER_UW_SKY_CAP));
            float softSun = pow(max(dot(refrDir, sunDirWorld), 0.0), 64.0);
            refrSky += vec3(1.00, 0.95, 0.86) * softSun
                     * WATER_UW_SUN * dayAmount;
            refrSky *= mix(0.55, 1.0, smoothstep(0.0, 0.35, k));
            refrSky *= clamp(0.90 + (uwSlope.x + uwSlope.y)
                             * WATER_UW_CREST, 0.72, 1.18);

            // Outside the window: total internal reflection. Reflect the ray
            // into the DOWNWARD hemisphere and project it back to the screen,
            // so the surface mirrors the real seabed/rock walls. Sampling the
            // lower half can never feed a water pixel back into itself (M50
            // v2's "red/green shards"), and the marker guard is a second net.
            vec3 mirrorDir = reflect(rd, Ndown);
            mirrorDir.y = min(mirrorDir.y, -0.08);
            mirrorDir = normalize(mirrorDir);
            vec4 mClip = gbufferProjection
                       * (gbufferModelView * vec4(mirrorDir, 0.0));
            // M55: an out-of-range lookup must NOT be clamped onto the screen
            // border. z107 showed exactly that failure: the first-person hand
            // / warm shore buildings in the bottom right were mirrored into
            // ORANGE SHARDS at the top right. Reject the sample instead.
            vec2 mUvRaw = mClip.w > 1e-4
                        ? mClip.xy / mClip.w * 0.5 + 0.5
                        : vec2(-1.0);
            vec2 mirrorUv = mUvRaw + uwSlope * WATER_UW_RIPPLE_UV;
            // M56: binary step() edges here were one more horizontal seam
            // where the mirror lookup walks out of frame / onto the surface.
            float inFrame = smoothstep(0.01, 0.08, mirrorUv.x)
                          * (1.0 - smoothstep(0.92, 0.99, mirrorUv.x))
                          * smoothstep(0.10, 0.26, mirrorUv.y)
                          * (1.0 - smoothstep(0.92, 0.99, mirrorUv.y));
            vec2 lookupUv = clamp(mirrorUv, vec2(0.002), vec2(0.998));
            float noWater = 1.0 - smoothstep(1.2, 1.8,
                                textureLod(colortex8, lookupUv, 0.0).b);
            float mirrorValid = inFrame * noWater;
            vec3 mirrorCol = max(textureLod(colortex3, lookupUv, 0.0).rgb,
                                 vec3(0.0));
            // M55: keep only the LUMINANCE of the mirrored scene. Carrying its
            // colour is what painted warm blotches on the interface; a grey
            // modulation still gives iterationT's dark "rocky ceiling", with
            // no chromatic contamination at all.
            float mirrorLum = clamp(zephyr_luma(mirrorCol), 0.0, 1.2);
            vec3 mirrorBody = inScatter * 1.55
                            + WATER_SCATTER_RGB * ambientUnder * 0.12;
            float reflW = WATER_UW_MIRROR * mix(1.0, 1.25, 1.0 - cosI);
            vec3 tirCol = mirrorBody
                        * mix(1.0,
                              clamp(0.72 + mirrorLum * reflW, 0.55, 1.45),
                              mirrorValid);
            // Wave facets modulate the mirror so the TIR region is rippled,
            // not a flat sheet of colour.
            tirCol *= clamp(0.90 + (uwSlope.x + uwSlope.y)
                            * WATER_UW_CREST * 3.0, 0.75, 1.18);

            vec3 surfCol = mix(tirCol, refrSky, window);
            // Grazing rays travel a very long way to the surface, so they
            // dissolve into the SAME fog colour as the water body: this is
            // what removes the straight horizon seam.
            vec3 Tsurf = exp(-sigmaA * min(tSurf, 160.0));
            surfCol = surfCol * Tsurf + inScatter * (1.0 - Tsurf);
            color = mix(color, surfCol,
                        clamp(surfaceMask * WATER_UW_MIX, 0.0, 1.0));
        }

#if WATER_VL_ENABLED
        // M54: broad, low-frequency beams instead of a caustics ridge mask.
        // The old mask projected a row of hard vertical bars onto the surface;
        // soft value noise + a forward lobe reads as volumetric glow. Fixed
        // world slabs and the gentle M49 extinction are unchanged.
        float vlStep = WATER_VL_RANGE / float(WATER_VL_STEPS);
        float phase = 0.25 + 0.75 * pow(mu, WATER_VL_PHASE);
        float beams = 0.0;
        for (int i = 0; i < WATER_VL_STEPS; ++i) {
            float t = (float(i) + 0.5) * vlStep;
            // M56: FRACTIONAL last slab. The old `if (t > dist) break`
            // quantised the integral into 2.75 m jumps (22 m / 8 steps);
            // every time dist crossed a slab boundary the accumulated light
            // jumped a whole step, projecting as stacked horizontal bands.
            float stepW = clamp((mediumEnd - t) / vlStep, 0.0, 1.0);
            if (stepW <= 0.0) break;
            vec3 p = cameraPosition + rd * t;
            vec2 bp = (p.xz + sunDirWorld.xz
                       * clamp(p.y, 0.0, 12.0) * 0.30) * WATER_VL_SCALE
                    + vec2(frameTimeCounter * 0.012,
                           -frameTimeCounter * 0.009);
            float n = zephyr_valueNoise(bp);
            beams += (0.30 + 0.70 * n * n)
                   * exp(-WATER_FOG_DENSITY * 0.30 * t) * stepW;
        }
        // Shafts live in the WATER COLUMN; the interface is not a
        // participating medium, so fade them as the surface takes over.
        // M56: the old `depth < 0.9999 ? 1.0 : 0.35` was a BINARY switch at
        // the geometry/sky boundary and drew another hard line. mediumEnd
        // now handles that continuously, so only the soft mask remains.
        float medium = 1.0 - 0.45 * surfaceMask;
        color += vec3(0.42, 0.72, 1.00) * beams
               * (WATER_VL_STRENGTH / float(WATER_VL_STEPS))
               * phase * dayAmount * (1.0 - rain * 0.55) * medium;
#endif

#if WATER_PARTICLE_ENABLED
        // M54: two depth layers in ONE raymarch - coarse distant motes plus a
        // finer, sparser near-field bubble layer. Both use the fixed world
        // grid, so neither re-rolls its hash while swimming (M33 rule).
        float pStep = WATER_PARTICLE_RANGE / float(WATER_PARTICLE_STEPS);
        float night = 1.0 - dayAmount;
        vec3 moteColor = mix(WATER_MOTE_UW_COLOR,
                             WATER_PARTICLE_GLOW_COLOR,
                             night * WATER_PARTICLE_NIGHT_GLOW);
        float moteGain = WATER_PARTICLE_BRIGHTNESS * WATER_MOTE_UW_GAIN
                       * (1.0 + night * WATER_PARTICLE_NIGHT_BOOST);
        vec3 motes = vec3(0.0);
        vec3 bubbles = vec3(0.0);
        for (int i = 0; i < WATER_PARTICLE_STEPS; ++i) {
            float t = (float(i) + 0.5) * pStep;
            // M56: same fractional-last-slab rule as the shafts, so the
            // particle field does not pop in a whole slab at a time.
            float stepW = clamp((mediumEnd - t) / pStep, 0.0, 1.0);
            if (stepW <= 0.0) break;
            vec3 p = cameraPosition + rd * t;
            vec3 Tp = exp(-sigmaA * t) * stepW;
            float m = zephyr_waterMoteEx(p, rd, WATER_PARTICLE_GRID,
                                         WATER_MOTE_UW_SIZE,
                                         WATER_PARTICLE_DENSITY);
            if (m > 0.0) motes += moteColor * m * Tp;
            if (t < WATER_BUBBLE_RANGE) {
                float b = zephyr_waterMoteEx(p, rd, WATER_BUBBLE_GRID,
                                            WATER_BUBBLE_SIZE,
                                            WATER_BUBBLE_DENSITY);
                bubbles += vec3(0.80, 0.90, 1.00) * b * Tp;
            }
        }
        color += motes * (moteGain / float(WATER_PARTICLE_STEPS))
               + bubbles * (WATER_BUBBLE_BRIGHTNESS
                            / float(WATER_PARTICLE_STEPS));
#endif
    }
#endif

    if (!underwaterView && depth < 0.9999) {
        vec3 worldPos = cameraPosition + rd * dist;
        float sigma = FOG_DENSITY * exp(-max(worldPos.y - 64.0, 0.0) * FOG_HEIGHT_FALLOFF);
        // Keep rain fog strong but stop it from flattening all local contrast.
        sigma *= 1.0 + rain * 0.95;
        // M35: a water surface is a specular mirror, not participating
        // medium. Full atmospheric fog replaced its reflected sky with the
        // SAME sky colour, flattening distant water into a grey-blue sheet.
        float fogWater = (texture(colortex1, texCoord).a > 0.5
                       && texture(colortex1, texCoord).a < 1.5) ? 1.0 : 0.0;
        sigma *= mix(1.0, WATER_SURFACE_FOG_MULT, fogWater);
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
