// Zephyr Z1 shared math. Linear HDR everywhere; gamma only in final.

vec3 zephyr_srgbToLinear(vec3 c) {
    return pow(max(c, vec3(0.0)), vec3(2.2));
}

vec3 zephyr_linearToSrgb(vec3 c) {
    return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
}

float zephyr_luma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 zephyr_encodeNormal(vec3 n) {
    return normalize(n) * 0.5 + 0.5;
}

vec3 zephyr_decodeNormal(vec3 e) {
    return normalize(e * 2.0 - 1.0);
}

float zephyr_linearDepth(float d) {
    float n = max(near, 0.05);
    float f = max(far, 100.0);
    float z = d * 2.0 - 1.0;
    return (2.0 * n * f) / max(f + n - z * (f - n), 1e-4);
}

float zephyr_hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float zephyr_valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = zephyr_hash12(i);
    float b = zephyr_hash12(i + vec2(1.0, 0.0));
    float c = zephyr_hash12(i + vec2(0.0, 1.0));
    float d = zephyr_hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float zephyr_fbm(vec2 p) {
    float v = 0.0;
    float amp = 0.5;
    mat2 rot = mat2(0.80, 0.60, -0.60, 0.80);
    for (int i = 0; i < 5; ++i) {
        v += amp * zephyr_valueNoise(p);
        p = rot * p * 2.03 + vec2(17.1, 9.7);
        amp *= 0.5;
    }
    return v;
}

float zephyr_D_GGX(float NoH, float a) {
    float a2 = a * a;
    float d = NoH * NoH * (a2 - 1.0) + 1.0;
    return a2 / max(ZEPHYR_PI * d * d, 1e-5);
}

float zephyr_G_Smith(float NoV, float NoL, float a) {
    float k = a * 0.5;
    float gv = NoV / max(NoV * (1.0 - k) + k, 1e-4);
    float gl = NoL / max(NoL * (1.0 - k) + k, 1e-4);
    return gv * gl;
}

vec3 zephyr_F_Schlick(vec3 f0, float VoH) {
    return f0 + (1.0 - f0) * pow(clamp(1.0 - VoH, 0.0, 1.0), 5.0);
}

// Day/night is derived from the world-space sun direction (sunPosition is in
// view space, so passes rotate it with gbufferModelViewInverse). The worldTime
// uniform was probed and does not track /time set on this Iris build; sunPosition.y
// does (measured +1.0 / +0.082 / -1.0 at 6000 / 12500 / 18000).
float zephyr_dayAmount(float sunY) {
    return smoothstep(-0.22, 0.30, sunY);
}

// Twilight strength peaks just above the horizon and is zero at noon/night.
float zephyr_twilight(float sunY) {
    return clamp(1.0 - abs(sunY) / 0.42, 0.0, 1.0) * smoothstep(-0.20, 0.05, sunY);
}

float zephyr_warmMix(float sunY) {
    return smoothstep(0.0, 0.45, sunY);
}

// F12 weather helpers -----------------------------------------------------
float zephyr_storm() {
    return clamp(rainStrength, 0.0, 1.0);
}

float zephyr_lightning() {
#if DEBUG_LIGHTNING
    return 1.0;
#else
    return clamp(lightningBoltPosition.w, 0.0, 1.0);
#endif
}

// A storm lowers and thickens the cloud deck. The density sampler and the
// integration bounds must read the same values or the layer will tear.
float zephyr_cloudBase() {
    return mix(CLOUD_ALTITUDE, STORM_CLOUD_ALTITUDE, zephyr_storm());
}

float zephyr_cloudThickness() {
    return mix(CLOUD_THICKNESS, STORM_CLOUD_THICKNESS, zephyr_storm());
}

float zephyr_cloudExtinction() {
    return mix(CLOUD_EXTINCTION, STORM_CLOUD_EXTINCTION, zephyr_storm());
}

// Shared by deferred (shading) and composite (reflection) so that a puddle's
// specular highlight and its reflected image land on exactly the same pixels.
float zephyr_puddleMask(vec3 worldPos, vec3 Nw, float skyLight, float rain) {
#if PUDDLE_ENABLED
    float n = zephyr_valueNoise(worldPos.xz * PUDDLE_FREQ_FINE) * 0.35
            + zephyr_valueNoise(worldPos.xz * PUDDLE_FREQ_COARSE + vec2(17.3, 9.1)) * 0.65;
    return smoothstep(PUDDLE_COVERAGE - 0.09, PUDDLE_COVERAGE + 0.06, n)
         * rain * pow(max(Nw.y, 0.0), 2.0)
         * smoothstep(0.55, 0.95, skyLight);
#else
    return 0.0;
#endif
}
// -------------------------------------------------------------------------

