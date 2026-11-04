# Zephyr 观感开发手册

这份文档回答两个问题：**「想要某种画面，应该改哪里」** 和 **「改完之后怎么确认没搞坏」**。

---

## 1. 渲染管线与色彩空间（必须先懂这个）

Zephyr 的调色层插在 Photon 的 `c14_color_grading` 里，顺序如下：

```
场景线性色 (working space = Rec.2020, 线性, 可 >1)
  │
  ├─ zephyr_pre_tonemap()      ← Zephyr：高光加暖、极亮高光去饱和
  │
  ├─ grade_input()             ← Photon：亮度 / 对比 / 饱和度 / 白平衡
  ├─ tonemap()                 ← Photon：Lottes 等 tone curve，输出 0~1
  ├─ grade_output()            ← Photon：HSL 分色相调色（橙青绿）
  │
  ├─ zephyr_post_tonemap()     ← Zephyr：分离色调 / 胶片曲线 / 黑位 / 自然饱和度
  │
  ▼
显示线性 Rec.709  ──►  final.fsh：zephyr_letterbox() + zephyr_apply_grain()
                     ──►  sRGB / CAS / dither 输出
```

关键约定：

| 阶段 | 色彩空间 | 亮度权重 | 备注 |
| --- | --- | --- | --- |
| `zephyr_pre_tonemap` | Rec.2020 线性，可 >1 | `luminance_weights`（Rec.2020） | 这里做「物理亮度」相关的判断，比如 `smoothstep(0.35, 3.2, lum)` |
| `zephyr_post_tonemap` | 显示线性 Rec.709，0~1 | `zephyr_luma_709` | 内部先 `sqrt()` 转到准感知空间再调，最后 `sqr()` 回来 |
| `final.fsh` 里的 lens 效果 | sRGB 显示空间 0~1 | `zephyr_luma_709` | 颗粒/黑边在这里，属于「显示器之后」的效果 |

> 记住：**任何在 `post_tonemap` 里写的 0~1 数值都是显示亮度，不是场景亮度。**
> 想改「太阳有多亮」→ 去 Photon 的 `SUN_I`；想改「高光在成片里多白」→ 改 `zephyr_post_tonemap` 的 `shoulder`。

---

## 2. 参数速查：想要 X，改哪里

### 2.1 不需要改代码（游戏内即可）

| 想要的效果 | 游戏内设置 |
| --- | --- |
| 整体更「电影」/更淡 | 后处理 → Zephyr Cinematic → 整体强度 / 胶片曲线 / 黑位抬升 |
| 暗部更青、亮部更暖 | 分离色调（0.4~0.8 之间最稳） |
| 高光不炸、保留细节 | 高光柔化（0.3~0.6） |
| 颜色更「动漫」一点 | 自然饱和度 +0.05~0.15 |
| 截图时的胶片颗粒 | 胶片颗粒 0.2~0.4 |
| 2.35:1 电影黑边 | 电影黑边 = 开，画幅 2.35 |
| 更强的景深/动态模糊 | 顶部 profile 切到 **Cinematic** |
| 一键黄昏 / 雨夜风格 | 顶部 profile 切到 **Sunset** / **Rain Night** |

### 2.2 需要改 `settings.glsl`（零风险、不涉及 GLSL 逻辑）

| 想要的效果 | 参数 | 参考范围 |
| --- | --- | --- |
| 整体更暖/更冷 | `GRADE_WHITE_BALANCE` | 5800（暖）~ 6800（冷） |
| 更「黄昏金」 | `GRADE_ORANGE_SAT_BOOST` | 0.00 → 0.10 |
| 暗部更青绿 | `GRADE_TEAL_SAT_BOOST` | 0.10 → 0.20 |
| 更亮/更暗 | `GRADE_BRIGHTNESS` | 0.90 ~ 1.05 |
| 对比更强 | `GRADE_CONTRAST` | 1.00 → 1.10 |
| 泛光更糊/更亮 | `BLOOM_INTENSITY` | 1.0 → 1.8 |
| 暗角更重 | `VIGNETTE_INTENSITY` | 1.0 → 1.6 |
| 雨/黄昏雾更浓 | `AIR_FOG_MIE_DENSITY_RAIN` / `_EVENING` | 0.03→0.05 / 0.005→0.012 |
| 空气透视更强 | `AIR_FOG_RAYLEIGH_DENSITY` | 0.0005 → 0.0008 |
| 反射更贵更清晰 | `SSR_RAY_COUNT` / `SSR_INTERSECTION_STEPS_SMOOTH` | 4→6 / 16→24 |
| 湿地面更强 | `RAIN_PUDDLES` 保持开启，配合 `wetnessHalflife`（默认 70） | — |

### 2.3 需要改 `zephyr_cinematic.glsl`（要重新跑校验）

