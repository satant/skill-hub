#!/usr/bin/env bash
#
# 业务方法三维聚类扫描器（A2 v2.4.0）
# 从项目源码中提取方法名，按三个维度聚类：
#   维度1：动词聚类（原有）- open/apply/check/build/query 等
#   维度2：业务名词聚类（新增）- Red/RedRush/Invalid/Invoice 等
#   维度3：修饰词变体标注（新增）- Part/Fast/Direct/ISV/Pre 等
#
# v2.4.0: 支持语言配置文件驱动，自动适配 Java/Vue/React 项目
#   - Java: 使用 Java 方法签名正则
#   - Vue/React: 使用前端函数定义正则
#
# 解决问题：issue-005 方法级业务变体识别缺失，单一动词聚类无法发现变体关系
# 升级原因：applyPartRedRush/applyRedRush/openRedInvoice 都是冲红变体，但动词不同
#
# 用法: bash cluster-by-business-verb.sh <源码目录> [输出文件]
# 环境变量:
#   LANG_PROFILE - 语言配置文件路径（不设则自动检测）
# 依赖: grep, awk, find（均为系统自带）
#
set -euo pipefail

SRC_DIR="${1:-}"
OUTPUT_FILE="${2:-/dev/stdout}"

if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
  echo "用法: bash cluster-by-business-verb.sh <源码目录> [输出文件]" >&2
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
  LANG_METHOD_REGEX='(public|protected).*(void|[A-Z][A-Za-z0-9<>]*)\s+([a-z]+[A-Za-z0-9]*)\s*\('
  LANG_METHOD_EXCLUDE_PATTERNS=('class ' 'interface ' 'enum ')
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

# 构建排除正则：将数组转为 "pattern1|pattern2|pattern3" 格式供 grep -vE 使用
build_exclude_regex() {
  local result=""
  local first=true
  for pattern in "${LANG_METHOD_EXCLUDE_PATTERNS[@]}"; do
    if $first; then
      result="${pattern}"
      first=false
    else
      result="${result}|${pattern}"
    fi
  done
  echo "$result"
}

METHOD_EXCLUDE_REGEX=$(build_exclude_regex)

# ============================================
# 维度定义（语言无关，所有语言共用）
# ============================================

# 维度1：动词分类（原有，保留兼容）
VERB_PATTERNS=(
  "创建类|create|insert|add|save|build|generate|init|register|apply|submit|open|start|开启|创建|新增|提交|申请|发起"
  "变更类|update|modify|change|edit|adjust|set|switch|transfer|变更|修改|调整|切换|转移"
  "撤销类|cancel|revoke|void|close|stop|end|terminate|abort|撤销|取消|关闭|终止"
  "审核类|audit|approve|reject|review|check|verify|confirm|validate|审核|审批|驳回|校验|确认"
  "查询类|query|get|find|list|search|count|detail|fetch|查询|获取|检索|统计"
  "删除类|delete|remove|drop|clear|clean|purge|删除|清除|清理"
  "财务类|pay|charge|refund|settle|reconcile|reverse|支付|计费|退款|结算|冲正|对账"
  "消息类|send|push|notify|callback|dispatch|发送|推送|通知|回调"
  "同步类|sync|refresh|reload|import|export|迁移|同步|刷新|导入|导出"
  "处理类|process|handle|execute|run|do|trigger|calc|compute|处理|执行|计算|触发"
)

# 维度2：业务名词族（新增）
NOUN_PATTERNS=(
  "冲红|Red|RedRush|RedBill|冲红|红字"
  "作废|Invalid|Cancel|Void|作废|撤销"
  "发票|Invoice|Bill|发票|账单"
  "签章|Sign|Signature|签章"
  "税务|Tax|税务|税目"
  "配置|Config|Setting|配置"
  "订单|Order|订单"
  "支付|Pay|Payment|支付"
  "退款|Refund|退款"
  "通知|Notify|Message|通知|消息"
)

