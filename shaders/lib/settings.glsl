// Zephyr Z1 feature parameters.
// Naming rule (D4): <module>_<parameter>.
// M29: the shader options exposed in shaders.properties ARE these macro names.
// The loader injects the selected value as a #define before compiling, so any
// option listed in a `screen`/`sliders` line may be overridden at runtime.
#include "/settings.glsl"

#define ATMOSPHERE_DENSITY        1.00 //[0 0.1 0.25 0.5 0.75 1 1.5 2]
#define ATMOSPHERE_MIE_G          0.76
#define ATMOSPHERE_SUN_INTENSITY  1.00

// M28: procedural night sky. gbuffers_sky* discard vanilla sun/moon/stars, so
// the night sky was pure black. This layer is added ONLY on sky pixels in
// deferred (fog / water reflections keep using zephyr_atmosphere alone).
#define NIGHT_SKY_ENABLED          1 //[0 1]
// M28: 1.00 was invisible after AgX; 2.00 reads as a deep blue night sky.
#define NIGHT_SKY_STRENGTH         2.00 //[0 0.1 0.25 0.5 0.75 1 2 3 4]
#define NIGHT_SKY_ZENITH           vec3(0.020, 0.034, 0.078)
#define NIGHT_SKY_HORIZON          vec3(0.048, 0.062, 0.110)
#define NIGHT_SKY_GLOW             vec3(0.060, 0.038, 0.022)
// Stars: quantised world-direction grid, one soft (TAA-stable) point per cell.
#define STAR_GRID                  220.0
#define STAR_SPARSE                0.80
#define STAR_SIZE                  0.32
#define STAR_BRIGHTNESS            2.40 //[0 0.1 0.25 0.5 0.75 1 1.2 2.4 3.6 4.8]
// Moon: angular radius in radians, phase from Iris moonPhase (0..7).
#define MOON_RADIUS                0.035
#define MOON_BRIGHTNESS            2.20 //[0 0.1 0.25 0.5 0.75 1 1.1 2.2 3.3 4.4]
#define MOON_COLOR                 vec3(0.92, 0.95, 1.00)
#define MOON_HALO_STRENGTH         0.35 //[0 0.1 0.175 0.25 0.35 0.5 0.525 0.7 0.75 1]
#define MOON_HALO_COLOR            vec3(0.55, 0.68, 1.00)

#define LIGHT_SUN_INTENSITY       3.20 //[0 0.1 0.25 0.5 0.75 1 1.6 3.2 4.8 6.4]
#define LIGHT_SKY_INTENSITY       0.85 //[0 0.1 0.25 0.425 0.5 0.75 0.85 1 1.275 1.7]
#define LIGHT_EMISSIVE_SCALE      1.60

