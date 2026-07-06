#!/usr/bin/env python3
"""
Python 类签名提取脚本
提取 .py 文件的类 docstring + 公开方法签名，输出 JSON。

用法: python3 extract-signature-python.py <源码文件或目录>
依赖: Python 3.8+（仅标准库）
"""

import ast
import json
import os
import sys
from pathlib import Path


def extract_signatures(filepath: str) -> dict:
    """提取单个 Python 文件的类签名信息。"""
    result = {"file": filepath, "classes": []}
    try:
        with open(filepath, encoding="utf-8") as f:
            source = f.read()
        tree = ast.parse(source, filename=filepath)
    except (SyntaxError, UnicodeDecodeError, OSError):
        return result

    for node in ast.walk(tree):
        if not isinstance(node, ast.ClassDef):
            continue

        class_info = {
            "className": node.name,
            "line": node.lineno,
            "docstring": "",
            "methods": [],
        }

        # 提取 docstring
        if (node.body and isinstance(node.body[0], ast.Expr)
                and isinstance(node.body[0].value, ast.Constant)
                and isinstance(node.body[0].value.value, str)):
            doc = node.body[0].value.value.strip()
            # 只取前 3 行
            class_info["docstring"] = "\n".join(doc.split("\n")[:3])

        # 提取公开方法（不以 _ 开头，或 __init__）
        for item in node.body:
            if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                if item.name.startswith("_") and item.name != "__init__":
                    continue
                args = [a.arg for a in item.args.args]
                # 添加 self/cls 之外的参数标注
                params = ", ".join(args)
                return_hint = ""
                if item.returns:
                    try:
                        return_hint = f" -> {ast.unparse(item.returns)}"
                    except Exception:
                        pass
                class_info["methods"].append({
                    "name": item.name,
                    "line": item.lineno,
                    "signature": f"def {item.name}({params}){return_hint}",
                })

        result["classes"].append(class_info)

    return result


def main():
    if len(sys.argv) < 2:
        print("用法: python3 extract-signature-python.py <源码文件或目录>", file=sys.stderr)
        sys.exit(1)

    target = sys.argv[1]
    files = []

    if os.path.isdir(target):
        for root, _, filenames in os.walk(target):
            for fname in filenames:
                if fname.endswith(".py"):
                    files.append(os.path.join(root, fname))
    elif os.path.isfile(target):
        files.append(target)
    else:
        print(f"错误: {target} 不存在", file=sys.stderr)
        sys.exit(1)

    results = [extract_signatures(f) for f in sorted(files)]
    print(json.dumps({"files": results}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
