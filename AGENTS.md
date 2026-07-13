# Skill Hub 协作约束

本文件定义 AI 与本项目协作时的规约，应始终注入 AI 会话上下文。

## 项目概述

Skill Hub 是 Trae IDE 的技能集合项目，为不同使用场景提供可复用、可安装的专业 AI 技能。当前包含 `knowledge-generator` 技能（v2.4.0），支持 Java/Vue/React 项目的知识库自动生成。

- **技术栈**: Shell（bash 脚本）+ Markdown（模板/SKILL.md）+ Python（签名提取/降级）
- **项目类型**: 非 JVM / 非前端，是 Trae Skill 开发项目（Shell + Markdown 为主）
- **构建命令**: 无（纯脚本项目，无需构建）
- **测试方式**: 手动执行脚本验证，无自动化测试框架

## 项目结构

| 模块 | 职责 | 目录 |
| --- | --- | --- |
| knowledge-generator | 知识库生成器 skill 主模块 | `skills/knowledge-generator/` |
| SKILL.md | skill 入口定义文件（frontmatter + 完整工作流程） | `skills/knowledge-generator/SKILL.md` |
| 语言配置 | Java/Vue/React 语言适配配置 + 自动检测 | `skills/knowledge-generator/lang-profiles/` |
| 扫描脚本 | A1-A7 增强识别脚本 + 签名提取 + 环境检查 | `skills/knowledge-generator/scripts/` |
| 校验器 | B1 质量校验 + B4 代码反向验证 + 体检扫描 | `skills/knowledge-generator/validators/` |
| 模板 | 知识库文档模板 + AGENTS.md 模板 + 机器可读摘要模板 | `skills/knowledge-generator/templates/` |
| 示例 | 知识库文档输出示例 | `skills/knowledge-generator/examples/` |
| 变更日志 | 版本管理与变更追溯 | `CHANGELOG.md` |
| 项目文档 | 安装说明与技能目录 | `README.md` |

### 目录职责说明

- `skills/knowledge-generator/SKILL.md`：skill 的唯一入口，定义 frontmatter（name/version/description）和完整工作流程。所有流程变更必须同步更新此文件
- `skills/knowledge-generator/lang-profiles/`：语言配置文件目录。新增语言支持时在此添加 `.profile.sh` 文件，并在 `detect-language.sh` 中注册检测规则
- `skills/knowledge-generator/scripts/`：扫描和工具脚本。每个脚本必须支持 `LANG_PROFILE` 环境变量和自动检测
- `skills/knowledge-generator/validators/`：校验器脚本。每个校验器必须支持 `--lang` 参数和 `LANG_PROFILE` 环境变量
- `skills/knowledge-generator/templates/`：知识库文档模板。模板必须包含版本标识和空值处理规则

### 分层依赖方向

```
SKILL.md（流程定义层）
    ↓ 驱动
lang-profiles/（语言配置层）
    ↓ 加载到
scripts/ + validators/（执行层）
    ↓ 产出
templates/（模板层）→ 知识库文档
```

> 禁止逆向依赖：脚本不能硬编码语言特性（必须通过 profile 配置），模板不能引用脚本内部变量。

---

## 编码规范

### 通用规范

- **脚本命名**：小写+短横线，如 `extract-business-terms.sh`、`cluster-by-business-verb.sh`
- **模板命名**：中文名，如 `业务领域类模板.md`；前端变体加 `-前端` 后缀
- **变量命名**：
  - 环境变量：全大写下划线，如 `LANG_PROFILE`、`KB_ROOT`
  - 脚本内局部变量：小写下划线，如 `src_dir`、`output_file`
  - profile 导出变量：`LANG_` 前缀，如 `LANG_NAME`、`LANG_FILE_EXTENSIONS`
- **注释规范**：
  - 每个脚本头部必须有功能描述、用法、依赖说明
  - 版本变更时在头部注释中标注 `v{版本号}` 和变更说明
  - 复杂正则必须有行内注释解释匹配目标

### Shell 脚本规范

- 所有脚本以 `#!/usr/bin/env bash` 开头
- 必须使用 `set -euo pipefail`（除非有特殊原因）
- macOS BSD 兼容性：禁止使用 `\s`（用 `[[:space:]]`）、禁止 `grep -P`（用 `grep -E`）、注意 `sed -i` 需要备份后缀
- 数组传给 `grep -vE` 时必须用 `build_exclude_regex()` 函数转为 `pattern1|pattern2` 格式，禁止 `${array[*]}` 直接拼接
- `find` 命令多扩展名用 `\( -name "*.ext" -o -name "*.ext" \)`，`grep` 多扩展名用 `--include`

### Markdown 模板规范

- 每个模板头部必须有 `<!-- 模板版本: x.x.x | 适配语言: xxx -->` 注释
- 占位符用 `{描述性文字}` 格式
- 空值处理规则在头部注释中声明

---

## 工作流

### 分析阶段

1. **先读 SKILL.md**：理解当前 skill 的完整工作流程和约束
2. **定位代码**：根据改动需求，确定涉及的脚本/校验器/模板/配置文件
3. **识别影响范围**：
   - 检查改动是否涉及语言配置（lang-profiles/）
   - 检查改动是否涉及门控检查点（ensure-python3.sh 的完整性校验列表）
   - 检查改动是否涉及模板选择表（SKILL.md 中的表格）
   - 检查改动是否影响现有 Java 项目的回归兼容性
4. **确认约束**：
   - 是否有 `LANG_PROFILE` 环境变量传递链需要同步
   - 是否有 `--lang` 参数解析需要同步
   - 是否有 `build_exclude_regex` 类似的正则构建函数需要同步

### 设计阶段

