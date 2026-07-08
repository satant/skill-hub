#!/usr/bin/env bash
#
# 跨领域子场景识别器（A7）
# 扫描项目入口方法（Controller/Facade），追踪调用链涉及的类清单，
# 识别调用链跨越多个模块的子场景，输出跨领域子场景登记表。
#
# 解决问题：issue-002 领域边界模糊导致跨领域子场景双重遗漏
# 核心逻辑：入口方法 → 被调用类清单 → 模块归属 → 跨模块标记
#
# 用法: bash cross-domain-scanner.sh <源码目录> [输出文件]
# 依赖: find, grep, awk, sed（均为系统自带）
#
set -euo pipefail

SRC_DIR="${1:-}"
OUTPUT_FILE="${2:-/dev/stdout}"

if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
  echo "用法: bash cross-domain-scanner.sh <源码目录> [输出文件]" >&2
  exit 1
fi

{
  echo "# 跨领域子场景识别报告（A7）"
  echo "# 生成时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# 源码目录: $SRC_DIR"
  echo "# 说明: 本报告识别入口方法的调用链涉及的模块，标记跨模块子场景"
  echo ""

  # ============================================
  # 阶段1：收集所有入口方法（Controller + Facade）
  # ============================================
  echo "## 阶段1：入口方法清单"
  echo ""
  echo "| 入口类 | 方法名 | 文件路径 | 行号 |"
  echo "| --- | --- | --- | --- |"

  # Controller 入口
  find "$SRC_DIR" -name "*Controller.java" -type f 2>/dev/null | while IFS= read -r FILE; do
    [ -z "$FILE" ] && continue
    CLASS_NAME=$(basename "$FILE" .java)
    REL_PATH="${FILE#$SRC_DIR/}"

    grep -nE '^\s*(@RequestMapping|@PostMapping|@GetMapping|@PutMapping|@DeleteMapping)' "$FILE" 2>/dev/null \
      | while IFS= read -r line; do
          LINE_NUM=$(echo "$line" | cut -d: -f1)
          # 尝试获取下一行的方法名
          NEXT_LINE=$((LINE_NUM + 1))
          METHOD_LINE=$(sed -n "${NEXT_LINE}p" "$FILE" 2>/dev/null || true)
          METHOD_NAME=$(echo "$METHOD_LINE" | sed -E 's/.*\s([a-zA-Z0-9_]+)\s*\(.*/\1/' || echo "unknown")
          echo "| ${CLASS_NAME} | ${METHOD_NAME} | ${REL_PATH} | ${LINE_NUM} |"
        done
  done

  # Facade 入口
  find "$SRC_DIR" -name "*Facade*Impl.java" -type f 2>/dev/null | while IFS= read -r FILE; do
    [ -z "$FILE" ] && continue
    CLASS_NAME=$(basename "$FILE" .java)
    REL_PATH="${FILE#$SRC_DIR/}"

    grep -nE '^\s*public\s+' "$FILE" 2>/dev/null \
      | grep -v 'class ' \
      | grep -v 'void set' \
      | while IFS= read -r line; do
          LINE_NUM=$(echo "$line" | cut -d: -f1)
          SIGNATURE=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//')
          METHOD_NAME=$(echo "$SIGNATURE" | sed -E 's/.*\s([a-zA-Z0-9_]+)\s*\(.*/\1/' || echo "unknown")
          echo "| ${CLASS_NAME} | ${METHOD_NAME} | ${REL_PATH} | ${LINE_NUM} |"
        done
  done

  echo ""

  # ============================================
  # 阶段2：识别跨模块调用链
  # ============================================
  echo "## 阶段2：跨模块调用链识别"
  echo ""
  echo "> 对每个入口方法，扫描其所在类中引用的其他类（import + 方法调用），"
  echo "> 按模块（顶级包名）分组，跨 2 个以上模块的方法标记为跨模块子场景。"
  echo ""

  echo "### 跨模块入口方法清单"
  echo ""
  echo "| 入口类.方法 | 涉及模块 | 涉及类数 | 是否跨模块 | 建议归属领域 |"
  echo "| --- | --- | --- | --- | --- |"

  # 对每个 Controller/Facade 类，分析其引用的类
  find "$SRC_DIR" \( -name "*Controller.java" -o -name "*Facade*Impl.java" \) -type f 2>/dev/null \
    | while IFS= read -r FILE; do
        [ -z "$FILE" ] && continue
        CLASS_NAME=$(basename "$FILE" .java)

        # 提取 import 语句中的类，按顶级模块分组
        MODULES=$(grep '^import ' "$FILE" 2>/dev/null \
          | grep -v 'java\.' \
          | grep -v 'javax\.' \
          | grep -v 'org.springframework' \
          | grep -v 'org.apache' \
          | grep -v 'com.alibaba' \
          | grep -v 'com.google' \
          | grep -v 'lombok' \
          | sed 's/import //' \
          | sed 's/;//' \
          | awk -F'.' '{
              if (NF >= 4) print $1"."$2"."$3"."$4
              else if (NF >= 3) print $1"."$2"."$3
            }' \
          | sort -u || true)

        MODULE_COUNT=$(echo "$MODULES" | grep -v '^$' | wc -l 2>/dev/null | tr -d ' ' || echo "0")
        MODULE_COUNT="${MODULE_COUNT:-0}"

        if [ "${MODULE_COUNT:-0}" -gt 1 ] 2>/dev/null; then
          MODULE_LIST=$(echo "$MODULES" | grep -v '^$' | tr '\n' ', ' | sed 's/,$//')
          echo "| ${CLASS_NAME} | ${MODULE_LIST} | ${MODULE_COUNT} | **是** | 需 AI 判定主领域 |"
        fi
      done

  echo ""

  # ============================================
  # 阶段3：状态枚举跨领域引用扫描
  # ============================================
  echo "## 阶段3：状态枚举跨领域引用"
  echo ""
  echo "> 识别被多个模块引用的状态枚举值，这些枚举关联的子场景可能跨领域。"
  echo ""

  echo "### 高频引用状态枚举（被 5+ 个类引用）"
  echo ""
  echo "| 枚举类 | 枚举值 | 引用类数 | 涉及模块 | 建议处理 |"
  echo "| --- | --- | --- | --- | --- |"

  # 查找所有 Enum 类（find -o 需要用括号分组确保 -type f 对所有条件生效）
  find "$SRC_DIR" \( -name "*Enum.java" -o -name "*Status.java" -o -name "*Type.java" \) -type f 2>/dev/null \
    | while IFS= read -r ENUM_FILE; do
        [ -z "$ENUM_FILE" ] && continue
        ENUM_NAME=$(basename "$ENUM_FILE" .java)

        # 提取枚举值（大写常量）
        ENUM_VALUES=$(grep -oE '\b[A-Z][A-Z_]{2,}\b' "$ENUM_FILE" 2>/dev/null | sort -u || true)

        if [ -n "$ENUM_VALUES" ]; then
          echo "$ENUM_VALUES" | while IFS= read -r ENUM_VAL; do
            [ -z "$ENUM_VAL" ] && continue
            # 统计引用该枚举值的类数量
            REF_COUNT=$(grep -rl "${ENUM_NAME}\.${ENUM_VAL}" "$SRC_DIR" --include='*.java' 2>/dev/null | wc -l 2>/dev/null | tr -d ' ' || echo "0")
            REF_COUNT="${REF_COUNT:-0}"

            if [ "${REF_COUNT:-0}" -ge 5 ] 2>/dev/null; then
              # 提取涉及模块
              REF_MODULES=$(grep -rl "${ENUM_NAME}\.${ENUM_VAL}" "$SRC_DIR" --include='*.java' 2>/dev/null \
                | sed "s|$SRC_DIR/||" \
                | awk -F'/' '{print $1"/"$2}' \
                | sort -u \
                | head -5 \
                | tr '\n' ', ' \
                | sed 's/,$//' || true)
              echo "| ${ENUM_NAME} | ${ENUM_VAL} | ${REF_COUNT} | ${REF_MODULES} | 核心状态，确保主领域覆盖 |"
            fi
          done
        fi
      done

  echo ""

  # ============================================
  # AI 处理指引
  # ============================================
  echo "## AI 处理指引"
  echo ""
  echo "1. **跨模块入口方法**：阶段2 标记为「跨模块」的入口方法，其调用链跨越多个领域，"
  echo "   必须在主领域记录完整链路，在关联领域记录入口引用"
  echo "2. **高频状态枚举**：阶段3 列出的高频枚举值关联核心业务子场景，"
  echo "   必须确保至少一个领域文档完整描述了该枚举的状态流转"
  echo "3. **跨领域子场景登记**：基于本报告，AI 必须输出「跨领域子场景登记表」，格式："
  echo "   | 子场景 | 入口领域 | 完整链路领域 | 入口方法 | 关联状态枚举 |"
  echo "4. **领域划分修正**：未被任何领域认领的跨模块子场景，必须补充到对应领域或独立成新领域"
  echo "5. **子场景路由表**：知识库索引中必须包含子场景路由表，覆盖所有跨领域子场景"
} > "$OUTPUT_FILE"

echo "跨领域子场景识别完成，输出到: $OUTPUT_FILE" >&2
