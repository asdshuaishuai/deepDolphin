#include "DocPages.h"

namespace DocPages {
namespace {

/// 客户端仓库（关于页 / 致谢页 / 帮助页共用的**唯一**出处）。
const char *const kClientRepo = "https://github.com/asdshuaishuai/deepDolphin";
/// 引擎仓库。
const char *const kEngineRepo = "https://github.com/asdshuaishuai/moongit";

/// 关于页。
///
/// ⚠ 平台词（Qt 6 / DDE / DTK / deepin）是**本平台的事实**，不是抄来的 ——
///   抄 mac 的就会把本客户端说成 Swift/macOS 的。
const char *const kAboutZhCN = R"MD(## deepDolphin

**moongit 引擎的原生客户端** — AI 驱动的本地项目群管理面板（deepin / UOS 桌面版）。

deepDolphin 是 [moongit](https://github.com/asdshuaishuai/moongit) 引擎的上层 UI 实现。
引擎（仓颉语言，AI 无关）提供事实与动作；客户端提供原生界面与 AI 层。

- **仪表盘** — 项目群脉搏 + 统计卡 + 项目卡片（整卡可点）
- **看板** — 按健康状态分列的项目画板
- **里程碑** — 绑定 git tag 自动判定达成
- **架构图** — 模块分层与依赖治理
- **代码图谱** — 符号树 / 置信度疑点 / 调用关系，左栏可切「列表 / 热力图」
- **补丁体检** — 工作区改动的置信度三层体检（算法 → 人工裁决 → 合并终稿）
- **AI 整合** — 浅 / 深更新 + AI 摘要、一键项目说明、定时简报
- **Git 白名单操作** — 拉取 / 推送 / 提交 / 暂存 / 恢复

### 架构

```
引擎（moongit，仓颉，AI 无关）
    ↑ CLI 子进程
客户端（deepDolphin，Qt 6 + DDE / DTK，AI 层）
    ↑ LLM API
用户选择的 AI Provider
```

### 版本

v0.1.0 — deepin / UOS 桌面版
)MD";

/// 帮助页。
const char *const kHelpZhCN = R"MD(## 使用指南

### 快速开始

1. 侧栏 **"+ 添加 / 扫描项目"** 注册你的项目
2. 仪表盘自动加载所有项目的进度数据
3. **点项目卡片的任意位置** 进入详情页（分支进度 / Git 操作 / 里程碑）

### 里程碑

在里程碑页面点 **"+"** 新建里程碑。绑定 git tag 后，tag 出现在仓库中即自动判定达成。

### 图谱三件套

- **架构图** — 详情页「架构图」入口，看模块分层与依赖治理；可生成、可导出
- **代码图谱** — 详情页「代码图谱」入口，看符号树 / 置信度 / 调用关系；左栏可在「列表 / 热力图」间切换
- **补丁体检** — 详情页「补丁体检」入口，对工作区未提交改动做三层体检：
  算法层给分与疑点 → 人工逐项裁决 → 合并出终稿

### AI 功能

1. 面板菜单 **「设置」** → AI 页签，配置 Provider 与 API Key
2. 更新菜单里的 **"+AI 摘要"** 变体
3. 项目页的 **"✦ 项目说明"** 一键生成
4. 仪表盘的 **"项目群说明"** 一键生成全局摘要

### Git 操作

项目详情页的 Git 操作区域支持：

- **拉取 / 推送** — 远端同步
- **暂存 / 恢复** — 工作区暂存
- **提交** — 输入提交信息后一键提交全部改动

### 引擎

deepDolphin 的一切事实与动作都来自 **moongit 引擎**（CLI 子进程）。
引擎缺席时面板会给出安装指引，而不是假装有数据。
)MD";

/// 开源感谢页。
///
/// 只感谢**非基础设施层级**的第三方项目 —— 系统框架（Qt 6 / DDE / DTK）
/// 是平台自带的能力，不在致谢之列（与 mac 同款口径）。
const char *const kOpenSourceZhCN = R"MD(## 开源感谢

这里只感谢**非基础设施层级**的第三方项目 —— 系统框架（Qt 6 / DDE / DTK 等）
是平台自带的能力，不在致谢之列。

### 引擎

- **[moongit](https://github.com/asdshuaishuai/moongit)** — 仓颉语言项目群进度引擎（本产品的核心）

### 模型目录

- **[models.dev](https://models.dev)** — AI 模型元数据目录（provider / model / 成本 / 能力），AI 设置页的数据来源

### 外部工具

- **git** — 版本控制（引擎的核心依赖）
- **curl** — HTTP 请求（引擎的 AI 调用依赖）
)MD";

/// 更新日志页。
const char *const kChangelogZhCN = R"MD(## v0.1.0

### 新功能

- **仪表盘** — 项目群脉搏 + 统计卡 + 看板 + 语言分布 + 里程碑 + 活跃项目（项目卡片整卡可点）
- **看板** — 按健康状态分列（活跃 / 待处理 / 停滞 / 其他）
- **项目详情** — 工程脉搏 / 提交构成 / 分支进度 / Git 操作 / 进度日志 / 文档平铺
- **里程碑管理** — CRUD + tag 自动达成 + 行内按钮
- **架构图** — 引擎 `graph arch` 的场景契约 + 自绘画布，支持生成与导出
- **代码图谱** — 符号树 + 置信度疑点 + 调用关系；左栏可切符号索引热力图
- **补丁体检** — 工作区改动的置信度三层体检（算法 → 人工裁决 → 合并终稿）
- **AI 整合更新流** — 浅 / 深更新 + AI 摘要 / 一键项目说明 / 一键项目群说明 / 定时简报
- **AI 设置** — models.dev 目录驱动 Provider 选择器 / 密钥存储 / 测试连接
- **添加 / 扫描项目** — 单个添加 + 批量扫描目录
- **托盘速览** — 项目状态一目了然 + 快捷更新

### 引擎

- moongit v0.1.0 — 仓颉语言，零第三方依赖
- deepin / UOS 桌面版首发
)MD";

} // namespace

