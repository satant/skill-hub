#!/usr/bin/env bash
#
# 执行证据链校验（门控8，v2.5.0 新增）
# 校验知识库生成流程中所有门控脚本的输出证据文件是否存在且有效。
# 同时校验 progress.json 是否已生成。
#
# 解决问题（元问题）：AI 可能跳过门控脚本执行，而 SKILL.md 中无机制检测到这一点。
# 本脚本通过检查「执行证据文件」是否存在，来反推门控脚本是否被执行过。
#
# 核心思路：每个门控脚本都有对应的输出文件，如果输出文件不存在或为空，
#           说明对应的门控脚本从未执行或执行失败。
#
# v2.5.0: issue 元问题修复（门控跳过检测）
#
# 用法: bash validate-gate-evidence.sh <知识库根目录> [--json]
#   --json: 输出 JSON 格式的结构化报告
#
# 依赖: grep, find, python3（可选，用于 progress.json 解析）
#
set -euo pipefail

KB_ROOT=""
JSON_OUTPUT=false

# 解析参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUTPUT=true; shift ;;
    *)
      if [ -z "$KB_ROOT" ]; then KB_ROOT="$1"; fi
      shift ;;
  esac
done

if [ -z "$KB_ROOT" ]; then
  echo "用法: bash validate-gate-evidence.sh <知识库根目录> [--json]" >&2
  exit 2
fi

if [ ! -d "$KB_ROOT" ]; then
  echo "错误: 知识库根目录不存在: $KB_ROOT" >&2
  exit 2
fi

CACHE_DIR="${KB_ROOT}/.cache"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
FAIL_DETAILS=()
MISSING_EVIDENCE=()

