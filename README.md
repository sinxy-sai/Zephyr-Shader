# Zephyr — Minecraft 电影感光影

> 目标：把 MC 画面做成一整套「雨夜湿地面 + 黄昏逆光 + 动漫写实混合」的电影感。
> 参考基准：用户截图中的异环/光追画面；舒适度基准：`ComplementaryReimagined_r5.7.1 + EuphoriaPatches_1.8.6`。
> 当前版本：**v0.1（Cinematic layer）**，在 Photon 1.2a 的成熟管线上叠加 Zephyr 调色/镜头层。

---

## 1. 现在有什么

| 模块 | 位置 | 说明 |
| --- | --- | --- |
| **Zephyr Cinematic 层** | `shaders/include/post_processing/zephyr_cinematic.glsl` | 分离色调（青暗部/暖高光）、胶片 S 曲线、黑位抬升、自然饱和度、高光去饱和、胶片颗粒、2.35:1 电影黑边 |
| 管线挂载点 | `program/c14_color_grading.fsh`（色调映射前后）/ `program/final.fsh`（颗粒/黑边） | 与 Photon 原有 ACES/tonemap 共存，可单独开关 |
| 设置界面 | `settings.glsl` + `shaders.properties` + `lang/*.lang` | 游戏内：光影设置 → 后处理 → **Zephyr Cinematic** |
| **Cinematic 预设** | `shaders.properties` 的 `profile.cinematic` | 一键启用 DoF / 动态模糊 / 更高泛光与暗角 |
| 默认观感（已按参考图调） | `settings.glsl` | 色温 6300K、橙色饱和度 +0.06、青 +0.14、泛光 1.30、暗角 1.25、黄昏/雨天 Mie 雾提高 |
| 离线校验工具 | `tools/validate_glsl.py` | 不开游戏就能编译全部 209 个光影程序入口 |
| 实机验证工具 | `tools/mc-test.ps1` | 启动 MC → 进存档 → 自动截图 → 抓 Iris 编译日志（由 mc-harness 搭建） |

当前默认配置下，**离线 GLSL 校验 209/209 通过**（62 个被光影自身禁用的 pass 跳过，0 失败）。

---

## 2. 快速开始

1. 打开游戏 → 选项 → 视频设置 → 光影 → 选择 **Zephyr**。
2. 光影设置 → 后处理 → **Zephyr Cinematic**：调节强度、胶片曲线、颗粒等。
3. 想要「截图模式」：光影设置顶部切换 profile 为 **Cinematic**（开启景深/动态模糊/更强泛光与黑边可选）。
4. 设置会被 Iris 存到 `shaderpacks/Zephyr.txt`；删掉它即可恢复默认。

> 提示：`ZEPHYR_LETTERBOX = On` 会画 2.35:1 黑边，只建议截图时开。

---

## 3. 参考图 → 参数对照

| 参考画面 | 视觉特征 | Zephyr 对应参数 |
| --- | --- | --- |
| 雨后黄昏保时捷（图 2/3/5） | 湿地面长条反射、暖阳逆光、光晕、浅景深 | `SSR_*` / `RAIN_PUDDLES`、`AIR_FOG_MIE_DENSITY_EVENING`、`BLOOM_INTENSITY`、`DoF` |
| 雨夜城市霓虹（图 6/7） | 沥青反射霓虹、路灯辉光、低饱和暗部 | `GRADE_WHITE_BALANCE=6300`、`ZEPHYR_SPLIT_STRENGTH`、`ZEPHYR_BLACK_LIFT`、`BLOOM_INTENSITY` |
| 沙滩动漫角色（图 4） | 亮部暖、阴影偏冷、皮肤干净 | `ZEPHYR_WARMTH`、`ZEPHYR_HIGHLIGHT_ROLLOFF`、`ZEPHYR_VIBRANCE` |
| 城市/林地全景光追（图 8/9/10/11） | 体积光、空气透视、樱花粉/雪景低饱和 | `OVERWORLD_FOG_INTENSITY`、`AIR_FOG_MIE_DENSITY_*`、`ZEPHYR_FILM_CURVE` |
| 黄昏玻璃/水洼（图 12/13） | 高光柔化不炸、反射带雾 | `ZEPHYR_HIGHLIGHT_ROLLOFF`、`BLOOM`、反射步进 |

