# Changelog

## v0.1 — Cinematic layer（2026-11-05）

首个可运行版本：在 **Photon Shaders 1.2a**（SixthSurge）基础上加入 Zephyr 电影感层。

### 新增

- `shaders/include/post_processing/zephyr_cinematic.glsl`
  - `zephyr_pre_tonemap()`：高光加暖（琥珀色）、极亮高光预压缩/去饱和
  - `zephyr_post_tonemap()`：青橙分离色调、胶片 S 曲线、黑位抬升 + 暗部去饱和、自然饱和度、高光肩部去饱和
  - `zephyr_letterbox()`：2.35:1 电影黑边
  - `zephyr_apply_grain()`：亮度加权的动态胶片颗粒
- 管线挂载：`program/c14_color_grading.fsh`、`program/final.fsh`
- 设置项（游戏内「后处理 → Zephyr Cinematic」）：
  `ZEPHYR_CINEMATIC / STRENGTH / FILM_CURVE / BLACK_LIFT / HIGHLIGHT_ROLLOFF / SPLIT_STRENGTH / WARMTH / VIBRANCE / GRAIN / LETTERBOX / LETTERBOX_RATIO`
- `profile.cinematic` 预设：DOF + 动态模糊 + 更高泛光/暗角 + 强度 1.0
- 中英文标签（`lang/en_US.lang`、`lang/zh_CN.lang`）
- 默认观感调校（按参考图）：
  - `GRADE_WHITE_BALANCE 6500 → 6300`
  - `GRADE_CONTRAST 1.00 → 1.04`、`GRADE_SATURATION 1.00 → 1.03`
  - `GRADE_ORANGE_SAT_BOOST 0.00 → 0.06`、`GRADE_TEAL_SAT_BOOST 0.10 → 0.14`
  - `BLOOM_INTENSITY 1.00 → 1.30`、`VIGNETTE_INTENSITY 1.00 → 1.25`
  - `AIR_FOG_MIE_DENSITY_EVENING 0.0050 → 0.0080`、`_RAIN 0.030 → 0.038`

### 修复（Photon 1.2a 遗留，Iris 1.8.8 会警告）

- `shaders.properties` 中失效的选项引用（实机日志中的 `Invalid pack option` / `Unable to resolve shader pack option menu element`）：
  - profile 中的 `GTAO` / `!GTAO` → `SHADER_AO=SHADER_AO_GTAO` / `SHADER_AO=SHADER_AO_NONE`
  - `WATER_REFRACTION` / `WATER_REFRACTION_INTENSITY` → `REFRACTION` / `REFRACTION_INTENSITY`
  - 移除已不存在的 `CLOUDS_DAILY_WEATHER`
  - `CLOUDS_CUMULUS_CONGESTUS_PRIMARY_STEPS_H/_Z` → `CLOUDS_CUMULUS_CONGESTUS_PRIMARY_STEPS`
- 修复后 `shaders.properties` 的未知选项引用数：**0**

### 工具

- `tools/validate_glsl.py`：离线 GLSL 校验（moderngl + PyOpenGL 真实驱动编译；Iris 宏注入 + `#include` 解析 + `shaders.properties` 启用条件）
- `tools/mc-test.ps1`：MC 启动 → 进存档 → 自动截图 → 抓 Iris 日志
- 文档：`README.md`、`docs/look-dev.md`、`NOTICE.md`

### 验证

- 离线：`209/209` 个光影程序入口编译通过（62 个被光影自身禁用的 pass 跳过，0 失败）
- 实机：见 `reports/launch-report.md`（由实机验证流程生成）

### 已知限制

- 没有夜间/蓝调专用预设（v0.3 计划）
- 泛光仍是各向同性，霓虹横向 streak 未做（v0.2 计划）
- 湿地面反射沿用 Photon 的 SSR + 雨坑系统，尚未加雨纹法线扰动（v0.2 计划）
- Distant Horizons 未安装，`dh_*` 程序未纳入离线校验
