# Trae Skill Hub

Trae IDE 技能集合，为不同使用场景提供可复用、可安装的专业 AI 技能。

## 技能目录

| 技能名称 | 说明 | 安装 |
| --- | --- | --- |
| [knowledge-generator](./skills/knowledge-generator/) | 分层渐进扫描项目代码，自动生成知识库文件并维护知识库索引 | 复制或上传 |

## 安装方式

### 方式一：复制到项目（项目级）

将需要的 skill 目录复制到你项目的 `.trae/skills/` 目录下：

```bash
# 克隆仓库
git clone https://github.com/YOUR_USERNAME/skill-hub.git

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
# 打包单个 skill
cd skills/knowledge-generator
zip -r knowledge-generator.zip .
```

## 技能结构

每个技能遵循 Trae 官方的 skill 结构规范：

```
skill-name/
├── SKILL.md          # 核心 skill 定义文件（必须）
├── templates/        # 可复用模板（可选）
├── examples/         # 输入/输出示例（可选）
└── resources/        # 参考文件、脚本或素材（可选）
```

## 贡献

欢迎贡献新的 skill 或改进现有 skill：

1. Fork 本仓库
2. 在 `skills/` 下创建新的 skill 目录（包含 SKILL.md）
3. 提交 Pull Request

## 许可证

MIT License - 详见 [LICENSE](./LICENSE)