// Analytic single-scattering sky. Every pass that needs sky/fog/cloud colour
// calls this function so the atmosphere stays a single source of truth (F4).
vec3 zephyr_atmosphere(vec3 rd, vec3 sunDir, float dayAmount, float rain) {
    float storm = clamp(rain, 0.0, 1.0);
    float y = clamp(rd.y, -0.25, 1.0);
    float horizon = pow(1.0 - max(y, 0.0), 2.5);
    float mu = clamp(dot(rd, sunDir), -1.0, 1.0);

    float rayleighPhase = 0.75 * (1.0 + mu * mu);
    float g = ATMOSPHERE_MIE_G;
    float denom = max(1.0 + g * g - 2.0 * g * mu, 1e-3);
    float miePhase = (1.0 - g * g) / (4.0 * ZEPHYR_PI * pow(denom, 1.5));

    // A multiplicative tint is not enough at sunset: blue must be *replaced*,
    // otherwise the 0.82 blue zenith always dominates the 0.10 red channel.
    float twilight = zephyr_twilight(sunDir.y);
    float warm = zephyr_warmMix(sunDir.y);

    vec3 zenithDay = vec3(0.10, 0.31, 0.82);
    vec3 horizonDay = vec3(0.42, 0.65, 0.94);
    vec3 zenithNight = vec3(0.008, 0.016, 0.042);
    vec3 horizonNight = vec3(0.035, 0.050, 0.090);
    vec3 zen = mix(zenithNight, zenithDay, dayAmount);
    vec3 hor = mix(horizonNight, horizonDay, dayAmount);
    zen = mix(zen, vec3(0.30, 0.13, 0.22), twilight * 0.70);
    hor = mix(hor, vec3(1.25, 0.44, 0.12), twilight * 0.92);

    vec3 sky = mix(zen, hor, horizon);
    sky *= mix(0.40, 1.0, max(dayAmount, twilight * 0.85));
    vec3 scatterTint = mix(vec3(0.12, 0.18, 0.28), vec3(0.30, 0.10, 0.05), twilight);
    sky += scatterTint * rayleighPhase * dayAmount * 0.30 * ATMOSPHERE_DENSITY;

    float glow = pow(max(mu, 0.0), 8.0) * 0.45 + miePhase * 0.35;
    vec3 sunTint = mix(vec3(1.00, 0.36, 0.12), vec3(1.00, 0.96, 0.86), warm);
    sky += sunTint * glow * dayAmount * (1.35 + twilight * 1.10)
         * ATMOSPHERE_SUN_INTENSITY;

    sky += vec3(0.55, 0.16, 0.03) * twilight * (0.30 + 0.70 * horizon)
         * (0.25 + 0.75 * max(mu, 0.0));

    float disk = smoothstep(0.9993, 0.99980, mu);
    vec3 diskColor = mix(vec3(14.0, 5.0, 1.6), vec3(12.0, 10.0, 8.0), warm);
    // The sun disc disappears behind the storm deck.
    sky += diskColor * disk * dayAmount * (1.0 - storm);

    // Overcast: desaturate towards a cold slate grey AND cut the radiance.
    // Desaturation on its own made storm skies brighter than clear ones.
    vec3 stormSky = vec3(zephyr_luma(sky)) * vec3(0.80, 0.85, 0.98);
    // Keep a little of the twilight warmth instead of flattening it to grey.
    sky = mix(sky, stormSky, storm * mix(0.88, 0.70, twilight));
    // Keep some night detail: a storm night is dim, not pitch black.
    sky *= mix(1.0, mix(0.82, 0.55, dayAmount), storm);
#if LIGHTNING_ENABLED
    sky += vec3(0.55, 0.66, 0.95) * zephyr_lightning() * storm
         * LIGHTNING_INTENSITY * 0.55;
#endif
    return max(sky, vec3(0.0));
}

// M28 ---------------------------------------------------------------------
// Vanilla sun/moon/stars are discarded by gbuffers_sky*, so the analytic
// atmosphere alone left the night sky pitch black. Everything here is derived
// from the WORLD ray direction (never screen pixels), so TAA jitter cannot
// make the stars jump between cells; soft round points let the history
// converge. Only deferred's sky branch calls this - fog, clouds and water
// reflections keep using zephyr_atmosphere and therefore never get fake stars.
vec2 zephyr_starPlane(vec3 rd) {
    // BSL-style hemisphere projection: no pole pinching, stable under camera
    // rotation. Denominator never vanishes for rd.y >= 0.
    return rd.xz / max(rd.y + length(rd.xz), 1e-3);
}