QString kindKey(Kind k)
{
    switch (k) {
    case Kind::about:
        return QStringLiteral("about");
    case Kind::help:
        return QStringLiteral("help");
    case Kind::openSource:
        return QStringLiteral("openSource");
    case Kind::changelog:
        return QStringLiteral("changelog");
    }
    return QString();
}

QString kindTitle(Kind k, Language lang)
{
    Q_UNUSED(lang); // 目前只有简体中文；接 i18n 时在这里按语言取
    switch (k) {
    case Kind::about:
        return QStringLiteral("关于");
    case Kind::help:
        return QStringLiteral("帮助");
    case Kind::openSource:
        return QStringLiteral("开源感谢");
    case Kind::changelog:
        return QStringLiteral("更新日志");
    }
    return QString();
}

QVector<Kind> kinds()
{
    return { Kind::about, Kind::help, Kind::openSource, Kind::changelog };
}

QString content(Kind k, Language lang)
{
    if (lang != Language::zhCN)
        return QString(); // 认不出的语言 → 空串，不回落成中文
    switch (k) {
    case Kind::about:
        return QString::fromUtf8(kAboutZhCN);
    case Kind::help:
        return QString::fromUtf8(kHelpZhCN);
    case Kind::openSource:
        return QString::fromUtf8(kOpenSourceZhCN);
    case Kind::changelog:
        return QString::fromUtf8(kChangelogZhCN);
    }
    return QString(); // 认不出的类目 → 空串（见头文件的纪律说明）
}

QString engineRepo()
{
    return QString::fromUtf8(kEngineRepo);
}

QString clientRepo()
{
    return QString::fromUtf8(kClientRepo);
}

} // namespace DocPages
