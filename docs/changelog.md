# Changelog

## v0.2 — 天气自适应与实机迭代（2026-11-05）

在 Weston City V0.3 上用 Iris 的 **R 键重载**做了真实画面迭代（实机截图见 `shots/`）。

### 新增

- **天气自适应调色** `ZEPHYR_WEATHER_ADAPT`（`zephyr_cinematic.glsl`）
  - 雨天/阴天自动：降低对比曲线 28%、黑位额外 +0.014、暗部加冷雾（`vec3(0.86,0.95,1.06)`）、
    自然饱和度 -35%、高光柔化 +0.18 —— 对应参考图里「雨天不发黑、亮部不炸」的观感
  - c14 新增 `rainStrength` uniform 传入调色层
- `tools/mc-ctl.ps1`：对已运行的游戏窗口做聚焦 / 按键 / 聊天命令（剪贴板粘贴绕开输入法）/ F2 截图 / R 重载
- `tools/mc-launch.ps1`：从 PCL 启动命令派生 `--quickPlaySingleplayer` 受控实例

### 调优（实机对比后）

- 湿地面/雨雾：`AIR_FOG_MIE_DENSITY_RAIN 0.038→0.055`、`OVERWORLD_FOG_INTENSITY 1.00→1.10`、
  `BLOOM_INTENSITY 1.30→1.38`、`GRADE_BRIGHTNESS 0.97→1.02`
- 日落去「整屏橙」：`ZEPHYR_WARMTH 0.70→0.15`、`GRADE_ORANGE_SAT_BOOST 0.06→0.02`、
  `GRADE_WHITE_BALANCE 6300→6700`、`AIR_FOG_MIE_DENSITY_EVENING 0.0080→0.0058`

### 验证

- 离线：209/209 入口编译通过（62 个被禁用的 pass 跳过，0 失败）
- 实机：Weston City V0.3 连续多轮 `R` 重载 + F2 截图，无编译错误

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
- `tools/analyze_look.py` + `docs/look-analysis.md`：把参考截图量化（影调/暗部色偏/高光色偏），并离线渲染调色响应曲线与色卡对比（可直接看 Zephyr 层对画面的影响）
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
