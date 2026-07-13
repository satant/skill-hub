#!/usr/bin/env bash
#
# 项目语言自动检测脚本
# 根据项目特征文件和源码统计，自动判断项目类型并输出对应的 profile 文件路径。
#
# 检测优先级：
#   1. package.json 中的框架依赖（最准确）
#   2. 构建配置文件（pom.xml / build.gradle → Java）
#   3. 源码文件统计（兜底）
#   4. 默认 Java（最终兜底）
#
# 用法: bash detect-language.sh [项目根目录]
#   不传参数时默认当前目录
# 输出: profile 文件的绝对路径（source 即可加载变量）
#   退出码 0: 检测成功
#   退出码 1: 目录不存在
#
set -euo pipefail

PROJECT_ROOT="${1:-.}"

# 转为绝对路径
PROJECT_ROOT=$(cd "$PROJECT_ROOT" 2>/dev/null && pwd || echo "$PROJECT_ROOT")

if [ ! -d "$PROJECT_ROOT" ]; then
  echo "错误: 项目根目录不存在: $PROJECT_ROOT" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ============================================
# 检测1：package.json 框架依赖
# ============================================
if [ -f "$PROJECT_ROOT/package.json" ]; then
  # 合并 dependencies 和 devDependencies，提取框架名
  DEPS=$(cat "$PROJECT_ROOT/package.json" 2>/dev/null \
    | grep -oE '"(vue|react|next|nuxt|@vue/core|@vitejs/plugin-vue|vue-router|pinia|vuex|react-dom|react-router-dom|react-router|@reduxjs/toolkit|redux|zustand|jotai|recoil|@tanstack/react-query|@apollo/client|next)"' \
    | tr -d '"' | sort -u 2>/dev/null || true)

  # Vue 检测
  if echo "$DEPS" | grep -qiE '^(vue|nuxt|@vue|vue-router|pinia|vuex)$'; then
    echo "${SCRIPT_DIR}/vue.profile.sh"
    exit 0
  fi

  # React 检测
  if echo "$DEPS" | grep -qiE '^(react|next|react-dom|react-router|react-router-dom|@reduxjs|redux|zustand|jotai|recoil|@tanstack/react-query)$'; then
    echo "${SCRIPT_DIR}/react.profile.sh"
    exit 0
  fi

  # package.json 存在但无已知框架，按文件统计判断
fi

# ============================================
# 检测2：构建配置文件（Java）
# ============================================
if [ -f "$PROJECT_ROOT/pom.xml" ] \
  || [ -f "$PROJECT_ROOT/build.gradle" ] \
  || [ -f "$PROJECT_ROOT/build.gradle.kts" ] \
  || [ -f "$PROJECT_ROOT/settings.gradle" ]; then
  echo "${SCRIPT_DIR}/java.profile.sh"
  exit 0
fi

# ============================================
# 检测3：源码文件统计
# ============================================
# 排除 node_modules 和 target 目录
count_files() {
  local pattern="$1"
  find "$PROJECT_ROOT" -name "$pattern" \
    -not -path "*/node_modules/*" \
    -not -path "*/target/*" \
    -not -path "*/dist/*" \
    -not -path "*/build/*" \
    -not -path "*/.git/*" \
    2>/dev/null | wc -l | tr -d ' '
}

VUE_COUNT=$(count_files "*.vue")
JSX_COUNT=$(count_files "*.jsx")
TSX_COUNT=$(count_files "*.tsx")
JAVA_COUNT=$(count_files "*.java")
TS_COUNT=$(count_files "*.ts")
JS_COUNT=$(count_files "*.js")

# Vue 优先：有 .vue 文件就判定为 Vue
if [ "${VUE_COUNT:-0}" -gt 0 ]; then
  echo "${SCRIPT_DIR}/vue.profile.sh"
  exit 0
fi

# React：有 .jsx/.tsx 文件
REACT_FILE_COUNT=$(( ${JSX_COUNT:-0} + ${TSX_COUNT:-0} ))
if [ "${REACT_FILE_COUNT:-0}" -gt 0 ]; then
  echo "${SCRIPT_DIR}/react.profile.sh"
  exit 0
fi

# Java：有 .java 文件
if [ "${JAVA_COUNT:-0}" -gt 0 ]; then
  echo "${SCRIPT_DIR}/java.profile.sh"
  exit 0
fi

# 有 .ts/.js 但无框架特征，默认按 React 处理（TS/JS 项目更可能是前端）
if [ "${TS_COUNT:-0}" -gt 0 ] || [ "${JS_COUNT:-0}" -gt 0 ]; then
  # 但排除只有配置文件的情况（如 .trae 目录下的 ts）
  SRC_TS_COUNT=$(find "$PROJECT_ROOT/src" -name "*.ts" -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
  SRC_JS_COUNT=$(find "$PROJECT_ROOT/src" -name "*.js" -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
  if [ "${SRC_TS_COUNT:-0}" -gt 0 ] || [ "${SRC_JS_COUNT:-0}" -gt 0 ]; then
    echo "${SCRIPT_DIR}/react.profile.sh"
    exit 0
  fi
fi

# ============================================
# 兜底：默认 Java
# ============================================
echo "${SCRIPT_DIR}/java.profile.sh"
