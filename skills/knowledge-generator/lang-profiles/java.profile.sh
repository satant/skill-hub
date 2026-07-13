#!/usr/bin/env bash
#
# Java 语言配置文件
# 从现有脚本中提取的 Java 特有配置，确保 Java 项目行为零变化
#
# 用法: source java.profile.sh
#

LANG_NAME="Java"

# 文件扩展名配置
LANG_FILE_EXTENSIONS=("java")
LANG_FILE_FIND_ARGS=(-name "*.java")

# 方法签名正则（A2/A6 共用）
# 匹配 Java public/protected 方法声明
LANG_METHOD_REGEX='(public|protected).*(void|[A-Z][A-Za-z0-9<>]*)\s+([a-z]+[A-Za-z0-9]*)\s*\('
LANG_METHOD_EXCLUDE_PATTERNS=('class ' 'interface ' 'enum ')

# 大方法提取正则（A6 专用，更严格）
LANG_LARGE_METHOD_REGEX='^\s*public\s+(static\s+)?(synchronized\s+)?(final\s+)?[A-Za-z0-9_<>\[\],?\s]+\s+[a-zA-Z0-9_]+\s*\('
LANG_LARGE_METHOD_EXCLUDE_PATTERNS=('class ' 'interface ' 'enum ')

# 入口文件匹配（A7）
LANG_ENTRY_GLOBS=("*Controller.java" "*Facade*Impl.java")
# 入口注解/装饰器正则（Spring MVC）
LANG_ENTRY_ANNOTATION_REGEX='^\s*(@RequestMapping|@PostMapping|@GetMapping|@PutMapping|@DeleteMapping|@PatchMapping)'

# 包名前缀（B1/B4 路径校验用）
LANG_PACKAGE_PREFIX_REGEX='\b(com|org|net|io|cn|edu|gov)\.[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)*\.[A-Z][a-zA-Z0-9_]*\b'

# 类名到文件路径的转换方式
LANG_CLASS_TO_PATH_CMD='tr "." "/"'
LANG_CLASS_FILE_SUFFIX=".java"

# 枚举文件匹配
LANG_ENUM_GLOBS=("*Enum.java" "*Status.java" "*Type.java")
# 枚举值正则（大写常量）
LANG_ENUM_VALUE_REGEX='\b[A-Z][A-Z_]{2,}\b'
# 枚举引用格式（ClassName.VALUE）
LANG_ENUM_REF_FORMAT='%s.%s'
LANG_ENUM_REF_REGEX='%s\\.%s'

# import 语句过滤（A7 跨模块分析用）
LANG_IMPORT_EXCLUDE_PATTERNS=('java\.' 'javax\.' 'org.springframework' 'org.apache' 'com.alibaba' 'com.google' 'lombok')

# 类后缀关键词（B1 关键词重复检查用）
LANG_CLASS_SUFFIX_REGEX='\b[A-Z][a-zA-Z0-9]+(Manager|Service|Controller|Facade|Enum|DO|DTO|Repository|Processor|Validator|Calculator|Helper|Builder|Factory|Adapter|Converter|Provider|Handler|Listener|Observer|Strategy)\b'

# 模板选择
LANG_TEMPLATE_DOMAIN="业务领域类模板.md"
LANG_TEMPLATE_DATA="数据模型类模板.md"

# 大类阈值默认值
LANG_LARGE_LINE_THRESHOLD=500
LANG_LARGE_METHOD_THRESHOLD=15

# 核心文件表类型标签（模板填充引导）
LANG_FILE_TYPE_LABELS=(
  "Web 入口"
  "服务接口"
  "服务实现"
  "业务编排"
  "数据对象"
  "枚举"
)
