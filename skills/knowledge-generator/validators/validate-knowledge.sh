#!/usr/bin/env bash
#
# 知识库文件质量校验脚本（B1+B2 增强 v2.5.0）
# 校验知识库 .md 文件中的引用路径是否存在、模板字段是否完整、关键词是否重复。
# 同时校验 .summary.json 机器可读摘要是否存在（B3 AI 可消费性维度）。
#
# v2.4.0: 支持语言配置文件驱动，自动适配 Java/Vue/React 项目
# v2.5.0: 覆盖率不足从 WARN 升级为 FAIL（门控7），新增 core gap 零容忍校验
#
# 用法: bash validate-knowledge.sh <知识库文件.md> <项目根目录> [索引文件.md] [--json] [--lang <profile>]
#   --json: 输出 JSON 格式的结构化报告（便于 AI 消费）
#   --lang: 指定语言配置文件路径（不设则自动检测）
#
# 依赖: grep, awk, find（均为系统自带）
#
set -euo pipefail

KB_FILE=""
PROJECT_ROOT=""
INDEX_FILE=""
JSON_OUTPUT=false

# 解析参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUTPUT=true; shift ;;
    --lang)
      shift
      LANG_PROFILE="${1:-}"
      shift
      ;;
    *)
      if [ -z "$KB_FILE" ]; then KB_FILE="$1"
      elif [ -z "$PROJECT_ROOT" ]; then PROJECT_ROOT="$1"
      elif [ -z "$INDEX_FILE" ]; then INDEX_FILE="$1"
      fi
      shift ;;
  esac
done

# ============================================
# 加载语言配置（v2.4.0 新增）
# ============================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "${LANG_PROFILE:-}" ]; then
  LANG_PROFILE=$(bash "$SCRIPT_DIR/../lang-profiles/detect-language.sh" "$PROJECT_ROOT" 2>/dev/null \
    || echo "$SCRIPT_DIR/../lang-profiles/java.profile.sh")
fi

if [ -f "$LANG_PROFILE" ]; then
  # shellcheck disable=SC1090
  source "$LANG_PROFILE"
else
  # 兜底：内联 Java 默认值
  LANG_NAME="Java"
  LANG_PACKAGE_PREFIX_REGEX='\b(com|org|net|io|cn|edu|gov)\.[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)*\.[A-Z][a-zA-Z0-9_]*\b'
  LANG_CLASS_SUFFIX_REGEX='\b[A-Z][a-zA-Z0-9]+(Manager|Service|Controller|Facade|Enum|DO|DTO|Repository|Processor|Validator|Calculator|Helper|Builder|Factory|Adapter|Converter|Provider|Handler|Listener|Observer|Strategy)\b'
  LANG_CLASS_FILE_SUFFIX=".java"
fi

if [ -z "$KB_FILE" ] || [ -z "$PROJECT_ROOT" ]; then
  echo "用法: bash validate-knowledge.sh <知识库文件.md> <项目根目录> [索引文件.md] [--json]" >&2
  exit 2
fi

if [ ! -f "$KB_FILE" ]; then
  echo "错误: 知识库文件不存在: $KB_FILE" >&2
  exit 2
fi

if [ ! -d "$PROJECT_ROOT" ]; then
  echo "错误: 项目根目录不存在: $PROJECT_ROOT" >&2
  exit 2
fi

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
FAIL_DETAILS=()