vec3 zephyr_nightSky(vec3 rd, vec3 sunDir, float dayAmount, float rain) {
    float twilight = zephyr_twilight(sunDir.y);
    // M28: rain should soften the night sky, not erase it. The old 0.92
    // factor left only 8% during a storm, which with the analytic atmosphere
    // read as pure black. Clouds are drawn by composite.fsh on top anyway, so
    // they still occlude stars/moon naturally.
    float vis = (1.0 - dayAmount) * (1.0 - twilight * 0.75)
              * (1.0 - rain * 0.35);
    if (vis < 0.001 || rd.y < -0.02) return vec3(0.0);

    float h = clamp(rd.y, 0.0, 1.0);
    vec3 sky = mix(NIGHT_SKY_HORIZON, NIGHT_SKY_ZENITH, pow(h, 0.55));
    // Faint warm light pollution near the horizon, so the skyline is not a
    // flat black cut-out against the buildings.
    sky += NIGHT_SKY_GLOW * pow(1.0 - h, 6.0);

    // --- stars -----------------------------------------------------------
    vec2 g = zephyr_starPlane(rd) * STAR_GRID;
    vec2 id = floor(g);
    vec2 f = fract(g) - 0.5;
    float r1 = zephyr_hash12(id);
    float r2 = zephyr_hash12(id + 17.3);
    float r3 = zephyr_hash12(id + 91.7);
    float density = r1 * r2 * r3;
    if (density > STAR_SPARSE) {
        vec2 off = (vec2(r2, r3) - 0.5) * 0.60;
        float d = length(f - off);
        float bright = (density - STAR_SPARSE) / (1.0 - STAR_SPARSE);
        float s = smoothstep(STAR_SIZE, 0.0, d) * (0.35 + 0.65 * bright);
        vec3 tint = mix(vec3(1.00, 0.82, 0.66), vec3(0.72, 0.85, 1.00), r1);
        sky += tint * s * STAR_BRIGHTNESS * pow(h, 0.25);
    }

    // --- moon ------------------------------------------------------------
    // MC's moon sits opposite the sun. Deriving it from sunDir avoids relying
    // on a moonPosition uniform that some Iris builds leave unbound.
    vec3 moonDir = -normalize(sunDir);
    if (moonDir.y > 0.0) {
        float ang = acos(clamp(dot(rd, moonDir), -1.0, 1.0));
        float disk = 1.0 - smoothstep(MOON_RADIUS * 0.90, MOON_RADIUS, ang);
        if (disk > 0.0) {
            vec3 mRight = normalize(cross(vec3(0.0, 1.0, 0.0), moonDir));
            vec3 mUp = cross(moonDir, mRight);
            vec2 muv = vec2(dot(rd, mRight), dot(rd, mUp)) / MOON_RADIUS;
            // A shadow disc slides across the lit one: phase 0 = full moon,
            // phase 4 = new moon, in between = crescent/gibbous.
            float ph = float(moonPhase) / 8.0;
            float shadowOffset = 2.2 * (1.0 - 2.0 * ph);
            float shadow = 1.0 - smoothstep(0.98, 1.02,
                            length(muv - vec2(shadowOffset, 0.0)));
            float lit = clamp(1.0 - shadow * 0.92, 0.08, 1.0);
            float craters = 1.0 - 0.28 * zephyr_valueNoise(muv * 3.7 + 4.2);
            sky += MOON_COLOR * disk * lit * craters * MOON_BRIGHTNESS;
        }
        // Soft halo around the moon, kept dim so it does not wash the stars.
        sky += MOON_HALO_COLOR
             * pow(max(dot(rd, moonDir), 0.0), 420.0) * MOON_HALO_STRENGTH;
    }
    return max(sky, vec3(0.0)) * vis * NIGHT_SKY_STRENGTH;
}
// -------------------------------------------------------------------------

