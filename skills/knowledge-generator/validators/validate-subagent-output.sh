#!/usr/bin/env bash
#
# subagent 返回值校验（门控8a，v2.5.0 新增）
# 校验 subagent 写入的结构化报告 JSON 是否满足质量要求。
#
# 解决问题（issue 4.2）：subagent 返回自然语言总结，主流程无法程序化校验。
# 本脚本通过校验 subagent 写入的 JSON 报告文件，实现结构化校验。
#
# 工作机制：
#   subagent 完成任务后，必须将结构化报告写入 $KB_ROOT/.cache/subagent-reports/ 目录。
#   主流程收到 subagent 返回后，执行本脚本校验报告内容。
#
# 用法: bash validate-subagent-output.sh <subagent-report.json> [--json]
#   或: bash validate-subagent-output.sh <知识库根目录> --all [--json]
#     --all: 校验 subagent-reports/ 目录下所有报告
#
# 依赖: python3（必须）
#
set -euo pipefail

TARGET=""
JSON_OUTPUT=false
CHECK_ALL=false

# 解析参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUTPUT=true; shift ;;
    --all) CHECK_ALL=true; shift ;;
    *)
      if [ -z "$TARGET" ]; then TARGET="$1"; fi
      shift ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "用法: bash validate-subagent-output.sh <subagent-report.json|知识库根目录> [--all] [--json]" >&2
  exit 2
fi

