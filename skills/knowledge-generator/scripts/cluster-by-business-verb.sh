#!/usr/bin/env bash
#
# 业务动词聚类扫描器（A2）
# 从项目源码中提取方法名，按业务动词（create/update/cancel/audit/query...）聚类，
# 帮助识别同一业务领域的跨模块方法集合。
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

# 定义业务动词分类
# 格式: "动词模式|聚类名称"
VERB_PATTERNS=(
  "create|insert|add|save|build|generate|init|register|apply|submit|open|start|开启|创建|新增|提交|申请|发起"
  "update|modify|change|edit|adjust|set|switch|transfer|modify|变更|修改|调整|切换|转移"
  "cancel|revoke|void|close|stop|end|terminate|abort|撤销|取消|关闭|终止"
  "audit|approve|reject|review|check|verify|confirm|validate|审核|审批|驳回|校验|确认"
  "query|get|find|list|search|count|detail|fetch|查询|获取|检索|统计"
  "delete|remove|drop|clear|clean|purge|删除|清除|清理"
  "pay|charge|refund|settle|reconcile|transfer|reverse|支付|计费|退款|结算|冲正|对账"
  "send|push|notify|callback|dispatch|发送|推送|通知|回调"
  "sync|refresh|reload|import|export|sync|迁移|同步|刷新|导入|导出"
  "process|handle|execute|run|do|trigger|calc|compute|处理|执行|计算|触发"
)

{
  echo "# 业务动词聚类报告"
  echo "# 生成时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# 源码目录: $SRC_DIR"
  echo ""

  for ENTRY in "${VERB_PATTERNS[@]}"; do
    CLUSTER_NAME="${ENTRY%%|*}"
    PATTERN="${ENTRY#*|}"

    # PATTERN 已是 grep -E 兼容的正则（| 分隔的备选项），无需额外转换

    # 临时存储当前聚类的匹配结果（先收集再计数输出）
    TMP_MATCHES=$(mktemp)

    # 搜索所有 Java 文件（不做文件数量截断，保证跨模块信号完整性）
    find "$SRC_DIR" -name "*.java" -type f 2>/dev/null \
      | while IFS= read -r FILE; do
          # 提取 public/protected 方法签名
          grep -nE "(public|protected).*(void|[A-Z][A-Za-z0-9<>]*)\s+([a-z]+[A-Za-z0-9]*)\s*\(" "$FILE" 2>/dev/null \
            | while IFS= read -r LINE; do
                METHOD_FULL=$(echo "$LINE" | sed -E 's/.*\s([a-z]+[A-Za-z0-9]*)\s*\(.*/\1/' || true)
                # 检查方法名是否匹配当前聚类模式
                if echo "$METHOD_FULL" | grep -iqE "^($PATTERN)"; then
                  CLASS_NAME=$(basename "$FILE" .java)
                  REL_PATH="${FILE#$SRC_DIR/}"
                  echo "| ${METHOD_FULL} | ${CLASS_NAME} | ${REL_PATH} |"
                fi
              done
        done > "$TMP_MATCHES"

    MATCH_COUNT=$(wc -l < "$TMP_MATCHES" | tr -d ' ')

    echo "## 聚类：${CLUSTER_NAME}（${MATCH_COUNT} 个方法）"
    echo ""
    echo "| 方法名 | 所在类 | 文件路径 |"
    echo "| --- | --- | --- |"
    cat "$TMP_MATCHES"
    rm -f "$TMP_MATCHES"
    echo ""
  done

  echo "## AI 处理指引"
  echo "1. 上述聚类展示了项目中按业务动词分组的方法分布"
  echo "2. 同一聚类中跨模块出现的方法，可能属于同一业务领域"
  echo "3. 结合业务术语字典（extract-business-terms.sh 输出）进行交叉验证"
  echo "4. 高频出现的'动词+名词'组合（如 applyRedRush、cancelRedRush）是领域边界的强信号"
} > "$OUTPUT_FILE"

echo "业务动词聚类完成，输出到: $OUTPUT_FILE" >&2
