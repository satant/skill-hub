# Trae Skill Hub

Trae IDE 技能集合，为不同使用场景提供可复用、可安装的专业 AI 技能。

## 技能目录

| 技能名称 | 版本 | 说明 | 安装 |
| --- | --- | --- | --- |
| [knowledge-generator](./skills/knowledge-generator/) | 2.2.0 | 为 AI 解决问题提供精准依据：扫描代码生成知识库（双产物 .md+.summary.json），增强领域识别（术语/动词/重叠率/深度/重组），合规反编译二方库，支持知识库查询与体检 | 复制或上传 |

## 安装方式

### 方式一：复制到项目（项目级）

将需要的 skill 目录复制到你项目的 `.trae/skills/` 目录下：

```bash
# 克隆仓库
git clone https://github.com/satant/skill-hub.git

# 复制单个 skill 到你的项目
cp -r skill-hub/skills/knowledge-generator /your-project/.trae/skills/
```

### 方式二：全局安装（所有项目生效）

将 skill 目录复制到全局 skills 目录：

- macOS/Linux：`~/.trae/skills/`
- Windows：`%userprofile%/.trae/skills/`

```bash
cp -r skill-hub/skills/knowledge-generator ~/.trae/skills/
```

### 方式三：Trae SOLO 上传安装

1. 将单个 skill 目录打包为 zip 文件（根目录必须包含 SKILL.md）
2. 在 Trae SOLO 中打开技能管理中心
3. 点击"上传技能"，上传 zip 文件

```bash
# 打包单个 skill（排除系统文件和临时文件）
cd skills/knowledge-generator
zip -r knowledge-generator.zip . -x "*.DS_Store" "*.zip" "__MACOSX/*"
```

## 更新已安装的 skill

当本仓库发布新版本时，已安装的 skill 需要手动更新。**更新前请务必先查阅 [CHANGELOG.md](./CHANGELOG.md)**，确认本次变更是否影响你正在使用的功能，以及是否包含破坏性变更（主版本号变化）。

### ⚠️ 重要：备份本地定制

如果你在已安装的 skill 目录下做过本地修改（如调整模板、补充示例），**覆盖更新会丢失这些改动**。更新前请先备份：

```bash
# 备份已安装的 skill
cp -r /your-project/.trae/skills/knowledge-generator /tmp/knowledge-generator.backup
```

或使用 `git diff` 对比差异后再决定保留哪些改动。

### 方式一：重新复制覆盖（适用于方式一、方式二安装）

```bash
# 1. 进入本地仓库目录并拉取最新代码
cd /path/to/skill-hub
git pull origin main

# 2. 覆盖到目标目录（项目级或全局）
cp -r skills/knowledge-generator /your-project/.trae/skills/
# 或全局：
cp -r skills/knowledge-generator ~/.trae/skills/
```

### 方式二：Trae SOLO 重新上传

重新打包 zip 并上传，会覆盖旧版本：

```bash
cd skills/knowledge-generator
zip -r knowledge-generator.zip . -x "*.DS_Store" "*.zip" "__MACOSX/*"
```

然后在 Trae SOLO 技能管理中心重新上传即可。

### 如何判断当前版本是否需要更新

每个 skill 的 `SKILL.md` 顶部 frontmatter 中包含 `version` 字段，对照本仓库 `CHANGELOG.md` 中的最新版本号即可判断：

- **主版本号（MAJOR）变化**：包含破坏性变更，建议尽快更新，更新前务必阅读 CHANGELOG 的破坏性变更说明
- **次版本号（MINOR）变化**：新增功能且向后兼容，按需更新
- **修订号（PATCH）变化**：仅修复问题，推荐更新

## 技能结构

每个技能遵循 Trae 官方的 skill 结构规范：

```
skill-name/
├── SKILL.md          # 核心 skill 定义文件（必须）
├── templates/        # 可复用模板（可选）
├── examples/         # 输入/输出示例（可选）
├── scripts/          # 可执行工具脚本（可选）
├── validators/       # 校验脚本（可选）
└── resources/        # 参考文件、脚本或素材（可选）
```

## 贡献

欢迎贡献新的 skill 或改进现有 skill：

1. Fork 本仓库
2. 在 `skills/` 下创建新的 skill 目录（包含 SKILL.md）
3. 提交 Pull Request

## 许可证

MIT License - 详见 [LICENSE](./LICENSE)
