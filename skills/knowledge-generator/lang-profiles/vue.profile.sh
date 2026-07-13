#!/usr/bin/env bash
#
# Vue 语言配置文件
# 适配 Vue 2/3 + TypeScript/JavaScript 项目
#
# 用法: source vue.profile.sh
#

LANG_NAME="Vue"

# 文件扩展名配置
LANG_FILE_EXTENSIONS=("vue" "js" "ts" "jsx" "tsx")
LANG_FILE_FIND_ARGS=(-name "*.vue" -o -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx")

# 方法签名正则（A2/A6 共用）
# 匹配 Vue/JS 的多种函数定义形式：
#   function methodName(
#   const methodName = (
#   const methodName = async (
#   async methodName(
#   methods: { methodName(
#   methodName(args) {   (Vue Options API methods)
LANG_METHOD_REGEX='(function[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*\(|const[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*=[[:space:]]*(async[[:space:]]*)?\(|async[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*\(|[a-zA-Z0-9_]+[[:space:]]*\([^)]*\)[[:space:]]*\{|const[[:space:]]+\[[a-zA-Z0-9_]+,[[:space:]]*set[A-Za-z]+\][[:space:]]*=)'
LANG_METHOD_EXCLUDE_PATTERNS=('if ' 'for ' 'while ' 'switch ' 'catch ' 'return ' 'new ' 'import ' 'export default ' 'interface ' 'type ' 'enum ' 'namespace ')

# 大方法提取正则（A6 专用）
LANG_LARGE_METHOD_REGEX='(function[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*\(|const[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*=[[:space:]]*(async[[:space:]]*)?\(|async[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*\(|[a-zA-Z0-9_]+[[:space:]]*\([^)]*\)[[:space:]]*\{|const[[:space:]]+\[[a-zA-Z0-9_]+,[[:space:]]*set[A-Za-z]+\][[:space:]]*=|setup[[:space:]]*\(\)|export[[:space:]]+(default[[:space:]]+)?(function|const)[[:space:]]+)'
LANG_LARGE_METHOD_EXCLUDE_PATTERNS=('if ' 'for ' 'while ' 'switch ' 'catch ' 'return ' 'new ' 'import ' 'interface ' 'type ' 'enum ')

# 入口文件匹配（A7）
# Vue Router 路由文件 + API 模块 + 页面入口
LANG_ENTRY_GLOBS=("*router*" "*routes*" "*api*.ts" "*api*.js" "*service*.ts" "*service*.js")
# 入口标识正则（Vue Router 定义 / axios/fetch 请求）
LANG_ENTRY_ANNOTATION_REGEX='(router\.(get|post|put|delete|patch|push|replace)|\$\.([[:space:]]*)(get|post|put|delete|patch)|axios\.(get|post|put|delete|patch|request)|request[[:space:]]*[<(]|fetch[[:space:]]*\(|createRouter|defineRoute)'

# 无传统包名，用文件路径定位
LANG_PACKAGE_PREFIX_REGEX=''

# 类名到文件路径的转换方式（前端直接用文件名）
LANG_CLASS_TO_PATH_CMD='cat'
LANG_CLASS_FILE_SUFFIX=""

# 枚举文件匹配（TS 常量枚举/对象）
LANG_ENUM_GLOBS=("*enum*" "*const*" "*type*" "*status*" "*constant*")
# 枚举值正则（大写常量）
LANG_ENUM_VALUE_REGEX='\b[A-Z][A-Z_]{2,}\b'
# 枚举引用格式（对象属性访问 EnumName.VALUE）
LANG_ENUM_REF_FORMAT='%s.%s'
LANG_ENUM_REF_REGEX='%s\\.%s'

# import 语句过滤（A7 跨模块分析用）
LANG_IMPORT_EXCLUDE_PATTERNS=('node_modules' '@types' 'vue$' 'react$' 'react-dom' 'vue-router' 'vuex' 'pinia' '@vue' 'next/' 'nuxt')

# 类后缀关键词（B1 关键词重复检查用）
LANG_CLASS_SUFFIX_REGEX='\b[A-Z][a-zA-Z0-9]+(Component|Hook|Store|Api|Service|Page|View|Layout|Modal|Provider|Composable|Controller|Manager|Helper|Util|Utils|Mixin|Directive|Plugin|Middleware|Guard|Interceptor)\b'

# 模板选择
LANG_TEMPLATE_DOMAIN="业务领域类模板-前端.md"
LANG_TEMPLATE_DATA="数据模型类模板-前端.md"

# 大类阈值默认值（前端文件通常更短）
LANG_LARGE_LINE_THRESHOLD=300
LANG_LARGE_METHOD_THRESHOLD=10

# 核心文件表类型标签（模板填充引导）
LANG_FILE_TYPE_LABELS=(
  "路由/页面入口"
  "页面组件"
  "状态管理"
  "API 服务"
  "类型定义"
  "公共组件"
)
