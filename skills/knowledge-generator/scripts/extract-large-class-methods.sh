#!/usr/bin/env bash
#
# 大类（God Class）方法枚举扫描器（A6 v2.4.0）
# 扫描指定目录下行数超过阈值的文件，列出所有公开方法/函数签名，
# 并按方法名前缀（动词）聚类，帮助识别同一业务的不同变体方法。
#
# v2.4.0: 支持语言配置文件驱动，自动适配 Java/Vue/React 项目
#   - Java: 扫描 .java 文件，行数阈值默认 500，方法数阈值默认 15
#   - Vue/React: 扫描 .vue/.js/.ts/.jsx/.tsx 文件，行数阈值默认 300，方法数阈值默认 10
#
# 解决问题：issue-001 大类子场景系统性遗漏
# 触发条件：文件行数 > 阈值 或 公开方法/函数数 > 阈值
#
# 用法: bash extract-large-class-methods.sh <源码目录> [行数阈值] [方法数阈值] [输出文件]
# 环境变量:
#   LANG_PROFILE - 语言配置文件路径（不设则自动检测）
# 依赖: find, wc, grep, awk（均为系统自带）
#
set -euo pipefail

SRC_DIR="${1:-}"
OUTPUT_FILE="${4:-/dev/stdout}"

if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
  echo "用法: bash extract-large-class-methods.sh <源码目录> [行数阈值] [方法数阈值] [输出文件]" >&2
  echo "  行数阈值默认按语言：Java 500 / 前端 300" >&2
  echo "  方法数阈值默认按语言：Java 15 / 前端 10" >&2
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
  LANG_LARGE_METHOD_REGEX='^\s*public\s+(static\s+)?(synchronized\s+)?(final\s+)?[A-Za-z0-9_<>\[\],?\s]+\s+[a-zA-Z0-9_]+\s*\('
  LANG_LARGE_METHOD_EXCLUDE_PATTERNS=('class ' 'interface ' 'enum ')
  LANG_LARGE_LINE_THRESHOLD=500
  LANG_LARGE_METHOD_THRESHOLD=15
fi

# 阈值：优先使用命令行参数，其次使用语言配置默认值
LINE_THRESHOLD="${2:-${LANG_LARGE_LINE_THRESHOLD:-500}}"
METHOD_THRESHOLD="${3:-${LANG_LARGE_METHOD_THRESHOLD:-15}}"

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

# 构建排除正则：将数组转为 "pattern1|pattern2|pattern3" 格式供 grep -vE 使用
build_exclude_regex() {
  local result=""
  local first=true
  for pattern in "${LANG_LARGE_METHOD_EXCLUDE_PATTERNS[@]}"; do
    if $first; then
      result="${pattern}"
      first=false
    else
      result="${result}|${pattern}"
    fi
  done
  echo "$result"
}

EXCLUDE_PATTERNS=$(build_exclude_regex)

# 根据语言选择方法提取正则
if [ "$LANG_NAME" = "Java" ]; then
  METHOD_REGEX="$LANG_LARGE_METHOD_REGEX"
  # Java 方法名提取：从方法签名中提取方法名
  extract_method_name() {
    echo "$1" | sed -E 's/.*[[:space:]]([a-zA-Z0-9_]+)[[:space:]]*\(.*/\1/' || echo ""
  }
