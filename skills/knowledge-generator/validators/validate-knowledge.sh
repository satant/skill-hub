#!/usr/bin/env bash
#
# 知识库文件质量校验脚本
# 校验知识库 .md 文件中的引用路径是否存在、模板字段是否完整、关键词是否重复。
#
# 用法: bash validate-knowledge.sh <知识库文件.md> <项目根目录> [索引文件.md]
# 依赖: grep, awk, find（均为系统自带）
#
set -euo pipefail

KB_FILE="${1:-}"
PROJECT_ROOT="${2:-}"
INDEX_FILE="${3:-}"

if [ -z "$KB_FILE" ] || [ -z "$PROJECT_ROOT" ]; then
  echo "用法: bash validate-knowledge.sh <知识库文件.md> <项目根目录> [索引文件.md]" >&2
  exit 1
fi

if [ ! -f "$KB_FILE" ]; then
  echo "错误: 知识库文件不存在: $KB_FILE" >&2
  exit 1
fi

if [ ! -d "$PROJECT_ROOT" ]; then
  echo "错误: 项目根目录不存在: $PROJECT_ROOT" >&2
  exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

print_pass() { echo "  [PASS] $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
print_fail() { echo "  [FAIL] $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
print_warn() { echo "  [WARN] $1"; WARN_COUNT=$((WARN_COUNT + 1)); }

echo "=========================================="
echo "知识库质量校验报告"
echo "文件: $KB_FILE"
echo "项目: $PROJECT_ROOT"
echo "=========================================="
echo ""

# ============================================
# 校验1：模板必填章节完整性
# ============================================
echo "--- 校验1: 模板必填章节完整性 ---"

REQUIRED_SECTIONS=("是什么" "核心文件" "排查建议" "高风险点" "待补充")
for SECTION in "${REQUIRED_SECTIONS[@]}"; do
  if grep -q "## .*${SECTION}" "$KB_FILE" 2>/dev/null; then
    print_pass "章节存在: $SECTION"
  else
    # 导航类和工具类的必填章节不同，做宽容检查
    print_warn "章节缺失（若为导航类/工具类模板可忽略）: $SECTION"
  fi
done
echo ""

# ============================================
# 校验2：核心文件表中引用的路径存在性
# ============================================
echo "--- 校验2: 核心文件路径存在性 ---"

# 提取表格中的路径引用（com.xxx.Yyy 格式的 Java 类名，或 src/ 开头的路径）
PATHS=$(grep -oE '(com|org|net|io|cn)\.[a-zA-Z0-9_.]+[A-Z][a-zA-Z0-9_]*' "$KB_FILE" 2>/dev/null | sort -u || true)
FILE_PATHS=$(grep -oE '`[^`]*(src/|/main/)[^`]*`' "$KB_FILE" 2>/dev/null | sed 's/`//g' | sort -u || true)

if [ -n "$PATHS" ]; then
  while IFS= read -r FULL_CLASS; do
    [ -z "$FULL_CLASS" ] && continue
    # 将 com.example.xxx.Yyy 转换为可能的文件路径
    REL_PATH=$(echo "$FULL_CLASS" | tr '.' '/')
    FOUND=$(find "$PROJECT_ROOT" -path "*/${REL_PATH}.java" -type f 2>/dev/null | head -1 || true)
    if [ -n "$FOUND" ]; then
      print_pass "类路径存在: $FULL_CLASS"
    else
      print_fail "类路径不存在: $FULL_CLASS"
    fi
  done <<< "$PATHS"
fi

if [ -n "$FILE_PATHS" ]; then
  while IFS= read -r FP; do
    [ -z "$FP" ] && continue
    if [ -f "${PROJECT_ROOT}/${FP}" ] || [ -f "$FP" ]; then
      print_pass "文件路径存在: $FP"
    else
      print_fail "文件路径不存在: $FP"
    fi
  done <<< "$FILE_PATHS"
fi

if [ -z "$PATHS" ] && [ -z "$FILE_PATHS" ]; then
  print_warn "未检测到可校验的路径引用"
fi
echo ""

# ============================================
# 校验3：关键词重复检查（需要索引文件）
# ============================================
echo "--- 校验3: 关键词重复检查 ---"

if [ -n "$INDEX_FILE" ] && [ -f "$INDEX_FILE" ]; then
  # 提取知识库文件中的表格行（候选关键词来源）
  KB_KEYWORDS=$(grep -oE '\b[A-Z][a-zA-Z0-9]+(Manager|Service|Controller|Facade|Enum|DO|DTO)\b' "$KB_FILE" 2>/dev/null | sort -u || true)

  if [ -n "$KB_KEYWORDS" ]; then
    while IFS= read -r KW; do
      [ -z "$KW" ] && continue
      # 在索引文件中搜索该关键词
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
echo ""

# ============================================
# 校验4：交叉引用路径检查
# ============================================
echo "--- 校验4: 交叉引用路径检查 ---"

# 提取引用其他 .md 文件的路径
MD_REFS=$(grep -oE '\[.*\]\(([^)]*\.md)\)' "$KB_FILE" 2>/dev/null | grep -oE '\([^)]*\.md\)' | tr -d '()' | sort -u || true)

if [ -n "$MD_REFS" ]; then
  while IFS= read -ref; do
    [ -z "$ref" ] && continue
    # 解析相对路径
    KB_DIR=$(dirname "$KB_FILE")
    if [ -f "${KB_DIR}/${ref}" ]; then
      print_pass "交叉引用存在: $ref"
    else
      print_fail "交叉引用不存在: $ref"
    fi
  done <<< "$MD_REFS"
else
  print_warn "未检测到交叉引用"
fi
echo ""

# ============================================
# 汇总
# ============================================
echo "=========================================="
echo "校验汇总: 通过 $PASS_COUNT | 失败 $FAIL_COUNT | 警告 $WARN_COUNT"
echo "=========================================="

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
