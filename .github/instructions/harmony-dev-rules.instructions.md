---
description: HarmonyOS 移植项目的全局规则，所有 Agent 执行任何移植任务时均须遵守
applyTo: '**'
---

# HarmonyOS 移植全局规则

所有 Agent 在执行移植任务时，必须严格遵守以下规则，无一例外。

---

## 1. 项目结构规则

- 库代码目录：`library/src/main/ets/`
- Demo 示例：`entry/src/main/ets/pages/Index.ets`
- 测试用例：`entry/src/ohosTest/ets/test/`
- **`bundleName` 必须保持 `"com.example.template"` 不变**（修改后需重新申请证书）
- 模板基础路径：`Template/`（不得修改 `Template/AppScope/app.json5` 中的 bundleName）
- oh-package.json5文件不允许修改
- native侧代码入口文件保持napi_init.cpp不变

## 2. API 查询规则

- 查询鸿蒙 API **必须** 使用 MCP 工具，禁止依赖过期的静态文档：
  - `harmony-docs/search_api` — 按关键词搜索 API
  - `harmony-docs/get_module_apis` — 获取某 Kit 的全部 API 列表
  - `harmony-docs/get_api_detail` — 获取具体 API 的签名与参数说明

## 3. 构建规则

- 构建工具：`hvigorw`（非 Gradle，非 npm）
- SDK 类型：`HarmonyOS`（`build-profile.json5` 中 `runtimeOS: "HarmonyOS"`）
- 构建顺序：`assembleHar` → `assembleHap` → `hdc install` → 运行测试
- **每步必须出现 `BUILD SUCCESSFUL` 才能进入下一步**
- 失败时：分析日志 → 修复代码 → 重试当前步骤，不得跳过

## 3.1 构建执行强制原则（行为偏差红线）

> 以下行为是**严重行为偏差**，一旦发生视为任务失败，必须立即纠正：

| ❌ 禁止行为 | ✅ 正确行为 |
|-----------|-----------|
| 创建 `build-instructions.md`、`移植总结.md` 等文档，然后宣告构建阶段完成 | 使用 `terminal` 工具**实际运行** `hvigorw` 命令，等待真实输出 |
| 以"代码看起来正确"为由跳过编译步骤 | 必须运行编译命令，以终端输出 `BUILD SUCCESSFUL` 为准 |
| 在未看到 `BUILD SUCCESSFUL` 的情况下进入下一步 | 每步等待输出，失败则原地修复重试 |
| 将"编写构建说明"当作"构建验证"的交付物 | 构建验证的唯一交付物是终端的成功输出日志 |

**根本原则**：`terminal` 工具是必须调用的，不是可选的。任何以文档生成代替命令执行的行为都是错误的。

## 4. ArkTS 代码规则

- 语言：ArkTS（TypeScript 超集），必须满足并发安全约束
- Native 模块类型声明：文件名固定为 `index.d.ts`
- 导出方式：`export const`（具名导出），禁止 `export default`
- 导入方式：`import { func } from 'lib.so'`（具名导入）
- CMake 库名**不加** `lib` 前缀：`add_library(mp4 SHARED ...)` → 生成 `libmp4.so`
- hilog 日志必须使用 `%{public}` 修饰符：

  ```c
  OH_LOG_INFO(LOG_APP, "val=%{public}d", val);  // ✅ 可见
  OH_LOG_INFO(LOG_APP, "val=%d", val);           // ❌ 显示 <private>
  ```

## 5. 测试规则

- 测试框架：hypium（`@ohos/hypium`）
- `describe()`/`it()` 名称**不能包含空格**
- `it()` 必须传入 3 个参数：`it('testCaseName', 0, (done: Function) => { ... })`
- 运行命令：

  ```powershell
  hdc shell "aa test -b com.example.template -m entry_test -s unittest OpenHarmonyTestRunner"
  ```

## 6. 文档强制规则（编码前必须完成）

在任何代码迁移工作开始之前，以下两份文档**必须先生成并保存到移植项目根目录**：

1. `三方库规格.md` — 基于 `references/三方库规格-template.md`，列出全部公开接口
2. `方案设计.md` — 基于 `references/方案设计-template.md`，涵盖架构设计与迁移决策

文档质量要求：
- 不允许出现"类似方式"、"对应处理"等模糊表述
- 每个公开接口必须有具体 API 名称和方法签名
- 与 Android 侧的差异必须明确标注（`[变更]` / `[新增]` / `[删除]` / `[不变]`）

## 7. 环境前置检查

所有构建/测试操作前，必须确认以下工具可用：

```powershell
Get-Command hvigorw   # 构建工具
Get-Command hdc       # 设备连接工具
hdc list targets      # 验证设备已连接
```

---

## 8. ArkTS 与 TypeScript 的差异规则（迁移必读）

ArkTS 是 TypeScript 的严格子集，以下 TS 特性在 ArkTS 中**不支持或受限**，迁移代码时必须规避。

### 9.1 类型系统

