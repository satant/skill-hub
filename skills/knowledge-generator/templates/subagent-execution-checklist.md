<!-- 模板版本: 2.5.0 | 适配语言: 语言无关 -->
<!--
  subagent 执行检查清单模板
  主流程委托 subagent 时，必须将本清单完整内容拼接到 query 参数中。
  subagent 完成任务返回前，必须逐项确认本清单。
  解决问题：subagent 无法感知 SKILL.md 门控约束，导致门控被跳过。
-->

# subagent 执行检查清单（v2.5.0 强制约束）

> **使用说明**：主流程通过 Task 工具委托 subagent 时，必须将本清单作为 query 的一部分传入。
> subagent 完成任务返回前，必须逐项执行并确认。任何一项未完成，subagent 不得声明「已完成」。

## 一、环境与脚本执行检查（门控0-3）

- [ ] 已执行 `bash scripts/ensure-python3.sh`，确认 python3 可用 + 脚本完整性通过
- [ ] 已执行 A1: `bash scripts/extract-business-terms.sh <源码目录> $KB_ROOT/.cache/business-terms.txt`
- [ ] 已执行 A2: `bash scripts/cluster-by-business-verb.sh <源码目录> $KB_ROOT/.cache/verb-clusters.txt`
- [ ] 已执行 A6: `bash scripts/extract-large-class-methods.sh <源码目录> $KB_ROOT/.cache/large-class-methods.txt`
- [ ] 已执行 A7: `bash scripts/cross-domain-scanner.sh <源码目录> $KB_ROOT/.cache/cross-domain-scenarios.txt`
- [ ] `.cache/` 目录下 4 个输出文件均存在且非空

## 二、脚本输出消费检查（v2.5.0 新增）

> 生成 .md 和 .summary.json 时，以下字段必须从脚本输出中提取，不可凭记忆手写：

- [ ] `businessTerms` 字段条目来源：`.cache/business-terms.txt`（A1 输出）
- [ ] `coreChain` 中的方法名已与 `.cache/verb-clusters.txt`（A2 输出）交叉验证
- [ ] 大类方法清单已参照 `.cache/large-class-methods.txt`（A6 输出），尾部方法（行号 > 500）已覆盖
- [ ] 跨领域子场景已参照 `.cache/cross-domain-scenarios.txt`（A7 输出）登记

## 三、分区完整性检查（门控6，v2.5.0 新增）

确认知识库索引包含以下六个分区表头（即使某分区暂无内容也要有表头和「待生成」标记）：

- [ ] `## 项目导航`
- [ ] `## 业务领域`
- [ ] `## 数据模型`
- [ ] `## 项目工具`
- [ ] `## 外部依赖`（或 `## 外部依赖清单`）
- [ ] `## 架构专题`

## 四、质量校验检查（门控4-5）

每个生成的知识库文件（.md + .summary.json）必须执行：

- [ ] 已执行 B1: `bash validators/validate-knowledge.sh <文件.md> <项目根目录> [索引文件.md] --json`，退出码为 0
- [ ] 已执行 B4: `bash validators/cross-validate-with-code.sh <文件.summary.json> <项目源码目录> --json`，退出码为 0
- [ ] B1/B4 报告中的 failures 为空

## 五、覆盖率门控检查（门控7，v2.5.0 新增）

- [ ] `.summary.json` 的 `coverageReport.methodCoverage` ≥ 70%
- [ ] `.summary.json` 的 `coverageGaps` 中不存在 `gapType: "core"` 的条目（core gap 零容忍）
- [ ] coreChain 中不存在 `confidence: "low"` 且 `confidenceNote` 包含「未完整阅读」「未验证」「推断」的条目

## 六、结构化返回格式（v2.5.0 新增）

subagent 返回时必须包含以下结构化信息（自然语言总结之外），**并写入文件**：

```bash
# subagent 返回前必须执行此写入操作
mkdir -p $KB_ROOT/.cache/subagent-reports
cat > $KB_ROOT/.cache/subagent-reports/{领域名称}-$(date +%Y%m%d%H%M%S).json << 'SUBAGENT_EOF'
{
  "completed": true,
  "generatedFiles": ["docs/knowledge/业务领域/xxx/xxx.md", "docs/knowledge/业务领域/xxx/xxx.summary.json"],
  "validationResults": {
    "B1": "passed",
    "B4": "passed"
  },
  "coverageReport": {
    "methodCoverage": "75%"
  },
  "indexSections": ["项目导航", "业务领域", "数据模型", "项目工具", "外部依赖", "架构专题"],
  "skippedSteps": [],
  "issues": []
}
SUBAGENT_EOF
```

主流程校验规则：收到 subagent 返回后，执行 `bash validators/validate-subagent-output.sh <报告文件>` 校验：
- `completed=true && validationResults.B1=passed && validationResults.B4=passed && coverageReport.methodCoverage≥70% && skippedSteps为空`
- 不满足时要求 subagent 重试

## 七、执行证据链检查（门控8，v2.5.0 新增）

> subagent 和主流程的所有操作都会留下「证据文件」。门控8 在批次完成后审计这些证据。

- [ ] `.cache/business-terms.txt`（A1 输出）存在且非空
- [ ] `.cache/verb-clusters.txt`（A2 输出）存在且非空
- [ ] `.cache/large-class-methods.txt`（A6 输出）存在且非空
- [ ] `.cache/cross-domain-scenarios.txt`（A7 输出）存在且非空
- [ ] `.cache/progress.json` 已写入（每个批次完成后强制更新）
- [ ] `.cache/subagent-reports/` 目录下有本批次的报告文件（模式B 时）
- [ ] 已执行 `bash validators/validate-gate-evidence.sh $KB_ROOT --json`，退出码为 0