#define SHADOW_ENABLED            1 //[0 1]
// Iris 1.8.8 actually binds shadowtex0 at 1024x1024 / 160 m here (F3), and
// ignores shadowMapResolution/shadowDistance in shaders.properties. At that
// texel density 1 texel ~= 0.31 m, so keep the disk well under one texel.
#define SHADOW_SOFTNESS           0.60 //[0 0.1 0.25 0.3 0.5 0.6 0.75 0.9 1 1.2]
#define SHADOW_PCF_SAMPLES        6
#define SHADOW_BIAS               0.00035
#define SHADOW_NORMAL_OFFSET      0.035
#define SHADOW_EDGE_FADE          0.88
// shadowtex0 = all casters, shadowtex1 = opaque only. Their difference
// isolates translucent-only occluders (glass, water, foliage).
#define TRANSLUCENT_SHADOW_LIFT   0.60
// M12 coloured shadows. 0 = the flat M11 lift above with no colour,
// 1 = fully coloured by the caster's shadowcolor0 albedo.
#define SHADOW_COLOR_STRENGTH     0.90 //[0 0.1 0.25 0.45 0.5 0.75 0.9 1 1.35 1.8]
// M17: floor under the alpha of stained glass; keeps the pane visible where
// the vanilla texture is alpha~0. The mask now lives in colortex8.a.
#define TRANSLUCENT_MIN_ALPHA      0.55
// Strength of the subtractive glass filter (composite.fsh, BEFORE fog and
// TAA). May exceed 1: the mix weight is clamped, and fog later washes part of
// it away. Transmittance only ATTENUATES channels, so this stays safe.
#define TRANSLUCENT_TINT_STRENGTH  1.50 //[0 0.1 0.25 0.5 0.75 1 1.5 2.25 3]
// Glass absorption saturation (0 = clear, 1 = fully coloured filter).
#define GLASS_ABSORPTION           0.95 //[0 0.1 0.25 0.475 0.5 0.75 0.95 1 1.425 1.9]
// Cool Fresnel reflection on grazing glass surfaces (no dFdx: TAA-safe).
#define GLASS_RIM_STRENGTH         0.30
// M20: white / black stained glass and tinted glass are low-saturation
// cases; without explicit density they read as clear air. Absorption is
// applied per material ID in gbuffers_water before colour reaches colortex8.
// M23: the old values were too weak - the additive neutral reflection below
// cancelled most of the subtractive tint, so white panes were still invisible.
#define GLASS_MIN_ABSORB           0.16
#define GLASS_WHITE_ABSORB         0.50
#define GLASS_BLACK_ABSORB         0.55
#define GLASS_TINTED_ABSORB        0.65
// M23: keep only a small all-over reflection (it would otherwise erase the
// tint again) and move the visible surface cue to the PANE EDGES, sampled
// from colortex8 in buffer space so it stays TAA-stable (no dFdx).
#define GLASS_NEUTRAL_REFLECT      0.06
#define GLASS_EDGE_STRENGTH        1.80 //[0 0.1 0.25 0.5 0.75 0.9 1 1.8 2.7 3.6]
#define GLASS_EDGE_GAIN            6.0
// M23: neutral frosted veil for colourless panes. An additive glow only made
// them brighter (= still invisible); desaturating + gently darkening the
// scene behind gives a readable surface without hiding the fog/silhouette.
#define GLASS_NEUTRAL_VEIL         0.60 //[0 0.1 0.25 0.3 0.5 0.6 0.75 0.9 1 1.2]

// M22: dynamic held-item light (torch / lantern / glowstone ...). Iris reports
// the held block-light level; treat it as a warm point light just above the
// camera so nearby geometry AND the player's hand are lit by it.
#define HAND_LIGHT_ENABLED         1 //[0 1]
#define HAND_LIGHT_INTENSITY       2.20 //[0 0.1 0.25 0.5 0.75 1 1.1 2.2 3.3 4.4]
#define HAND_LIGHT_RADIUS          9.00
#define HAND_LIGHT_HEIGHT          0.60
// M27: neutral white. The old fixed torch-orange made a held SEA LANTERN look
// yellow and lit the street orange, while the same block placed on the ground
// is cyan-white. heldItemId is NOT 44000+index on this Iris build (probed 0),
// so we cannot key the colour off item ids; neutral keeps every held emitter
// consistent with its placed counterpart.
#define HAND_LIGHT_COLOR           vec3(1.00, 0.98, 0.95)
// M27: held emitters keep their OWN texture colour instead of being tinted by
// the point light they cast.
#define HAND_EMITTER_GAIN          1.60
// M27: cap emissive HDR. writeEmissive already multiplies by 2.6 and the old
// lightmap boost stacked another 2.2x on top, so a placed sea lantern hit ~7
// in linear HDR and produced an absurdly large bloom halo.
#define EMISSIVE_HDR_CAP           1.60 //[0 0.1 0.25 0.5 0.75 0.8 1 1.6 2.4 3.2]
// M23: a held torch must cross BLOOM_THRESHOLD to cast a halo, not merely
// look a bit brighter. This is an HDR radiance gain, not an LDR colour tweak.
#define HAND_EMISSIVE_GAIN         2.20
// Coverage floor for a held translucent item in the colortex8 glass layer.
// M23: 0.45 left tintWeight too low for white panes (0.675); 0.60 -> 0.90.
#define HAND_GLASS_MIN_ALPHA       0.60
// M23: HDR gain for world light sources tagged block.12000. Their linear
// albedo is ~0.3..0.7, so this is what lifts them above BLOOM_THRESHOLD.
#define EMISSIVE_BLOCK_GAIN        2.60

