// Zephyr Z1 feature parameters.
// Naming rule (D4): <module>_<parameter>. No quality presets at this stage.
#include "/settings.glsl"

#define ATMOSPHERE_DENSITY        1.00
#define ATMOSPHERE_MIE_G          0.76
#define ATMOSPHERE_SUN_INTENSITY  1.00

#define LIGHT_SUN_INTENSITY       3.20
#define LIGHT_SKY_INTENSITY       0.85
#define LIGHT_EMISSIVE_SCALE      1.60

#define SHADOW_ENABLED            1
// Iris 1.8.8 actually binds shadowtex0 at 1024x1024 / 160 m here (F3), and
// ignores shadowMapResolution/shadowDistance in shaders.properties. At that
// texel density 1 texel ~= 0.31 m, so keep the disk well under one texel.
#define SHADOW_SOFTNESS           0.60
#define SHADOW_PCF_SAMPLES        6
#define SHADOW_BIAS               0.00035
#define SHADOW_NORMAL_OFFSET      0.035
#define SHADOW_EDGE_FADE          0.88

#define FOLIAGE_TRANSLUCENCY      0.45
#define AO_ENABLED                1
#define AO_STRENGTH               0.35
#define AO_SAMPLES                6
#define AO_RADIUS                 1.6

#define CLOUD_ENABLED             1
#define CLOUD_COVERAGE            0.55
#define CLOUD_STEPS               8
#define CLOUD_ALTITUDE          168.0
#define CLOUD_THICKNESS          48.0
#define CLOUD_DENSITY             1.00
#define CLOUD_EXTINCTION          0.020
#define CLOUD_SUN_STEPS           3

#define FOG_DENSITY               0.0042
#define FOG_HEIGHT_FALLOFF        0.026
#define FOG_INSCATTER_BOOST       1.25

#define VL_ENABLED                1
#define VL_STEPS                 16
#define VL_MAX_DISTANCE          96.0
#define VL_INTENSITY              1.10
#define VL_DECAY                  0.94

#define WAVE_AMPLITUDE            0.055
#define WATER_ABSORPTION          0.36
#define WATER_F0                  0.02
#define SSR_ENABLED               1
#define SSR_STEPS                16
#define SSR_STEP_LENGTH           1.50
#define SSR_THICKNESS             6.00
#define SSR_STRENGTH              0.75

#define BLOOM_STRENGTH            0.20
#define BLOOM_THRESHOLD           1.05
#define BLOOM_RADIUS              1.00
#define BLOOM_TAPS                 5
#define BLOOM_KNEE                 0.50

// M6 display transform. 0 = ACES (A/B baseline), 1 = AgX-inspired log tonemap.
#define TONEMAP_MODE               1
#define AGX_MIN_EV                -6.0
#define AGX_MAX_EV                 6.0
#define AGX_MIDDLE_OUT             0.12
#define AGX_TOE_POWER              3.00
#define AGX_SHOULDER_POWER         1.50
#define AGX_GAIN                   0.95
#define AGX_ROLLOFF                0.60
#define AGX_DESAT_START            3.00
#define AGX_DESAT_END             12.00
#define AGX_DESAT_AMOUNT           0.45
// AgX has a softer toe/shoulder, so it needs its own grade calibration.
// ACES (TONEMAP_MODE=0) keeps the original values for a fair A/B.
#define AGX_GRADE_SAT              1.10
#define AGX_GRADE_CONTRAST         1.06

// M7 temporal history: AO accumulation on colortex6 (flip.deferred.colortex6)
// Skeleton kept, runtime disabled: measured frame-to-frame RMSE showed no
// denoising gain on Iris 1.8.8 (3.138 vs 2.800; 3.569 vs 3.486 with AO x2.9).
// Fixed spatial jitter above removes the shimmer at the source instead.
#define TEMPORAL_AO_ENABLED        0
#define TEMPORAL_AO_MAX_AGE       10.0
#define TEMPORAL_AO_DEPTH_REJECT   0.45
#define TEMPORAL_AO_VELOCITY       0.020
#define TEMPORAL_AO_CLAMP          0.18

// TAA (composite2, linear HDR before tonemap).
#define TAA_ENABLED                1
#define TAA_BLEND                  0.82
#define TAA_VELOCITY_REJECT        0.010
#define TAA_DEPTH_REJECT           0.60
#define TAA_NEIGHBOUR_CLAMP        1
#define TAA_MIN_BLEND              0.05
#define TAA_DEBUG_HISTORY          0
#define TAA_JITTER_ENABLED         1
#define TAA_JITTER_PHASES         16

// Halton(2,3) sub-pixel jitter. Uniforms are passed in explicitly so this
// header stays independent of uniform declaration order (config -> settings
// -> uniforms -> common in every pass).
float zephyr_halton(int index, int base) {
    float result = 0.0;
    float f = 1.0 / float(base);
    int i = index;
    while (i > 0) {
        int digit = i - (i / base) * base;   // GLSL has no integer % operator
        result += f * float(digit);
        i = i / base;
        f /= float(base);
    }
    return result;
}

vec2 zephyr_taaJitterNDC(int frame, float width, float height) {
#if TAA_JITTER_ENABLED
    int phase = frame - (frame / TAA_JITTER_PHASES) * TAA_JITTER_PHASES + 1;
    vec2 h = vec2(zephyr_halton(phase, 2), zephyr_halton(phase, 3)) - 0.5;
    return h * (2.0 / vec2(width, height));
#else
    return vec2(0.0);
#endif
}

#define EXPOSURE_EV               0.00
#define EXPOSURE_TARGET           0.22
#define EXPOSURE_ADAPT_SPEED      0.06
#define TONEMAP_EXPOSURE_BIAS     1.00
#define GRADE_SATURATION          1.22
#define GRADE_CONTRAST            1.04

// F12 weather layer: storm cloud deck, puddles, rain bloom, lightning
#define STORM_CLOUD_ALTITUDE      118.0
#define STORM_CLOUD_THICKNESS      76.0
#define STORM_CLOUD_FREQ           0.0021
#define STORM_CLOUD_COVERAGE       0.34
#define STORM_CLOUD_DENSITY        1.30
#define STORM_CLOUD_EXTINCTION     0.026
#define STORM_CLOUD_SUN_ABSORB     2.40

#define PUDDLE_ENABLED             1
#define PUDDLE_COVERAGE            0.56
#define PUDDLE_FREQ_FINE           0.42
#define PUDDLE_FREQ_COARSE         0.11
#define PUDDLE_ROUGHNESS           0.045
#define PUDDLE_STRENGTH            0.60
#define PUDDLE_RIPPLE              0.025

#define RAIN_BLOOM_BOOST           0.90
#define LIGHTNING_ENABLED          1
#define LIGHTNING_INTENSITY        1.30

// Storm-night polish: bounce light, bounded exposure lift, fog distance shaping
#define STORM_NIGHT_BOUNCE         0.075
#define RAIN_NIGHT_EV              0.45
#define RAIN_DAY_EV                0.30
#define RAIN_FOG_DIST_POW          0.92
#define RAIN_GRADE_CONTRAST        0.05