else
  METHOD_REGEX="$LANG_LARGE_METHOD_REGEX"
  # 前端方法名提取：多种格式
  extract_method_name() {
    local content="$1"
    local name=""

    # function methodName( → methodName
    name=$(echo "$content" | sed -E 's/.*function[[:space:]]+([a-zA-Z0-9_]+)[[:space:]]*\(.*/\1/' 2>/dev/null || true)
    if [ -n "$name" ] && echo "$name" | grep -qE '^[a-zA-Z][a-zA-Z0-9_]*$'; then echo "$name"; return; fi

    # const methodName = → methodName
    name=$(echo "$content" | sed -E 's/.*const[[:space:]]+([a-zA-Z0-9_]+)[[:space:]]*=.*/\1/' 2>/dev/null || true)
    if [ -n "$name" ] && echo "$name" | grep -qE '^[a-zA-Z][a-zA-Z0-9_]*$'; then echo "$name"; return; fi

    # async methodName( → methodName
    name=$(echo "$content" | sed -E 's/.*async[[:space:]]+([a-zA-Z0-9_]+)[[:space:]]*\(.*/\1/' 2>/dev/null || true)
    if [ -n "$name" ] && echo "$name" | grep -qE '^[a-zA-Z][a-zA-Z0-9_]*$'; then echo "$name"; return; fi

    # methodName(args) { → methodName
    name=$(echo "$content" | sed -E 's/^[[:space:]]*([a-zA-Z0-9_]+)[[:space:]]*\(.*/\1/' 2>/dev/null || true)
    if [ -n "$name" ] && echo "$name" | grep -qE '^[a-zA-Z][a-zA-Z0-9_]*$'; then echo "$name"; return; fi

    # const [name, setName] → name
    name=$(echo "$content" | sed -E 's/.*const[[:space:]]+\[([a-zA-Z0-9_]+),.*/\1/' 2>/dev/null || true)
    if [ -n "$name" ] && echo "$name" | grep -qE '^[a-zA-Z][a-zA-Z0-9_]*$'; then echo "$name"; return; fi

    echo ""
  }
fi

# 过滤非方法名关键字
is_valid_method_name() {
  local name="$1"
  case "$name" in
    if|for|while|switch|catch|return|new|import|export|interface|type|enum|class|const|let|var|function|async|await|extends|implements|namespace|from|default)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