#define FOLIAGE_TRANSLUCENCY      0.45

// M30 - thin-leaf subsurface transmission ("lush foliage").
// Real leaves are thin laminae: light entering the back is scattered forward
// toward the viewer, and chlorophyll absorbs red/blue so the transmitted light
// is saturated yellow-green, not white. Reference models: BSL
// forwardLighting.glsl (pow(VoL,16) forward peak + wrapped NoL) and
// Complementary leaves.glsl (green-channel-driven leaf highlight).
#define LEAF_SSS_ENABLED           1 //[0 1]
#define LEAF_TRANSMISSION          0.95 //[0 0.25 0.5 0.75 0.95 1.25 1.5]
#define LEAF_VITALITY              0.35 //[0 0.1 0.2 0.35 0.5 0.75 1.0]
#define LEAF_FORWARD_POWER        12.0
#define LEAF_FORWARD_GAIN          1.40
#define LEAF_WRAP                  0.55
// Chlorophyll transmittance: green passes, red/blue are absorbed.
#define LEAF_CHLOROPHYLL           vec3(0.46, 1.00, 0.30)
#define LEAF_SPECTRAL_MIX          0.55
#define LEAF_SPECULAR              0.30
#define LEAF_SPEC_POWER            42.0
#define LEAF_RAIN_DAMPEN           0.35
#define AO_ENABLED                1 //[0 1]
#define AO_STRENGTH               0.35 //[0 0.1 0.175 0.25 0.35 0.5 0.525 0.7 0.75 1]
#define AO_SAMPLES                6
#define AO_RADIUS                 1.6

#define CLOUD_ENABLED             1 //[0 1]
#define CLOUD_COVERAGE            0.55 //[0 0.1 0.25 0.275 0.5 0.55 0.75 0.825 1 1.1]
#define CLOUD_STEPS               8
#define CLOUD_ALTITUDE          168.0
#define CLOUD_THICKNESS          48.0
#define CLOUD_DENSITY             1.00 //[0 0.1 0.25 0.5 0.75 1 1.5 2]
#define CLOUD_EXTINCTION          0.020
#define CLOUD_SUN_STEPS           3

#define FOG_DENSITY               0.0042 //[0 0.0021 0.0042 0.0063 0.0084 0.1 0.25 0.5 0.75 1]
#define FOG_HEIGHT_FALLOFF        0.026
#define FOG_INSCATTER_BOOST       1.25

#define VL_ENABLED                1 //[0 1]
#define VL_STEPS                 16
#define VL_MAX_DISTANCE          96.0
#define VL_INTENSITY              1.10
#define VL_DECAY                  0.94
#define VL_SHADOW_SOFTNESS        0.0010

#define WATER_ABSORPTION          0.36
#define WATER_F0                  0.02