if [ "$JSON_OUTPUT" = false ]; then
  print_pass() { echo "  [PASS] $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
  print_fail() { echo "  [FAIL] $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_DETAILS+=("$1"); }
  print_warn() { echo "  [WARN] $1"; WARN_COUNT=$((WARN_COUNT + 1)); }
else
  print_pass() { PASS_COUNT=$((PASS_COUNT + 1)); }
  print_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_DETAILS+=("$1"); }
  print_warn() { WARN_COUNT=$((WARN_COUNT + 1)); }
fi

if [ "$JSON_OUTPUT" = false ]; then
  echo "=========================================="
  echo "门控8：执行证据链校验"
  echo "知识库根目录: $KB_ROOT"
  echo "=========================================="
fi

# ============================================
# 校验1：门控脚本输出证据文件（门控1-3：A1/A2/A6/A7）
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "--- 校验1: 门控脚本输出证据（A1/A2/A6/A7）---"
fi

# 定义证据文件清单：格式 "文件名|门控编号|描述"
EVIDENCE_FILES=(
  "business-terms.txt|门控1/A1|业务术语提取输出"
  "verb-clusters.txt|门控1/A2|业务方法聚类输出"
  "large-class-methods.txt|门控2/A6|大类方法枚举输出"
  "cross-domain-scenarios.txt|门控3/A7|跨领域子场景输出"
)

for EVIDENCE_SPEC in "${EVIDENCE_FILES[@]}"; do
  IFS='|' read -r FILENAME GATE_ID DESC <<< "$EVIDENCE_SPEC"
  EVIDENCE_PATH="${CACHE_DIR}/${FILENAME}"

  if [ ! -f "$EVIDENCE_PATH" ]; then
    print_fail "${GATE_ID} 证据文件缺失: ${FILENAME}（${DESC}）— 对应门控脚本可能未执行"
    MISSING_EVIDENCE+=("${GATE_ID}:${FILENAME}")
  elif [ ! -s "$EVIDENCE_PATH" ]; then
    print_fail "${GATE_ID} 证据文件为空: ${FILENAME}（${DESC}）— 对应门控脚本执行可能失败"
    MISSING_EVIDENCE+=("${GATE_ID}:${FILENAME}(empty)")
  else
    LINE_COUNT=$(wc -l < "$EVIDENCE_PATH" | tr -d ' ')
    print_pass "${GATE_ID} 证据文件存在: ${FILENAME}（${LINE_COUNT} 行）"
  fi
done

# ============================================
# 校验2：B1/B4 校验结果证据（门控4-5）
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "--- 校验2: 质量校验执行证据（B1/B4）---"
fi

# B1/B4 校验结果记录文件（subagent 或主流程执行 B1/B4 后应写入）
B1_RESULTS="${CACHE_DIR}/b1-validation-results.json"
B4_RESULTS="${CACHE_DIR}/b4-validation-results.json"

if [ -f "$B1_RESULTS" ]; then
  print_pass "门控4/B1 校验结果记录存在: b1-validation-results.json"
else
  print_warn "门控4/B1 校验结果记录缺失: b1-validation-results.json（可能是首次生成，或 B1 结果未被记录）"
fi

if [ -f "$B4_RESULTS" ]; then
  print_pass "门控5/B4 校验结果记录存在: b4-validation-results.json"
else
  print_warn "门控5/B4 校验结果记录缺失: b4-validation-results.json（可能是首次生成，或 B4 结果未被记录）"
fi

# ============================================
# 校验3：subagent 返回值证据（门控8a）
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "--- 校验3: subagent 返回值证据 ---"
fi

SUBAGENT_REPORTS_DIR="${CACHE_DIR}/subagent-reports"

if [ -d "$SUBAGENT_REPORTS_DIR" ]; then
  REPORT_COUNT=$(find "$SUBAGENT_REPORTS_DIR" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$REPORT_COUNT" -gt 0 ]; then
    print_pass "subagent 返回值报告存在: ${REPORT_COUNT} 个文件（subagent-reports/）"
  else
    print_warn "subagent 返回值报告目录存在但无报告文件"
  fi
else
  # subagent 报告目录不存在不一定是错误（主流程直读模式不经过 subagent）
  if [ -d "${KB_ROOT}/业务领域" ]; then
    # 有业务领域文档但没有 subagent 报告，可能是主流程直读模式（模式A）
    print_pass "subagent 报告目录不存在（可能是主流程直读模式A，涉及类 ≤ 10）"
  else
    print_warn "subagent 报告目录不存在（${SUBAGENT_REPORTS_DIR}）"
  fi
fi

# ============================================
# 校验4：progress.json 进度状态（issue 5.1 修复）
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "--- 校验4: progress.json 进度状态 ---"
fi

PROGRESS_FILE="${CACHE_DIR}/progress.json"

if [ -f "$PROGRESS_FILE" ]; then
  print_pass "progress.json 存在"

  # 如果 python3 可用，校验 progress.json 内容完整性
  if command -v python3 &>/dev/null; then
    PROGRESS_VALID=$(python3 -c "
import json, sys
try:
    data = json.load(open('$PROGRESS_FILE'))
    required_fields = ['project', 'totalDomains', 'completedDomains']
    missing = [f for f in required_fields if f not in data]
    if missing:
        print('MISSING:' + ','.join(missing))
    else:
        completed = data.get('completedDomains', 0)
        total = data.get('totalDomains', 0)
        if total > 0:
            rate = int(completed * 100 / total)
            print(f'OK:{rate}%')
        else:
            print('OK:0%')
except Exception as e:
    print(f'ERROR:{e}')
" 2>/dev/null || echo "ERROR:解析失败")

    if echo "$PROGRESS_VALID" | grep -q "^OK:"; then
      RATE=$(echo "$PROGRESS_VALID" | sed 's/OK://')
      print_pass "progress.json 内容完整（完成进度: ${RATE}）"
    elif echo "$PROGRESS_VALID" | grep -q "^MISSING:"; then
      MISSING_FIELDS=$(echo "$PROGRESS_VALID" | sed 's/MISSING://')
      print_fail "progress.json 字段缺失: ${MISSING_FIELDS}"
    else
      print_fail "progress.json 解析失败: $PROGRESS_VALID"
    fi
  fi
else
  # 检查是否已有生成的知识库文档（如果有文档但没有 progress.json，说明遗漏了写入）
  KB_DOC_COUNT=$(find "${KB_ROOT}" -name "*.md" -not -path "*/.cache/*" -type f 2>/dev/null | wc -l | tr -d ' ')

  if [ "$KB_DOC_COUNT" -gt 0 ]; then
    print_fail "progress.json 缺失但已有 ${KB_DOC_COUNT} 个知识库文档 — 门控8：批次完成后必须写入 progress.json"
  else
    print_warn "progress.json 不存在（首次构建时允许，批次完成后必须写入）"
  fi
fi

# ============================================
# 校验5：生成文档与 evidence 的时间一致性
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "--- 校验5: 生成文档与脚本证据的时间一致性 ---"
fi

# 检查知识库文档是否在脚本输出之后生成（如果文档早于脚本输出，说明脚本未被执行就生成了文档）
if [ -d "${KB_ROOT}/业务领域" ] && [ -d "$CACHE_DIR" ]; then
  # 跨平台时间戳获取：macOS 用 stat -f "%m"，Linux 用 stat -c "%Y"
  NEWEST_DOC=$(find "${KB_ROOT}/业务领域" -name "*.md" -type f -exec sh -c 'stat -f "%m" "$1" 2>/dev/null || stat -c "%Y" "$1" 2>/dev/null' _ {} \; 2>/dev/null | sort -rn | head -1 || true)
  OLDEST_EVIDENCE=$(find "$CACHE_DIR" -name "*.txt" -type f -exec sh -c 'stat -f "%m" "$1" 2>/dev/null || stat -c "%Y" "$1" 2>/dev/null' _ {} \; 2>/dev/null | sort -n | head -1 || true)

  if [ -n "$NEWEST_DOC" ] && [ -n "$OLDEST_EVIDENCE" ]; then
    if [ "$NEWEST_DOC" -ge "$OLDEST_EVIDENCE" ] 2>/dev/null; then
      print_pass "文档生成时间晚于脚本输出时间（证据链时序正确）"
    else
      print_fail "文档生成时间早于脚本输出时间 — 可能未执行脚本就生成了文档（门控跳过）"
    fi
  else
    print_warn "无法获取时间戳（目录为空或 stat 命令不支持）"
  fi
else
  print_warn "业务领域目录或 .cache 目录不存在，跳过时序校验"
fi

# ============================================
# 汇总输出
# ============================================
if [ "$JSON_OUTPUT" = true ]; then
  echo "{"
  echo "  \"gate\": \"门控8：执行证据链校验\","
  echo "  \"kbRoot\": \"$KB_ROOT\","
  echo "  \"passed\": $PASS_COUNT,"
  echo "  \"failed\": $FAIL_COUNT,"
  echo "  \"warnings\": $WARN_COUNT,"
  echo "  \"allPassed\": $([ "$FAIL_COUNT" -eq 0 ] && echo true || echo false),"
  if [ ${#MISSING_EVIDENCE[@]} -gt 0 ]; then
    echo "  \"missingEvidence\": ["
    for i in "${!MISSING_EVIDENCE[@]}"; do
      echo -n "    \"${MISSING_EVIDENCE[$i]}\""
      [ $i -lt $((${#MISSING_EVIDENCE[@]} - 1)) ] && echo ","
    done
    echo ""
    echo "  ]"
  else
    echo "  \"missingEvidence\": []"
  fi
  if [ ${#FAIL_DETAILS[@]} -gt 0 ]; then
    if [ ${#MISSING_EVIDENCE[@]} -gt 0 ]; then echo ","; fi
    echo "  \"failures\": ["
    for i in "${!FAIL_DETAILS[@]}"; do
      echo -n "    \"${FAIL_DETAILS[$i]}\""
      [ $i -lt $((${#FAIL_DETAILS[@]} - 1)) ] && echo ","
    done
    echo ""
    echo "  ]"
  fi
  echo "}"
else
  echo ""
  echo "=========================================="
  echo "门控8 汇总: 通过 $PASS_COUNT | 失败 $FAIL_COUNT | 警告 $WARN_COUNT"
  if [ ${#MISSING_EVIDENCE[@]} -gt 0 ]; then
    echo ""
    echo "缺失证据清单（对应门控脚本可能未执行）:"
    for evidence in "${MISSING_EVIDENCE[@]}"; do
      echo "  - $evidence"
    done
    echo ""
    echo "修复建议: 执行缺失的门控脚本，或重新运行知识库生成流程"
  fi
  echo "=========================================="
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
