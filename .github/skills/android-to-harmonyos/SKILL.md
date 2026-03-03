---
name: android-to-harmonyos
description:
  Android 三方库移植到 HarmonyOS (API 12+) 的领域知识库。提供可移植性分析标准、代码迁移模式、
  构建操作规范和故障排查方案。SOP 执行流程由 Agent 负责，本 Skill 只提供知识支撑。
  支持所有类型的 Android 库移植：Java/Kotlin 纯逻辑库、Android UI 组件库、包含 JNI/NDK Native 代码的库。
---

# Android 三方库移植 HarmonyOS — 知识库

> **架构说明**：本 Skill 是领域知识库，提供迁移模式和参考材料。
> 移植的 SOP 执行流程由 `.github/agents/` 下的 Agent 负责，请勿在此重复工作流逻辑。

## Skill 子模块索引

| 子模块 | 说明 | 由哪个 Agent 调用 |
|--------|------|-----------------|
| [skills/project-setup](skills/project-setup/README.md) | OH 项目结构规范、Template 使用说明 | `migrator` |
| [skills/code-migration](skills/code-migration/README.md) | Java/Kotlin → ArkTS 语法映射、代码模式 | `migrator` |
| [skills/native-migration](skills/native-migration/README.md) | JNI/NDK → NAPI 迁移样例 | `migrator` |
| [skills/ui-migration](skills/ui-migration/README.md) | View/Compose → ArkUI 组件映射表 | `migrator` |

## 参考文档索引

| 文档 | 内容 | 状态 |
|------|------|------|
| [references/native-migration.md](references/native-migration.md) | JNI → NAPI 完整迁移示例 | ✅ 有效 |
| [references/ui-migration.md](references/ui-migration.md) | View/Compose → ArkUI 完整映射 | ✅ 有效 |
| [references/project-structure.md](references/project-structure.md) | OH 项目结构与构建系统 | ✅ 有效 |
| [references/template-structure.md](references/template-structure.md) | Template 项目结构详解 | ✅ 有效 |
| [references/testing.md](references/testing.md) | hypium 测试框架完整文档 | ✅ 有效 |

> 请使用 MCP 工具 `deveco-mcp/harmonyos_knowledge_search(keywords=[...])` 获取实时、准确的 API 文档（已更新至 API 22）。

---

## 辅助脚本

> 以下脚本在 workspace 根目录（含 `Template/` 和 `.github/`）下执行。

| 脚本 | 说明 | 用法 |
|------|------|------|
| `install_hap.ps1` | 编译并安装 HAP 到设备 | `powershell -EP Bypass -File .github\skills\android-to-harmonyos\scripts\install_hap.ps1 -ProjectPath Template -Uninstall` |
| `run_tests.ps1` | 运行测试用例 | `powershell -EP Bypass -File .github\skills\android-to-harmonyos\scripts\run_tests.ps1 -ShowLog` |


