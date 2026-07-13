#!/usr/bin/env bash
#
# 环境前置检查与自愈（门控0）
# 自动检测 python3 是否可用，不可用时按操作系统自动安装。
# 同时校验所有门控脚本的存在性和可执行权限。
#
# 解决问题：门控机制的双刃剑——python3 不可用时整个流程被卡住
# 设计原则：不让技术工具问题阻塞知识库生成流程
#
# 用法: bash ensure-python3.sh
# 支持系统: macOS（brew）、Ubuntu/Debian（apt）、CentOS/RHEL（yum/dnf）
#
set -euo pipefail

# ============================================
# 工具函数
# ============================================
log_info()  { echo "[INFO] $1"; }
log_pass()  { echo "[PASS] $1"; }
log_warn()  { echo "[WARN] $1" >&2; }
log_fail()  { echo "[FAIL] $1" >&2; }

# ============================================
# 步骤1：检测 python3
# ============================================
check_python3() {
  if command -v python3 &>/dev/null; then
    local version
    version=$(python3 --version 2>&1 | sed 's/Python //')
    log_pass "python3 已安装（版本 ${version}）"
    return 0
  fi
  log_warn "python3 未安装，开始自动安装..."
  return 1
}

# ============================================
# 步骤2：按操作系统安装 python3
# ============================================
install_python3() {
  local os_type
  os_type="$(uname -s)"

  case "$os_type" in
    Darwin)
      # macOS: 优先用 Homebrew
      if command -v brew &>/dev/null; then
        log_info "通过 Homebrew 安装 python3..."
        brew install python3
      else
        # 尝试安装 Homebrew
        log_info "Homebrew 未安装，先安装 Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        brew install python3
      fi
      ;;

    Linux)
      # Linux: 检测包管理器
      if command -v apt-get &>/dev/null; then
        # Ubuntu / Debian
        log_info "通过 apt-get 安装 python3..."
        sudo apt-get update -qq
        sudo apt-get install -y python3
      elif command -v yum &>/dev/null; then
        # CentOS / RHEL（旧版）
        log_info "通过 yum 安装 python3..."
        sudo yum install -y python3
      elif command -v dnf &>/dev/null; then
        # Fedora / RHEL（新版）
        log_info "通过 dnf 安装 python3..."
        sudo dnf install -y python3
      elif command -v apk &>/dev/null; then
        # Alpine（容器场景）
        log_info "通过 apk 安装 python3..."
        apk add --no-cache python3
      else
        log_fail "无法识别的 Linux 包管理器，请手动安装 python3"
        log_fail "常见安装命令："
        log_fail "  Ubuntu/Debian: sudo apt-get install python3"
        log_fail "  CentOS/RHEL:   sudo yum install python3"
        log_fail "  Fedora:        sudo dnf install python3"
        log_fail "  Alpine:        apk add python3"
        return 1
      fi
      ;;

    MINGW*|MSYS*|CYGWIN*)
      # Windows（Git Bash / MSYS2 / Cygwin 环境）
      if command -v winget &>/dev/null; then
        # Windows 10 1809+ 自带 winget
        log_info "通过 winget 安装 Python3..."
        winget install Python.Python.3
      elif command -v choco &>/dev/null; then
        # Chocolatey 包管理器
        log_info "通过 Chocolatey 安装 Python3..."
        choco install python3 -y
      elif command -v scoop &>/dev/null; then
        # Scoop 包管理器
        log_info "通过 Scoop 安装 Python3..."
        scoop install python
      else
        log_fail "Windows 上未检测到包管理器（winget/choco/scoop）"
        log_fail "请选择以下任一方式安装 Python3："
        log_fail "  方式1（推荐）: 官网下载安装包 https://www.python.org/downloads/"
        log_fail "  方式2: 安装 winget 后执行 winget install Python.Python.3"
        log_fail "  方式3: 安装 Chocolatey 后执行 choco install python3 -y"
        log_fail "  方式4: 安装 Scoop 后执行 scoop install python"
        log_fail "  安装时务必勾选「Add Python to PATH」"
        return 1
      fi
      ;;

    *)
      log_fail "不支持的操作系统: ${os_type}"
      log_fail "请手动安装 python3 后重试："
      log_fail "  macOS:    brew install python3"
      log_fail "  Linux:    apt-get/yum/dnf install python3"
      log_fail "  Windows:  https://www.python.org/downloads/"
      return 1
      ;;
  esac

  # 验证安装结果
  if command -v python3 &>/dev/null; then
    local version
    version=$(python3 --version 2>&1 | sed 's/Python //')
    log_pass "python3 安装成功（版本 ${version}）"
    return 0
  else
    log_fail "python3 安装失败，请手动安装后重试"
    return 1
  fi
}