// M31 - water volume: Beer-Lambert spectral absorption + underwater fog.
// Red is absorbed fastest, so depth/slant path turns the body cyan-green
// instead of merely making a flat tint darker.
#define WATER_VOLUME_ENABLED       1 //[0 1]
#define WATER_ABSORB_RGB           vec3(0.52, 0.16, 0.10)
#define WATER_SCATTER_RGB          vec3(0.10, 0.42, 0.48)
#define WATER_SURFACE_PATH         0.80
#define WATER_FOG_DENSITY          0.10 //[0 0.03 0.06 0.10 0.14 0.2 0.3 0.45]
#define WATER_INSCATTER            0.85
// M31 - suspended motes. A fixed WORLD-space grid with continuous drift is
// TAA-stable: TAA jitter cannot re-roll the points each frame.
// M32 (real underwater tuning): SIZE is in NORMALISED CELL units, and the
// raymarch only takes STEPS discrete samples. The hit probability of one 3D
// sphere is ~(4/3)*PI*SIZE^3, so SIZE=0.035 made motes effectively invisible
// (all "particle A/B" deltas were just wave animation / TAA noise), while
// SIZE=0.42 with GRID=1.35 turned them into big blurry blobs. Physical mote
// radius = SIZE * GRID = 0.24 * 0.55 ~= 0.13 m: small discrete points.
#define WATER_PARTICLE_ENABLED     1 //[0 1]
#define WATER_PARTICLE_DENSITY     0.16 //[0 0.06 0.10 0.16 0.22 0.30 0.45]
#define WATER_PARTICLE_GRID        0.55
#define WATER_PARTICLE_SIZE        0.24
#define WATER_PARTICLE_STEPS       8
#define WATER_PARTICLE_RANGE       14.0
#define WATER_PARTICLE_SPEED       0.045
#define WATER_PARTICLE_BRIGHTNESS  1.60 //[0 0.4 0.85 1.3 1.6 2.0 2.5]
#define WATER_PARTICLE_COLOR       vec3(0.72, 0.92, 1.00)
#define SSR_ENABLED               1 //[0 1]
#define SSR_STEPS                16
#define SSR_STEP_LENGTH           1.50
#define SSR_THICKNESS             6.00
#define SSR_STRENGTH              0.75

// M23: 1.05 excluded almost every in-world lamp (their lit albedo stays well
// below 1 in linear HDR). Lower the knee so ALL light sources bloom; the sky
// is masked separately in composite1.fsh so this does NOT wash out the frame.
// Tagged emitters get an extra HDR lift from EMISSIVE_BLOCK_GAIN.
#define BLOOM_STRENGTH            0.95 //[0 0.1 0.25 0.475 0.5 0.75 0.95 1 1.425 1.9]
#define BLOOM_THRESHOLD           0.70 //[0 0.1 0.25 0.35 0.5 0.7 0.75 1 1.05 1.4]
#define BLOOM_SKY_ATTENUATION     0.12
// M23: generic light-source lift that does NOT depend on a block ID list. A
// block's own lightmap block-light channel is ~1 only on the emitter and its
// immediate neighbours, so a high power isolates emitters without lighting
// every nearby wall. This lifts small lamps above the bloom mip threshold.
#define EMISSIVE_LIGHTMAP_GAIN     2.20
#define EMISSIVE_LIGHTMAP_POW      8.0
// M25: widen the halo. BLOOM_RADIUS scales the mip level of each tap, so a
// larger value samples a bigger neighbourhood. BLOOM_HALO_BOOST re-weights
// the outer taps; composite1 normalises by weightSum, so the bright CORE does
// not get brighter - only the ring around it spreads further out.
#define BLOOM_RADIUS              1.90
#define BLOOM_HALO_BOOST          1.60
// M25: a wide mip averages a bright lamp down to a dim value, so the outer
// taps need a LOWER threshold than the sharp core. Without this they contribute
// ~0 and widening the radius only dilutes the core (measured changed>5
// 6.61% -> 5.36%). 0.45 => outermost tap threshold = 0.45 * BLOOM_THRESHOLD.
#define BLOOM_HALO_THRESHOLD_SCALE 0.45
#define BLOOM_TAPS                 5
#define BLOOM_KNEE                 0.50
// M25: dedicated WIDE halo, additive and outside the normalised tight bloom.
// A high mip spreads each lamp over a large radius; because it is not divided
// by weightSum, making the ring bigger never dilutes the bright core.
#define BLOOM_HALO_LOD             7.0
#define BLOOM_HALO_STRENGTH        0.35 //[0 0.1 0.175 0.25 0.35 0.5 0.525 0.7 0.75 1]
#define BLOOM_HALO_FLOOR           0.18

