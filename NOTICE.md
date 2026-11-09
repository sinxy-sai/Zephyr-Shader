# NOTICE / 归属与第三方声明

## Zephyr

Zephyr Shader 的原创源码、GLSL 程序、配置、光影包选项语言文件（`shaders/lang/en_US.lang`、`zh_CN.lang`）与项目文档由本项目维护者创作，除另有说明外以 **Apache License 2.0** 发布，见 [`LICENSE`](LICENSE)。

## 参考光影

开发过程中，本项目参考了若干公开可获取的第三方光影包，用于了解通用的技术方向与实现惯例。涉及的项目包括（但不限于）：

BSL、Bliss（Chocapic13 Shaders edit）、Chocapic13（V6 / V9 系列）、Complementary Reimagined（含 EuphoriaPatches 组合）、Continuum、iterationT、Photon、SEUS 系列（Renewed / v11 / PTGI E12 / PTGI HRR 3）、Solas。

学习的方向属于图形编程中的通用做法，例如：时域抗锯齿的历史重投影与邻域钳制、程序化星空的方向采样、半透明材质的透过率处理、动态手持光的光源强度输入，以及 OptiFine / Iris 自定义光影包选项的公开配置格式（`screen`、`sliders`、`profile`、宏定义的值列表注释与语言文件键）。

## 边界

- 本仓库**不包含**上述项目的源码、纹理、噪声图、二进制资源、语言文件文本或许可证文本，也没有复制改写其代码。所有效果均为本项目自行实现，或由数学函数程序化生成。
- 参考项目的名称、作者、商标与许可证归各自权利人所有；其分发、修改与再利用须遵循各自项目的许可证。列出名称仅用于说明技术参考范围，不代表关联、背书或授权。
- `shaders/lang/` 中的标签与悬停说明为本项目原创撰写，依据 Zephyr 自身的功能参数命名，不译自任何第三方语言文件。
- 本项目不包含第三方贴图、字体、音频或模型，不依赖任何外部下载资源。

## 工具链

Minecraft、Fabric、Iris 以及 Java / Python 等工具链各自遵循其发布者的许可条款，不随本仓库分发。

## English Summary

Zephyr's original code, configuration, bilingual option labels and documentation are maintained by this project and licensed under Apache-2.0 (see `LICENSE`). During development we studied publicly available third-party shaderpacks — including BSL, Bliss, Chocapic13, Complementary (with EuphoriaPatches), Continuum, iterationT, Photon, SEUS and Solas — to understand general graphics techniques and the public OptiFine/Iris shader-option configuration format. This repository contains none of their source code, textures, binary assets, language files or license texts, and no copied or rewritten code. All names and marks belong to their respective owners; listing them indicates a technical reference only and implies no affiliation or endorsement. No third-party assets or external downloads are required.
