#!/usr/bin/env bash
#
# 代码反向验证脚本（B4 v2.4.0）
# 对知识库 .summary.json 中的关键信息（枚举值/方法名/类名/路径），
# 反向在项目源码中验证是否存在，消除 AI 自校验的确认偏差。
#
# v2.4.0: 支持语言配置文件驱动，自动适配 Java/Vue/React 项目
#   - Java: 包名转路径 + .java 文件查找
#   - Vue/React: 直接按文件名/路径查找，方法定义匹配前端语法
#
# 解决问题：issue-009 质量校验降级为 AI 手动校验，确认偏差导致错误漏检
# 核心逻辑：提取 .summary.json 结构化字段 → 在源码中 grep 验证 → 输出验证报告
#
# 用法: bash cross-validate-with-code.sh <summary.json 文件> <项目源码目录> [--json] [--lang <profile>]
# 依赖: grep, find, awk, sed, python3 或 jq（用于 JSON 解析）
#
set -euo pipefail

SUMMARY_FILE="${1:-}"
SRC_DIR="${2:-}"
JSON_OUTPUT=false

# 解析参数
for arg in "$@"; do
  case "$arg" in
    --json) JSON_OUTPUT=true ;;
    --lang) shift_found=true ;;
  esac
done

# 解析 --lang 参数
ARGS=()
for arg in "$@"; do
  ARGS+=("$arg")
