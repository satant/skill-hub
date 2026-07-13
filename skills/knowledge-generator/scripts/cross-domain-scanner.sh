#!/usr/bin/env bash
#
# 跨领域子场景识别器（A7 v2.4.0）
# 扫描项目入口方法（Controller/Facade 或 路由/API模块），追踪调用链涉及的文件清单，
# 识别调用链跨越多个模块的子场景，输出跨领域子场景登记表。
#
# v2.4.0: 支持语言配置文件驱动，自动适配 Java/Vue/React 项目
#   - Java: 扫描 *Controller.java + Spring 注解
#   - Vue: 扫描路由文件 + API 模块（src/api/）
#   - React: 扫描 pages/routes + API 服务文件
#
# 解决问题：issue-002 领域边界模糊导致跨领域子场景双重遗漏
# 核心逻辑：入口方法 → 被调用文件清单 → 模块归属 → 跨模块标记
#
# 用法: bash cross-domain-scanner.sh <源码目录> [输出文件]
# 环境变量:
#   LANG_PROFILE - 语言配置文件路径（不设则自动检测）
# 依赖: find, grep, awk, sed（均为系统自带）
#
set -euo pipefail

SRC_DIR="${1:-}"
OUTPUT_FILE="${2:-/dev/stdout}"

if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
  echo "用法: bash cross-domain-scanner.sh <源码目录> [输出文件]" >&2
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
  LANG_ENTRY_GLOBS=("*Controller.java" "*Facade*Impl.java")
  LANG_ENTRY_ANNOTATION_REGEX='^\s*(@RequestMapping|@PostMapping|@GetMapping|@PutMapping|@DeleteMapping|@PatchMapping)'
  LANG_ENUM_GLOBS=("*Enum.java" "*Status.java" "*Type.java")
  LANG_IMPORT_EXCLUDE_PATTERNS=('java\.' 'javax\.' 'org.springframework' 'org.apache' 'com.alibaba' 'com.google' 'lombok')
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

# 构建入口文件 find 参数
build_entry_find_args() {
  local args=()
  local first=true
  for glob in "${LANG_ENTRY_GLOBS[@]}"; do
    if $first; then
      args+=(-name "$glob")
      first=false
    else
      args+=(-o -name "$glob")
    fi
  done
  echo "${args[@]}"
}

ENTRY_FIND_ARGS=$(build_entry_find_args)

# 构建枚举文件 find 参数
build_enum_find_args() {
  local args=()
  local first=true
  for glob in "${LANG_ENUM_GLOBS[@]}"; do
    if $first; then
      args+=(-name "$glob")
      first=false
    else
      args+=(-o -name "$glob")
    fi
  done
  echo "${args[@]}"
}

ENUM_FIND_ARGS=$(build_enum_find_args)

# 构建 import 排除正则：将数组转为 "pattern1|pattern2" 格式供 grep -vE 使用
build_import_exclude_regex() {
  local result=""
  local first=true
  for pattern in "${LANG_IMPORT_EXCLUDE_PATTERNS[@]}"; do
    if $first; then
      result="${pattern}"
      first=false
    else
      result="${result}|${pattern}"
    fi
  done
  echo "$result"
}

IMPORT_EXCLUDE_REGEX=$(build_import_exclude_regex)

