# 更新日志

本文件记录 skill-hub 项目的所有显著变更。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.1.0] - 2026-07-06

### 新增
- SKILL.md 新增 `version` 字段，便于用户识别已安装版本
- 新增 `CHANGELOG.md`，用于版本管理与变更追溯
- 新增 `.gitignore`，避免误提交系统文件与临时文件
- README 新增"更新已安装的 skill"章节，明确升级路径

### 变更
- 精简 SKILL.md frontmatter 的 description，触发关键词统一收敛到正文"触发条件"章节，避免重复
- SKILL.md 内嵌的三套模板收敛为引用 `templates/` 目录，消除"双份维护"风险

### 修复
- 修正 README.md 中未替换的 `YOUR_USERNAME` 占位符为实际仓库地址
- 修复首次使用时维护规则缺失导致"代码修改后不会自动维护知识库"的联动断链问题

## [1.0.0] - 2026-07-06

### 新增
- 初始化 skill-hub 项目
- 发布 `knowledge-generator` skill，支持分层渐进扫描、分批生成、质量校验与索引维护
- 提供业务领域类、项目导航类、项目工具类三套知识库模板
- 提供业务领域类输出示例