# 维度3：修饰词变体标注（新增）
MODIFIER_PATTERNS=(
  "Part|Partial|部分"
  "Fast|快速|快捷"
  "Direct|直接|自营"
  "ISV|Isv|isv"
  "Pre|预"
  "Batch|批量"
  "Async|异步"
  "Sync|同步"
  "Auto|自动"
  "Manual|手动"
)

# ============================================
# 方法名提取（v2.4.0 语言感知）
# ============================================

# 根据语言类型选择提取策略
if [ "$LANG_NAME" = "Java" ]; then
  # Java 方法提取（原有逻辑）
  extract_methods_from_file() {
    local file="$1"
    local class_name
    class_name=$(basename "$file" .java)
    local rel_path="${file#$SRC_DIR/}"

    grep -nE "$LANG_METHOD_REGEX" "$file" 2>/dev/null \
      | grep -vE "$METHOD_EXCLUDE_REGEX" \
      | while IFS= read -r line; do
          local line_num method_full
          line_num=$(echo "$line" | cut -d: -f1)
          method_full=$(echo "$line" | sed -E 's/.*[[:space:]]([a-z]+[A-Za-z0-9]*)[[:space:]]*\(.*/\1/' || true)
          if [ -n "$method_full" ]; then
            echo "${method_full}|${class_name}|${rel_path}|${line_num}"
          fi
        done
  }
else
  # 前端方法提取（Vue/React 通用）
  extract_methods_from_file() {
    local file="$1"
    local file_name
    file_name=$(basename "$file")
    local rel_path="${file#$SRC_DIR/}"

    # 匹配前端各种函数定义形式
    grep -nE "$LANG_METHOD_REGEX" "$file" 2>/dev/null \
      | grep -vE "$METHOD_EXCLUDE_REGEX" \
      | while IFS= read -r line; do
          local line_num content method_full

          line_num=$(echo "$line" | cut -d: -f1)
          content=$(echo "$line" | cut -d: -f2-)

          # 尝试多种提取方式
          # function methodName( → methodName
          method_full=$(echo "$content" | sed -E 's/.*function[[:space:]]+([a-zA-Z0-9_]+)[[:space:]]*\(.*/\1/' 2>/dev/null || true)

          # const methodName = ( → methodName
          if [ -z "$method_full" ] || echo "$method_full" | grep -qE '^[[:space:]]*$'; then
            method_full=$(echo "$content" | sed -E 's/.*const[[:space:]]+([a-zA-Z0-9_]+)[[:space:]]*=.*/\1/' 2>/dev/null || true)
          fi

          # async methodName( → methodName
          if [ -z "$method_full" ] || echo "$method_full" | grep -qE '^[[:space:]]*$'; then
            method_full=$(echo "$content" | sed -E 's/.*async[[:space:]]+([a-zA-Z0-9_]+)[[:space:]]*\(.*/\1/' 2>/dev/null || true)
          fi

          # methodName(args) { → methodName (Vue Options API)
          if [ -z "$method_full" ] || echo "$method_full" | grep -qE '^[[:space:]]*$'; then
            method_full=$(echo "$content" | sed -E 's/^[[:space:]]*([a-zA-Z0-9_]+)[[:space:]]*\(.*/\1/' 2>/dev/null || true)
          fi

          # const [name, setName] = → name (React useState 解构)
          if [ -z "$method_full" ] || echo "$method_full" | grep -qE '^[[:space:]]*$'; then
            method_full=$(echo "$content" | sed -E 's/.*const[[:space:]]+\[([a-zA-Z0-9_]+),.*/\1/' 2>/dev/null || true)
          fi

          # 清理：确保只拿到合法的方法名
          if [ -n "$method_full" ] && echo "$method_full" | grep -qE '^[a-zA-Z][a-zA-Z0-9_]*$'; then
            # 过滤掉明显的非方法名（语句关键字等）
            case "$method_full" in
              if|for|while|switch|catch|return|new|import|export|interface|type|enum|class|const|let|var|function|async|await|extends|implements|namespace|from|default)
                continue
                ;;
              *)
                echo "${method_full}|${file_name}|${rel_path}|${line_num}"
                ;;
            esac
          fi
        done
  }
