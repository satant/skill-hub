#!/usr/bin/env bash
#
# 知识库体检脚本（失效扫描 v2.4.0）
# 扫描知识库文件中引用的类名/方法名/路径，在项目源码中验证是否存在，输出失效报告。
#
# v2.4.0: 支持语言配置文件驱动，自动适配 Java/Vue/React 项目
#
# 用法: bash audit-knowledge.sh <知识库目录> <项目源码目录> [--lang <profile>]
# 依赖: grep, find, awk（均为系统自带）
#
set -euo pipefail

KB_DIR="${1:-}"
SRC_DIR="${2:-}"

# 解析 --lang 参数
ARGS=("$@")
for i in "${!ARGS[@]}"; do
  if [ "${ARGS[$i]}" = "--lang" ] && [ $((i + 1)) -lt ${#ARGS[@]} ]; then
    LANG_PROFILE="${ARGS[$((i + 1))]:-}"
  fi
done

if [ -z "$KB_DIR" ] || [ -z "$SRC_DIR" ]; then
  echo "用法: bash audit-knowledge.sh <知识库目录> <项目源码目录> [--lang <profile>]" >&2
  exit 1
fi

if [ ! -d "$KB_DIR" ]; then
  echo "错误: 知识库目录不存在: $KB_DIR" >&2
  exit 1
fi

if [ ! -d "$SRC_DIR" ]; then
  echo "错误: 源码目录不存在: $SRC_DIR" >&2
  exit 1
fi

# ============================================
# 加载语言配置（v2.4.0 新增）
# ============================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "${LANG_PROFILE:-}" ]; then
  LANG_PROFILE=$(bash "$SCRIPT_DIR/../lang-profiles/detect-language.sh" "$SRC_DIR" 2>/dev/null \
    || echo "$SCRIPT_DIR/../lang-profiles/java.profile.sh")
fi

if [ -f "$LANG_PROFILE" ]; then
  # shellcheck disable=SC1090
  source "$LANG_PROFILE"
else
  # 兜底：内联 Java 默认值
  LANG_NAME="Java"
  LANG_PACKAGE_PREFIX_REGEX='(com|org|net|io|cn)\.[a-zA-Z0-9_.]+[A-Z][a-zA-Z0-9_]*'
  LANG_CLASS_FILE_SUFFIX=".java"
fi

HEALTHY_COUNT=0
FAILED_COUNT=0
SUSPECT_COUNT=0

echo "=========================================="
echo "知识库体检报告"
echo "知识库目录: $KB_DIR"
echo "源码目录: $SRC_DIR"
echo "=========================================="
echo ""

# 收集所有知识库 .md 文件
KB_FILES=$(find "$KB_DIR" -name "*.md" -type f 2>/dev/null || true)

if [ -z "$KB_FILES" ]; then
  echo "未找到知识库文件"
  exit 0
fi

echo "### 失效引用（代码中已不存在）"
echo ""
echo "| 知识库文件 | 引用内容 | 类型 | 建议操作 |"
echo "| --- | --- | --- | --- |"

for KB in $KB_FILES; do
  KB_NAME=$(basename "$KB")

  # ============================================
  # 1. 提取并校验类名/路径引用
  # ============================================
  if [ "$LANG_NAME" = "Java" ]; then
    # Java: 提取包名引用
    CLASS_REFS=$(grep -oE "$LANG_PACKAGE_PREFIX_REGEX" "$KB" 2>/dev/null | sort -u || true)
  else
    # 前端: 提取文件路径引用（src/xxx 或 components/xxx 等）
    CLASS_REFS=$(grep -oE '`[^`]*(src/|components/|hooks/|api/|store/|pages/|views/)[^`]*`' "$KB" 2>/dev/null | sed 's/`//g' | sort -u || true)
  fi

  if [ -n "$CLASS_REFS" ]; then
    while IFS= read -r ref; do
      [ -z "$ref" ] && continue

      if [ "$LANG_NAME" = "Java" ]; then
        REL_PATH=$(echo "$ref" | tr '.' '/')
        FOUND=$(find "$SRC_DIR" -path "*/${REL_PATH}.java" -type f 2>/dev/null | head -1 || true)
        CLASS_NAME=$(echo "$ref" | sed 's/.*\.//' || true)
      else
        # 前端: 直接按路径查找
        FOUND=""
        if [ -f "${SRC_DIR}/${ref}" ]; then
          FOUND="$ref"
        else
          FOUND=$(find "$SRC_DIR" -path "*/${ref}" -type f 2>/dev/null | head -1 || true)
        fi
        CLASS_NAME=$(basename "$ref" | sed 's/\.[^.]*$//' || true)
      fi

      if [ -z "$FOUND" ]; then
        # 再用类名/文件名搜索一次
        if [ "$LANG_NAME" = "Java" ]; then
          NAME_FOUND=$(find "$SRC_DIR" -name "${CLASS_NAME}.java" -type f 2>/dev/null | head -1 || true)
        else
          NAME_FOUND=$(find "$SRC_DIR" -name "${CLASS_NAME}.*" \( -name "*.vue" -o -name "*.ts" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.js" \) -not -path "*/node_modules/*" -type f 2>/dev/null | head -1 || true)
        fi
        if [ -z "$NAME_FOUND" ]; then
          echo "| $KB_NAME | $ref | 文件已移除 | 检查替代文件并更新 |"
          FAILED_COUNT=$((FAILED_COUNT + 1))
        else
          echo "| $KB_NAME | $ref | 路径变更（文件名仍存在） | 更新路径引用 |"
          SUSPECT_COUNT=$((SUSPECT_COUNT + 1))
        fi
      else
        HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
      fi
    done <<< "$CLASS_REFS"
  fi

  # ============================================
  # 2. 提取并校验文件路径引用（v2.4.0: 兼容前端路径）
  # ============================================
  FILE_REFS=$(grep -oE '`[^`]*(src/|/main/|/test/|components/|hooks/|api/|store/|pages/|views/)[^`]*`' "$KB" 2>/dev/null | sed 's/`//g' | sort -u || true)

  if [ -n "$FILE_REFS" ]; then
    while IFS= read -r ref; do
      [ -z "$ref" ] && continue
      if [ ! -f "${SRC_DIR}/${ref}" ] && [ ! -f "$ref" ]; then
        echo "| $KB_NAME | $ref | 文件路径不存在 | 更新或删除引用 |"
        FAILED_COUNT=$((FAILED_COUNT + 1))
      else
        HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
      fi
    done <<< "$FILE_REFS"
  fi

  # ============================================
  # 3. 提取并校验方法名引用（ClassName.methodName 格式）
  # ============================================
  METHOD_REFS=$(grep -oE '[A-Z][a-zA-Z0-9]+\.[a-z][a-zA-Z0-9]*\(\)' "$KB" 2>/dev/null | sort -u || true)

  if [ -n "$METHOD_REFS" ]; then
    while IFS= read -r ref; do
      [ -z "$ref" ] && continue
      CLASS_PART=$(echo "$ref" | sed 's/\..*//' || true)
      METHOD_PART=$(echo "$ref" | sed 's/.*\.//;s/()//' || true)

      # 找到类文件
      if [ "$LANG_NAME" = "Java" ]; then
        CLASS_FILE=$(find "$SRC_DIR" -name "${CLASS_PART}.java" -type f 2>/dev/null | head -1 || true)
      else
        CLASS_FILE=$(find "$SRC_DIR" -name "${CLASS_PART}.*" \( -name "*.vue" -o -name "*.ts" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.js" \) -not -path "*/node_modules/*" -type f 2>/dev/null | head -1 || true)
      fi
      if [ -n "$CLASS_FILE" ]; then
        # 在类文件中搜索方法定义
        if [ "$LANG_NAME" = "Java" ]; then
          if ! grep -qE "(public|protected|private|static).*${METHOD_PART}\s*\(" "$CLASS_FILE" 2>/dev/null; then
            echo "| $KB_NAME | $ref | 方法已删除或重命名 | 更新方法引用 |"
            FAILED_COUNT=$((FAILED_COUNT + 1))
          else
            HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
          fi
        else
          # 前端: 匹配函数定义
          if ! grep -qE "(function[[:space:]]+${METHOD_PART}|const[[:space:]]+${METHOD_PART}|async[[:space:]]+${METHOD_PART}|${METHOD_PART}[[:space:]]*\()" "$CLASS_FILE" 2>/dev/null; then
            echo "| $KB_NAME | $ref | 方法已删除或重命名 | 更新方法引用 |"
            FAILED_COUNT=$((FAILED_COUNT + 1))
          else
            HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
          fi
        fi
      fi
    done <<< "$METHOD_REFS"
  fi

done

echo ""
echo "### 存疑引用（类存在但方法签名可能变更）"
echo ""
echo "| 知识库文件 | 引用内容 | 问题 | 建议操作 |"
echo "| --- | --- | --- | --- |"
echo "（需 AI 结合上下文进一步判断，脚本仅标记方法名未匹配项）"
echo ""

echo "### 健康引用"
echo ""
echo "共 $HEALTHY_COUNT 条引用校验通过。"
echo ""
echo "=========================================="
echo "体检汇总: 健康 $HEALTHY_COUNT | 失效 $FAILED_COUNT | 存疑 $SUSPECT_COUNT"
echo "=========================================="

if [ "$FAILED_COUNT" -gt 0 ]; then
  exit 1
fi
