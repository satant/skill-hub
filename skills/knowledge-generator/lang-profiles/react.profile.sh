#!/usr/bin/env bash
#
# React 语言配置文件
# 适配 React 16+ / Next.js / TypeScript/JavaScript 项目
#
# 用法: source react.profile.sh
#

LANG_NAME="React"

# 文件扩展名配置
LANG_FILE_EXTENSIONS=("jsx" "tsx" "js" "ts")
LANG_FILE_FIND_ARGS=(-name "*.jsx" -o -name "*.tsx" -o -name "*.js" -o -name "*.ts")

# 方法签名正则（A2/A6 共用）
# 匹配 React 的多种函数/组件定义形式：
#   function ComponentName(
#   const ComponentName = (
#   const [state, setState] = useState(
#   const handleClick = useCallback / useMemo / useEffect
#   export function / export default function
#   async functionName(
LANG_METHOD_REGEX='(function[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*\(|const[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*=[[:space:]]*(async[[:space:]]*)?\(|async[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*\(|const[[:space:]]+\[[a-zA-Z0-9_]+,[[:space:]]*set[A-Za-z]+\][[:space:]]*=|export[[:space:]]+(default[[:space:]]+)?function[[:space:]]+|const[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*=[[:space:]]*(useCallback|useMemo)[[:space:]]*\()'
LANG_METHOD_EXCLUDE_PATTERNS=('if ' 'for ' 'while ' 'switch ' 'catch ' 'return ' 'new ' 'import ' 'interface ' 'type ' 'enum ')

# 大方法提取正则（A6 专用）
LANG_LARGE_METHOD_REGEX='(function[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*\(|const[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*=[[:space:]]*(async[[:space:]]*)?\(|async[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*\(|const[[:space:]]+\[[a-zA-Z0-9_]+,[[:space:]]*set[A-Za-z]+\][[:space:]]*=|export[[:space:]]+(default[[:space:]]+)?function[[:space:]]+|const[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*=[[:space:]]*(useCallback|useMemo)[[:space:]]*\()'
LANG_LARGE_METHOD_EXCLUDE_PATTERNS=('if ' 'for ' 'while ' 'switch ' 'catch ' 'return ' 'new ' 'import ' 'interface ' 'type ' 'enum ')

# 入口文件匹配（A7）
# Next.js pages/app 目录 + React Router + API 服务
LANG_ENTRY_GLOBS=("*page*" "*layout*" "*route*" "*api*.ts" "*api*.js" "*service*.ts" "*service*.js")
# 入口标识正则（React Router / fetch / axios / Next.js 数据获取）
LANG_ENTRY_ANNOTATION_REGEX='(Route[[:space:]]+path|fetch[[:space:]]*\(|axios\.(get|post|put|delete|patch|request)|createAsyncThunk|getServerSideProps|getStaticProps|defineRoute|createBrowserRouter|useRouter)'

# 无传统包名，用文件路径定位
LANG_PACKAGE_PREFIX_REGEX=''

# 类名到文件路径的转换方式
LANG_CLASS_TO_PATH_CMD='cat'
LANG_CLASS_FILE_SUFFIX=""

# 枚举文件匹配（TS 常量枚举/对象）
LANG_ENUM_GLOBS=("*enum*" "*const*" "*type*" "*status*" "*constant*")
# 枚举值正则
LANG_ENUM_VALUE_REGEX='\b[A-Z][A-Z_]{2,}\b'
# 枚举引用格式
LANG_ENUM_REF_FORMAT='%s.%s'
LANG_ENUM_REF_REGEX='%s\\.%s'

# import 语句过滤
LANG_IMPORT_EXCLUDE_PATTERNS=('node_modules' '@types' 'react$' 'react-dom' 'next/' 'react-router' 'redux' '@reduxjs' 'zustand' 'jotai' 'recoil')

# 类后缀关键词（B1 关键词重复检查用）
LANG_CLASS_SUFFIX_REGEX='\b[A-Z][a-zA-Z0-9]+(Component|Hook|Store|Api|Service|Page|View|Layout|Modal|Provider|Container|Presenter|Controller|Manager|Helper|Util|Utils|Context|Reducer|Middleware|Guard|HOC)\b'

# 模板选择
LANG_TEMPLATE_DOMAIN="业务领域类模板-前端.md"
LANG_TEMPLATE_DATA="数据模型类模板-前端.md"

# 大类阈值默认值
LANG_LARGE_LINE_THRESHOLD=300
LANG_LARGE_METHOD_THRESHOLD=10

# 核心文件表类型标签
LANG_FILE_TYPE_LABELS=(
  "路由/页面入口"
  "页面组件"
  "状态管理"
  "API 服务"
  "类型定义"
  "公共组件"
)
