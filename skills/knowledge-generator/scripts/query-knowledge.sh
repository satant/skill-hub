#!/usr/bin/env bash
#
# 知识库查询工具（D1）
# AI 执行任务前调用此工具查询知识库，命中后消费 .summary.json 减少扫描范围。
#
# 用法:
#   bash query-knowledge.sh <知识库目录> <关键词1> [关键词2] [关键词3] ...
#
# 输出格式（JSON）:
#   {
#     "matched": true/false,
#     "results": [
#       {
#         "domain": "领域名称",
#         "summaryFile": ".summary.json 路径",
#         "docFile": ".md 文件路径",
#         "matchedKeywords": ["命中的关键词"],
#         "confidence": "high/low"
#       }
#     ],
#     "hint": "建议消费路径说明"
#   }
#
set -euo pipefail

KB_DIR="${1:-}"
shift
KEYWORDS=("$@")

if [ -z "$KB_DIR" ] || [ ${#KEYWORDS[@]} -eq 0 ]; then
  echo '{"matched":false,"results":[],"hint":"用法: bash query-knowledge.sh <知识库目录> <关键词1> [关键词2] ..."}' >&2
  exit 1
fi

if [ ! -d "$KB_DIR" ]; then
  echo '{"matched":false,"results":[],"hint":"知识库目录不存在"}'
  exit 0
fi

# 收集所有 .summary.json 文件
SUMMARY_FILES=$(find "$KB_DIR" -name "*.summary.json" -type f 2>/dev/null || true)

if [ -z "$SUMMARY_FILES" ]; then
  INDEX_FILE="${KB_DIR}/知识库索引.md"
  if [ -f "$INDEX_FILE" ]; then
    echo '{"matched":false,"results":[],"hint":"未找到 .summary.json 文件，建议读取知识库索引手动查找"}'
  else
    echo '{"matched":false,"results":[],"hint":"知识库为空或首次构建"}'
  fi
  exit 0
fi

# 使用 python3 安全地生成 JSON（避免手工拼接的转义问题）
KEYWORDS_JSON=$(printf '%s\n' "${KEYWORDS[@]}" | python3 -c '
import sys, json
keywords = [line.strip() for line in sys.stdin if line.strip()]
print(json.dumps(keywords, ensure_ascii=False))
')

SUMMARY_LIST_JSON=$(echo "$SUMMARY_FILES" | python3 -c '
import sys, json
lines = [line.strip() for line in sys.stdin if line.strip()]
print(json.dumps(lines, ensure_ascii=False))
')

# 传递给 python3 处理：搜索每个 summary 文件，输出安全 JSON
python3 -c "
import json, sys, os, re

kb_dir = $(python3 -c "import json; print(json.dumps('$KB_DIR'))")
keywords = ${KEYWORDS_JSON}
summary_files = ${SUMMARY_LIST_JSON}

results = []
for sf in summary_files:
    try:
        with open(sf, encoding='utf-8') as f:
            content = f.read()
    except Exception:
        continue

    # 检查关键词命中
    matched_kw = []
    for kw in keywords:
        if kw.lower() in content.lower():
            matched_kw.append(kw)

    if not matched_kw:
        continue

    # 尝试解析 JSON 提取字段
    domain = ''
    doc_file = ''
    confidence = 'high'
    try:
        data = json.loads(content)
        domain = data.get('domain', '')
        doc_file = data.get('docFile', '')
        # 取最低置信度
        def check_conf(obj):
            if isinstance(obj, dict):
                c = obj.get('confidence', '')
                if c == 'low':
                    return 'low'
                for v in obj.values():
                    r = check_conf(v)
                    if r == 'low':
                        return 'low'
            elif isinstance(obj, list):
                for item in obj:
                    r = check_conf(item)
                    if r == 'low':
                        return 'low'
            return 'high'
        if check_conf(data) == 'low':
            confidence = 'mixed'
    except json.JSONDecodeError:
        # 非 JSON 或解析失败，用正则降级提取
        m = re.search(r'\"domain\"\s*:\s*\"([^\"]+)\"', content)
        if m:
            domain = m.group(1)
        m = re.search(r'\"docFile\"\s*:\s*\"([^\"]+)\"', content)
        if m:
            doc_file = m.group(1)

    rel_summary = os.path.relpath(sf, kb_dir)
    results.append({
        'domain': domain,
        'summaryFile': rel_summary,
        'docFile': doc_file,
        'matchedKeywords': matched_kw,
        'confidence': confidence
    })

output = {
    'matched': len(results) > 0,
    'results': results,
    'hint': '已命中知识库，建议优先读取 summaryFile（.summary.json），仅在需要深入细节时读取 docFile（.md）' if results else '未命中任何知识库文档，建议正常扫描代码'
}
print(json.dumps(output, ensure_ascii=False, indent=2))
"