| 禁止 / 限制 | 替代方案 |
|-----------|---------|
| `any` / `unknown` 类型 | 使用具体类型或 `Object` |
| 结构类型（Structural Typing） | 使用继承（`extends`）或接口（`implements`）显式表达关系 |
| 交叉类型 `A & B` | 改用接口多继承 `interface C extends A, B {}` |
| 条件类型 `T extends U ? X : Y` | 引入显式约束类型或用 `Object` 重写 |
| `typeof` 用于类型标注（如 `let x: typeof y`） | 直接写类型名 |
| 泛型参数仅从返回值推断（无法推断时） | 显式传入泛型参数 `func<T>()` |
| `is` 类型守卫 | 用 `instanceof` + `as` 替代 |

### 8.2 对象与类

| 禁止 / 限制 | 替代方案 |
|-----------|---------|
| 运行时动态增删属性（`p.z = ...` / `delete p.x`） | 类属性必须在类定义中声明 |
| 索引访问 `obj['field']` | 改用 `obj.field` 点号访问 |
| 索引签名 `[index: number]: string` | 用数组或 `Map` 替代 |
| 对象字面量用作类型声明 `{ x: number }` | 定义 `class` 或 `interface` |
| 对象字面量初始化含方法的类 | 用 `new` + 逐字段赋值 |
| 对象字面量初始化含自定义 `constructor` 的类 | 改用 `new ClassName(args)` |
| `Symbol()` API（`Symbol.iterator` 除外） | 不支持，需重构逻辑 |
| 私有字段 `#field` | 改用 `private field` |
| 类型名和变量/函数名**不能重名** | 使用唯一名称 |
| 同一类中多个 `static {}` 块 | 合并为单个 `static {}` |
| `implements` 子句中使用类（非接口） | 改为 `interface` 后再 `implements` |
| 运行时重赋对象方法 `obj.method = fn` | 用继承 `extends` + 方法重写替代 |
| 类字面量 `const Foo = class { ... }` | 声明具名类 `class Foo { ... }` |
| 接口 `extends` 类 | 接口只能 `extends` 接口 |
| 声明合并（同名 interface / enum 多次声明） | 将所有成员写入单一声明 |
| constructor 参数声明即赋值（`constructor(private x: T)`） | 在类体内显式声明字段 |
| 接口中定义 constructor 签名 `new(...)` | 改为普通工厂方法 |

### 8.3 函数与表达式

| 禁止 / 限制 | 替代方案 |
|-----------|---------|
| `var` 关键字 | 改用 `let` |
| 函数表达式 `let f = function(...) {}` | 改用箭头函数 `let f = (...) => {}` |
| 嵌套函数定义 | 改用 lambda（箭头函数）赋值给变量 |
| 解构赋值 `let { x, y } = obj` | 手动逐字段赋值 |
| 解构参数 `function f({x, y}: Point)` | 改为普通参数，函数内手动取值 |
| 解构变量声明 `let [a, b] = arr` | 用下标 `arr[0]`、`arr[1]` 赋值 |
| 逗号运算符（`for` 循环以外） | 改为顺序语句 |
| 一元 `+` / `-` / `~` 作用于非数字 | 须显式类型转换为数字 |
| `delete` 运算符 | 用 `null` 赋值模拟缺省 |
| `in` 运算符 | 改用 `instanceof` |
| `for...in` 循环 | 改用 `for` + 下标或 `for...of` |
| Generator 函数 `function*` / `yield` | 改用 `async/await` |
| `with` 语句 | 直接写完整引用路径 |
| `throw` 抛出非 Error 值（如 `throw 42`） | 只能 `throw new Error(...)` |
| `catch (e: unknown)` 类型标注 | `catch (e)` 省略类型 |
| 展开运算符 `...obj`（对象展开） | 手动逐字段复制；数组展开 `...arr` 仅限特定场景 |
| `<Type>` 强转语法 | 只支持 `as Type` |
| JSX 表达式 | 不支持，无替代方案 |
| `require(...)` / `import x = require(...)` | 改用标准 `import` 语法 |
| `export = ...` | 改用 `export` / `export default` |

### 8.4 接口与枚举

| 禁止 / 限制 | 替代方案 |
|-----------|---------|
| 接口中 call signature `(arg): T` | 改为 `class` + 具名方法 |
| 接口中 constructor signature `new(...)` | 改为工厂方法 |
| 两个父接口有同名方法，子接口继承时需重声明 | 重命名父接口方法避免冲突 |
| `enum` 成员用运行时表达式初始化（如 `Math.random()`） | 只允许编译期常量 |
| 同一 `enum` 多次声明（合并） | 合并为单一声明 |
| `enum` 成员混用 `number` 和 `string` 类型 | 所有成员使用同一类型 |

### 8.5 命名空间

| 禁止 / 限制 | 替代方案 |
|-----------|---------|
| namespace 用作对象赋值 `let m = MyNS; m.x = 1` | 直接使用 `MyNS.x = 1` |
| namespace 内部写非声明语句 | 封装为 `export function init()` 后外部调用 |

### 8.6 关键总结

```
✅ ArkTS 支持：let / const、interface、class、extends、implements（接口）、
              async/await、Promise、泛型、装饰器、for...of、arrow functions
❌ ArkTS 禁止：any、var、delete、in、for...in、Symbol、#私有字段、
              结构类型、动态属性、解构赋值、函数表达式、Generator、JSX、
              对象展开、运行时枚举初始化、声明合并
```

## 迁移策略规则
- 优先使用Arkts接口实现
- 若为性能敏感模块且Arkts接口无法满足需求，才考虑使用Native模块