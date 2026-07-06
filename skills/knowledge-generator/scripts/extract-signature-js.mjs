#!/usr/bin/env node
/**
 * JS/TS 类签名提取脚本
 * 提取 .js/.ts/.jsx/.tsx 文件的 class 声明 + JSDoc + 导出方法签名，输出 JSON。
 *
 * 用法: node extract-signature-js.mjs <源码文件或目录>
 * 依赖: Node.js 16+（仅标准库）
 */

import { readFileSync, readdirSync, statSync, existsSync } from 'fs';
import { join, extname } from 'path';

const EXTS = ['.js', '.ts', '.jsx', '.tsx'];

/**
 * 递归收集目录下所有目标文件
 */
function collectFiles(target) {
  const files = [];
  if (!existsSync(target)) return files;

  const stat = statSync(target);
  if (stat.isFile()) {
    files.push(target);
  } else if (stat.isDirectory()) {
    const walk = (dir) => {
      for (const entry of readdirSync(dir)) {
        const fullPath = join(dir, entry);
        const s = statSync(fullPath);
        if (s.isDirectory()) {
          // 跳过 node_modules
          if (entry !== 'node_modules') walk(fullPath);
        } else if (EXTS.includes(extname(entry))) {
          files.push(fullPath);
        }
      }
    };
    walk(target);
  }
  return files;
}

/**
 * 从源码中提取类和方法签名
 */
function extractSignatures(filepath) {
  const result = { file: filepath, classes: [] };

  let source;
  try {
    source = readFileSync(filepath, 'utf-8');
  } catch {
    return result;
  }

  const lines = source.split('\n');

  // 匹配 class 声明
  const classRegex = /(?:export\s+)?(?:default\s+)?(?:abstract\s+)?class\s+([A-Za-z0-9_]+)/g;

  for (const match of source.matchAll(classRegex)) {
    const className = match[1];
    const matchIndex = match.index;

    // 计算行号
    const beforeMatch = source.substring(0, matchIndex);
    const lineNum = beforeMatch.split('\n').length;

    // 向上查找 JSDoc 注释
    let docstring = '';
    let searchLine = lineNum - 2; // class 声明上一行开始
    while (searchLine >= 0) {
      const line = (lines[searchLine] || '').trim();
      if (line.endsWith('*/')) {
        // 找到 JSDoc 结尾，向上找到开头
        let docLines = [];
        let docEnd = searchLine;
        while (docEnd >= 0 && !(lines[docEnd] || '').includes('/**')) {
          docLines.unshift(lines[docEnd].trim());
          docEnd--;
        }
        if (docEnd >= 0) {
          docLines.unshift(lines[docEnd].trim());
        }
        docstring = docLines.join('\n').substring(0, 300);
        break;
      }
      if (line === '' || line.startsWith('//')) {
        searchLine--;
        continue;
      }
      break; // 遇到非空非注释行，停止
    }

    // 提取类体内的方法签名（简化版：匹配方法定义模式）
    const methods = [];
    // 找到 class body 范围
    let braceStart = source.indexOf('{', matchIndex);
    if (braceStart === -1) continue;

    let depth = 0;
    let braceEnd = braceStart;
    for (let i = braceStart; i < source.length; i++) {
      if (source[i] === '{') depth++;
      else if (source[i] === '}') {
        depth--;
        if (depth === 0) {
          braceEnd = i;
          break;
        }
      }
    }

    const classBody = source.substring(braceStart + 1, braceEnd);

    // 匹配方法签名：async methodName(params) / methodName(params): RetType
    const methodRegex = /(?:async\s+)?([a-zA-Z0-9_]+)\s*\(([^)]*)\)/g;
    const seen = new Set();
    for (const m of classBody.matchAll(methodRegex)) {
      const methodName = m[1];
      // 跳过 constructor 之外的关键字
      if (['if', 'for', 'while', 'switch', 'catch', 'return', 'function', 'new'].includes(methodName)) continue;
      if (seen.has(methodName)) continue;
      seen.add(methodName);

      const params = m[2].split(',').map(p => p.trim()).filter(Boolean);
      const paramNames = params.map(p => p.split(/[:\s=]/)[0].trim()).join(', ');
      methods.push({
        name: methodName,
        signature: `${methodName}(${paramNames})`,
      });
    }

    result.classes.push({
      className,
      line: lineNum,
      docstring,
      methods,
    });
  }

  return result;
}

// 主逻辑
const target = process.argv[2];
if (!target) {
  console.error('用法: node extract-signature-js.mjs <源码文件或目录>');
  process.exit(1);
}

const files = collectFiles(target);
const results = files.map(extractSignatures);
console.log(JSON.stringify({ files: results }, null, 2));