# ============================================
# 步骤3：校验门控脚本完整性
# ============================================
check_scripts() {
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"

  local required_scripts=(
    "extract-business-terms.sh"
    "cluster-by-business-verb.sh"
    "extract-large-class-methods.sh"
    "cross-domain-scanner.sh"
  )

  local required_validators=(
    "../validators/validate-knowledge.sh"
    "../validators/cross-validate-with-code.sh"
    "../validators/validate-index-completeness.sh"
    "../validators/validate-gate-evidence.sh"
    "../validators/validate-subagent-output.sh"
  )

  local all_ok=true

  for script in "${required_scripts[@]}"; do
    local path="${script_dir}/${script}"
    if [ ! -f "$path" ]; then
      log_fail "脚本缺失: ${script}"
      all_ok=false
    elif [ ! -r "$path" ]; then
      log_fail "脚本不可读: ${script}"
      all_ok=false
    else
      log_pass "脚本就绪: ${script}"
    fi
  done

  for validator in "${required_validators[@]}"; do
    local path="${script_dir}/${validator}"
    if [ ! -f "$path" ]; then
      log_fail "校验器缺失: ${validator}"
      all_ok=false
    elif [ ! -r "$path" ]; then
      log_fail "校验器不可读: ${validator}"
      all_ok=false
    else
      log_pass "校验器就绪: ${validator}"
    fi
  done

  # v2.4.0 新增：语言配置文件校验
  local profile_dir="${script_dir}/../lang-profiles"
  local required_profiles=(
    "java.profile.sh"
    "vue.profile.sh"
    "react.profile.sh"
    "detect-language.sh"
  )

  if [ ! -d "$profile_dir" ]; then
    log_fail "语言配置目录缺失: lang-profiles/"
    all_ok=false
  else
    for profile in "${required_profiles[@]}"; do
      local path="${profile_dir}/${profile}"
      if [ ! -f "$path" ]; then
        log_fail "语言配置缺失: lang-profiles/${profile}"
        all_ok=false
      elif [ ! -r "$path" ]; then
        log_fail "语言配置不可读: lang-profiles/${profile}"
        all_ok=false
      else
        log_pass "语言配置就绪: lang-profiles/${profile}"
      fi
    done
  fi

  if [ "$all_ok" = true ]; then
    log_pass "所有门控脚本和校验器就绪"
    return 0
  else
    log_fail "部分脚本/校验器缺失或不可读，请检查文件完整性"
    return 1
  fi
}

# ============================================
# 步骤4：校验依赖命令
# ============================================
check_dependencies() {
  local required_cmds=("grep" "awk" "sed" "find" "wc")
  local missing=()

  for cmd in "${required_cmds[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [ ${#missing[@]} -eq 0 ]; then
    log_pass "所有基础依赖命令就绪（grep/awk/sed/find/wc）"
    return 0
  else
    log_fail "缺失基础命令: ${missing[*]}"
    log_fail "这些命令通常由 coreutils/textutils 提供，请安装后重试"
    return 1
  fi
}

# ============================================
# 主流程
# ============================================
main() {
  echo "=========================================="
  echo "环境前置检查（门控0）"
  echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "=========================================="
  echo ""

  # 1. python3 检测与安装
  if ! check_python3; then
    install_python3 || {
      echo ""
      echo "=========================================="
      echo "环境检查失败：python3 安装失败"
      echo "请手动安装 python3 后重新执行知识库生成"
      echo "=========================================="
      exit 1
    }
  fi
  echo ""

  # 2. 依赖命令校验
  check_dependencies || true
  echo ""

  # 3. 脚本完整性校验
  check_scripts || true
  echo ""

  # 汇总
  echo "=========================================="
  echo "环境前置检查完成，门控机制可以正常工作"
  echo "=========================================="
}

main "$@"
