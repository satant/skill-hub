#!/usr/bin/env bash
#
# 知识库索引分区完整性校验（门控6，v2.5.0 新增）
# 校验知识库索引文件是否包含六个必需分区表头 + 外部依赖清单。
#
# 解决问题：subagent 生成知识库时只创建 2 个分区（项目导航 + 业务领域），
# 缺失数据模型/项目工具/架构专题/外部依赖四个分区，导致索引不完整。
#
# v2.5.0: issue 反馈「三分区为空」核心修复
#
# 用法: bash validate-index-completeness.sh <索引文件.md> [--json]
#   --json: 输出 JSON 格式的结构化报告
#
# 依赖: grep（系统自带）
#
set -euo pipefail

INDEX_FILE=""
JSON_OUTPUT=false

# 解析参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUTPUT=true; shift ;;
    *)
      if [ -z "$INDEX_FILE" ]; then INDEX_FILE="$1"; fi
      shift ;;
  esac
done

if [ -z "$INDEX_FILE" ]; then
  echo "用法: bash validate-index-completeness.sh <索引文件.md> [--json]" >&2
  exit 2
fi

if [ ! -f "$INDEX_FILE" ]; then
  echo "错误: 索引文件不存在: $INDEX_FILE" >&2
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
# 校验1：六分区表头完整性（门控6 核心）
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo "--- 校验1: 六分区表头完整性 ---"
fi

# 六个必需分区（支持多种写法）
# 格式: "分区名|别名1|别名2"
REQUIRED_SECTIONS=(
  "项目导航"
  "业务领域"
  "数据模型"
  "项目工具"
  "外部依赖|外部依赖清单"
  "架构专题"
)

MISSING_SECTIONS=()

for SECTION_SPEC in "${REQUIRED_SECTIONS[@]}"; do
  # 按管道分割别名
  IFS='|' read -ra ALIASES <<< "$SECTION_SPEC"
  FOUND=false
  for ALIAS in "${ALIASES[@]}"; do
    # 匹配 ## 开头的标题行（支持二级/三级标题）
    if grep -qE "^#{2,3}[[:space:]]+.*${ALIAS}" "$INDEX_FILE" 2>/dev/null; then
      FOUND=true
      print_pass "分区表头存在: ${ALIAS}"
      break
    fi
  done
  if [ "$FOUND" = false ]; then
    PRIMARY_NAME="${ALIASES[0]}"
    print_fail "分区表头缺失: ${PRIMARY_NAME}"
    MISSING_SECTIONS+=("$PRIMARY_NAME")
  fi
done

# ============================================
# 校验2：空分区标记检查（有表头但无内容）
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "--- 校验2: 空分区内容检查 ---"
fi

# 检查有表头但内容为「待生成」或完全无内容的分区
EMPTY_MARKED_SECTIONS=()
while IFS= read -r line; do
  if echo "$line" | grep -qE '^#{2,3}[[:space:]]+'; then
    SECTION_TITLE=$(echo "$line" | sed 's/^#*[[:space:]]*//' | tr -d ' ')
    # 跳过非六分区的标题
    case "$SECTION_TITLE" in
      *项目导航*|*业务领域*|*数据模型*|*项目工具*|*外部依赖*|*架构专题*)
        # 检查该标题下是否有实质内容（非空行、非「待生成」标记）
        # 使用 awk 提取该标题到下一个同级标题之间的内容
        SECTION_CONTENT=$(awk -v target="$line" '
          $0 ~ target { found=1; next }
          found && /^#{2,3}[[:space:]]/ { exit }
          found { print }
        ' "$INDEX_FILE" 2>/dev/null | grep -vE '^[[:space:]]*$|待生成|TODO|待补充' || true)

        if [ -z "$SECTION_CONTENT" ]; then
          EMPTY_MARKED_SECTIONS+=("$SECTION_TITLE")
          print_warn "分区内容为空或仅标记「待生成」: ${SECTION_TITLE}"
        fi
        ;;
    esac
  fi
done < "$INDEX_FILE"

# ============================================
# 校验3：外部依赖清单表格格式检查
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "--- 校验3: 外部依赖清单格式 ---"
fi

# 检查外部依赖清单是否有表格结构
if grep -qE '^#{2,3}[[:space:]]+.*外部依赖' "$INDEX_FILE" 2>/dev/null; then
  # 提取外部依赖分区内容
  DEPENDENCY_SECTION=$(awk '/^#{2,3}[[:space:]]+.*外部依赖/{found=1} found{print} /^#{2,3}[[:space:]]/ && found && NR>1 && !/外部依赖/ {exit}' "$INDEX_FILE" 2>/dev/null || true)

  if echo "$DEPENDENCY_SECTION" | grep -qE '\|.*\|.*\|' 2>/dev/null; then
    print_pass "外部依赖清单包含表格结构"
  else
    print_warn "外部依赖清单缺少表格结构（应有列：依赖名称/Maven坐标/知识库文档/是否已反编译/备注）"
  fi
else
  print_warn "无外部依赖清单分区（首次生成时允许，后续应补充）"
fi

# ============================================
# 汇总输出
# ============================================
if [ "$JSON_OUTPUT" = true ]; then
  echo "{"
  echo "  \"file\": \"$(basename "$INDEX_FILE")\","
  echo "  \"passed\": $PASS_COUNT,"
  echo "  \"failed\": $FAIL_COUNT,"
  echo "  \"warnings\": $WARN_COUNT,"
  echo "  \"allPassed\": $([ "$FAIL_COUNT" -eq 0 ] && echo true || echo false),"
  if [ ${#MISSING_SECTIONS[@]} -gt 0 ]; then
    echo "  \"missingSections\": ["
    for i in "${!MISSING_SECTIONS[@]}"; do
      echo -n "    \"${MISSING_SECTIONS[$i]}\""
      [ $i -lt $((${#MISSING_SECTIONS[@]} - 1)) ] && echo ","
    done
    echo ""
    echo "  ]"
  else
    echo "  \"missingSections\": []"
  fi
  if [ ${#FAIL_DETAILS[@]} -gt 0 ]; then
    if [ ${#MISSING_SECTIONS[@]} -gt 0 ]; then echo ","; fi
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
  echo "校验汇总: 通过 $PASS_COUNT | 失败 $FAIL_COUNT | 警告 $WARN_COUNT"
  if [ ${#MISSING_SECTIONS[@]} -gt 0 ]; then
    echo ""
    echo "缺失分区:"
    for section in "${MISSING_SECTIONS[@]}"; do
      echo "  - $section"
    done
    echo ""
    echo "修复建议: 在索引文件中补充以下分区表头（即使暂无内容也要有「待生成」标记）:"
    for section in "${MISSING_SECTIONS[@]}"; do
      echo "  ## ${section}"
      echo "  > 待生成"
      echo ""
    done
  fi
  echo "=========================================="
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