---

## 4. 工程结构

```
Zephyr/
├─ shaders/                 # 光影本体（Photon 1.2a 基底 + Zephyr 修改）
│  ├─ include/post_processing/zephyr_cinematic.glsl   # ← Zephyr 新模块
│  ├─ program/c14_color_grading.fsh                   # ← 挂载点 A
│  ├─ program/final.fsh                               # ← 挂载点 B
│  ├─ settings.glsl                                   # ← Zephyr 设置块 + 默认值
│  ├─ shaders.properties                              # ← 设置界面 / Cinematic 预设
│  └─ lang/{en_US,zh_CN}.lang                         # ← 中英文标签
├─ tools/validate_glsl.py   # 离线 GLSL 校验（需要开发 venv）
├─ tools/mc-test.ps1        # 实机启动 + 截图 + 日志验证
├─ reports/                 # 实机验证报告（Iris 编译日志、启动报告）
├─ shots/                   # 实机截图证据
├─ docs/look-dev.md         # 观感开发手册（调参攻略）
├─ docs/changelog.md        # 版本记录
├─ NOTICE.md                # 许可与二次开发声明
└─ LICENSE                  # Photon 原始许可（必须保留）
```

---

## 5. 开发流程

```powershell
# 0) 开发用 Python 环境（已装 moderngl / PyOpenGL / numpy）
$py = "C:\Users\liubingliang\Downloads\_shader_lab\venv\Scripts\python.exe"

# 1) 改完 shader 后，离线编译全部入口，先排除 GLSL 错误
& $py tools\validate_glsl.py
#    只测某几个 pass：
& $py tools\validate_glsl.py --only composite14 final

# 2) 实机验证（启动游戏 → 截图 → 抓日志）
powershell -File tools\mc-test.ps1

# 3) 看结果
#    reports\launch-report.md   是否编译成功 / 耗时 / 问题
#    shots\                     实机截图
```

改观感的顺序建议：**先调 `settings.glsl` 默认值（快速、零风险）→ 再调 `zephyr_cinematic.glsl` 的公式（需要重新校验）→ 最后才动 Photon 的管线**。

`docs/look-dev.md` 里有完整的「想要 X 效果 → 改哪个参数」对照表。

---

## 6. 版本规划

- **v0.1（当前）**：电影感调色层、Cinematic 预设、默认观感调校、离线校验 + 实机验证闭环。
- **v0.2**：湿地面专项（雨纹法线扰动、反射拉长）、泛光形状（neon 横向 streak）、镜头光晕。
- **v0.3**：天空/体积雾按「黄昏 · 雨夜 · 蓝调」三套预设；樱花/雪景低饱和分支。
- **v0.4**：参考图逐张校准（截图 vs 参考图 的色板/直方图对比脚本）。

---

## 7. 许可与致谢

Zephyr 是 **Photon Shaders 1.2a**（作者 SixthSurge）的二次开发版本，遵循 Photon 的许可（个人使用、修改、保留许可文件后可再分发；不可在付费平台分发）。原始许可见 `LICENSE`，二次开发声明见 `NOTICE.md`。

Photon 原项目致谢（保留）：

* 中文翻译：NakiriRuri、OrzMiku；意大利语：Jmayk；俄语：Timtaran
* [Emin](https://github.com/EminGT)（Complementary Reimagined）— shadow bias 方案
* [DrDesten](https://github.com/DrDesten) — SSR 深度容差
* [Jessie](https://github.com/Jessie-LC) — labPBR 金属 f0/f82
* Sledgehammer Games — bloom 降采样方案
* momentsingraphics.de — 蓝噪声纹理；NASA SVS — 银河贴图
