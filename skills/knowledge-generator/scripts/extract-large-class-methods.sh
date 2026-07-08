#!/usr/bin/env bash
#
# 大类（God Class）方法枚举扫描器（A6）
# 扫描指定目录下行数超过阈值的 Java 类，列出所有 public 方法签名，
# 并按方法名前缀（动词）聚类，帮助识别同一业务的不同变体方法。
#
# 解决问题：issue-001 大类子场景系统性遗漏
# 触发条件：类行数 > 阈值（默认 500）或 public 方法数 > 阈值（默认 15）
#
# 用法: bash extract-large-class-methods.sh <源码目录> [行数阈值] [方法数阈值] [输出文件]
# 依赖: find, wc, grep, awk（均为系统自带）
#
set -euo pipefail

SRC_DIR="${1:-}"
LINE_THRESHOLD="${2:-500}"
METHOD_THRESHOLD="${3:-15}"
OUTPUT_FILE="${4:-/dev/stdout}"

if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
  echo "用法: bash extract-large-class-methods.sh <源码目录> [行数阈值] [方法数阈值] [输出文件]" >&2
  echo "  行数阈值默认 500，方法数阈值默认 15" >&2
  exit 1
fi

{
  echo "# 大类方法枚举报告（A6）"
  echo "# 生成时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# 源码目录: $SRC_DIR"
  echo "# 行数阈值: > ${LINE_THRESHOLD} 行"
  echo "# 方法数阈值: > ${METHOD_THRESHOLD} 个 public 方法"
  echo "# 说明: 本报告列出所有大类的方法清单，AI 必须为每个方法标注业务子场景"
  echo ""

  LARGE_CLASS_COUNT=0

  # 遍历所有 Java 文件
  find "$SRC_DIR" -name "*.java" -type f 2>/dev/null | while IFS= read -r FILE; do
    [ -z "$FILE" ] && continue

    # 计算行数
    LINE_COUNT=$(wc -l < "$FILE" 2>/dev/null | tr -d ' ' || echo "0")

    # 提取 public 方法数
    PUBLIC_METHODS=$(grep -cE '^\s*public\s+(static\s+)?(synchronized\s+)?(final\s+)?[A-Za-z0-9_<>\[\],?\s]+\s+[a-zA-Z0-9_]+\s*\(' "$FILE" 2>/dev/null || echo "0")
    # 排除 class 声明行
    PUBLIC_METHODS=$(grep -nE '^\s*public\s+(static\s+)?(synchronized\s+)?(final\s+)?[A-Za-z0-9_<>\[\],?\s]+\s+[a-zA-Z0-9_]+\s*\(' "$FILE" 2>/dev/null \
      | grep -v 'class ' | grep -v 'interface ' | grep -v 'enum ' | wc -l | tr -d ' ' || echo "0")

    # 判断是否为大类
    IS_LARGE=0
    if [ "$LINE_COUNT" -gt "$LINE_THRESHOLD" ]; then
      IS_LARGE=1
    fi
    if [ "$PUBLIC_METHODS" -gt "$METHOD_THRESHOLD" ]; then
      IS_LARGE=1
    fi

    if [ "$IS_LARGE" -eq 1 ]; then
      LARGE_CLASS_COUNT=$((LARGE_CLASS_COUNT + 1))

      CLASS_NAME=$(basename "$FILE" .java)
      REL_PATH="${FILE#$SRC_DIR/}"

      echo "## 大类 #${LARGE_CLASS_COUNT}: ${CLASS_NAME}"
      echo ""
      echo "- 文件路径: \`${REL_PATH}\`"
      echo "- 总行数: ${LINE_COUNT}"
      echo "- public 方法数: ${PUBLIC_METHODS}"
      echo "- 触发原因: $([ "$LINE_COUNT" -gt "$LINE_THRESHOLD" ] && echo "行数超阈值" || echo "")$([ "$PUBLIC_METHODS" -gt "$METHOD_THRESHOLD" ] && [ "$LINE_COUNT" -gt "$LINE_THRESHOLD" ] && echo " + " || echo "")$([ "$PUBLIC_METHODS" -gt "$METHOD_THRESHOLD" ] && echo "方法数超阈值" || echo "")"
      echo ""

      # 列出所有 public 方法，按行号排序
      echo "### 方法清单（按行号排序）"
      echo ""
      echo "| 行号 | 方法签名 | 动词前缀 |"
      echo "| --- | --- | --- |"

      grep -nE '^\s*public\s+(static\s+)?(synchronized\s+)?(final\s+)?[A-Za-z0-9_<>\[\],?\s]+\s+[a-zA-Z0-9_]+\s*\(' "$FILE" 2>/dev/null \
        | grep -v 'class ' \
        | grep -v 'interface ' \
        | grep -v 'enum ' \
        | while IFS= read -r line; do
            LINE_NUM=$(echo "$line" | cut -d: -f1)
            SIGNATURE=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//' | sed 's/{.*$//' | sed 's/;$//')
            # 提取方法名
            METHOD_NAME=$(echo "$SIGNATURE" | sed -E 's/.*\s([a-zA-Z0-9_]+)\s*\(.*/\1/' || echo "")
            # 提取动词前缀（方法名的第一个小写单词）
            VERB=$(echo "$METHOD_NAME" | sed -E 's/^([a-z]+).*/\1/' || echo "")
            echo "| ${LINE_NUM} | \`${SIGNATURE}\` | ${VERB} |"
          done

      echo ""

      # 按动词前缀聚类
      echo "### 方法聚类（按动词前缀）"
      echo ""
      echo "| 动词前缀 | 方法列表 | 方法数 |"
      echo "| --- | --- | --- |"

      grep -nE '^\s*public\s+(static\s+)?(synchronized\s+)?(final\s+)?[A-Za-z0-9_<>\[\],?\s]+\s+[a-zA-Z0-9_]+\s*\(' "$FILE" 2>/dev/null \
        | grep -v 'class ' \
        | grep -v 'interface ' \
        | grep -v 'enum ' \
        | while IFS= read -r line; do
            SIGNATURE=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//')
            METHOD_NAME=$(echo "$SIGNATURE" | sed -E 's/.*\s([a-zA-Z0-9_]+)\s*\(.*/\1/' || echo "")
            VERB=$(echo "$METHOD_NAME" | sed -E 's/^([a-z]+).*/\1/' || echo "")
            echo "${VERB}|${METHOD_NAME}"
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
      echo "> 4. 位于类尾部（行号 > 500）的方法容易被遗漏，需重点检查"
      echo ""
      echo "---"
      echo ""
    fi
  done

  echo "## AI 处理指引"
  echo ""
  echo "1. 本报告列出了所有大类的完整方法清单，是防止大类子场景遗漏的核心输入"
  echo "2. 对每个大类，必须为所有 public 方法标注业务子场景（而非只读前 N 个方法）"
  echo "3. 按动词聚类结果识别业务变体（如 applyPartRedRush / applyRedRush 是冲红变体）"
  echo "4. 类尾部方法（行号 > 500）是遗漏高发区，必须检查是否已被领域文档覆盖"
  echo "5. 方法覆盖率 < 80% 的大类，不允许标记领域为「已完成」"
} > "$OUTPUT_FILE"

echo "大类方法枚举完成，输出到: $OUTPUT_FILE" >&2
