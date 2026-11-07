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
#define SHADOW_SOFTNESS           1.00
#define SHADOW_BIAS               0.0008

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

#define BLOOM_STRENGTH            0.42
#define BLOOM_THRESHOLD           1.05
#define BLOOM_RADIUS              1.00

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