| 想要的效果 | 改哪里 | 怎么改 |
| --- | --- | --- |
| 阳光更「炸」 | `zephyr_pre_tonemap` 的 `warm` 系数 | `0.16/0.04/0.12` 是 R/G/B 偏移，别超过 ±0.3 |
| 高光过渡更柔 | `zephyr_pre_tonemap` 的 `hot`/`roll` | 增大 `smoothstep(0.55, 1.60, chroma)` 范围 |
| 暗部更「奶」 | `zephyr_post_tonemap` 的 `lift` 分支 | `lift * 0.55` 是抬升量；`lift * 1.6` 是暗部去饱和 |
| 调色更偏青橙 | `shadow_tint` / `highlight_tint` | 写成 `vec3`，注意整体亮度大致守恒 |
| 曲线更「S」 | `curve` 分支 | `smoothstep` 混合两次 = 更强 |
| 颗粒更细 | `zephyr_apply_grain` | `0.055` 是幅度，`1137.0` 是时间抖动尺度 |

---

## 3. 三个「向参考图靠拢」的配方

### 配方 A：雨夜霓虹（参考图 6/7）

```
GRADE_WHITE_BALANCE        = 6100
GRADE_TEAL_SAT_BOOST       = 0.18
BLOOM_INTENSITY            = 1.55
AIR_FOG_MIE_DENSITY_RAIN   = 0.045
ZEPHYR_SPLIT_STRENGTH      = 0.65
ZEPHYR_BLACK_LIFT          = 0.015   # 湿沥青的「抬黑」
ZEPHYR_VIBRANCE            = 0.12
```

### 配方 B：黄昏逆光（参考图 2/3/12/13）

```
GRADE_WHITE_BALANCE        = 6200
GRADE_ORANGE_SAT_BOOST     = 0.10
AIR_FOG_MIE_DENSITY_EVENING= 0.010
BLOOM_INTENSITY            = 1.45
ZEPHYR_WARMTH              = 1.00
ZEPHYR_HIGHLIGHT_ROLLOFF   = 0.55
ZEPHYR_FILM_CURVE          = 1.10
```
再把 profile 切到 **Cinematic**（开 DoF），并把 `DOF_FOCUS` 设为想要的米数（`-1` = 自动对焦屏幕中心）。

### 配方 C：动漫写实（参考图 4/8/9）

```
GRADE_SATURATION           = 1.08
ZEPHYR_VIBRANCE            = 0.18
ZEPHYR_HIGHLIGHT_ROLLOFF   = 0.25   # 动漫高光要保留颜色
ZEPHYR_BLACK_LIFT          = 0.005
ZEPHYR_FILM_CURVE          = 0.85
```

---

## 3.5 雨水相关的参数

| 想要的效果 | 参数 |
| --- | --- |
| 雨丝更长/更细 | `ZEPHYR_RAIN_STREAK`（0 = 原版；0.5 默认；>0.8 很电影） |
| 关掉雨丝重塑 | `ZEPHYR_RAIN_SHAPE` 关闭 |
| 地面更湿更亮 | `ZEPHYR_RAIN_WETNESS`（0.8 默认；1.0 接近刚下过雨） |
| 雨点涟漪更明显 | `ZEPHYR_RAIN_RIPPLE`（0.9 默认；1.4 很夸张） |
| 墙面水线更明显 | `zephyr_rain.glsl` 里 `zephyr_wall_streak` 的倍率与 `0.055` 法线扰动 |
| 涟漪更细/更粗 | `zephyr_rain.glsl` 中 ripple 的 `scale`（4.2 / 6.7）与 `radius`（0.42） |

> 注意：涟漪只在**正在下雨**（rainStrength > 0）时出现；湿润高光由 `wetness` 驱动，雨停后还会保留一段时间。

## 3.6 湿地面 / 飞溅 / 雾 / 光柱（v0.4）

| 想要的效果 | 参数 / 位置 |
| --- | --- |
| 地面整体更湿（不出现干块） | `zephyr_rain.glsl` 的 `zephyr_macro_wetness`（0.55~1.0 区间） |
| 湿地面更亮/更暗 | 同文件里 `albedo *= 1.0 - 0.20 * coat` 的 `0.20` |
| 水洼更明显/更弱 | `rain_puddles.glsl` 的 `smoothstep(0.40, 0.62)` 与 `puddle_roughness` |
| 飞溅白点更强 | `zephyr_rain.glsl` 里 `albedo += vec3(0.045,…) * splash * k` |
| 雨/黄昏雾更浓 | `AIR_FOG_MIE_DENSITY_RAIN / _EVENING`、`OVERWORLD_FOG_INTENSITY` |
| 雨天泛光 | `c14_color_grading.fsh` 的 `(1.0 + 0.30 * rainStrength)` |
| 光柱更强 | `CREPUSCULAR_RAYS_INTENSITY`（当前 1.60）+ Photon 的 `VL` |

> 雾的甜点区：`RAIN 0.060 / EVENING 0.0046`。再高（0.085 / 0.0090）会整屏发白。

## 3.7 光柱 / 材质立体 / 雨风感（v0.5）