{
  echo "# 大文件方法枚举报告（A6 v2.4.0）"
  echo "# 生成时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# 源码目录: $SRC_DIR"
  echo "# 项目语言: ${LANG_NAME}"
  echo "# 行数阈值: > ${LINE_THRESHOLD} 行"
  echo "# 方法数阈值: > ${METHOD_THRESHOLD} 个公开方法/函数"
  echo "# 说明: 本报告列出所有大文件的方法/函数清单，AI 必须为每个方法标注业务子场景"
  echo ""

  LARGE_FILE_COUNT=0

  # 遍历所有目标文件
  # shellcheck disable=SC2086
  while IFS= read -r FILE; do
    [ -z "$FILE" ] && continue

    # 计算行数
    LINE_COUNT=$(wc -l < "$FILE" 2>/dev/null | tr -d ' ' || true)
    LINE_COUNT="${LINE_COUNT:-0}"

    # 提取方法/函数数（排除声明行）
    PUBLIC_METHODS=$(grep -nE "$METHOD_REGEX" "$FILE" 2>/dev/null \
      | grep -vE "$EXCLUDE_PATTERNS" | wc -l | tr -d ' ' || true)
    PUBLIC_METHODS="${PUBLIC_METHODS:-0}"

    # 判断是否为大文件
    IS_LARGE=0
    if [ "${LINE_COUNT:-0}" -gt "${LINE_THRESHOLD:-500}" ] 2>/dev/null; then
      IS_LARGE=1
    fi
    if [ "${PUBLIC_METHODS:-0}" -gt "${METHOD_THRESHOLD:-15}" ] 2>/dev/null; then
      IS_LARGE=1
    fi

    if [ "$IS_LARGE" -eq 1 ]; then
      LARGE_FILE_COUNT=$((LARGE_FILE_COUNT + 1))

      if [ "$LANG_NAME" = "Java" ]; then
        FILE_DISPLAY_NAME=$(basename "$FILE" .java)
      else
        FILE_DISPLAY_NAME=$(basename "$FILE")
      fi
      REL_PATH="${FILE#$SRC_DIR/}"

      echo "## 大文件 #${LARGE_FILE_COUNT}: ${FILE_DISPLAY_NAME}"
      echo ""
      echo "- 文件路径: \`${REL_PATH}\`"
      echo "- 总行数: ${LINE_COUNT}"
      echo "- 公开方法/函数数: ${PUBLIC_METHODS}"
      echo "- 触发原因: $([ "${LINE_COUNT:-0}" -gt "${LINE_THRESHOLD:-500}" ] 2>/dev/null && echo "行数超阈值" || echo "")$([ "${PUBLIC_METHODS:-0}" -gt "${METHOD_THRESHOLD:-15}" ] 2>/dev/null && [ "${LINE_COUNT:-0}" -gt "${LINE_THRESHOLD:-500}" ] 2>/dev/null && echo " + " || echo "")$([ "${PUBLIC_METHODS:-0}" -gt "${METHOD_THRESHOLD:-15}" ] 2>/dev/null && echo "方法数超阈值" || echo "")"
      echo ""

      # 列出所有方法/函数，按行号排序
      echo "### 方法清单（按行号排序）"
      echo ""
      echo "| 行号 | 方法签名 | 动词前缀 |"
      echo "| --- | --- | --- |"

      grep -nE "$METHOD_REGEX" "$FILE" 2>/dev/null \
        | grep -vE "$EXCLUDE_PATTERNS" \
        | while IFS= read -r line; do
            LINE_NUM=$(echo "$line" | cut -d: -f1)
            SIGNATURE=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//' | sed 's/{.*$//' | sed 's/;$//')
            # 提取方法名
            METHOD_NAME=$(extract_method_name "$SIGNATURE")
            # 提取动词前缀
            VERB=$(echo "$METHOD_NAME" | sed -E 's/^([a-z]+).*/\1/' || echo "")
            if is_valid_method_name "$METHOD_NAME"; then
              echo "| ${LINE_NUM} | \`${SIGNATURE}\` | ${VERB} |"
            fi
          done

      echo ""

      # 按动词前缀聚类
      echo "### 方法聚类（按动词前缀）"
      echo ""
      echo "| 动词前缀 | 方法列表 | 方法数 |"
      echo "| --- | --- | --- |"

      grep -nE "$METHOD_REGEX" "$FILE" 2>/dev/null \
        | grep -vE "$EXCLUDE_PATTERNS" \
        | while IFS= read -r line; do
            SIGNATURE=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//')
            METHOD_NAME=$(extract_method_name "$SIGNATURE")
            VERB=$(echo "$METHOD_NAME" | sed -E 's/^([a-z]+).*/\1/' || echo "")
            if is_valid_method_name "$METHOD_NAME"; then
              echo "${VERB}|${METHOD_NAME}"
            fi
          done \
        | sort | awk -F'|' '{
            if (curr_verb != $1) {
              if (curr_verb != "") print "| " curr_verb " | " methods " | " count " |"
              curr_verb = $1; methods = $2; count = 1
            } else {
              methods = methods ", " $2; count++
            }
          }
          END {
            if (curr_verb != "") print "| " curr_verb " | " methods " | " count " |"
          }'

      echo ""

      # 业务变体识别提示
      echo "### 业务变体识别提示"
      echo ""
      echo "> AI 必须对上述方法进行业务变体识别："
      echo "> 1. 同一业务名词（如 Red/RedRush/RedBill）的不同方法可能是业务变体"
      echo "> 2. 修饰词（Part/Fast/Direct/ISV/Pre）标记不同变体类型"
      echo "> 3. 每个变体必须追踪其独立调用链，不可合并描述"
      if [ "$LANG_NAME" = "Java" ]; then
        echo "> 4. 位于类尾部（行号 > ${LINE_THRESHOLD}）的方法容易被遗漏，需重点检查"
      else
        echo "> 4. 位于文件尾部（行号 > ${LINE_THRESHOLD}）的函数容易被遗漏，需重点检查"
      fi
      echo ""
      echo "---"
      echo ""
    fi
  done < <(find "$SRC_DIR" -type f \( $FIND_EXT_ARGS \) -not -path "*/node_modules/*" 2>/dev/null || true)

  echo "## AI 处理指引"
  echo ""
  echo "**当前项目语言: ${LANG_NAME}**"
  echo ""
  echo "1. 本报告列出了所有大文件的完整方法/函数清单，是防止大文件子场景遗漏的核心输入"
  echo "2. 对每个大文件，必须为所有公开方法/函数标注业务子场景（而非只读前 N 个方法）"
  echo "3. 按动词聚类结果识别业务变体（如 applyPartRedRush / applyRedRush 是冲红变体）"
  echo "4. 文件尾部方法（行号 > ${LINE_THRESHOLD}）是遗漏高发区，必须检查是否已被领域文档覆盖"
  echo "5. 方法覆盖率 < 80% 的大文件，不允许标记领域为「已完成」"
} > "$OUTPUT_FILE"

echo "大文件方法枚举完成（语言: ${LANG_NAME}），输出到: $OUTPUT_FILE" >&2
