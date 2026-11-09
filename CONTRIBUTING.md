# CONTRIBUTING / 贡献规范

欢迎参与 Zephyr 的开发。本文件说明提交范围、代码约定与验证要求。

## 适用范围

提交内容应服务于 Zephyr 的光影本体或其公开文档。请勿提交本地 Minecraft 配置、截图、日志、缓存、构建中间产物，或任何第三方光影的源码与资源。

## 代码约定

- Iris 入口程序使用约定的 `.vsh` / `.fsh` / `.csh` / `.comp` 扩展名；可复用 GLSL 放在 `shaders/lib/`。
- 渲染参数集中在 `shaders/lib/settings.glsl`，命名遵循 `<模块>_<参数>`。每个开关都要有明确默认值，以及关闭后可用的降级路径。
- `shaders/gbuffers_*.fsh/.vsh` 与 `shaders/shadow.vsh` 结构一致。修改这类模板化代码时，请同步所有相关程序，避免某个阶段与其它阶段使用了不同的顶点位移或输出布局。
- 新增或改变渲染缓冲、渲染阶段、格式或通道语义时，请先更新 `shaders/lib/config.glsl` 并在 PR 描述中明确说明「契约变更」。
- 全屏阶段在 tonemap 之前的线性 HDR 空间工作；`final` 是唯一做 gamma 编码的阶段。
- 不复制参考光影的代码、纹理、命名体系或许可证文本；借鉴算法时重新设计接口，并在提交说明中注明参考的类别。

## 光影包选项与国际化

选项采用 OptiFine / Iris 的自定义 shader options 机制，有四条容易出错的约束：

1. **每个暴露的选项宏必须在 `#define` 同一行附带 `//[...]` 可选值注释**，例如 `#define BLOOM_STRENGTH 0.95 //[0 0.25 0.5 0.75 0.95 1.0]`，开关用 `//[0 1]`。加载器依此生成控件；缺少注释时页面只会显示标题而没有控件。
2. **`screen` 只能列出真正的选项宏**。`shadowMapResolution`、`shadowDistance` 等属于加载器内置指令，只能出现在 `profile.*` 中，放进 `screen` 会产生无法解析的菜单元素。
3. **性能预设中，数值型开关用 `X=0` / `X=1`**。Zephyr 的开关是带值的宏并配合 `#if X` 使用；`!X` 形式仅适用于无值的 `#ifdef` 风格宏。
4. **新增或修改选项时，同步更新三处**：`shaders/shaders.properties`（`screen` / `screen.<page>` / `sliders` / `profile.*`）、`shaders/lang/en_US.lang`、`shaders/lang/zh_CN.lang`。语言文件键为 `option.<NAME>`、`option.<NAME>.comment`、`value.<NAME>.<n>`、`screen.<PAGE>`、`screen.<PAGE>.comment`、`profile.<NAME>`；两份语言的条目必须一一对应，且不引用其它项目的译文。

子页名请保持小写并与 `[page]` 引用一致。改动选项布局后需要重新选择光影包或重启游戏才能刷新加载器缓存。

## 文档约定

- 面向使用者的说明放在 `README.md`；产品行为承诺放在 `CODE_OF_PRODUCT.md`；归属与第三方边界放在 `NOTICE.md`；贡献与验证约定放在本文件。
- 只引用仓库中实际存在的文件，不要指向本地专有目录或工具。
- 对外文档使用克制、可验证的表述；不要把尚未实现的行为写成已完成特性，也不要把内部缺陷编号写进门面文档。
- 中英双语内容需同时维护，避免一种语言包含另一种语言没有的信息。

## 验证要求

提交前请至少完成：

1. `git diff --check`，并确认 `git status --short` 没有测试产物或本地配置。
2. 启用光影包并热重载，检查游戏日志没有编译错误；改动选项时额外确认没有 `Invalid pack option` 或 `Unable to resolve ... menu element` 之类的警告。
3. 修改渲染效果时，在**同一机位、同一天气、同一时间**下做改前 / 改后对比，并记录可复核的量化数据（亮度、暗部与高光占比、差异分布等）。评估闪烁或时域问题时使用连续帧截图，避免截图动作本身干扰测量。
4. 关键开关应能一键关闭以回到接近基线的状态，便于回退与定位问题。
5. 交付前将调试视图全部复位为关闭，并恢复天气、时间与快捷栏等观察条件。
6. 在提交说明中写明验证所用的 Minecraft / Fabric / Iris 版本与观察场景。

## 提交信息

使用简短可读的 Conventional Commits 风格：

```text
docs: update shader options documentation
feat: add procedural night sky
fix: prevent held cutout items from writing a glass mask
tune: reduce wide bloom halo strength
```

## English Summary

Contributions are welcome via issues and pull requests. Keep GLSL helpers in `shaders/lib/`, centralise parameters in `shaders/lib/settings.glsl`, keep the gbuffer programs structurally consistent, and add a `//[...]` value-list annotation to every option macro. Any new or changed option must be registered in `shaders/shaders.properties` and in both language files (`en_US.lang`, `zh_CN.lang`). Verify with `git diff --check`, a clean hot-reload with no compilation errors, and same-scene before/after comparisons; reset debug views before delivery. Use Conventional Commits.
