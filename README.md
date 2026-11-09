# Zephyr Shader / Zephyr 光影

> 中文正文见下，[English](#english) 见文末。

Zephyr 是面向 Minecraft Java Edition 的开源 Iris 光影包，把自然的光照、稳定的时域效果与电影化成像结合在一个可配置、可自由分发的包里。

## 特性 / Features

- **光照与天气**：PCF 软阴影、半透明与彩色阴影、动态手持光、雷雨与厚云、闪电、雨雾、湿滑表面与水洼。
- **天空**：解析大气、程序化夜空、星星、带月相的月亮与月晕、体积云。
- **材质**：彩色与低饱和染色玻璃、遮光玻璃、水面波纹与反射、植被摇曳、表面凹凸细节。
- **成像**：AgX 与 ACES 色调映射、自动曝光、柔和高光、可调节的泛光与光晕、时间抗锯齿（TAA）、低调饱和度调色。
- **可配置**：游戏内光影包设置提供中文与英文标签、说明，以及四档性能预设。

## 支持范围 / Requirements

| 项目 | 版本 |
| --- | --- |
| Minecraft | 1.21.1 |
| Mod loader | Fabric 0.18.4 |
| Shader loader | Iris 1.8.x |

其它版本组合未验证，不保证可运行。

## 安装 / Installation

1. 将 `Zephyr` 目录放入 `.minecraft/shaderpacks/`，或将其打包为 zip。
2. 游戏内依次打开 **选项 → 视频设置 → 光影包**，选择 `Zephyr` 并应用。
3. 修改配置后重新选择一次光影包；若调整了选项布局，需要重新选择光影包或重启游戏，加载器会缓存选项定义。

## 光影包设置 / Shader Options

在「光影包配置」中可以切换 **四档性能预设**（低 / 中 / 高 / 极致），预设只调整公开选项，应用后每一项仍可单独修改。设置分为六页：

| 页面 | 内容 |
| --- | --- |
| 画质与性能 | TAA、环境光遮蔽、屏幕空间反射、体积光、阴影、云、水洼、闪电 |
| 光照与阴影 | 动态手持光、发光体亮度上限、太阳与天空强度、彩色阴影、阴影柔和度 |
| 天空与大气 | 夜空、星星、月亮与月晕、云量、大气密度 |
| 泛光与色彩 | 泛光强度与光晕范围、阈值、曝光、饱和度、对比度、色调映射 |
| 材质与动画 | 玻璃染色与吸收、磨砂玻璃、边缘高光、植被摇曳、表面起伏 |
| 天气 | 水洼、雨雾、雷雨云、闪电强度 |

界面文本与悬停说明提供英文与简体中文，位于 `shaders/lang/`，随游戏语言自动选择，缺失时回退英文。

## 仓库结构 / Repository Layout

```text
Zephyr/
├─ shaders/                 # 可分发的 Iris 光影源码
│  ├─ lib/                  # 公共 GLSL 模块与集中参数
│  ├─ lang/                 # en_US.lang / zh_CN.lang
│  ├─ block.properties      # 自定义方块标识
│  ├─ shaders.properties    # 管线配置与选项界面定义
│  └─ *.vsh / *.fsh         # 各渲染阶段程序
├─ CONTRIBUTING.md          # 贡献规范
├─ CODE_OF_PRODUCT.md       # 产品行为准则
├─ NOTICE.md                # 归属与第三方边界
├─ LICENSE                  # Apache License 2.0
└─ README.md
```

## 参与贡献 / Contributing

欢迎通过 Issue 与 Pull Request 反馈问题或提交改进。开发、验证与提交约定见 [`CONTRIBUTING.md`](CONTRIBUTING.md)，产品承诺见 [`CODE_OF_PRODUCT.md`](CODE_OF_PRODUCT.md)，第三方归属见 [`NOTICE.md`](NOTICE.md)。

## 已知限制 / Known Limitations

- 树叶等镂空材质的边缘在远处仍可能有轻微闪烁。
- 阴影分辨率与距离受加载器实际分配限制，相关设置项可能不生效。
- 完整视差映射、真前向半透明、接触硬化阴影、反射与环境光遮蔽的时域降噪仍在开发中。

## 许可 / License

Zephyr 自有源码与文档以 [Apache License 2.0](LICENSE) 发布。参考光影仅用于技术学习与对比，不属于本仓库的代码或资源来源，详见 [`NOTICE.md`](NOTICE.md)。

---

<a id="english"></a>

## English

Zephyr is an open-source Iris shaderpack for Minecraft Java Edition, combining natural lighting, stable temporal effects and filmic imaging in a configurable, freely redistributable package.

**Highlights:** PCF soft shadows with translucent and coloured casters, dynamic held-item light, storm weather with volumetric clouds, lightning, rain fog and wet-surface puddles; an analytic atmosphere with a procedural night sky, stars and a phased moon; stained, low-chroma and tinted glass, water ripples and reflections, foliage waving and surface relief; AgX and ACES tonemapping, auto-exposure, adjustable bloom and halo, temporal anti-aliasing and restrained colour grading.

**Requirements:** Minecraft 1.21.1, Fabric 0.18.4, Iris 1.8.x. Other combinations are unverified.

**Install:** place the `Zephyr` folder in `.minecraft/shaderpacks/` (or zip it), then enable it under Options → Video Settings → Shader Packs. Re-select the pack after changing configuration; after changing the options layout, re-select the pack or restart the game because the loader caches option definitions.

**Shader Options:** four performance presets (Low / Medium / High / Ultra) plus six pages — Quality & Performance, Lighting & Shadows, Sky & Atmosphere, Bloom & Colour, Materials & Animation, Weather. Presets only change public options and every option remains individually editable. All labels and tooltips are available in English and Simplified Chinese under `shaders/lang/`, selected automatically from the game language with an English fallback.

**Known limitations:** slight distant shimmer on cutout foliage edges; shadow resolution/distance is bounded by the loader's actual allocation; full parallax mapping, true forward translucency, contact-hardening shadows and temporal denoising for reflections/AO are still in development.

**Contributing:** see `CONTRIBUTING.md`, `CODE_OF_PRODUCT.md` and `NOTICE.md`. Original code and documentation are licensed under [Apache-2.0](LICENSE).
