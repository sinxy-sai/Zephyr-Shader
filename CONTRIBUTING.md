# Zephyr Shader

## Scope

提交内容必须服务于 Zephyr 的开源光影本体或项目文档。不要提交本地 Minecraft 配置、截图、日志、报告、预处理文本、虚拟环境、调试缓存或参考光影的任何源码与资源。

## Shader 代码规范

- Iris 入口文件使用 Minecraft/Iris 约定的 `.vsh`、`.fsh`、`.csh`、`.comp` 扩展名。
- 可复用 GLSL 放在 `shaders/include/`，按 `lighting`、`atmosphere`、`water`、`post`、`utility` 等职责分组。
- 每个新模块在文件头说明用途、输入资源、输出资源、质量档位和时域依赖。
- 不复制参考光影的代码、纹理、命名体系或许可证文本；借鉴算法时重新设计接口并记录来源类别。
- 所有开关都必须有明确的默认值和关闭后的降级路径。

## 文档规范

- 面向使用者的说明放在 `README.md`。
- 技术决策和设计放在 `docs/`。
- 文档使用 Markdown，避免提交自动生成的大型中间文件。

## 验证规范

提交前至少完成：

1. 检查 `git diff --check`。
2. 确认 `git status --short` 没有测试产物或本地配置。
3. 对 shader 入口执行当前阶段约定的离线语法检查。
4. 如果改动了渲染路径，记录 Iris/Minecraft 版本和验证场景。

## 提交信息

使用简短、可读的 Conventional Commits 风格，例如：

```text
docs: add reference shader analysis
feat: add shadow sampling pass
fix: clamp temporal history weight
chore: update project ignore rules
```
