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

        // Water path proxy, then PER-CHANNEL Beer-Lambert absorption.
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
        vec3 atten = pow(WATER_ATTEN_RGB,
                         vec3(wPath * WATER_ATTEN_RATE));
        behind *= atten;

        // Inscattering: deep water tends to the water's own scatter colour.
        float visibility = exp2(-wPath * WATER_SCATTER_RATE);
        vec3 scatterCol = WATER_SCATTER_SURF
                        * (0.35 + 0.65 * zephyr_luma(skyAmb));
        behind = mix(scatterCol, behind, visibility);

        // iterationT's shallow field reads as NEUTRAL bright bottom while the
        // far field is cyan-blue. Zephyr has no separate seabed buffer (the
        // gbuffer albedo here is MC's blue water texture), so reproduce the
        // chromatic behaviour explicitly: desaturate + lift nearby, keep the
        // absorbed blue-green tint farther out.
        // Decoupled from wPath: measured water distances here are 20-35 m,
        // so a wPath-based gradient collapsed the whole surface into "near".
        float depthT = smoothstep(WATER_NEAR_DIST, WATER_FAR_DIST, dist);
        float sat = mix(WATER_NEAR_SAT, 1.0, depthT);
        float gain = mix(WATER_NEAR_GAIN, 1.0, depthT);
        float bLum = zephyr_luma(behind);
        behind = mix(vec3(bLum), behind, sat) * gain;

        // Facet highlights from the wave slope break up the flat tile look.
        behind *= 1.0 + (slope.x + slope.y) * WATER_FACET_GAIN;

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

        vec3 refl = mix(skyR, envR, WATER_REFL_ENV_MIX)
                  * WATER_REFLECT_TINT;
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

#if WATER_VL_ENABLED
        // M33: underwater light shafts. FIXED world-space slabs (step length
        // does NOT depend on per-pixel dist, the M33 swim flicker), a
        // sun-aligned caustics mask, a Mie-like forward phase and the same
        // Beer-Lambert attenuation as the fog.
        float vlStep = WATER_VL_RANGE / float(WATER_VL_STEPS);
        // A tight sun-aligned lobe almost never faces a downward underwater
        // view; keep a broad scatter floor so shafts stay visible.
        float phase = 0.55 + 0.45 * pow(mu, 2.0);
        vec3 shafts = vec3(0.0);
        for (int i = 0; i < WATER_VL_STEPS; ++i) {
            float t = (float(i) + 0.5) * vlStep;
            if (t > dist) break;
            vec3 p = cameraPosition + rd * t;
            // Bound the sun-aligned offset: using raw p.y on tall distant
            // geometry produced high-frequency stripes in the sky (M33).
            float c = zephyr_caustics(p + sunDirWorld
                          * clamp(p.y, 0.0, 12.0) * 0.25,
                          frameTimeCounter * CAUSTICS_SPEED);
            shafts += vec3(0.55, 0.85, 1.00) * c
                    * exp(-WATER_FOG_DENSITY * t);
        }
        // Shafts live in the water between the eye and a solid surface; a
        // sky pixel has no such medium, so do not paint beams onto the sky.
        float skyGate = depth < 0.9999 ? 1.0 : 0.0;
        color += shafts * (WATER_VL_STRENGTH / float(WATER_VL_STEPS))
               * phase * dayAmount * (1.0 - rain * 0.55) * skyGate;
#endif

#if WATER_PARTICLE_ENABLED
        // M33: fixed-length slabs, 2D perpendicular footprint, no grid drift.
        // At night the motes shift to a faint bioluminescent cyan-green and
        // gain a little intensity so they stay readable underwater.
        float pStep = WATER_PARTICLE_RANGE / float(WATER_PARTICLE_STEPS);
        float night = 1.0 - dayAmount;
        vec3 moteColor = mix(WATER_PARTICLE_COLOR,
                             WATER_PARTICLE_GLOW_COLOR,
                             night * WATER_PARTICLE_NIGHT_GLOW);
        float moteGain = WATER_PARTICLE_BRIGHTNESS
                       * (1.0 + night * WATER_PARTICLE_NIGHT_BOOST);
        vec3 motes = vec3(0.0);
        for (int i = 0; i < WATER_PARTICLE_STEPS; ++i) {
            float t = (float(i) + 0.5) * pStep;
            if (t > dist) break;
            float m = zephyr_waterMote(cameraPosition + rd * t, rd);
            if (m > 0.0) motes += moteColor * m * exp(-sigmaA * t);
        }
        color += motes * (moteGain / float(WATER_PARTICLE_STEPS));
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
