# NOTICE — 二次开发与许可声明

## 上游项目

Zephyr 是 **Photon Shaders 1.2a** 的二次开发版本。

- 上游作者：Benjamin Stott（SixthSurge）
- 上游版本：Photon 1.2a（`shaders/` 目录中的绝大部分文件来自 Photon）
- 上游许可：见仓库根目录 `LICENSE`（Photon Shaders License Agreement，随原始发行包提供，**必须保留**）

## 本项目的修改

本项目在 Photon 基础上新增/修改了以下内容（文件级清单）：

| 类型 | 文件 | 说明 |
| --- | --- | --- |
| 新增 | `shaders/include/post_processing/zephyr_cinematic.glsl` | Zephyr 电影感调色/镜头层（分离色调、胶片曲线、黑位、自然饱和度、颗粒、黑边） |
| 修改 | `shaders/program/c14_color_grading.fsh` | 挂载 pre/post tonemap 调用 |
| 修改 | `shaders/program/final.fsh` | 挂载黑边与颗粒 |
| 修改 | `shaders/settings.glsl` | 新增 `ZEPHYR_*` 设置块；按参考图调整默认观感（白平衡/对比/饱和/泛光/雾） |
| 修改 | `shaders/shaders.properties` | 新增 `screen.zephyr`、`profile.cinematic`；修复 Photon 1.2a 遗留的失效选项引用（`GTAO`、`WATER_REFRACTION*`、`CLOUDS_DAILY_WEATHER`、`CLOUDS_CUMULUS_CONGESTUS_PRIMARY_STEPS_H/Z`） |
| 修改 | `shaders/lang/en_US.lang`、`shaders/lang/zh_CN.lang` | 新增 Zephyr 相应标签 |
| 新增 | `README.md`、`docs/`、`tools/`、`reports/`、`shots/` | 项目文档、开发工具与验证证据 |

## 使用与分发

按 Photon 许可：

- 允许个人使用、修改、学习源码；
- 允许在**非付费平台**再分发修改后的版本（需保留本 NOTICE 与 `LICENSE`）；
- **不允许**在 Modrinth / CurseForge 等会直接或间接给创作者带来收益的平台分发，除非获得 SixthSurge 的书面许可；
- **不允许**以收费方式提供副本。

Zephyr 目前是**个人开发/学习用途**，不对外分发。