1. **配置驱动优先**：新增语言支持时，优先通过新增 `.profile.sh` 文件实现，不在脚本中硬编码语言特性
2. **脚本改造设计**：
   - 在脚本头部加载语言 profile（`source "$LANG_PROFILE"`）
   - 将硬编码的 glob/正则/阈值替换为 profile 变量引用
   - 保留兜底默认值（profile 加载失败时使用 Java 默认值）
3. **模板设计**：
   - 前端模板与 Java 模板独立维护，不做条件占位符
   - 模板中的概念映射在 SKILL.md 的"前端概念映射"表中记录
4. **文档同步设计**：
   - 确定需要同步更新的章节（SKILL.md 配套工具表/模板选择表/门控检查点表）
   - 确定是否需要更新 CHANGELOG

### 实现阶段

1. **编码顺序**：语言配置 → 脚本改造 → 校验器改造 → 模板新增 → 文档更新 → CHANGELOG 更新
2. **编码约束**：
   - 脚本改造后必须确保 Java 项目行为零变化（通过 profile 提取原有硬编码值）
   - 新增正则必须用 `[[:space:]]` 替代 `\s`
   - 数组排除必须用 `build_exclude_regex()` 函数
   - `find` + `grep` 混用时注意命令边界（grep 不支持 find 的 `\( \)` 参数）
3. **测试规范**：
   - Java 回归测试：`LANG_PROFILE=java.profile.sh bash scripts/xxx.sh <java源码>`
   - 前端测试：`LANG_PROFILE=vue.profile.sh bash scripts/xxx.sh <vue源码>`
   - 自动检测测试：`bash lang-profiles/detect-language.sh <项目根目录>`
   - 校验器测试：生成前端知识库文件后执行 `LANG_PROFILE=vue bash validators/validate-knowledge.sh`
4. **提交规范**：
   - 单次提交只包含一个功能点或一个 bugfix
   - 提交信息格式：`{type}: {description}`，type 为 feat/fix/refactor/test/docs
   - 功能变更必须同步更新 CHANGELOG.md

---

## 变更配套检查清单

> **每次改动 skill 代码后，必须逐项检查以下文件是否需要同步更新。未过完此清单前，禁止宣告任务完成。**

| 改动类型 | 必须同步检查的文件 | 检查内容 |
| --- | --- | --- |
| 新增/删除脚本或校验器 | SKILL.md 配套工具表 + ensure-python3.sh 完整性校验列表 + CHANGELOG | 工具表是否有新条目；完整性校验数组是否包含新文件；CHANGELOG 是否记录 |
| 新增/删除模板文件 | SKILL.md 模板选择表 + CHANGELOG | 模板表是否有新条目；CHANGELOG 是否记录 |
| 新增/删除语言配置 | SKILL.md 适配语言声明 + ensure-python3.sh + detect-language.sh + CHANGELOG | 语言声明是否更新；完整性校验是否包含新 profile；检测脚本是否注册新规则 |
| 改脚本逻辑/正则 | CHANGELOG + 对应 profile 配置 | CHANGELOG 是否记录变更；如涉及语言适配，profile 变量是否同步 |
| 改 SKILL.md 流程步骤 | CHANGELOG + 门控检查点表 | CHANGELOG 是否记录；门控表是否与流程一致 |
| 改 frontmatter version | CHANGELOG + 所有模板版本号 + AGENTS.md 模板版本号 | 版本号是否统一；CHANGELOG 是否有对应版本条目 |
| 改 AGENTS.md 模板 | CHANGELOG | CHANGELOG 是否记录 |

### 检查清单执行规则

1. **强制执行**：每次代码变更完成后（包括 bug 修复），必须过一遍此清单
2. **逐项确认**：对清单中每一行，明确判断"需要更新"或"不需要更新"，不可跳过
3. **CHANGELOG 兜底**：任何改动都必须在 CHANGELOG.md 中有对应记录，无例外
4. **版本号同步**：SKILL.md frontmatter 的 version 变更时，所有模板的版本标识必须同步更新

---

## 知识库

> 本项目自身不需要知识库（是 skill 开发项目，不是业务项目）。
> 但 knowledge-generator skill 的 SKILL.md 中定义了知识库生成流程，开发时需参照。

---

## 问题定位

### 常见问题排查路径

| 问题类型 | 排查入口 | 关键文件 |
| --- | --- | --- |
| 脚本执行报错 | 脚本头部 `set -euo pipefail` | 检查 `LANG_PROFILE` 是否正确加载 |
| Java 回归失败 | `lang-profiles/java.profile.sh` | 对比改动前后 profile 值是否一致 |
| 前端扫描无输出 | `lang-profiles/vue.profile.sh` 或 `react.profile.sh` | 检查 `LANG_FILE_EXTENSIONS` 和 `LANG_METHOD_REGEX` |
| 校验器全部 FAIL | `validators/validate-knowledge.sh` | 检查路径提取正则是否匹配前端文件路径 |
| 语言检测错误 | `lang-profiles/detect-language.sh` | 检查 package.json 解析和文件统计逻辑 |

### Grep 快速定位

```bash
# 查找所有硬编码的 .java（应该已被替换为 profile 变量）
grep -rn '\.java' skills/knowledge-generator/scripts/ --include="*.sh" | grep -v 'LANG_\|profile\|#\|注释'

# 查找所有 \s（应该已替换为 [[:space:]]，Java 原有除外）
grep -rn '\\s' skills/knowledge-generator/scripts/ --include="*.sh"

# 查找所有 ${array[*]} 传给 grep 的模式（应该用 build_exclude_regex）
grep -rn '\[\*\]' skills/knowledge-generator/scripts/ --include="*.sh"
```