fi

{
  echo "# 业务方法三维聚类报告（A2 v2.4.0）"
  echo "# 生成时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# 源码目录: $SRC_DIR"
  echo "# 项目语言: ${LANG_NAME}"
  echo "# 维度1: 动词聚类（open/apply/check...）"
  echo "# 维度2: 业务名词聚类（Red/Invalid/Invoice...）"
  echo "# 维度3: 修饰词变体标注（Part/Fast/Direct/ISV...）"
  echo ""

  # ============================================
  # 收集所有方法名
  # ============================================
  TMP_ALL_METHODS=$(mktemp 2>/dev/null || mktemp -t kbgit)

  # shellcheck disable=SC2086
  find "$SRC_DIR" -type f \( $FIND_EXT_ARGS \) -not -path "*/node_modules/*" 2>/dev/null \
    | while IFS= read -r FILE; do
        extract_methods_from_file "$FILE"
      done > "$TMP_ALL_METHODS"

  TOTAL_METHODS=$(wc -l < "$TMP_ALL_METHODS" | tr -d ' ')

  echo "## 总览"
  echo ""
  echo "- 项目语言: ${LANG_NAME}"
  echo "- 扫描方法总数: ${TOTAL_METHODS}"
  echo ""

  # ============================================
  # 维度1：动词聚类（原有逻辑，保留兼容）
  # ============================================
  echo "## 维度1：动词聚类"
  echo ""
  echo "> 按方法名的动词前缀分组，识别同类型操作。"
  echo ""

  for ENTRY in "${VERB_PATTERNS[@]}"; do
    CLUSTER_NAME="${ENTRY%%|*}"
    PATTERN="${ENTRY#*|}"

    TMP_MATCHES=$(mktemp 2>/dev/null || mktemp -t kbgit)
    grep -iE "^([a-z]+).*(${PATTERN})" "$TMP_ALL_METHODS" 2>/dev/null \
      | while IFS='|' read -r METHOD CLASS PATH LINE; do
          if echo "$METHOD" | grep -iqE "^(${PATTERN})"; then
            echo "| ${METHOD} | ${CLASS} | ${PATH} |"
          fi
        done > "$TMP_MATCHES"

    MATCH_COUNT=$(wc -l < "$TMP_MATCHES" | tr -d ' ')

    if [ "$MATCH_COUNT" -gt 0 ]; then
      echo "### 聚类：${CLUSTER_NAME}（${MATCH_COUNT} 个方法）"
      echo ""
      echo "| 方法名 | 所在文件 | 文件路径 |"
      echo "| --- | --- | --- |"
      cat "$TMP_MATCHES"
      echo ""
    fi
    rm -f "$TMP_MATCHES"
  done

  # ============================================
  # 维度2：业务名词聚类
  # ============================================
  echo "## 维度2：业务名词聚类"
  echo ""
  echo "> 按方法名包含的业务名词分组，识别同一业务族的不同方法。"
  echo "> 同一业务名词族的方法可能是业务变体，需要追踪独立调用链。"
  echo ""

  for NOUN_ENTRY in "${NOUN_PATTERNS[@]}"; do
    NOUN_NAME="${NOUN_ENTRY%%|*}"
    NOUN_PATTERN="${NOUN_ENTRY#*|}"

    TMP_MATCHES=$(mktemp 2>/dev/null || mktemp -t kbgit)
    grep -iE "(${NOUN_PATTERN})" "$TMP_ALL_METHODS" 2>/dev/null \
      | while IFS='|' read -r METHOD CLASS PATH LINE; do
          echo "| ${METHOD} | ${CLASS} | ${PATH} |"
        done > "$TMP_MATCHES"

    MATCH_COUNT=$(wc -l < "$TMP_MATCHES" | tr -d ' ')

    if [ "$MATCH_COUNT" -gt 0 ]; then
      echo "### 业务族：${NOUN_NAME}（${MATCH_COUNT} 个方法）"
      echo ""
      echo "| 方法名 | 所在文件 | 文件路径 |"
      echo "| --- | --- | --- |"
      cat "$TMP_MATCHES"
      echo ""
    fi
    rm -f "$TMP_MATCHES"
  done

  # ============================================
  # 维度3：修饰词变体标注
  # ============================================
  echo "## 维度3：修饰词变体标注"
  echo ""
  echo "> 识别方法名中的修饰词，标记业务变体类型。"
  echo "> 修饰词（Part/Fast/Direct/ISV/Pre）是区分业务变体的关键。"
  echo ""

  echo "### 变体方法清单"
  echo ""
  echo "| 方法名 | 动词前缀 | 业务名词 | 修饰词 | 变体类型 | 所在文件 |"
  echo "| --- | --- | --- | --- | --- | --- |"

  while IFS='|' read -r METHOD CLASS PATH LINE; do
    [ -z "$METHOD" ] && continue

    # 提取动词前缀
    VERB=$(echo "$METHOD" | sed -E 's/^([a-z]+).*/\1/' 2>/dev/null || echo "")

    # 识别业务名词
    BUSINESS_NOUN="-"
    for NOUN_ENTRY in "${NOUN_PATTERNS[@]}"; do
      NOUN_PATTERN="${NOUN_ENTRY#*|}"
      if echo "$METHOD" | grep -iqE "(${NOUN_PATTERN})" 2>/dev/null; then
        BUSINESS_NOUN="${NOUN_ENTRY%%|*}"
        break
      fi
    done

    # 识别修饰词
    MODIFIER="-"
    VARIANT_TYPE="默认/完整"
    for MOD_ENTRY in "${MODIFIER_PATTERNS[@]}"; do
      MOD_PATTERN="${MOD_ENTRY%%|*}"
      if echo "$METHOD" | grep -iqE "(${MOD_PATTERN})" 2>/dev/null; then
        MODIFIER="${MOD_PATTERN}"
        # 映射变体类型
        case "$MOD_PATTERN" in
          Part|Partial) VARIANT_TYPE="部分变体" ;;
          Fast) VARIANT_TYPE="快捷变体" ;;
          Direct) VARIANT_TYPE="自营变体" ;;
          ISV|Isv|isv) VARIANT_TYPE="ISV变体" ;;
          Pre) VARIANT_TYPE="预操作变体" ;;
          Batch) VARIANT_TYPE="批量变体" ;;
          Async) VARIANT_TYPE="异步变体" ;;
          Sync) VARIANT_TYPE="同步变体" ;;
          Auto) VARIANT_TYPE="自动变体" ;;
          Manual) VARIANT_TYPE="手动变体" ;;
        esac
        break
      fi
    done

    # 只输出包含修饰词的方法（有变体特征的）
    if [ "$MODIFIER" != "-" ]; then
      echo "| ${METHOD} | ${VERB} | ${BUSINESS_NOUN} | ${MODIFIER} | ${VARIANT_TYPE} | ${CLASS} |"
    fi
  done < "$TMP_ALL_METHODS" || true

  echo ""

  # ============================================
  # 交叉输出：业务变体矩阵
  # ============================================
  echo "## 业务变体矩阵（维度交叉）"
  echo ""
  echo "> 同一业务名词族下的方法，按修饰词分组，识别完整/部分/快捷等变体。"
  echo "> AI 必须为每个变体追踪独立调用链，不可合并描述。"
  echo ""

  for NOUN_ENTRY in "${NOUN_PATTERNS[@]}"; do
    NOUN_NAME="${NOUN_ENTRY%%|*}"
    NOUN_PATTERN="${NOUN_ENTRY#*|}"

    # 收集该业务名词族的所有方法
    TMP_NOUN_METHODS=$(mktemp 2>/dev/null || mktemp -t kbgit)
    grep -iE "(${NOUN_PATTERN})" "$TMP_ALL_METHODS" 2>/dev/null > "$TMP_NOUN_METHODS"
    NOUN_COUNT=$(wc -l < "$TMP_NOUN_METHODS" | tr -d ' ')

    if [ "$NOUN_COUNT" -gt 0 ]; then
      echo "### ${NOUN_NAME} 业务族（${NOUN_COUNT} 个方法）"
      echo ""
      echo "| 方法名 | 动词 | 修饰词 | 变体类型 |"
      echo "| --- | --- | --- | --- |"

      while IFS='|' read -r METHOD CLASS PATH LINE; do
        [ -z "$METHOD" ] && continue
        VERB=$(echo "$METHOD" | sed -E 's/^([a-z]+).*/\1/' 2>/dev/null || echo "")

        MODIFIER="-"
        VARIANT_TYPE="默认/完整"
        for MOD_ENTRY in "${MODIFIER_PATTERNS[@]}"; do
          MOD_PATTERN="${MOD_ENTRY%%|*}"
          if echo "$METHOD" | grep -iqE "(${MOD_PATTERN})" 2>/dev/null; then
            MODIFIER="${MOD_PATTERN}"
            case "$MOD_PATTERN" in
              Part|Partial) VARIANT_TYPE="部分变体" ;;
              Fast) VARIANT_TYPE="快捷变体" ;;
              Direct) VARIANT_TYPE="自营变体" ;;
              ISV|Isv|isv) VARIANT_TYPE="ISV变体" ;;
              Pre) VARIANT_TYPE="预操作变体" ;;
              Batch) VARIANT_TYPE="批量变体" ;;
              Async) VARIANT_TYPE="异步变体" ;;
              Sync) VARIANT_TYPE="同步变体" ;;
              Auto) VARIANT_TYPE="自动变体" ;;
              Manual) VARIANT_TYPE="手动变体" ;;
            esac
            break
          fi
        done

        echo "| ${METHOD} | ${VERB} | ${MODIFIER} | ${VARIANT_TYPE} |"
      done < "$TMP_NOUN_METHODS" || true

      echo ""
      rm -f "$TMP_NOUN_METHODS"
    fi
  done

  rm -f "$TMP_ALL_METHODS"

  # ============================================
  # AI 处理指引
  # ============================================
  echo "## AI 处理指引"
  echo ""
  echo "**当前项目语言: ${LANG_NAME}**"
  echo ""
  echo "1. **维度1 动词聚类**：识别同类型操作，用于领域边界判定"
  echo "2. **维度2 业务名词聚类**：识别同一业务族的不同方法，是变体识别的核心输入"
  echo "3. **维度3 修饰词标注**：区分同一业务的不同变体（完整/部分/快捷/ISV等）"
  echo "4. **变体矩阵**：对每个业务族的变体，必须："
  if [ "$LANG_NAME" = "Java" ]; then
    echo "   - 追踪每个变体的独立调用链（Controller → Service → Manager → DAO）"
  else
    echo "   - 追踪每个变体的独立调用链（路由/页面 → 组件 → Store/Hook → API 模块）"
  fi
  echo "   - 在知识库文档中为每个变体写独立的「核心链路」"
  echo "   - 在状态流转章节标注变体的状态差异"
  echo "   - 明确说明变体之间的差异（如：部分冲红只冲红部分明细，完整冲红冲红全部）"
  echo "5. **A8 业务变体识别**：基于本报告的维度2+维度3，执行变体全覆盖检查"
} > "$OUTPUT_FILE"

echo "业务方法三维聚类完成（语言: ${LANG_NAME}），输出到: $OUTPUT_FILE" >&2
