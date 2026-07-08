#!/usr/bin/env bash
#
# Java 类签名提取脚本
# 提取 .java 文件的类级注释 + public/protected 方法签名，输出 JSON。
#
# 用法: bash extract-signature-java.sh <源码文件或目录>
# 依赖: grep, awk, find（均为系统自带）
#
set -euo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "用法: bash extract-signature-java.sh <源码文件或目录>" >&2
  exit 1
fi

# 收集所有 .java 文件
if [ -d "$TARGET" ]; then
  # 用 while read 避免空格断裂（兼容 Git Bash 3.x 无 mapfile）
  FILES=()
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(find "$TARGET" -name "*.java" -type f 2>/dev/null || true)
else
  FILES=("$TARGET")
fi

if [ ${#FILES[@]} -eq 0 ]; then
  echo '{"files":[]}'
  exit 0
fi

echo -n '{"files":['
FIRST_FILE=1

for FILE in "${FILES[@]}"; do
  [ -f "$FILE" ] || continue

  [ "$FIRST_FILE" -eq 0 ] && echo -n ','
  FIRST_FILE=0

  # 提取 package
  PKG=$(grep -m1 '^package ' "$FILE" 2>/dev/null | sed 's/package //;s/;//' | tr -d '[:space:]' || true)

  # 提取类名
  CLASS_LINE=$(grep -mE '^(public |abstract |final )*(class|interface|enum) ' "$FILE" 2>/dev/null | head -1 || true)
  CLASS_NAME=$(echo "$CLASS_LINE" | sed -E 's/.*(class|interface|enum) +([A-Za-z0-9_]+).*/\2/' || true)

  # 提取类级注释（文件开头的 /** ... */，取前 5 行内容）
  CLASS_DOC=$(awk '/^\/\*\*/{found=1} found{print} /\*\//{if(found) exit}' "$FILE" 2>/dev/null \
    | head -5 \
    | sed 's/"/\\"/g' | tr '\n' ' ' \
    | sed 's/[[:space:]]*$//' || true)

  echo -n "{\"file\":\"$FILE\",\"package\":\"${PKG:-}\",\"className\":\"${CLASS_NAME:-}\",\"classDoc\":\"${CLASS_DOC:-}\",\"methods\":["

  # 提取 public/protected 方法签名
  METHODS_OUTPUT=$(grep -nE '^\s*(public|protected)\s+(static\s+)?(synchronized\s+)?(final\s+)?[A-Za-z0-9_<>\[\],?\s]+\s+[a-zA-Z0-9_]+\s*\(' "$FILE" 2>/dev/null \
    | grep -v '^\s*.*class ' \
    | grep -v '^\s*.*interface ' \
    | grep -v '^\s*.*enum ' || true)

  FIRST_METHOD=1
  if [ -n "$METHODS_OUTPUT" ]; then
    while IFS= read -r line; do
      LINE_NUM=$(echo "$line" | cut -d: -f1)
      SIGNATURE=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//' | sed 's/"/\\"/g')
      [ "$FIRST_METHOD" -eq 0 ] && echo -n ','
      FIRST_METHOD=0
      echo -n "{\"line\":$LINE_NUM,\"signature\":\"${SIGNATURE}\"}"
    done <<< "$METHODS_OUTPUT"
  fi

  echo -n ']}'
done

echo ']}'