# ============================================
# 校验单个报告文件（所有校验逻辑在 python3 中完成，避免 shell 函数返回值传递问题）
# ============================================
validate_report() {
  local report_file="$1"

  if [ ! -f "$report_file" ]; then
    if [ "$JSON_OUTPUT" = false ]; then
      echo "[FAIL] 报告文件不存在: $report_file"
    fi
    echo "0:1"
    return
  fi

  if ! command -v python3 &>/dev/null; then
    if [ "$JSON_OUTPUT" = false ]; then
      echo "[FAIL] python3 不可用，无法校验 JSON 报告"
    fi
    echo "0:1"
    return
  fi

  # 使用 python3 完成所有校验 + 格式化输出，通过 stdout 传递 "pass:fail" 计数
  python3 -c "
import json, sys

report_path = sys.argv[1]
json_output = sys.argv[2] == 'true'

try:
    with open(report_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
except Exception as e:
    if not json_output:
        print(f'[FAIL] JSON解析失败: {e}')
    print('0:1')
    sys.exit(0)

errors = []
warnings = []
pass_count = 0
fail_count = 0

# 校验1：必填字段
required_fields = {
    'completed': '完成状态',
    'generatedFiles': '生成的文件列表',
    'coverageReport': '覆盖率报告',
    'skippedSteps': '跳过的步骤',
}

for field, desc in required_fields.items():
    if field not in data:
        errors.append(f'必填字段缺失: {field}（{desc}）')

# 校验2：completed 必须为 true
if data.get('completed') is not True:
    errors.append('completed 不为 true — subagent 声明未完成任务')

# 校验3：skippedSteps 必须为空
skipped = data.get('skippedSteps', [])
if skipped and len(skipped) > 0:
    errors.append(f'skippedSteps 非空（{len(skipped)} 项）— 不允许跳过步骤: {skipped}')

# 校验4：coverageReport.methodCoverage >= 70
coverage = data.get('coverageReport', {})
method_cov_str = str(coverage.get('methodCoverage', '0%'))
try:
    method_cov_num = int(method_cov_str.replace('%', '').replace('unknown', '0') or '0')
except:
    method_cov_num = 0

if method_cov_num < 70:
    errors.append(f'方法覆盖率不足: {method_cov_str}（阈值 >=70%）— 门控7：禁止标记领域为已完成')
else:
    pass_count += 1

# 校验5：generatedFiles 不能为空
generated = data.get('generatedFiles', [])
if not generated or len(generated) == 0:
    errors.append('generatedFiles 为空 — subagent 未生成任何文件')

# 校验6：validationResults（如果存在）
validation = data.get('validationResults', {})
if validation:
    b1 = validation.get('B1', '')
    b4 = validation.get('B4', '')
    if b1 and b1 != 'passed':
        errors.append(f'B1 校验未通过: {b1}')
    if b4 and b4 != 'passed':
        errors.append(f'B4 校验未通过: {b4}')
    if not b1 and not b4:
        warnings.append('validationResults 存在但 B1/B4 均为空')

# 校验7：indexSections 六分区完整性（如果存在）
index_sections = data.get('indexSections', [])
if index_sections:
    required_sections = ['项目导航', '业务领域', '数据模型', '项目工具', '外部依赖', '架构专题']
    for req in required_sections:
        found = any(req in s for s in index_sections)
        if not found:
            errors.append(f'索引分区缺失: {req}')

# 统计结果
fail_count = len(errors)
if fail_count == 0:
    pass_count += 1

# 输出
import os
basename = os.path.basename(report_path)

if not json_output:
    print(f'--- 校验报告: {basename} ---')
    if fail_count == 0:
        print('  [PASS] 报告校验通过')
    else:
        print('  [FAIL] 报告校验未通过')
        for err in errors:
            print(f'    - {err}')
    for warn in warnings:
        print(f'  [WARN] {warn}')

# 通过 stdout 输出 pass:fail 计数，供调用方解析
print(f'{pass_count}:{fail_count}')
" "$report_file" "$JSON_OUTPUT" 2>/dev/null || echo "0:1"
}

# ============================================
# 主逻辑
# ============================================
TOTAL_PASS=0
TOTAL_FAIL=0

if [ "$CHECK_ALL" = true ]; then
  # 校验目录下所有报告
  REPORTS_DIR="${TARGET}/.cache/subagent-reports"

  if [ ! -d "$REPORTS_DIR" ]; then
    if [ "$JSON_OUTPUT" = false ]; then
      echo "[WARN] subagent 报告目录不存在: $REPORTS_DIR"
      echo "       （如果使用主流程直读模式A，则不会有 subagent 报告）"
    fi
    exit 0
  fi

  REPORT_COUNT=$(find "$REPORTS_DIR" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')

  if [ "$REPORT_COUNT" -eq 0 ]; then
    if [ "$JSON_OUTPUT" = false ]; then
      echo "[WARN] subagent 报告目录为空: $REPORTS_DIR"
    fi
    exit 0
  fi

  if [ "$JSON_OUTPUT" = false ]; then
    echo "=========================================="
    echo "门控8a：subagent 返回值批量校验"
    echo "报告目录: $REPORTS_DIR"
    echo "报告数量: $REPORT_COUNT"
    echo "=========================================="
  fi

  while IFS= read -r report; do
    RESULT=$(validate_report "$report")
    P_FAIL=$(echo "$RESULT" | tail -1 | cut -d: -f1)
    F_FAIL=$(echo "$RESULT" | tail -1 | cut -d: -f2)
    TOTAL_PASS=$((TOTAL_PASS + ${P_FAIL:-0}))
    TOTAL_FAIL=$((TOTAL_FAIL + ${F_FAIL:-0}))
  done < <(find "$REPORTS_DIR" -name "*.json" -type f 2>/dev/null)

else
  # 校验单个报告文件
  if [ "$JSON_OUTPUT" = false ]; then
    echo "=========================================="
    echo "门控8a：subagent 返回值校验"
    echo "=========================================="
  fi

  RESULT=$(validate_report "$TARGET")
  TOTAL_PASS=$(echo "$RESULT" | tail -1 | cut -d: -f1)
  TOTAL_FAIL=$(echo "$RESULT" | tail -1 | cut -d: -f2)
  TOTAL_PASS=${TOTAL_PASS:-0}
  TOTAL_FAIL=${TOTAL_FAIL:-0}
fi

# ============================================
# 汇总输出
# ============================================
if [ "$JSON_OUTPUT" = true ]; then
  echo "{"
  echo "  \"gate\": \"门控8a：subagent 返回值校验\","
  echo "  \"passed\": $TOTAL_PASS,"
  echo "  \"failed\": $TOTAL_FAIL,"
  echo "  \"allPassed\": $([ "$TOTAL_FAIL" -eq 0 ] && echo true || echo false)"
  echo "}"
else
  echo ""
  echo "=========================================="
  echo "门控8a 汇总: 通过 $TOTAL_PASS | 失败 $TOTAL_FAIL"
  if [ "$TOTAL_FAIL" -gt 0 ]; then
    echo ""
    echo "修复建议:"
    echo "  1. 检查 subagent 是否完成了所有必须步骤"
    echo "  2. 补充覆盖率不足的领域（methodCoverage >= 70%）"
    echo "  3. 重新执行被跳过的门控脚本"
    echo "  4. 确保 subagent 报告写入 .cache/subagent-reports/ 目录"
  fi
  echo "=========================================="
fi

if [ "$TOTAL_FAIL" -gt 0 ]; then
  exit 1
fi