done
for i in "${!ARGS[@]}"; do
  if [ "${ARGS[$i]}" = "--lang" ] && [ $((i + 1)) -lt ${#ARGS[@]} ]; then
    LANG_PROFILE="${ARGS[$((i + 1))]:-}"
  fi
done

if [ -z "$SUMMARY_FILE" ] || [ -z "$SRC_DIR" ]; then
  echo "用法: bash cross-validate-with-code.sh <summary.json 文件> <项目源码目录> [--json]" >&2
  exit 2
fi

if [ ! -f "$SUMMARY_FILE" ]; then
  echo "错误: summary.json 文件不存在: $SUMMARY_FILE" >&2
  exit 2
fi

if [ ! -d "$SRC_DIR" ]; then
  echo "错误: 源码目录不存在: $SRC_DIR" >&2
  exit 2
fi

# python3 必须可用（门控0 ensure-python3.sh 负责安装）
if ! command -v python3 &>/dev/null; then
  echo "错误: python3 不可用，请先执行 bash scripts/ensure-python3.sh" >&2
  exit 2
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
  LANG_CLASS_FILE_SUFFIX=".java"
  LANG_FILE_EXTENSIONS=("java")
fi

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
FAIL_DETAILS=()

if [ "$JSON_OUTPUT" = false ]; then
  print_pass() { echo "  [PASS] $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
  print_fail() { echo "  [FAIL] $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_DETAILS+=("$1"); }
  print_warn() { echo "  [WARN] $1"; WARN_COUNT=$((WARN_COUNT + 1)); }
else
  print_pass() { PASS_COUNT=$((PASS_COUNT + 1)); }
  print_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_DETAILS+=("$1"); }
  print_warn() { WARN_COUNT=$((WARN_COUNT + 1)); }
fi

# ============================================
# 验证1：入口类路径存在性
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo "--- 验证1: 入口类（entryPoints）路径存在性 ---"
fi

ENTRY_CLASSES=$(python3 -c "
import json
try:
    data = json.load(open('$SUMMARY_FILE'))
    for ep in data.get('entryPoints', []):
        cls = ep.get('className', '')
        if cls: print(cls)
except: pass
" 2>/dev/null || true)

if [ -n "$ENTRY_CLASSES" ]; then
  echo "$ENTRY_CLASSES" | while IFS= read -r CLASS; do
    [ -z "$CLASS" ] && continue
    if [ "$LANG_NAME" = "Java" ]; then
      # Java: 包名转路径查找
      REL_PATH=$(echo "$CLASS" | tr '.' '/')
      FOUND=$(find "$SRC_DIR" -path "*/${REL_PATH}.java" -type f 2>/dev/null | head -1 || true)
    else
      # 前端: 按文件名查找（多种扩展名）
      BASE_NAME=$(basename "$CLASS")
      FOUND=$(find "$SRC_DIR" -name "${BASE_NAME}.*" \( -name "*.vue" -o -name "*.ts" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.js" \) -not -path "*/node_modules/*" -type f 2>/dev/null | head -1 || true)
    fi
    if [ -n "$FOUND" ]; then
      print_pass "入口类存在: $CLASS"
    else
      print_fail "入口类不存在: $CLASS"
    fi
  done
else
  print_warn "未检测到 entryPoints"
fi

# ============================================
# 验证2：核心类（coreClasses）路径存在性
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "--- 验证2: 核心类（coreClasses）路径存在性 ---"
fi

CORE_CLASSES=$(python3 -c "
import json
try:
    data = json.load(open('$SUMMARY_FILE'))
    for cc in data.get('coreClasses', []):
        cls = cc.get('className', '')
        if cls: print(cls)
except: pass
" 2>/dev/null || true)

if [ -n "$CORE_CLASSES" ]; then
  echo "$CORE_CLASSES" | while IFS= read -r CLASS; do
    [ -z "$CLASS" ] && continue
    if [ "$LANG_NAME" = "Java" ]; then
      # Java: 包名转路径查找
      REL_PATH=$(echo "$CLASS" | tr '.' '/')
      FOUND=$(find "$SRC_DIR" -path "*/${REL_PATH}.java" -type f 2>/dev/null | head -1 || true)
    else
      # 前端: 按文件名查找（多种扩展名）
      BASE_NAME=$(basename "$CLASS")
      FOUND=$(find "$SRC_DIR" -name "${BASE_NAME}.*" \( -name "*.vue" -o -name "*.ts" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.js" \) -not -path "*/node_modules/*" -type f 2>/dev/null | head -1 || true)
    fi
    if [ -n "$FOUND" ]; then
      print_pass "核心类存在: $CLASS"
    else
      print_fail "核心类不存在: $CLASS"
    fi
  done
else
  print_warn "未检测到 coreClasses"
fi

# ============================================
# 验证3：状态枚举值在代码中存在
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "--- 验证3: 状态枚举值（stateMachine.states）存在性 ---"
fi

ENUM_CLASS=$(python3 -c "
import json
try:
    data = json.load(open('$SUMMARY_FILE'))
    print(data.get('stateMachine', {}).get('enumClass', ''))
except: pass
" 2>/dev/null || true)

STATE_VALUES=$(python3 -c "
import json
try:
    data = json.load(open('$SUMMARY_FILE'))
    for s in data.get('stateMachine', {}).get('states', []):
        v = s.get('value', '')
        if v: print(v)
except: pass
" 2>/dev/null || true)

if [ -n "$ENUM_CLASS" ] && [ -n "$STATE_VALUES" ]; then
  # 找到枚举类文件
  if [ "$LANG_NAME" = "Java" ]; then
    ENUM_REL_PATH=$(echo "$ENUM_CLASS" | tr '.' '/')
    ENUM_FILE=$(find "$SRC_DIR" -path "*/${ENUM_REL_PATH}.java" -type f 2>/dev/null | head -1 || true)
  else
    # 前端: 按文件名查找
    ENUM_BASE_NAME=$(basename "$ENUM_CLASS")
    ENUM_FILE=$(find "$SRC_DIR" -name "${ENUM_BASE_NAME}.*" \( -name "*.ts" -o -name "*.js" \) -not -path "*/node_modules/*" -type f 2>/dev/null | head -1 || true)
  fi

  if [ -n "$ENUM_FILE" ]; then
    print_pass "状态枚举类存在: $ENUM_CLASS"
    echo "$STATE_VALUES" | while IFS= read -r STATE; do
      [ -z "$STATE" ] && continue
      if grep -qE "\b${STATE}\b" "$ENUM_FILE" 2>/dev/null; then
        print_pass "枚举值存在: ${ENUM_CLASS}.${STATE}"
      else
        print_fail "枚举值不存在: ${ENUM_CLASS}.${STATE}"
      fi
    done
  else
    print_fail "状态枚举类不存在: $ENUM_CLASS"
  fi
else
  print_warn "未检测到 stateMachine.states"
fi

# ============================================
# 验证4：核心链路方法名在代码中存在
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "--- 验证4: 核心链路（coreChain）方法名存在性 ---"
fi

CORE_CHAIN_METHODS=$(python3 -c "
import json, re
try:
    data = json.load(open('$SUMMARY_FILE'))
    for chain in data.get('coreChain', []):
        for flow in chain.get('flow', []):
            # 提取 ClassName.method() 格式的方法引用
            matches = re.findall(r'([A-Z][a-zA-Z0-9]+)\.([a-z][a-zA-Z0-9]+)\s*\(', flow)
            for cls, method in matches:
                print(f'{cls}.{method}')
except: pass
" 2>/dev/null || true)

if [ -n "$CORE_CHAIN_METHODS" ]; then
  echo "$CORE_CHAIN_METHODS" | sort -u | while IFS= read -r METHOD_REF; do
    [ -z "$METHOD_REF" ] && continue
    CLASS_PART=$(echo "$METHOD_REF" | sed 's/\..*//')
    METHOD_PART=$(echo "$METHOD_REF" | sed 's/.*\.//')

    # 找到类文件
    if [ "$LANG_NAME" = "Java" ]; then
      CLASS_FILE=$(find "$SRC_DIR" -name "${CLASS_PART}.java" -type f 2>/dev/null | head -1 || true)
    else
      # 前端: 按文件名查找（多种扩展名）
      CLASS_FILE=$(find "$SRC_DIR" -name "${CLASS_PART}.*" \( -name "*.vue" -o -name "*.ts" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.js" \) -not -path "*/node_modules/*" -type f 2>/dev/null | head -1 || true)
    fi
    if [ -n "$CLASS_FILE" ]; then
      if [ "$LANG_NAME" = "Java" ]; then
        if grep -qE "(public|protected|private|static).*\s${METHOD_PART}\s*\(" "$CLASS_FILE" 2>/dev/null; then
          print_pass "链路方法存在: ${METHOD_REF}"
        else
          print_fail "链路方法不存在: ${METHOD_REF}"
        fi
      else
        # 前端: 匹配函数定义
        if grep -qE "(function[[:space:]]+${METHOD_PART}|const[[:space:]]+${METHOD_PART}|async[[:space:]]+${METHOD_PART}|${METHOD_PART}[[:space:]]*\()" "$CLASS_FILE" 2>/dev/null; then
          print_pass "链路方法存在: ${METHOD_REF}"
        else
          print_fail "链路方法不存在: ${METHOD_REF}"
        fi
      fi
    else
      print_warn "链路方法所在类未找到: ${CLASS_PART}（可能来自外部依赖）"
    fi
  done
else
  print_warn "未检测到 coreChain 方法引用"
fi

# ============================================
# 验证5：filePath 路径缩写检查
# ============================================
if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "--- 验证5: 文件路径缩写检查 ---"
fi

ALL_PATHS=$(python3 -c "
import json
try:
    data = json.load(open('$SUMMARY_FILE'))
    # entryPoints 的 filePath
    for ep in data.get('entryPoints', []):
        fp = ep.get('filePath', '')
        if fp: print(fp)
    # coreClasses 的 filePath
    for cc in data.get('coreClasses', []):
        fp = cc.get('filePath', '')
        if fp: print(fp)
except: pass
" 2>/dev/null || true)

if [ -n "$ALL_PATHS" ]; then
  echo "$ALL_PATHS" | sort -u | while IFS= read -r FP; do
    [ -z "$FP" ] && continue
    # 检查是否包含缩写
    if echo "$FP" | grep -qE '\.\.\.' 2>/dev/null; then
      print_fail "路径包含缩写（必须使用完整路径）: $FP"
    elif [ -f "${SRC_DIR}/${FP}" ] || find "$SRC_DIR" -path "*/${FP}" -type f 2>/dev/null | grep -q .; then
      print_pass "文件路径存在: $FP"
    else
      print_fail "文件路径不存在: $FP"
    fi
  done
else
  print_warn "未检测到 filePath"
fi

# ============================================
# 汇总输出
# ============================================
if [ "$JSON_OUTPUT" = true ]; then
  echo "{"
  echo "  \"file\": \"$(basename "$SUMMARY_FILE")\","
  echo "  \"passed\": $PASS_COUNT,"
  echo "  \"failed\": $FAIL_COUNT,"
  echo "  \"warnings\": $WARN_COUNT,"
  echo "  \"allPassed\": $([ "$FAIL_COUNT" -eq 0 ] && echo true || echo false),"
  if [ ${#FAIL_DETAILS[@]} -gt 0 ]; then
    echo "  \"failures\": ["
    for i in "${!FAIL_DETAILS[@]}"; do
      echo -n "    \"${FAIL_DETAILS[$i]}\""
      [ $i -lt $((${#FAIL_DETAILS[@]} - 1)) ] && echo ","
    done
    echo ""
    echo "  ]"
  else
    echo "  \"failures\": []"
  fi
  echo "}"
else
  echo ""
  echo "=========================================="
  echo "代码反向验证汇总: 通过 $PASS_COUNT | 失败 $FAIL_COUNT | 警告 $WARN_COUNT"
  if [ ${#FAIL_DETAILS[@]} -gt 0 ]; then
    echo ""
    echo "失败项明细:"
    for detail in "${FAIL_DETAILS[@]}"; do
      echo "  - $detail"
    done
  fi
  echo "=========================================="
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
