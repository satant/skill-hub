#!/usr/bin/env bash
#
# 知识库体检脚本（失效扫描）
# 扫描知识库文件中引用的类名/方法名/路径，在项目源码中验证是否存在，输出失效报告。
#
# 用法: bash audit-knowledge.sh <知识库目录> <项目源码目录>
# 依赖: grep, find, awk（均为系统自带）
#
set -euo pipefail

KB_DIR="${1:-}"
SRC_DIR="${2:-}"

if [ -z "$KB_DIR" ] || [ -z "$SRC_DIR" ]; then
  echo "用法: bash audit-knowledge.sh <知识库目录> <项目源码目录>" >&2
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
  # 1. 提取并校验 Java 类名引用
  # ============================================
  CLASS_REFS=$(grep -oE '(com|org|net|io|cn)\.[a-zA-Z0-9_.]+[A-Z][a-zA-Z0-9_]*' "$KB" 2>/dev/null | sort -u || true)

  if [ -n "$CLASS_REFS" ]; then
    while IFS= read -ref; do
      [ -z "$ref" ] && continue
      REL_PATH=$(echo "$ref" | tr '.' '/')
      FOUND=$(find "$SRC_DIR" -path "*/${REL_PATH}.java" -type f 2>/dev/null | head -1 || true)

      # 提取纯类名（最后一段）
      CLASS_NAME=$(echo "$ref" | sed 's/.*\.//' || true)

      if [ -z "$FOUND" ]; then
        # 再用类名搜索一次（可能包名变了）
        NAME_FOUND=$(find "$SRC_DIR" -name "${CLASS_NAME}.java" -type f 2>/dev/null | head -1 || true)
        if [ -z "$NAME_FOUND" ]; then
          echo "| $KB_NAME | $ref | 类已移除 | 检查替代类并更新 |"
          FAILED_COUNT=$((FAILED_COUNT + 1))
        else
          echo "| $KB_NAME | $ref | 包路径变更（类名仍存在） | 更新包路径引用 |"
          SUSPECT_COUNT=$((SUSPECT_COUNT + 1))
        fi
      else
        HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
      fi
    done <<< "$CLASS_REFS"
  fi

  # ============================================
  # 2. 提取并校验文件路径引用
  # ============================================
  FILE_REFS=$(grep -oE '`[^`]*(src/|/main/|/test/)[^`]*`' "$KB" 2>/dev/null | sed 's/`//g' | sort -u || true)

  if [ -n "$FILE_REFS" ]; then
    while IFS= read -ref; do
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
    while IFS= read -ref; do
      [ -z "$ref" ] && continue
      CLASS_PART=$(echo "$ref" | sed 's/\..*//' || true)
      METHOD_PART=$(echo "$ref" | sed 's/.*\.//;s/()//' || true)

      # 找到类文件
      CLASS_FILE=$(find "$SRC_DIR" -name "${CLASS_PART}.java" -type f 2>/dev/null | head -1 || true)
      if [ -n "$CLASS_FILE" ]; then
        # 在类文件中搜索方法定义
        if ! grep -qE "(public|protected|private|static).*${METHOD_PART}\s*\(" "$CLASS_FILE" 2>/dev/null; then
          echo "| $KB_NAME | $ref | 方法已删除或重命名 | 更新方法引用 |"
          FAILED_COUNT=$((FAILED_COUNT + 1))
        else
          HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
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
