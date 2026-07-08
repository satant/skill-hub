#!/usr/bin/env bash
#
# 业务方法三维聚类扫描器（A2 v2.3.0）
# 从项目源码中提取方法名，按三个维度聚类：
#   维度1：动词聚类（原有）- open/apply/check/build/query 等
#   维度2：业务名词聚类（新增）- Red/RedRush/Invalid/Invoice 等
#   维度3：修饰词变体标注（新增）- Part/Fast/Direct/ISV/Pre 等
#
# 解决问题：issue-005 方法级业务变体识别缺失，单一动词聚类无法发现变体关系
# 升级原因：applyPartRedRush/applyRedRush/openRedInvoice 都是冲红变体，但动词不同
#
# 用法: bash cluster-by-business-verb.sh <源码目录> [输出文件]
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
# 维度定义
# ============================================

# 维度1：动词分类（原有，保留兼容）
# 格式："聚类名称|动词正则"（用第一个 | 分割，左边是聚类名，右边是正则）
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
# 格式："族名称|名词正则"
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
# 用于区分同一业务的不同变体
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

{
  echo "# 业务方法三维聚类报告（A2 v2.3.0）"
  echo "# 生成时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# 源码目录: $SRC_DIR"
  echo "# 维度1: 动词聚类（open/apply/check...）"
  echo "# 维度2: 业务名词聚类（Red/Invalid/Invoice...）"
  echo "# 维度3: 修饰词变体标注（Part/Fast/Direct/ISV...）"
  echo ""

  # ============================================
  # 收集所有方法名
  # ============================================
  TMP_ALL_METHODS=$(mktemp 2>/dev/null || mktemp -t kbgit)

  find "$SRC_DIR" -name "*.java" -type f 2>/dev/null \
    | while IFS= read -r FILE; do
        CLASS_NAME=$(basename "$FILE" .java)
        REL_PATH="${FILE#$SRC_DIR/}"
        grep -nE "(public|protected).*(void|[A-Z][A-Za-z0-9<>]*)\s+([a-z]+[A-Za-z0-9]*)\s*\(" "$FILE" 2>/dev/null \
          | grep -v 'class ' \
          | grep -v 'interface ' \
          | while IFS= read -r line; do
              LINE_NUM=$(echo "$line" | cut -d: -f1)
              METHOD_FULL=$(echo "$line" | sed -E 's/.*\s([a-z]+[A-Za-z0-9]*)\s*\(.*/\1/' || true)
              if [ -n "$METHOD_FULL" ]; then
                echo "${METHOD_FULL}|${CLASS_NAME}|${REL_PATH}|${LINE_NUM}"
              fi
            done
      done > "$TMP_ALL_METHODS"

  TOTAL_METHODS=$(wc -l < "$TMP_ALL_METHODS" | tr -d ' ')

  echo "## 总览"
  echo ""
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
      echo "| 方法名 | 所在类 | 文件路径 |"
      echo "| --- | --- | --- |"
      cat "$TMP_MATCHES"
      echo ""
    fi
    rm -f "$TMP_MATCHES"
  done

  # ============================================
  # 维度2：业务名词聚类（新增）
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
      echo "| 方法名 | 所在类 | 文件路径 |"
      echo "| --- | --- | --- |"
      cat "$TMP_MATCHES"
      echo ""
    fi
    rm -f "$TMP_MATCHES"
  done

  # ============================================
  # 维度3：修饰词变体标注（新增）
  # ============================================
  echo "## 维度3：修饰词变体标注"
  echo ""
  echo "> 识别方法名中的修饰词，标记业务变体类型。"
  echo "> 修饰词（Part/Fast/Direct/ISV/Pre）是区分业务变体的关键。"
  echo ""

  echo "### 变体方法清单"
  echo ""
  echo "| 方法名 | 动词前缀 | 业务名词 | 修饰词 | 变体类型 | 所在类 |"
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
  echo "1. **维度1 动词聚类**：识别同类型操作，用于领域边界判定"
  echo "2. **维度2 业务名词聚类**：识别同一业务族的不同方法，是变体识别的核心输入"
  echo "3. **维度3 修饰词标注**：区分同一业务的不同变体（完整/部分/快捷/ISV等）"
  echo "4. **变体矩阵**：对每个业务族的变体，必须："
  echo "   - 追踪每个变体的独立调用链（Controller → Service → Manager → DAO）"
  echo "   - 在知识库文档中为每个变体写独立的「核心链路」"
  echo "   - 在状态流转章节标注变体的状态差异"
  echo "   - 明确说明变体之间的差异（如：部分冲红只冲红部分明细，完整冲红冲红全部）"
  echo "5. **A8 业务变体识别**：基于本报告的维度2+维度3，执行变体全覆盖检查"
} > "$OUTPUT_FILE"

echo "业务方法三维聚类完成，输出到: $OUTPUT_FILE" >&2