{
  echo "# 跨领域子场景识别报告（A7 v2.4.0）"
  echo "# 生成时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# 源码目录: $SRC_DIR"
  echo "# 项目语言: ${LANG_NAME}"
  echo "# 说明: 本报告识别入口方法的调用链涉及的模块，标记跨模块子场景"
  echo ""

  # ============================================
  # 阶段1：收集所有入口方法
  # ============================================
  echo "## 阶段1：入口方法清单"
  echo ""
  echo "| 入口文件 | 方法名/路由 | 文件路径 | 行号 |"
  echo "| --- | --- | --- | --- |"

  if [ "$LANG_NAME" = "Java" ]; then
    # Java: Controller + Facade 入口
    # shellcheck disable=SC2086
    find "$SRC_DIR" \( $ENTRY_FIND_ARGS \) -type f -not -path "*/node_modules/*" 2>/dev/null | while IFS= read -r FILE; do
      [ -z "$FILE" ] && continue
      CLASS_NAME=$(basename "$FILE" .java)
      REL_PATH="${FILE#$SRC_DIR/}"

      grep -nE "$LANG_ENTRY_ANNOTATION_REGEX" "$FILE" 2>/dev/null \
        | while IFS= read -r line; do
            LINE_NUM=$(echo "$line" | cut -d: -f1)
            # 尝试获取下一行的方法名
            NEXT_LINE=$((LINE_NUM + 1))
            METHOD_LINE=$(sed -n "${NEXT_LINE}p" "$FILE" 2>/dev/null || true)
            METHOD_NAME=$(echo "$METHOD_LINE" | sed -E 's/.*[[:space:]]([a-zA-Z0-9_]+)[[:space:]]*\(.*/\1/' || echo "unknown")
            echo "| ${CLASS_NAME} | ${METHOD_NAME} | ${REL_PATH} | ${LINE_NUM} |"
          done
    done
  else
    # 前端: 路由文件 + API 模块
    # shellcheck disable=SC2086
    find "$SRC_DIR" \( $ENTRY_FIND_ARGS \) -type f -not -path "*/node_modules/*" 2>/dev/null | while IFS= read -r FILE; do
      [ -z "$FILE" ] && continue
      FILE_NAME=$(basename "$FILE")
      REL_PATH="${FILE#$SRC_DIR/}"

      # 查找入口标识（路由定义/API 调用）
      grep -nE "$LANG_ENTRY_ANNOTATION_REGEX" "$FILE" 2>/dev/null \
        | while IFS= read -r line; do
            LINE_NUM=$(echo "$line" | cut -d: -f1)
            CONTENT=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//')
            # 提取方法名或路由路径
            METHOD_NAME=$(echo "$CONTENT" | sed -E 's/.*((get|post|put|delete|patch|push|replace|request|fetch)[[:space:]]*[<(]?[[:space:]]*["'\''`]([^"'\'']*)["'\''`]).*/\2 \3/' 2>/dev/null || echo "$CONTENT")
            # 截断过长的行
            METHOD_NAME=$(echo "$METHOD_NAME" | head -c 80)
            echo "| ${FILE_NAME} | ${METHOD_NAME} | ${REL_PATH} | ${LINE_NUM} |"
          done
    done
  fi

  echo ""

  # ============================================
  # 阶段2：识别跨模块调用链
  # ============================================
  echo "## 阶段2：跨模块调用链识别"
  echo ""
  echo "> 对每个入口文件，扫描其引用的其他模块（import/require），"
  echo "> 按模块（目录）分组，跨 2 个以上模块的文件标记为跨模块子场景。"
  echo ""

  echo "### 跨模块入口文件清单"
  echo ""
  echo "| 入口文件 | 涉及模块 | 涉及文件数 | 是否跨模块 | 建议归属领域 |"
  echo "| --- | --- | --- | --- | --- |"

  # shellcheck disable=SC2086
  find "$SRC_DIR" \( $ENTRY_FIND_ARGS \) -type f -not -path "*/node_modules/*" 2>/dev/null \
    | while IFS= read -r FILE; do
        [ -z "$FILE" ] && continue
        FILE_NAME=$(basename "$FILE")

        if [ "$LANG_NAME" = "Java" ]; then
          # Java: 提取 import 语句中的类，按顶级模块分组
          MODULES=$(grep '^import ' "$FILE" 2>/dev/null \
            | grep -vE "$IMPORT_EXCLUDE_REGEX" \
            | sed 's/import //' \
            | sed 's/;//' \
            | awk -F'.' '{
                if (NF >= 4) print $1"."$2"."$3"."$4
                else if (NF >= 3) print $1"."$2"."$3
              }' \
            | sort -u || true)
        else
          # 前端: 提取 import/require 语句，按目录分组
          MODULES=$(grep -E '^[[:space:]]*(import |const .*= require\()' "$FILE" 2>/dev/null \
            | grep -vE "$IMPORT_EXCLUDE_REGEX" \
            | grep -oE "from[[:space:]]+['\"]([^'\"]+)['\"]" \
            | sed "s/from[[:space:]]*['\"]//;s/['\"]//g" \
            | grep -v '^\.' \
            | sort -u || true)

          # 也提取相对路径引用（按目录分组）
          RELATIVE_IMPORTS=$(grep -E '^[[:space:]]*(import |const .*= require\()' "$FILE" 2>/dev/null \
            | grep -oE "from[[:space:]]+['\"](\.[^'\"]+)['\"]" \
            | sed "s/from[[:space:]]*['\"]//;s/['\"]//g" \
            | awk -F'/' '{if (NF >= 3) print $1"/"$2"/"$3; else if (NF >= 2) print $1"/"$2}' \
            | sort -u || true)

          MODULES=$(echo -e "${MODULES}\n${RELATIVE_IMPORTS}" | grep -v '^$' | sort -u || true)
        fi

        MODULE_COUNT=$(echo "$MODULES" | grep -v '^$' | wc -l 2>/dev/null | tr -d ' ' || echo "0")
        MODULE_COUNT="${MODULE_COUNT:-0}"

        if [ "${MODULE_COUNT:-0}" -gt 1 ] 2>/dev/null; then
          MODULE_LIST=$(echo "$MODULES" | grep -v '^$' | tr '\n' ', ' | sed 's/,$//')
          echo "| ${FILE_NAME} | ${MODULE_LIST} | ${MODULE_COUNT} | **是** | 需 AI 判定主领域 |"
        fi
      done

  echo ""

  # ============================================
  # 阶段3：状态枚举/常量跨领域引用扫描
  # ============================================
  echo "## 阶段3：状态枚举/常量跨领域引用"
  echo ""
  echo "> 识别被多个文件引用的状态枚举/常量值，这些枚举关联的子场景可能跨领域。"
  echo ""

  echo "### 高频引用状态枚举/常量（被 5+ 个文件引用）"
  echo ""
  echo "| 枚举文件 | 枚举值 | 引用文件数 | 涉及模块 | 建议处理 |"
  echo "| --- | --- | --- | --- | --- |"

  # 查找所有枚举/常量文件
  # shellcheck disable=SC2086
  find "$SRC_DIR" \( $ENUM_FIND_ARGS \) -type f -not -path "*/node_modules/*" 2>/dev/null \
    | while IFS= read -r ENUM_FILE; do
        [ -z "$ENUM_FILE" ] && continue

        if [ "$LANG_NAME" = "Java" ]; then
          ENUM_NAME=$(basename "$ENUM_FILE" .java)
        else
          ENUM_NAME=$(basename "$ENUM_FILE" | sed 's/\.[^.]*$//')
        fi

        # 提取枚举值（大写常量）
        ENUM_VALUES=$(grep -oE "$LANG_ENUM_VALUE_REGEX" "$ENUM_FILE" 2>/dev/null | sort -u || true)

        if [ -n "$ENUM_VALUES" ]; then
          echo "$ENUM_VALUES" | while IFS= read -r ENUM_VAL; do
            [ -z "$ENUM_VAL" ] && continue
            # 统计引用该枚举值的文件数量（用 grep --include 替代 find 参数）
            REF_COUNT=0
            for ext in "${LANG_FILE_EXTENSIONS[@]}"; do
              CNT=$(grep -rl --include="*.${ext}" "${ENUM_VAL}" "$SRC_DIR" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
              REF_COUNT=$((REF_COUNT + ${CNT:-0}))
            done

            if [ "${REF_COUNT:-0}" -ge 5 ] 2>/dev/null; then
              # 提取涉及模块
              REF_MODULES=""
              for ext in "${LANG_FILE_EXTENSIONS[@]}"; do
                MODS=$(grep -rl --include="*.${ext}" "${ENUM_VAL}" "$SRC_DIR" 2>/dev/null \
                  | sed "s|$SRC_DIR/||" \
                  | awk -F'/' '{print $1"/"$2}' \
                  | sort -u \
                  | head -5 || true)
                if [ -n "$MODS" ]; then
                  if [ -n "$REF_MODULES" ]; then
                    REF_MODULES="${REF_MODULES}"$'\n'"${MODS}"
                  else
                    REF_MODULES="${MODS}"
                  fi
                fi
              done
              REF_MODULES=$(echo "$REF_MODULES" | sort -u | head -5 | tr '\n' ', ' | sed 's/,$//' || true)
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
  echo "**当前项目语言: ${LANG_NAME}**"
  echo ""
  echo "1. **跨模块入口文件**：阶段2 标记为「跨模块」的入口文件，其调用链跨越多个领域，"
  echo "   必须在主领域记录完整链路，在关联领域记录入口引用"
  echo "2. **高频状态枚举**：阶段3 列出的高频枚举值关联核心业务子场景，"
  echo "   必须确保至少一个领域文档完整描述了该枚举的状态流转"
  echo "3. **跨领域子场景登记**：基于本报告，AI 必须输出「跨领域子场景登记表」，格式："
  echo "   | 子场景 | 入口领域 | 完整链路领域 | 入口方法 | 关联状态枚举 |"
  echo "4. **领域划分修正**：未被任何领域认领的跨模块子场景，必须补充到对应领域或独立成新领域"
  echo "5. **子场景路由表**：知识库索引中必须包含子场景路由表，覆盖所有跨领域子场景"
} > "$OUTPUT_FILE"

echo "跨领域子场景识别完成（语言: ${LANG_NAME}），输出到: $OUTPUT_FILE" >&2