// M33 ---------------------------------------------------------------------
// Suspended motes. The grid is anchored in WORLD space and NEVER moves with
// time: a drifting grid re-rolled hash cells as the player swam (M33
// flicker). Only the particle centre breathes with smooth sines. The
// footprint is measured in the plane PERPENDICULAR to the view ray, because
// a 3D sphere test is almost never hit by discrete raymarch samples (M32).
float zephyr_waterMote(vec3 p, vec3 rd) {
    vec3 q = p / WATER_PARTICLE_GRID;
    vec3 id = floor(q);
    float h = zephyr_hash12(id.xy + vec2(id.z * 37.0, id.z * 17.0));
    if (h > WATER_PARTICLE_DENSITY) return 0.0;
    float h2 = zephyr_hash12(id.xy + vec2(id.z * 11.0 + 5.3,
                                          id.z * 3.7));
    float h3 = zephyr_hash12(id.xy + vec2(id.z * 7.1,
                                          id.z * 23.0 + 9.1));
    vec3 offset = (vec3(h, h2, h3) - 0.5) * 0.60;
    float t = frameTimeCounter;
    offset += 0.06 * vec3(sin(t * 0.31 + h  * 6.2831),
                          sin(t * 0.23 + h2 * 6.2831),
                          sin(t * 0.19 + h3 * 6.2831));
    vec3 d3 = fract(q) - 0.5 - offset;
    vec3 perp = d3 - rd * dot(d3, rd);
    float m = smoothstep(WATER_PARTICLE_SIZE, 0.0, length(perp));
    return m * m;
}

// Procedural caustics: two counter-drifting value-noise layers ridged into a
// thin bright net. Same structure as BSL shadow.glsl / photon
// water_fog_vl.glsl, but fully analytic so no noise texture is needed.
float zephyr_caustics(vec3 p, float t) {
    vec2 uv = p.xz - p.y * 0.14;
    vec2 d0 = vec2(0.88, 0.48);
    vec2 d1 = vec2(-0.42, 0.91);
    float a = zephyr_valueNoise((uv + d0 * t) * CAUSTICS_SCALE);
    float b = zephyr_valueNoise((uv + d1 * t * 0.73)
                                * CAUSTICS_SCALE * 1.9);
    float ridge = (1.0 - abs(a * 2.0 - 1.0))
                * (1.0 - abs(b * 2.0 - 1.0));
    return pow(clamp(ridge, 0.0, 1.0), CAUSTICS_SHARPNESS);
}
// -------------------------------------------------------------------------

vec3 zephyr_aces(vec3 x) {
    x = max(x * 0.6, vec3(0.0));
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

// AgX-inspired display transform, derived for GLSL 330 (no inverse(), no LUT).
//   1. rotate linear RGB into XYZ/D65 with the public colour-science constants
//   2. encode open-domain radiance into a normalised log2 range
//   3. apply an adjustable toe/shoulder S-curve (soft highlight shoulder)
//   4. desaturate very bright colours towards white, avoiding ACES hue skew
//   5. rotate back to sRGB primaries; the caller applies the sRGB OETF
vec3 zephyr_agx(vec3 x) {
    x = max(x, vec3(0.0));
    float l = max(zephyr_luma(x), 1e-6);

    // The curve runs on luminance only, then RGB is scaled by the same factor.
    // A per-channel log curve visibly greys the image (measured: saturation
    // 61.4 -> 35.9), while this keeps hue and saturation intact.
    float logv = log2(l / 0.18);
    float t = clamp((logv - AGX_MIN_EV) / (AGX_MAX_EV - AGX_MIN_EV), 0.0, 1.0);

    // Both halves meet exactly at middle grey, anchoring the display transform
    // to the same 0.18 reference as ACES instead of lifting shadows into grey.
    float pivotIn = clamp((0.0 - AGX_MIN_EV) / (AGX_MAX_EV - AGX_MIN_EV), 0.01, 0.99);
    float shaped = t < pivotIn
        ? AGX_MIDDLE_OUT * pow(t / pivotIn, AGX_TOE_POWER)
        : 1.0 - (1.0 - AGX_MIDDLE_OUT)
              * pow(max((1.0 - t) / (1.0 - pivotIn), 0.0), AGX_SHOULDER_POWER);
    float mappedL = shaped * AGX_GAIN;

    vec3 outLin = x * (mappedL / l);

    // AgX-style "path to white": only genuinely bright pixels desaturate.
    float peak = max(max(x.r, x.g), x.b);
    float desat = smoothstep(AGX_DESAT_START, AGX_DESAT_END, peak);
    outLin = mix(outLin, vec3(mappedL), desat * AGX_DESAT_AMOUNT);

    // Soft roll-off above display white instead of a hard clamp.
    return outLin / (1.0 + max(outLin - 1.0, vec3(0.0)) * AGX_ROLLOFF);
}

vec3 zephyr_tonemap(vec3 x) {
#if TONEMAP_MODE == 1
    return zephyr_agx(x);
#else
    return zephyr_aces(x);
#endif
}