// M6 display transform. 0 = ACES (A/B baseline), 1 = AgX-inspired log tonemap.
#define TONEMAP_MODE               1 //[0 1]
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
#define TAA_ENABLED                1 //[0 1]
// Near-field history weight. Velocity/depth rejection drops it when the
// camera moves so the M8 "fast turn ghosting" stays under control.
// M18: raising the GLOBAL blend made the weight itself oscillate with the
// jitter phase; instead composite2 ramps the weight up with linear depth.
#define TAA_BLEND                  0.82
#define TAA_VELOCITY_REJECT        0.010
// Far geometry has almost no screen-space parallax, so it can keep ~97% of
// history and converge on high-contrast edges without visible ghosting.
#define TAA_FAR_START              24.0
#define TAA_FAR_END                96.0
#define TAA_FAR_BLEND              0.97
#define TAA_DEPTH_REJECT           0.60
#define TAA_NEIGHBOUR_CLAMP        1
// M19: a 0.05 floor meant a single bad depth rejection threw away 95% of the
// history - exactly on distant high-contrast edges. Complementary's
// blendMinimum is 0.35; keep at least that much history at all times.
#define TAA_MIN_BLEND              0.35 //[0 0.1 0.175 0.25 0.35 0.5 0.525 0.7 0.75 1]
// M20: subtract animated-geometry velocity from the reprojected history UV.
// 0 reverts to pure depth reprojection (A/B switch).
#define TAA_WAVE_VELOCITY          1
// M19: cutout foliage is animated, so a long history stacks several instants
// of the leaves and shows up as coloured speckle. Complementary uses a
// "Reduced Edge TAA" material for exactly this; we shorten the history on
// pixels whose colortex2.a says "thin surface" instead.
#define TAA_FOLIAGE_WEIGHT         1.0
#define TAA_DEBUG_HISTORY          0
#define TAA_JITTER_ENABLED         1
#define TAA_JITTER_PHASES         16
// M19: 0.60px jitter amplitude. Reprojection no longer injects jitter into
// prevUv, so the remaining per-frame excursion is resolved by history
// accumulation instead of becoming a moving sample offset. Keeping it below
// one pixel still limits distant high-contrast edge crawling.
#define TAA_JITTER_SCALE           0.20 //[0 0.1 0.2 0.25 0.3 0.4 0.5 0.75 1]

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
    return h * (2.0 / vec2(width, height)) * TAA_JITTER_SCALE;
#else
    return vec2(0.0);
#endif
}

#define EXPOSURE_EV               0.00 //[0 0.1 0.25 0.5 0.75 1]
#define EXPOSURE_TARGET           0.22
#define EXPOSURE_ADAPT_SPEED      0.06
#define TONEMAP_EXPOSURE_BIAS     1.00
#define GRADE_SATURATION          1.22 //[0 0.1 0.25 0.5 0.61 0.75 1 1.22 1.83 2.44]
#define GRADE_CONTRAST            1.04 //[0 0.1 0.25 0.5 0.52 0.75 1 1.04 1.56 2.08]

// F12 weather layer: storm cloud deck, puddles, rain bloom, lightning
#define STORM_CLOUD_ALTITUDE      118.0
#define STORM_CLOUD_THICKNESS      76.0
#define STORM_CLOUD_FREQ           0.0021
#define STORM_CLOUD_COVERAGE       0.34 //[0 0.1 0.17 0.25 0.34 0.5 0.51 0.68 0.75 1]
#define STORM_CLOUD_DENSITY        1.30
#define STORM_CLOUD_EXTINCTION     0.026
#define STORM_CLOUD_SUN_ABSORB     2.40

#define PUDDLE_ENABLED             1 //[0 1]
#define PUDDLE_COVERAGE            0.56
#define PUDDLE_FREQ_FINE           0.42
#define PUDDLE_FREQ_COARSE         0.11
#define PUDDLE_ROUGHNESS           0.045
#define PUDDLE_STRENGTH            0.60 //[0 0.1 0.25 0.3 0.5 0.6 0.75 0.9 1 1.2]
#define PUDDLE_RIPPLE              0.025 //[0 0.0125 0.025 0.0375 0.05 0.1 0.25 0.5 0.75 1]