if [ "$JSON_OUTPUT" = false ]; then
  print_pass() { echo "  [PASS] $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
  print_fail() { echo "  [FAIL] $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_DETAILS+=("$1"); }
  print_warn() { echo "  [WARN] $1"; WARN_COUNT=$((WARN_COUNT + 1)); }
else
  print_pass() { PASS_COUNT=$((PASS_COUNT + 1)); }
  print_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_DETAILS+=("$1"); }
  print_warn() { WARN_COUNT=$((WARN_COUNT + 1)); }
fi

# ============================================
# 校验1：模板必填章节完整性（按文档类型区分）
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo "--- 校验1: 模板必填章节完整性 ---"
fi

# 根据文档内容自动识别类型，选择对应的必填章节
# 业务领域类：是什么 + 核心文件 + 核心链路 + 排查建议 + 高风险点
# 数据模型类：是什么 + 核心表 + 排查建议
# 项目工具类：背景 + 使用说明 + 关键代码 + 排查建议
# 项目导航类：概述 + 核心目录 + 问题定位
# 架构专题类：是什么 + 架构拓扑 + 核心机制 + 排查建议 + 高风险点
# 待补充为所有类型的可选章节（不再列为必填）

if grep -q "## 架构拓扑\|## 架构决策记录" "$KB_FILE" 2>/dev/null; then
  # 架构专题类
  REQUIRED_SECTIONS=("架构拓扑" "核心机制" "排查建议")
elif grep -q "## 根模块\|## 子场景路由表\|## 架构特征清单" "$KB_FILE" 2>/dev/null; then
  # 项目导航类
  REQUIRED_SECTIONS=("概述" "核心目录" "问题定位")
elif grep -q "## 关键代码\|## 使用说明" "$KB_FILE" 2>/dev/null; then
  # 项目工具类
  REQUIRED_SECTIONS=("背景" "使用说明" "关键代码")
elif grep -q "## 核心表\|## 数据表" "$KB_FILE" 2>/dev/null; then
  # 数据模型类
  REQUIRED_SECTIONS=("是什么" "排查建议")
else
  # 业务领域类（默认）
  REQUIRED_SECTIONS=("是什么" "核心文件" "排查建议" "高风险点")
fi

for SECTION in "${REQUIRED_SECTIONS[@]}"; do
  if grep -q "## .*${SECTION}" "$KB_FILE" 2>/dev/null; then
    print_pass "章节存在: $SECTION"
  else
    print_warn "章节缺失: $SECTION"
  fi
done

# ============================================
# 校验2：核心文件表中引用的路径存在性（B2 增强）
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "--- 校验2: 核心文件路径存在性 ---"
fi

# B2增强：多种路径格式提取
# 格式1: Java 完整类名 (com.xxx.Yyy)
# 格式2: 反引号包裹的文件路径 (`xxx/src/main/...`)
# 格式3: Markdown 表格中的裸文件路径 (| ... | src/...)
# 格式4: 包含 /src/ 或 /main/ 的任意路径片段

# 提取 Java 完整类名（仅 Java 项目）
JAVA_CLASSES=""
if [ "$LANG_NAME" = "Java" ]; then
  JAVA_CLASSES=$(grep -oE "$LANG_PACKAGE_PREFIX_REGEX" "$KB_FILE" 2>/dev/null | sort -u || true)
fi

# 提取反引号包裹的文件路径（v2.4.0: 支持前端文件扩展名）
BACKTICK_PATHS=$(grep -oE '`[^`]*(/src/|/main/|/test/|/components/|/hooks/|/api/|/store/|/pages/|/views/|\.java|\.vue|\.py|\.ts|\.tsx|\.jsx|\.js|\.go)[^`]*`' "$KB_FILE" 2>/dev/null | sed 's/`//g' | sort -u || true)

# B2增强：提取 Markdown 表格中的裸路径（v2.4.0: 兼容前端路径）
if [ "$LANG_NAME" = "Java" ]; then
  TABLE_PATHS=$(grep -oE '\|\s*[^|`]*(/src/|/main/java/)[^|`]*\.' "$KB_FILE" 2>/dev/null \
    | sed 's/|\s*//' | sed 's/\.$//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' \
    | grep -v '^$' | sort -u || true)
else
  TABLE_PATHS=$(grep -oE '\|[[:space:]]*[^|`]*(/src/|/components/|/hooks/|/api/|/store/|/pages/|/views/)[^|`]*' "$KB_FILE" 2>/dev/null \
    | sed 's/|[[:space:]]*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' \
    | grep -v '^$' | sort -u || true)
fi

# 提取纯文件路径片段（v2.4.0: 兼容前端文件扩展名）
RAW_FILE_PATHS=$(grep -oE '[a-zA-Z0-9_/-]+/(src|components|hooks|api|store|pages|views)/[a-zA-Z0-9_/-]+\.(java|vue|py|ts|tsx|jsx|js|go)' "$KB_FILE" 2>/dev/null | sort -u || true)

if [ -n "$JAVA_CLASSES" ]; then
  while IFS= read -r FULL_CLASS; do
    [ -z "$FULL_CLASS" ] && continue
    REL_PATH=$(echo "$FULL_CLASS" | tr '.' '/')
    FOUND=$(find "$PROJECT_ROOT" -path "*/${REL_PATH}.java" -type f 2>/dev/null | head -1 || true)
    if [ -n "$FOUND" ]; then
      print_pass "类路径存在: $FULL_CLASS"
    else
      print_fail "类路径不存在: $FULL_CLASS"
    fi
  done <<< "$JAVA_CLASSES"
fi

# 合并所有文件路径进行校验
ALL_FILE_PATHS=$(echo -e "${BACKTICK_PATHS}\n${TABLE_PATHS}\n${RAW_FILE_PATHS}" | grep -v '^$' | sort -u || true)

if [ -n "$ALL_FILE_PATHS" ]; then
  while IFS= read -r FP; do
    [ -z "$FP" ] && continue
    # 尝试多种匹配方式
    if [ -f "${PROJECT_ROOT}/${FP}" ] || [ -f "$FP" ] || find "$PROJECT_ROOT" -path "*/${FP}" -type f 2>/dev/null | grep -q .; then
      print_pass "文件路径存在: $FP"
    else
      print_fail "文件路径不存在: $FP"
    fi
  done <<< "$ALL_FILE_PATHS"
fi

if [ -z "$JAVA_CLASSES" ] && [ -z "$ALL_FILE_PATHS" ]; then
  print_warn "未检测到可校验的路径引用"
fi

# ============================================
# 校验3：关键词重复检查
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "--- 校验3: 关键词重复检查 ---"
fi

if [ -n "$INDEX_FILE" ] && [ -f "$INDEX_FILE" ]; then
  KB_KEYWORDS=$(grep -oE "$LANG_CLASS_SUFFIX_REGEX" "$KB_FILE" 2>/dev/null | sort -u || true)
  if [ -n "$KB_KEYWORDS" ]; then
    while IFS= read -r KW; do
      [ -z "$KW" ] && continue
      MATCH_COUNT=$(grep -c "$KW" "$INDEX_FILE" 2>/dev/null || echo "0")
      if [ "$MATCH_COUNT" -gt 1 ]; then
        print_fail "关键词重复（索引中出现 ${MATCH_COUNT} 次）: $KW"
      elif [ "$MATCH_COUNT" -eq 1 ]; then
        print_pass "关键词无重复: $KW"
      fi
    done <<< "$KB_KEYWORDS"
  else
    print_warn "未检测到可校验的关键词"
  fi
else
  print_warn "未提供索引文件，跳过关键词重复检查"
fi

# ============================================
# 校验4：交叉引用路径检查
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "--- 校验4: 交叉引用路径检查 ---"
fi

MD_REFS=$(grep -oE '\[.*\]\(([^)]*\.md)\)' "$KB_FILE" 2>/dev/null | grep -oE '\([^)]*\.md\)' | tr -d '()' | sort -u || true)
if [ -n "$MD_REFS" ]; then
  while IFS= read -r REF; do
    [ -z "$REF" ] && continue
    KB_DIR=$(dirname "$KB_FILE")
    if [ -f "${KB_DIR}/${REF}" ]; then
      print_pass "交叉引用存在: $REF"
    else
      print_fail "交叉引用不存在: $REF"
    fi
  done <<< "$MD_REFS"
else
  print_warn "未检测到交叉引用"
fi

# ============================================
# 校验5：AI 可消费性检查（B3，FAIL 级别）
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "--- 校验5: AI 可消费性检查 ---"
fi

# 检查 .summary.json 是否存在
SUMMARY_FILE="${KB_FILE%.md}.summary.json"
if [ -f "$SUMMARY_FILE" ]; then
  print_pass "机器可读摘要存在: $(basename "$SUMMARY_FILE")"
  # 检查关键字段是否非空（使用 python3 校验顶层字段存在性）
  if command -v python3 &>/dev/null; then
    MISSING_FIELDS=$(python3 -c "
import json, sys
try:
    data = json.load(open('$SUMMARY_FILE'))
    required = ['domain', 'entryPoints', 'coreClasses', 'coreChain', 'stateMachine', 'grepHints', 'coverageGaps']
    missing = [f for f in required if f not in data or data[f] in (None, '', [], {})]
    if missing:
        print(' '.join(missing))
except Exception as e:
    print(f'__PARSE_ERROR__:{e}')
" 2>/dev/null || echo "__PARSE_ERROR__")

    if [ -z "$MISSING_FIELDS" ]; then
      print_pass "摘要关键字段完整（domain/entryPoints/coreClasses/coreChain/stateMachine/grepHints/coverageGaps）"
    elif echo "$MISSING_FIELDS" | grep -q "__PARSE_ERROR__" 2>/dev/null; then
      print_fail "summary.json 解析失败: $MISSING_FIELDS"
    else
      for FIELD in $MISSING_FIELDS; do
        print_fail "摘要字段缺失或为空: ${FIELD}"
      done
    fi
  else
    # python3 不可用时降级为 grep 检查（无法区分嵌套字段）
    for FIELD in "domain" "entryPoints" "coreClasses" "coreChain" "stateMachine" "grepHints" "coverageGaps"; do
      if grep -q "\"${FIELD}\"" "$SUMMARY_FILE" 2>/dev/null; then
        print_pass "摘要字段存在: ${FIELD}"
      else
        print_fail "摘要字段缺失: ${FIELD}"
      fi
    done
  fi
else
  print_fail "机器可读摘要不存在（.summary.json 是 AI 消费的首选入口，必须生成）"
fi

# ============================================
# 校验6：覆盖深度双维度校验（issue-004 增强）
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "--- 校验6: 覆盖深度双维度校验（密度 + 覆盖率） ---"
fi

# 维度1：密度校验（原有）- 核心链路描述行数/条数
CHAIN_SECTION=$(awk '/^## .*核心链路|^## .*核心逻辑/{found=1} found{print} /^## /{if(found && NR>1 && !/核心链路|核心逻辑/) exit}' "$KB_FILE" 2>/dev/null || true)
CHAIN_COUNT=$(echo "$CHAIN_SECTION" | grep -cE '^### |^- \*\*' 2>/dev/null || echo "0")
CHAIN_LINES=$(echo "$CHAIN_SECTION" | wc -l | tr -d ' ' || echo "0")

if [ "$CHAIN_COUNT" -gt 0 ]; then
  AVG_DENSITY=$((CHAIN_LINES / CHAIN_COUNT))
  if [ "$AVG_DENSITY" -ge 10 ]; then
    print_pass "链路描述密度达标（${AVG_DENSITY} 行/条，阈值 ≥10）"
  else
    print_warn "链路描述密度不足（${AVG_DENSITY} 行/条，阈值 ≥10）"
  fi
fi

# 维度2：待补充分类检查（issue-004 新增）
# 检查"待补充"章节是否区分了"核心子场景"和"实现细节"
PENDING_SECTION=$(awk '/^## 待补充/{found=1} found{print} /^## /{if(found && NR>1 && !/待补充/) exit}' "$KB_FILE" 2>/dev/null || true)

if [ -n "$PENDING_SECTION" ]; then
  # 检查是否有分类标记
  if echo "$PENDING_SECTION" | grep -qE '核心子场景|实现细节' 2>/dev/null; then
    print_pass "待补充章节已分类（核心子场景 / 实现细节）"

    # 统计核心子场景条目数
    CORE_PENDING=$(echo "$PENDING_SECTION" | awk '/核心子场景/{in_core=1; next} /实现细节/{in_core=0} in_core && /^- /{count++} END{print count+0}')
    if [ "$CORE_PENDING" -le 2 ]; then
      print_pass "核心子场景待补充 ≤ 2 条（${CORE_PENDING} 条）"
    else
      print_fail "核心子场景待补充 > 2 条（${CORE_PENDING} 条），不允许标记为「已完成」"
    fi
  else
    print_warn "待补充章节未区分「核心子场景」和「实现细节」（issue-004 要求分类）"
  fi
fi

# 维度3：覆盖率校验（需要 .summary.json 支持）
if [ -f "$SUMMARY_FILE" ] && command -v python3 &>/dev/null; then
  COVERAGE_RATE=$(python3 -c "
import json
try:
    data = json.load(open('$SUMMARY_FILE'))
    report = data.get('coverageReport', {})
    rate = report.get('methodCoverage', '0%')
    rate_num = int(rate.replace('%','').replace('unknown','0') or '0')
    print(rate_num)
except: print(0)
" 2>/dev/null || echo "0")

  if [ "$COVERAGE_RATE" -ge 70 ]; then
    print_pass "方法覆盖率达标（${COVERAGE_RATE}%，阈值 ≥70%）"
  else
    print_fail "方法覆盖率不足（${COVERAGE_RATE}%，阈值 ≥70%）— 门控7：禁止标记领域为「已完成」，必须补充阅读"
  fi

  # 维度4：待补充与 coverageGaps 一致性校验（v2.3.0 新增）
  # 检查 .md 的待补充章节是否与 .summary.json 的 coverageGaps 保持一致
  COVERAGE_GAPS_COUNT=$(python3 -c "
import json
try:
    data = json.load(open('$SUMMARY_FILE'))
    gaps = data.get('coverageGaps', [])
    print(len(gaps))
except: print(0)
" 2>/dev/null || echo "0")

  HAS_PENDING_SECTION=0
  if grep -q "## 待补充" "$KB_FILE" 2>/dev/null; then
    HAS_PENDING_SECTION=1
  fi

  if [ "$COVERAGE_GAPS_COUNT" -eq 0 ] && [ "$HAS_PENDING_SECTION" -eq 1 ]; then
    print_warn "coverageGaps 为空但 .md 仍有「待补充」章节（建议删除空壳章节）"
  elif [ "$COVERAGE_GAPS_COUNT" -gt 0 ] && [ "$HAS_PENDING_SECTION" -eq 0 ]; then
    print_warn "coverageGaps 非空但 .md 无「待补充」章节（建议补充或确认 coverageGaps）"
  elif [ "$COVERAGE_GAPS_COUNT" -eq 0 ] && [ "$HAS_PENDING_SECTION" -eq 0 ]; then
    print_pass "待补充与 coverageGaps 一致（均为空，领域已充分覆盖）"
  else
    print_pass "待补充与 coverageGaps 一致（均非空）"
  fi

  # 维度5：core gap 零容忍校验（v2.5.0 新增，issue 反馈修复）
  # coverageGaps 中不允许存在 gapType=core 的条目
  CORE_GAP_COUNT=$(python3 -c "
import json
try:
    data = json.load(open('$SUMMARY_FILE'))
    gaps = data.get('coverageGaps', [])
    core_gaps = [g for g in gaps if g.get('gapType') == 'core']
    print(len(core_gaps))
except: print(0)
" 2>/dev/null || echo "0")

  if [ "$CORE_GAP_COUNT" -eq 0 ]; then
    print_pass "coverageGaps 中无 core gap（零容忍通过）"
  else
    print_fail "coverageGaps 中存在 ${CORE_GAP_COUNT} 个 core gap — 门控7：core gap 零容忍，存在任何 core gap 时不允许标记领域为「已完成」，必须先补充"
  fi

  # 维度6：coreChain 未验证信息检查（v2.5.0 新增，issue 2.1 反馈修复）
  # coreChain 中不允许存在 confidence=low 且 confidenceNote 包含「未完整阅读/未验证/推断」的条目
  UNVERIFIED_CHAIN_COUNT=$(python3 -c "
import json
try:
    data = json.load(open('$SUMMARY_FILE'))
    chains = data.get('coreChain', [])
    unverified = []
    for c in chains:
        if c.get('confidence') == 'low':
            note = c.get('confidenceNote', '')
            if any(kw in note for kw in ['未完整阅读', '未验证', '推断', '猜测', '未确认']):
                unverified.append(c)
    print(len(unverified))
except: print(0)
" 2>/dev/null || echo "0")

  if [ "$UNVERIFIED_CHAIN_COUNT" -eq 0 ]; then
    print_pass "coreChain 中无未验证信息（confidence=low 且标注未阅读/未验证）"
  else
    print_fail "coreChain 中存在 ${UNVERIFIED_CHAIN_COUNT} 条未验证信息 — 禁止在 coreChain 中使用未经验证的信息，未执行深度阅读的链路应为空或标注为 coverageGaps"
  fi
fi

# ============================================
# 汇总输出
# ============================================
if [ "$JSON_OUTPUT" = true ]; then
  # JSON 结构化报告
  echo "{"
  echo "  \"file\": \"$(basename "$KB_FILE")\","
  echo "  \"passed\": $PASS_COUNT,"
  echo "  \"failed\": $FAIL_COUNT,"
  echo "  \"warnings\": $WARN_COUNT,"
  echo "  \"allPassed\": $([ "$FAIL_COUNT" -eq 0 ] && echo true || echo false),"
  if [ ${#FAIL_DETAILS[@]} -gt 0 ]; then
    echo "  \"failures\": ["
    for i in "${!FAIL_DETAILS[@]}"; do
      echo -n "    \"${FAIL_DETAILS[$i]}\""
      [ $i -lt $((${#FAIL_DETAILS[@]} - 1)) ] && echo ","
    done
    echo ""
    echo "  ]"
  else
    echo "  \"failures\": []"
  fi
  echo "}"
else
  echo ""
  echo "=========================================="
  echo "校验汇总: 通过 $PASS_COUNT | 失败 $FAIL_COUNT | 警告 $WARN_COUNT"
  if [ ${#FAIL_DETAILS[@]} -gt 0 ]; then
    echo ""
    echo "失败项明细:"
    for detail in "${FAIL_DETAILS[@]}"; do
      echo "  - $detail"
    done
  fi
  echo "=========================================="
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
