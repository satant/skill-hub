#!/usr/bin/env bash
#
# 业务术语候选字符串提取器（A1）
# 从项目源码中提取含中文的字符串常量，作为业务术语字典的候选输入。
# 注意：本脚本只负责提取"候选字符串"，分词和归类由 AI 在步骤4完成。
#
# 用法: bash extract-business-terms.sh <源码目录> [输出文件]
# 依赖: grep（需支持 -P 或 rg）
#
set -euo pipefail

SRC_DIR="${1:-}"
OUTPUT_FILE="${2:-/dev/stdout}"

if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
  echo "用法: bash extract-business-terms.sh <源码目录> [输出文件]" >&2
  exit 1
fi

# 检查是否有 rg（ripgrep），否则用 perl 辅助 grep
if command -v rg &>/dev/null; then
  SEARCH_CMD="rg"
  # rg 正则：匹配引号内的中文字符串（至少包含2个中文字符）
  RG_PATTERN='"[^"]*[\x{4e00}-\x{9fff}][^"]*[\x{4e00}-\x{9fff}][^"]*"'
  RG_GLOB='*.{java,py,js,ts,jsx,tsx,go}'
else
  # grep 降级模式：用 perl 做正则匹配（macOS 自带 perl）
  SEARCH_CMD="perl"
fi

{
  echo "# 业务术语候选字符串清单"
  echo "# 生成时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# 源码目录: $SRC_DIR"
  echo "# 说明: 本文件仅包含候选字符串，需由 AI 进行分词和归类形成业务术语字典"
  echo ""

  # 提取中文字符串，去重，按出现频率排序
  if [ "$SEARCH_CMD" = "rg" ]; then
    rg -o "$RG_PATTERN" -g "$RG_GLOB" "$SRC_DIR" 2>/dev/null \
      | tr -d '"' \
      | sort | uniq -c | sort -rn \
      | head -200 \
      | while IFS= read -r line; do
          COUNT=$(echo "$line" | awk '{print $1}')
          TEXT=$(echo "$line" | cut -d' ' -f2-)
          echo "| ${COUNT} | ${TEXT} |"
        done
  elif [ "$SEARCH_CMD" = "perl" ]; then
    # perl 降级模式：遍历文件用 perl 提取中文引号字符串
    find "$SRC_DIR" -type f \( -name "*.java" -o -name "*.py" -o -name "*.js" -o -name "*.ts" \) 2>/dev/null \
      | while IFS= read -r FILE; do
          perl -ne 'while (/"([^"]*[\x{4e00}-\x{9fff}][^"]*[\x{4e00}-\x{9fff}][^"]*)"/g) { print "$1\n" }' "$FILE" 2>/dev/null
        done \
      | sort | uniq -c | sort -rn \
      | head -200 \
      | while IFS= read -r line; do
          COUNT=$(echo "$line" | awk '{print $1}')
          TEXT=$(echo "$line" | cut -d' ' -f2-)
          echo "| ${COUNT} | ${TEXT} |"
        done
  else
    echo "| 0 | （错误：需要 rg 或 perl，均未找到） |"
  fi

  echo ""
  echo "## AI 处理指引"
  echo "1. 对上述候选字符串进行分词，提取业务术语（如'已申请冲红'→'冲红'）"
  echo "2. 按业务概念聚类（如'冲红申请'、'冲红审核'、'冲红驳回'→'冲红'领域）"
  echo "3. 为每个术语标注对应的英文类名/方法名/枚举名"
  echo "4. 输出为业务术语字典，用于领域识别和知识库索引"
} > "$OUTPUT_FILE"

echo "候选字符串提取完成，输出到: $OUTPUT_FILE" >&2