#define RAIN_BLOOM_BOOST           0.90 //[0 0.1 0.25 0.45 0.5 0.75 0.9 1 1.35 1.8]
#define LIGHTNING_ENABLED          1 //[0 1]
#define LIGHTNING_INTENSITY        1.30 //[0 0.1 0.25 0.5 0.65 0.75 1 1.3 1.95 2.6]

// Storm-night polish: bounce light, bounded exposure lift, fog distance shaping
#define STORM_NIGHT_BOUNCE         0.075
#define RAIN_NIGHT_EV              0.55

// M10 night balance: moonlight is weak, so its shadows should be soft and
// shallow, while sky glow / city bounce must keep shadowed geometry readable.
#define NIGHT_SHADOW_MIN           0.30
#define NIGHT_AO_RELAX             0.50
#define NIGHT_AMBIENT_FLOOR        0.050 //[0 0.025 0.05 0.075 0.1 0.25 0.5 0.75 1]
#define NIGHT_BLACK_LIFT           0.018

// M11 vertex waving for plants / leaves (category IDs come from block.properties)
#define WAVE_ENABLED               1 //[0 1]
#define WAVE_SPEED                 1.30
#define WAVE_AMPLITUDE             0.08 //[0 0.04 0.08 0.1 0.12 0.16 0.25 0.5 0.75 1]
// M20: rain multiplies the clear-sky amplitude by (1 + WAVE_RAIN_BOOST).
// M21: a full storm sways at (1 + 1.25) = 2.25x the clear-sky amplitude.
// Clear weather is untouched (rainStrength=0).
// Verified in-game with a 20.0 probe: foliage silhouette visibly changes.
#define WAVE_RAIN_BOOST            1.25 //[0 0.1 0.25 0.5 0.625 0.75 1 1.25 1.875 2.5]
// Iris does not reliably expose frameTime to gbuffer programs; when it reads 0
// the previous-frame wave phase would equal the current one and the velocity
// would silently be zero. Fall back to a nominal 60 Hz step.
#define WAVE_FRAME_DT              0.016667
// M19: distant leaves are sub-pixel; slow their TIME frequency instead of
// fading the wave out, so TAA can accumulate while sway stays visible.
#define WAVE_SLOW_START            32.0
#define WAVE_SLOW_END              112.0
#define WAVE_FAR_TIME_SCALE        0.20
// M19: waving is active at EVERY distance again. M18's 4->22 block fade was
// a workaround for distant shimmer whose real cause was a broken TAA
// reprojection (prevUv drifted with the jitter phase); it silently removed
// foliage motion from the whole scene. Complementary / EuphoriaPatches / BSL
// all wave at full range with a small amplitude and rely on a converged TAA.
// Kept as a tunable knob, defaulted outside the visible world.
#define WAVE_FADE_START            40.0
#define WAVE_FADE_END              96.0
// 1 = lift every ID-matched vertex by one block, to verify the ID map end to
// end without relying on the (small) wind amplitude. Keep 0 for normal play.
#define WAVE_DEBUG_LIFT            0

// M11 lightweight albedo-driven parallax (no height map required)
#define POM_ENABLED                1 //[0 1]
// Atlas-UV space displacement, disabled by default. On Iris 1.8.8 the tile
// window derived from mc_midTexCoord is too narrow, so ANY non-zero value
// re-arranges the block texture instead of adding subtle relief (verified over
// 0.0008 / 0.0035 / 0.05 in z11_pom_*). The tile-clamped code stays available
// as an experimental path; the shipped surface relief comes from
// zephyr_parallaxNormal(), which never moves UVs. See 06-eval.md M11.
#define POM_DEPTH                  0
#define POM_BUMP                   1.20
#define RAIN_DAY_EV                0.30
#define RAIN_FOG_DIST_POW          0.92 //[0 0.1 0.25 0.46 0.5 0.75 0.92 1 1.38 1.84]
#define RAIN_GRADE_CONTRAST        0.05
