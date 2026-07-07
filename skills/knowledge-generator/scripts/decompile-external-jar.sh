#!/usr/bin/env bash
#
# 二方库合规反编译工具（C1）
# 在合规前提下，使用 javap 提取二方库 jar 中的类结构信息，
# 帮助补充外部依赖的知识黑洞。
#
# 重要合规声明：
#   - 反编译前必须检查 jar 的 LICENSE/NOTICE 文件
#   - 仅提取结构信息（字段名、方法签名、枚举值），不提取方法体
#   - 标注为"禁止反编译"的 jar 跳过，不做任何提取
#   - javap 只能获取结构定义，业务含义需 AI 从使用点反推
#
# 用法: bash decompile-external-jar.sh <jar文件或Maven坐标> <输出目录>
#       bash decompile-external-jar.sh "groupId:artifactId:version" <输出目录>
#
# 依赖: javap（JDK 自带）、unzip、mvn（可选，用于坐标定位）
#
set -euo pipefail

TARGET="${1:-}"
OUTPUT_DIR="${2:-}"

if [ -z "$TARGET" ] || [ -z "$OUTPUT_DIR" ]; then
  echo "用法: bash decompile-external-jar.sh <jar文件或Maven坐标> <输出目录>" >&2
  echo "示例:" >&2
  echo "  bash decompile-external-jar.sh /path/to/lib.jar /tmp/decomp" >&2
  echo "  bash decompile-external-jar.sh 'cn.gov.zcy:zcy-invoice-sdk:1.0.0' /tmp/decomp" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

JAR_FILE=""

# ============================================
# 步骤1：定位 jar 文件
# ============================================

if [ -f "$TARGET" ]; then
  # 直接给出 jar 文件路径
  JAR_FILE="$TARGET"
elif echo "$TARGET" | grep -qE '^[^:]+:[^:]+:[^:]+'; then
  # Maven 坐标格式 groupId:artifactId:version
  GROUP_ID=$(echo "$TARGET" | cut -d: -f1)
  ARTIFACT_ID=$(echo "$TARGET" | cut -d: -f2)
  VERSION=$(echo "$TARGET" | cut -d: -f3)

  # 将 groupId 转换为路径（如 cn.gov.zcy → cn/gov/zcy）
  GROUP_PATH=$(echo "$GROUP_ID" | tr '.' '/')

  # 搜索本地 Maven 仓库
  MAVEN_REPO="${HOME}/.m2/repository"
  JAR_FILE=$(find "${MAVEN_REPO}/${GROUP_PATH}/${ARTIFACT_ID}/${VERSION}" -name "${ARTIFACT_ID}-${VERSION}.jar" -type f 2>/dev/null | head -1 || true)

  if [ -z "$JAR_FILE" ]; then
    echo "错误: 未找到 jar 文件。坐标: $TARGET" >&2
    echo "请确认依赖已在本地 Maven 仓库中，或直接指定 jar 文件路径。" >&2
    # 尝试从 pom.xml 解析（不执行 mvn 命令，只输出建议）
    echo "建议: 检查 pom.xml 是否声明了该依赖，或使用 mvn dependency:resolve 下载。" >&2
    exit 1
  fi
else
  echo "错误: 无法识别目标 '$TARGET'（既不是文件也不是 Maven 坐标）" >&2
  exit 1
fi

echo "目标 jar: $JAR_FILE" >&2

# ============================================
# 步骤2：合规检查
# ============================================

COMPLIANCE_FILE="${OUTPUT_DIR}/COMPLIANCE.md"
LICENSE_STATUS="unknown"

# 解压检查 LICENSE/NOTICE 文件（仅解压 META-INF，不全量解压）
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# 只解压 META-INF 目录（含 LICENSE/NOTICE）
unzip -q "$JAR_FILE" 'META-INF/*' -d "$TMP_DIR" 2>/dev/null || true

# 检查 META-INF 下的 LICENSE/NOTICE
LICENSE_FILES=$(find "$TMP_DIR/META-INF" -maxdepth 1 \( -iname "LICENSE*" -o -iname "NOTICE*" \) -type f 2>/dev/null || true)

