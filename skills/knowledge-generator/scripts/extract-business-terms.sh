#!/usr/bin/env bash
#
# 业务术语候选字符串提取器（A1）
# 从项目源码中提取含中文的字符串常量，作为业务术语字典的候选输入。
# 注意：本脚本只负责提取"候选字符串"，分词和归类由 AI 在步骤4完成。
#
# v2.4.0: 支持语言配置文件驱动，自动适配 Java/Vue/React 项目
#
# 用法: bash extract-business-terms.sh <源码目录> [输出文件]
# 环境变量:
#   LANG_PROFILE - 语言配置文件路径（不设则自动检测）
# 依赖: grep（需支持 -P 或 rg）
#
set -euo pipefail

SRC_DIR="${1:-}"
OUTPUT_FILE="${2:-/dev/stdout}"

if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
  echo "用法: bash extract-business-terms.sh <源码目录> [输出文件]" >&2
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
  LANG_FILE_EXTENSIONS=("java")
fi

# 构建 find 命令的文件扩展名参数
build_find_ext_args() {
  local args=()
  local first=true
  for ext in "${LANG_FILE_EXTENSIONS[@]}"; do
    if $first; then
      args+=(-name "*.${ext}")
      first=false
    else
      args+=(-o -name "*.${ext}")
    fi
  done
  echo "${args[@]}"
}

FIND_EXT_ARGS=$(build_find_ext_args)

# 构建 rg 的 glob 参数（支持多扩展名）
build_rg_globs() {
  local globs=()
  for ext in "${LANG_FILE_EXTENSIONS[@]}"; do
    globs+=("-g" "*.${ext}")
  done
  echo "${globs[@]}"
}

RG_GLOB_ARGS=$(build_rg_globs)

# 检查是否有 rg（ripgrep），否则用 python3 或 perl 辅助
if command -v rg &>/dev/null; then
  SEARCH_CMD="rg"
  # rg 正则：匹配引号内的中文字符串（至少包含2个中文字符）
  RG_PATTERN='"[^"]*[\x{4e00}-\x{9fff}][^"]*[\x{4e00}-\x{9fff}][^"]*"'
elif command -v python3 &>/dev/null; then
  # python3 降级模式（跨平台兼容性最好）
  SEARCH_CMD="python3"
elif command -v perl &>/dev/null; then
  # perl 降级模式
  SEARCH_CMD="perl"
else
  SEARCH_CMD="none"
fi

{
  echo "# 业务术语候选字符串清单"
  echo "# 生成时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# 源码目录: $SRC_DIR"
  echo "# 项目语言: ${LANG_NAME}"
  echo "# 文件扩展名: ${LANG_FILE_EXTENSIONS[*]}"
  echo "# 说明: 本文件仅包含候选字符串，需由 AI 进行分词和归类形成业务术语字典"
  echo ""

  # 提取中文字符串，去重，按出现频率排序
  if [ "$SEARCH_CMD" = "rg" ]; then
    # shellcheck disable=SC2086
    rg -o "$RG_PATTERN" $RG_GLOB_ARGS "$SRC_DIR" 2>/dev/null \
      | tr -d '"' \
      | sort | uniq -c | sort -rn \
      | head -200 \
      | while IFS= read -r line; do
          COUNT=$(echo "$line" | awk '{print $1}')
          TEXT=$(echo "$line" | cut -d' ' -f2-)
          echo "| ${COUNT} | ${TEXT} |"
        done
  elif [ "$SEARCH_CMD" = "python3" ]; then
    # python3 模式：跨平台兼容性最好
    # shellcheck disable=SC2086
    find "$SRC_DIR" -type f \( $FIND_EXT_ARGS \) -not -path "*/node_modules/*" 2>/dev/null \
      | while IFS= read -r FILE; do
          python3 -c "
import re, sys
try:
    with open('$FILE', encoding='utf-8', errors='ignore') as f:
        for m in re.finditer(r'\"([^\"]*[\u4e00-\u9fff][^\"]*[\u4e00-\u9fff][^\"]*)\"', f.read()):
            print(m.group(1))
except: pass
" 2>/dev/null || true
        done \
      | sort | uniq -c | sort -rn \
      | head -200 \
      | while IFS= read -r line; do
          COUNT=$(echo "$line" | awk '{print $1}')
          TEXT=$(echo "$line" | cut -d' ' -f2-)
          echo "| ${COUNT} | ${TEXT} |"
        done
  elif [ "$SEARCH_CMD" = "perl" ]; then
    # perl 降级模式：遍历文件用 perl 提取中文引号字符串
    # shellcheck disable=SC2086
    find "$SRC_DIR" -type f \( $FIND_EXT_ARGS \) -not -path "*/node_modules/*" 2>/dev/null \
      | while IFS= read -r FILE; do
          perl -ne 'while (/"([^"]*[\x{4e00}-\x{9fff}][^"]*[\x{4e00}-\x{9fff}][^"]*)"/g) { print "$1\n" }' "$FILE" 2>/dev/null || true
        done \
      | sort | uniq -c | sort -rn \
      | head -200 \
      | while IFS= read -r line; do
          COUNT=$(echo "$line" | awk '{print $1}')
          TEXT=$(echo "$line" | cut -d' ' -f2-)
          echo "| ${COUNT} | ${TEXT} |"
        done
  else
    echo "| 0 | （错误：需要 rg 或 python3 或 perl，均未找到） |"
  fi

  echo ""
  echo "## AI 处理指引"
  echo "1. 对上述候选字符串进行分词，提取业务术语（如'已申请冲红'→'冲红'）"
  echo "2. 按业务概念聚类（如'冲红申请'、'冲红审核'、'冲红驳回'→'冲红'领域）"
  echo "3. 为每个术语标注对应的英文类名/方法名/枚举名"
  echo "4. 输出为业务术语字典，用于领域识别和知识库索引"
} > "$OUTPUT_FILE"

echo "候选字符串提取完成（语言: ${LANG_NAME}），输出到: $OUTPUT_FILE" >&2
