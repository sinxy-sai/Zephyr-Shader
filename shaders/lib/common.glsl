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

vec3 zephyr_aces(vec3 x) {
    x = max(x * 0.6, vec3(0.0));
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}