| 想要的效果 | 参数 / 位置 |
| --- | --- |
| 光柱更强/更弱 | `ZEPHYR_GODRAYS_INTENSITY`（0.2~0.8 安全；3.0 直接整屏白） |
| 光柱只在缝隙出现 | `c14` 里 `openness = pow(coverage, 3.0)`，指数越大越只保留「视野开阔」的光柱 |
| 材质凹凸更强 | `ZEPHYR_MATERIAL_RELIEF`（0~1）；太强会出现描边噪声 |
| 雨被风吹斜 | `ZEPHYR_RAIN_WIND_X/Z`、`ZEPHYR_RAIN_DISTURBANCE` |
| 反射更长更锐 | `zephyr_rain.glsl` 的 coat roughness（0.16）与 `ssr_multiplier`（1.00） |

> 光柱是加法光：默认 0.40 很克制，截图时想要明显效果可以临时调到 0.7~0.9。

## 4. 安全守则（踩过的坑）

1. **GLSL 的 `#if` 里不能出现浮点字面量**
   `#if ZEPHYR_GRAIN > 0.0` 在 AMD 驱动上直接报 `bad expression`。
   正确写法：`#ifdef` 包住，里面用运行时 `if (ZEPHYR_GRAIN > 0.0)`。
2. **布尔设置必须有 `#ifdef` 用法**
   Iris 的设置解析器只识别 `#ifdef SETTING`。如果设置只被 `#if defined(...)` 或只在 `shaders.properties` 里用到，要在 `settings.glsl` 末尾补一个空 `#ifdef` 作为「decoy」（Zephyr 已经补了 `ZEPHYR_CINEMATIC`）。
3. **`#include` 必须用 `/include/...` 绝对路径**
   Photon 的 include 根是 `shaders/`。
4. **不要在 `c14` 之外做 tonemap 后的调色**
   除了 `final.fsh`（显示空间），其它 pass 的色彩空间都不一样。
5. **改完必须跑校验**
   `validate_glsl.py` 会用真实驱动编译全部入口；它抓不到「观感不对」，但能抓 100% 的语法/条件编译错误。
6. **别用编辑器把 `settings.glsl` 存成 UTF-16**
   Iris 只读 UTF-8 / ASCII；`lang/*.lang` 也必须是 UTF-8。

---

## 5. 实机迭代（R 键重载）

游戏运行中改 shader 的循环：

```powershell
# 设置场景（聊天命令走剪贴板，绕开输入法）
powershell -File tools\mc-ctl.ps1 -Action chat -Text "/time set 11600"
powershell -File tools\mc-ctl.ps1 -Action chat -Text "/weather rain"

# 改完 shader 后：按 R 重载 → 等 8~12 秒编译 → F2 截图
powershell -File tools\mc-ctl.ps1 -Action reload
powershell -File tools\mc-ctl.ps1 -Action shot
```

`shots/` 里会多一张 PNG；对比新旧截图即可判断改动方向。Iris 的 R 键重载日志长这样：

```
[01:26:04] Destroying pipeline minecraft:overworld
[01:26:05] Using shaderpack: Zephyr
[01:26:05] Creating pipeline for dimension minecraft:overworld
```

> 如果日志里跟着 `Shader compilation log for ...` 或 `Failed to create shader rendering pipeline`，
> 说明改坏了：先用 `tools/validate_glsl.py` 定位，再重载。

## 6. 实机对比流程（推荐）

1. 固定一个场景：`Weston City V0.3` + `/time set 12500` + `/weather rain` + 关闭昼夜循环。
2. 用 `tools/mc-test.ps1` 自动截图，产物进 `shots/`。
3. 改参数 → 重跑同一条命令 → 两张截图并排看。
4. 只看三件事：**暗部是否发灰/发绿、高光是否炸、反射是否「湿」**。
5. 确认后把最终值写回 `settings.glsl` 默认值（否则下次重置设置就丢了）。

---

## 6. 常见问题

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 进游戏全黑 / 报 shader 编译失败 | GLSL 错误 | 看 `logs/latest.log` 里的 `[Iris]` 行；或本地跑 `validate_glsl.py` |
| 设置界面看不到 Zephyr Cinematic | 布尔设置没被解析 | 检查 `settings.glsl` 里的 `#ifdef` decoy 与 `shaders.properties` 的 `screen.zephyr` |
| 调了没反应 | 改的是默认值，但游戏里已存了 `shaderpacks/Zephyr.txt` | 删掉该文件或游戏内重置 |
| 画面偏灰 | `ZEPHYR_BLACK_LIFT` 太大 | 降到 0.005~0.01 |
| 画面塑料感 | 高光去饱和过度 | `ZEPHYR_HIGHLIGHT_ROLLOFF` 降到 0.2~0.3 |
| 帧数掉太多 | SSR / 体积雾 / DoF 全开 | 切回 High profile，或降 `SSR_*`、关 DoF |