{
  echo "# 合规检查报告"
  echo ""
  echo "## jar 文件: $(basename "$JAR_FILE")"
  echo "## 检查时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""

  if [ -n "$LICENSE_FILES" ]; then
    echo "## 发现许可证文件"
    for LF in $LICENSE_FILES; do
      echo ""
      echo "### $(basename "$LF")"
      echo '```'
      head -50 "$LF" 2>/dev/null || echo "(无法读取)"
      echo '```'
    done

    # 检查是否包含禁止反编译条款（#6 修复：加引号防止空值和分词问题）
    if echo "$LICENSE_FILES" | xargs grep -liE "prohibit|reverse engineer|decompil|不得反编译|禁止反编译" 2>/dev/null | grep -q .; then
      LICENSE_STATUS="prohibited"
      echo ""
      echo "## ⚠️ 合规判定：禁止反编译"
      echo "许可证中包含禁止反编译/逆向工程的条款，已跳过反编译操作。"
      echo "建议：从使用点代码中反推外部库行为，或联系库提供方获取文档。"
    else
      LICENSE_STATUS="permitted"
      echo ""
      echo "## ✅ 合规判定：允许结构提取"
      echo "许可证未包含禁止反编译条款，将使用 javap 提取结构信息（不提取方法体）。"
    fi
  else
    LICENSE_STATUS="unknown"
    echo "## ⚠️ 合规判定：未知（未找到 LICENSE 文件）"
    echo "jar 包未包含 LICENSE/NOTICE 文件，无法确认是否允许反编译。"
    echo "默认行为：仅提取结构信息，不做方法体反编译。"
    echo "建议：人工确认该库的许可协议后再决定是否使用提取结果。"
  fi
} > "$COMPLIANCE_FILE"

echo "合规检查完成: $LICENSE_STATUS" >&2

# 如果禁止反编译，到此终止
if [ "$LICENSE_STATUS" = "prohibited" ]; then
  echo "合规检查未通过（禁止反编译），已终止。报告: $COMPLIANCE_FILE" >&2
  exit 0
fi

# ============================================
# 步骤3：使用 javap 提取结构信息（#13 优化：批量执行提升性能）
# ============================================

# 全量解压 jar（此时需要 class 文件列表）
unzip -q "$JAR_FILE" -d "$TMP_DIR" 2>/dev/null || true

# 提取 jar 中所有 class 文件（排除 inner class、module-info）
CLASS_FILES=$(find "$TMP_DIR" -name "*.class" -type f 2>/dev/null \
  | grep -v '\$' \
  | grep -v 'module-info' \
  | sed "s|${TMP_DIR}/||" \
  | sed 's|/|.|g' \
  | sed 's|\.class$||' \
  | sort || true)

OUTPUT_STRUCT="${OUTPUT_DIR}/struct-extract.json"

# 批量执行 javap（一次传入所有类，比逐类执行快数倍）
JAVAP_BATCH_OUTPUT=$(javap -p -cp "$JAR_FILE" $CLASS_FILES 2>/dev/null || true)

# 解析批量输出：javap 批量输出以 "Compiled from ..." 分隔每个类
{
  echo "{"
  echo "  \"jarFile\": \"$(basename "$JAR_FILE")\","
  echo "  \"complianceStatus\": \"${LICENSE_STATUS}\","
  echo "  \"extractTime\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"note\": \"javap 只能获取结构定义（字段名、方法签名、枚举值），业务含义需 AI 从使用点反推\","
  echo "  \"classes\": ["

  FIRST_CLASS=1
  CURRENT_CLASS=""

  echo "$JAVAP_BATCH_OUTPUT" | while IFS= read -r LINE; do
    # 检测类名行（javap 输出格式：Class cn.xxx.Yyy 或 Compiled from "Yyy.java"）
    if echo "$LINE" | grep -qE '^(public |abstract |final )*(class|interface|enum) '; then
      # 输出上一个类的结构
      if [ -n "$CURRENT_CLASS" ] && [ "$FIRST_CLASS" -eq 0 ]; then
        echo -n "\"}"
        echo ""
      fi

      if [ "$FIRST_CLASS" -eq 0 ]; then
        echo ","
      fi
      FIRST_CLASS=0

      # 提取类名
      CURRENT_CLASS=$(echo "$LINE" | sed -E 's/.*(class|interface|enum) +([A-Za-z0-9_.]+).*/\2/' || true)
      echo -n "    {\"className\": \"${CURRENT_CLASS}\", \"structure\": \""
    elif [ "$FIRST_CLASS" -eq 0 ]; then
      # 累积结构信息（过滤无关行）
      echo "$LINE" \
        | grep -E '(public|protected|private|static|final)' 2>/dev/null \
        | grep -v 'synthetic\|bridge\|abstract class\|interface\|Compiled from' \
        | sed 's/"/\\"/g' \
        | sed 's/\t/ /g' \
        | tr -d '\n' \
        | sed 's/  */ /g' || true
    fi
  done

  # 输出最后一个类
  if [ "$FIRST_CLASS" -eq 0 ]; then
    echo -n "\"}"
  fi

  echo ""
  echo "  ]"
  echo "}"
} > "$OUTPUT_STRUCT"

echo "结构提取完成: $OUTPUT_STRUCT" >&2
echo "" >&2
echo "=== 重要提醒 ===" >&2
echo "1. javap 只能获取结构定义（字段名、方法签名），不包含业务含义注释" >&2
echo "2. 枚举值只能看到名称（如 INIT），具体含义需从项目代码使用点反推" >&2
echo "3. 提取结果需要 AI 结合项目代码验证后才能写入知识库" >&2
